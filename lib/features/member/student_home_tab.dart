import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/firestore_keys.dart';

// 학생 대시보드 홈 탭
// 소속 반 정보 카드 + 지원 현황 통계 + 공지 롤링 배너
class StudentHomeTab extends StatefulWidget {
  final String userName;
  final VoidCallback onViewApplications; // 내 지원 탭 이동 콜백
  const StudentHomeTab({
    super.key,
    required this.userName,
    required this.onViewApplications,
  });

  @override
  State<StudentHomeTab> createState() => _StudentHomeTabState();
}

class _StudentHomeTabState extends State<StudentHomeTab> {
  final _db       = FirebaseFirestore.instance;
  final _pageCtrl = PageController();
  Timer? _bannerTimer;

  String _courseName  = '';
  int    _pending     = 0;
  int    _approved    = 0;
  List<QueryDocumentSnapshot> _notices = [];
  int    _bannerIndex = 0;
  bool   _loading     = true;

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    _pageCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    await Future.wait([_loadCourse(), _loadStats(), _loadNotices()]);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadCourse() async {
    final userSnap = await _db.collection(FsCol.users).doc(_uid).get();
    final courseId = userSnap.data()?[FsUser.courseId] as String? ?? '';
    if (courseId.isEmpty) return;
    final courseSnap = await _db.collection(FsCol.courses).doc(courseId).get();
    if (!mounted) return;
    _courseName = courseSnap.data()?[FsCourse.name] as String? ?? '';
  }

  Future<void> _loadStats() async {
    final uid = _uid;
    // 대기·승인 건수를 개별 쿼리로 조회
    final results = await Future.wait([
      _db
          .collection(FsCol.jobApplications)
          .where(FsJobApp.applicantId, isEqualTo: uid)
          .where(FsJobApp.status, isEqualTo: FsJobApp.statusPending)
          .get(),
      _db
          .collection(FsCol.jobApplications)
          .where(FsJobApp.applicantId, isEqualTo: uid)
          .where(FsJobApp.status, isEqualTo: FsJobApp.statusApproved)
          .get(),
    ]);
    if (!mounted) return;
    _pending  = results[0].docs.length;
    _approved = results[1].docs.length;
  }

  Future<void> _loadNotices() async {
    final snap = await _db
        .collection(FsCol.notices)
        .orderBy(FsNotice.createdAt, descending: true)
        .limit(20)
        .get();
    if (!mounted) return;
    _notices = snap.docs.where((d) {
      return !((d.data()[FsNotice.isDeleted] as bool?) ?? false);
    }).take(5).toList();
    if (_notices.length > 1) _startTimer();
  }

  // 4초 간격 자동 롤링 (3~5초 범위 내)
  void _startTimer() {
    _bannerTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || _notices.isEmpty) return;
      final next = (_bannerIndex + 1) % _notices.length;
      _pageCtrl.animateToPage(next,
          duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildProfileCard(),
          const SizedBox(height: 20),
          _buildStatsRow(),
          const SizedBox(height: 24),
          const Text('공지사항',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 12),
          _notices.isEmpty
              ? const Text('등록된 공지사항이 없습니다.',
                  style: TextStyle(
                      fontSize: 14, color: AppColors.textSecondary))
              : _buildBanner(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // 소속 반 + 이름 카드 — 탭 시 마이페이지
  Widget _buildProfileCard() {
    final course = _courseName.isEmpty ? '반 미배정' : _courseName;
    return Semantics(
      label: '소속 반 $course, ${widget.userName}님. 마이페이지로 이동합니다.',
      button: true,
      child: InkWell(
        onTap: () => ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('마이페이지 준비 중입니다.'),
              duration: Duration(seconds: 2)),
        ),
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.primary, AppColors.primaryLight],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(course,
                          style: const TextStyle(
                              fontSize: 13,
                              color: Colors.white70,
                              fontWeight: FontWeight.w500)),
                      const SizedBox(height: 4),
                      Text(widget.userName,
                          style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: Colors.white)),
                    ],
                  ),
                ),
                const Icon(Icons.person_rounded,
                    color: Colors.white70, size: 28),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 지원 현황 통계 카드 2개
  Widget _buildStatsRow() {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            icon: Icons.hourglass_top_rounded,
            iconColor: const Color(0xFFEF6C00),
            bgColor: const Color(0xFFFFF3E0),
            label: '지원 대기',
            count: _pending,
            onTap: widget.onViewApplications,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            icon: Icons.check_circle_rounded,
            iconColor: const Color(0xFF2E7D32),
            bgColor: const Color(0xFFE8F5E9),
            label: '지원 승인',
            count: _approved,
            onTap: widget.onViewApplications,
          ),
        ),
      ],
    );
  }

  // 공지 롤링 배너 (PageView.builder + Timer)
  Widget _buildBanner() {
    return Container(
      height: 88,
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Stack(
        children: [
          PageView.builder(
            controller: _pageCtrl,
            itemCount: _notices.length,
            onPageChanged: (i) => setState(() => _bannerIndex = i),
            itemBuilder: (_, i) {
              final title =
                  (_notices[i].data()[FsNotice.title] as String?) ?? '-';
              return Semantics(
                label: '공지사항 ${i + 1}: $title',
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 22),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('공지',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(title,
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          // 페이지 도트 인디케이터
          Positioned(
            bottom: 8,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _notices.length,
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: _bannerIndex == i ? 16 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: _bannerIndex == i
                        ? AppColors.primary
                        : AppColors.primary.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// 지원 현황 통계 아이콘 카드
class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color    iconColor;
  final Color    bgColor;
  final String   label;
  final int      count;
  final VoidCallback onTap;
  const _StatCard({
    required this.icon,
    required this.iconColor,
    required this.bgColor,
    required this.label,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label $count건. 내 지원 탭으로 이동합니다.',
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: iconColor, size: 22),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary)),
                    Text('$count건',
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
