import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/auth_service.dart';
import '../../core/utils/firestore_keys.dart';
import '../login/login_intro_page.dart';

// 졸업·중도탈락 학생 전용 재신청 화면
// 활성 강좌 선택 후 신청 시 status=pending, course_id 업데이트
class ReapplyPage extends StatefulWidget {
  final String status;   // FsUser.statusGraduated | statusDropped
  final String userName;
  const ReapplyPage({
    super.key,
    required this.status,
    required this.userName,
  });

  @override
  State<ReapplyPage> createState() => _ReapplyPageState();
}

class _ReapplyPageState extends State<ReapplyPage> {
  bool _isLoading  = false;
  bool _loadingCourses = true;

  // 선택된 강좌 id
  String? _selectedCourseId;
  // 강좌 목록 {id: name}
  final List<_CourseItem> _courses = [];

  bool get _isGraduated => widget.status == FsUser.statusGraduated;

  @override
  void initState() {
    super.initState();
    _loadCourses();
  }

  // Firestore courses 컬렉션에서 status=active 강좌 목록 조회
  Future<void> _loadCourses() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection(FsCol.courses)
          .where(FsCourse.status, isEqualTo: FsCourse.statusActive)
          .get();
      if (!mounted) return;
      _courses.clear();
      for (final doc in snap.docs) {
        final name = doc.data()[FsCourse.name] as String? ?? '';
        if (name.isNotEmpty) {
          _courses.add(_CourseItem(id: doc.id, name: name));
        }
      }
    } finally {
      if (mounted) setState(() => _loadingCourses = false);
    }
  }

  // status=pending, course_id 업데이트 후 로그아웃
  Future<void> _reapply() async {
    if (_selectedCourseId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('수강할 과정을 선택해 주세요.'), backgroundColor: Colors.red),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        await FirebaseFirestore.instance
            .collection(FsCol.users)
            .doc(uid)
            .update({
          FsUser.status:   FsUser.statusPending,
          FsUser.courseId: _selectedCourseId,
        });
      }
      AuthService.instance.clear();
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginIntroPage()),
        (_) => false,
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _logout() async {
    AuthService.instance.clear();
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginIntroPage()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        title: const Text(
          'Job 알리미',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
        actions: [
          Semantics(
            label: '로그아웃 버튼',
            button: true,
            child: IconButton(
              icon: const Icon(Icons.logout_rounded),
              tooltip: '로그아웃',
              onPressed: _isLoading ? null : _logout,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Semantics(
                    label: _isGraduated ? '졸업 상태 아이콘' : '중도탈락 상태 아이콘',
                    child: Icon(
                      _isGraduated
                          ? Icons.school_rounded
                          : Icons.pause_circle_outline_rounded,
                      size: 72,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Semantics(
                    header: true,
                    child: Text(
                      _isGraduated ? '수료 완료' : '수강 중단',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _isGraduated
                        ? '${widget.userName}님의 과정이 완료되었습니다.\n재수강을 원하시면 과정을 선택해 주세요.'
                        : '${widget.userName}님의 수강이 중단된 상태입니다.\n재신청을 원하시면 과정을 선택해 주세요.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 15,
                      color: AppColors.textSecondary,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // 강좌 선택 드롭다운
                  Semantics(
                    label: '수강 과정 선택 드롭다운입니다.',
                    child: _loadingCourses
                        ? const CircularProgressIndicator()
                        : _courses.isEmpty
                            ? const Text(
                                '현재 신청 가능한 과정이 없습니다.',
                                style: TextStyle(
                                    fontSize: 14,
                                    color: AppColors.textSecondary),
                              )
                            : DropdownButtonFormField<String>(
                                initialValue: _selectedCourseId,
                                isExpanded: true,
                                decoration: InputDecoration(
                                  labelText: '수강 과정 선택',
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14)),
                                  enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: const BorderSide(
                                          color: Color(0xFFE0E0E0))),
                                  focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: const BorderSide(
                                          color: AppColors.primary, width: 2)),
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 14),
                                ),
                                items: _courses
                                    .map((c) => DropdownMenuItem(
                                          value: c.id,
                                          child: Text(c.name,
                                              style: const TextStyle(
                                                  fontSize: 14)),
                                        ))
                                    .toList(),
                                onChanged: _isLoading
                                    ? null
                                    : (v) =>
                                        setState(() => _selectedCourseId = v),
                              ),
                  ),
                  const SizedBox(height: 32),

                  // 재신청 버튼
                  Semantics(
                    label: '재신청 버튼. 선택한 과정으로 재신청 요청을 보냅니다.',
                    child: SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: (_isLoading || _loadingCourses || _courses.isEmpty)
                            ? null
                            : _reapply,
                        child: _isLoading
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2),
                              )
                            : const Text('재신청하기'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ));
  }
}

class _CourseItem {
  final String id;
  final String name;
  const _CourseItem({required this.id, required this.name});
}
