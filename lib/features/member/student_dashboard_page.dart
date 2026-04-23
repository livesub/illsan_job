import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/enums/user_role.dart';
import '../../core/utils/firestore_keys.dart';
import '../manage/tabs/board_tab.dart';
import '../login/login_intro_page.dart';
import 'student_home_tab.dart';
import 'student_outing_tab.dart';

// 학생 전용 대시보드 — BottomNavigationBar 3탭
// Tab 0: 홈, Tab 1: 내 지원(준비 중), Tab 2: 게시판
class StudentDashboardPage extends StatefulWidget {
  final UserRole userRole;
  final String userName;
  const StudentDashboardPage({
    super.key,
    required this.userRole,
    required this.userName,
  });

  @override
  State<StudentDashboardPage> createState() => _StudentDashboardPageState();
}

class _StudentDashboardPageState extends State<StudentDashboardPage> {
  static const Color _blue = Color(0xFF1565C0);
  int _tabIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      appBar: AppBar(
        title: const Text(
          'Job 알리미',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        backgroundColor: _blue,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          Semantics(
            label: '로그아웃 버튼',
            button: true,
            child: IconButton(
              icon: const Icon(Icons.logout_rounded),
              tooltip: '로그아웃',
              onPressed: _logout,
            ),
          ),
        ],
      ),
      body: _buildBody(),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tabIndex,
        onTap: (i) => setState(() => _tabIndex = i),
        selectedItemColor: _blue,
        unselectedItemColor: const Color(0xFF9E9E9E),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.home_rounded), label: '홈'),
          BottomNavigationBarItem(
              icon: Icon(Icons.assignment_rounded), label: '내 지원'),
          BottomNavigationBarItem(
              icon: Icon(Icons.work_rounded), label: '구직공고'),
          BottomNavigationBarItem(
              icon: Icon(Icons.directions_walk_rounded), label: '외출 관리'),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return IndexedStack(
      index: _tabIndex,
      children: [
        StudentHomeTab(
          userName: widget.userName,
          onViewApplications: () => setState(() => _tabIndex = 1),
        ),
        const _StudentApplicationsTab(),
        BoardTab(userRole: widget.userRole, userName: widget.userName, showNotices: false),
        StudentOutingTab(userName: widget.userName),
      ],
    );
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginIntroPage()),
      (_) => false,
    );
  }
}

// 학생 내 지원 목록 탭
class _StudentApplicationsTab extends StatefulWidget {
  const _StudentApplicationsTab();

  @override
  State<_StudentApplicationsTab> createState() => _StudentApplicationsTabState();
}

class _StudentApplicationsTabState extends State<_StudentApplicationsTab> {
  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';
  List<QueryDocumentSnapshot> _apps = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadApplications();
  }

  Future<void> _loadApplications() async {
    final snap = await FirebaseFirestore.instance
        .collection(FsCol.jobApplications)
        .where(FsJobApp.applicantId, isEqualTo: _uid)
        .get();
    if (!mounted) return;
    final docs = List<QueryDocumentSnapshot>.from(snap.docs);
    // appliedAt Timestamp 기준 내림차순 클라이언트 정렬
    docs.sort((a, b) {
      final ta = (a.data() as Map)[FsJobApp.appliedAt] as Timestamp?;
      final tb = (b.data() as Map)[FsJobApp.appliedAt] as Timestamp?;
      if (ta == null && tb == null) return 0;
      if (ta == null) return 1;
      if (tb == null) return -1;
      return tb.seconds.compareTo(ta.seconds);
    });
    setState(() {
      _apps = docs;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_apps.isEmpty) {
      return Semantics(
        label: '지원한 공고가 없습니다.',
        child: const Center(
          child: Text('지원한 공고가 없습니다.',
              style: TextStyle(fontSize: 15, color: Color(0xFF757575))),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () async {
        setState(() { _apps.clear(); _loading = true; });
        await _loadApplications();
      },
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _apps.length,
        itemBuilder: (_, i) {
          final data      = _apps[i].data() as Map<String, dynamic>;
          final jobTitle  = data[FsJobApp.jobTitle] as String? ?? '-';
          final status    = data[FsJobApp.status]   as String? ?? '';
          final ts        = data[FsJobApp.appliedAt] as Timestamp?;
          final dateStr   = ts != null
              ? '${ts.toDate().year}-${ts.toDate().month.toString().padLeft(2, '0')}-${ts.toDate().day.toString().padLeft(2, '0')}'
              : '-';

          final (statusLabel, statusColor) = switch (status) {
            FsJobApp.statusPending   => ('대기', const Color(0xFFEF6C00)),
            FsJobApp.statusApproved  => ('승인', const Color(0xFF2E7D32)),
            _                        => ('취소', const Color(0xFF9E9E9E)),
          };

          return Semantics(
            label: '$jobTitle, 상태: $statusLabel, 지원일: $dateStr',
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 6,
                      offset: const Offset(0, 2)),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(jobTitle,
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1A1A2E)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        Text(dateStr,
                            style: const TextStyle(
                                fontSize: 12, color: Color(0xFF757575))),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(statusLabel,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: statusColor)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
