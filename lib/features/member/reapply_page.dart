import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/auth_service.dart';
import '../../core/utils/firestore_keys.dart';
import '../login/login_intro_page.dart';

// 졸업·중도탈락 학생 전용 재신청 화면 — 타 메뉴 없이 이 화면만 표시
class ReapplyPage extends StatefulWidget {
  final String status;    // FsUser.statusGraduated | statusDropped
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
  bool _isLoading = false;

  bool get _isGraduated => widget.status == FsUser.statusGraduated;

  // status → pending 업데이트 후 로그아웃 (관리자가 재승인)
  Future<void> _reapply() async {
    setState(() => _isLoading = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        await FirebaseFirestore.instance
            .collection(FsCol.users)
            .doc(uid)
            .update({FsUser.status: FsUser.statusPending});
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
    return Scaffold(
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
        child: Padding(
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
                    ? '${widget.userName}님의 과정이 완료되었습니다.\n재수강을 원하시면 아래 버튼을 눌러 주세요.'
                    : '${widget.userName}님의 수강이 중단된 상태입니다.\n재신청을 원하시면 아래 버튼을 눌러 주세요.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  color: AppColors.textSecondary,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 48),
              Semantics(
                label: '재신청 버튼. 관리자에게 재신청 요청을 보냅니다.',
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _reapply,
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
      ),
    );
  }
}
