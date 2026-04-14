import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/enums/user_role.dart';
import '../manage/tabs/board_tab.dart';
import '../login/login_intro_page.dart';
import 'student_home_tab.dart';

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
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.home_rounded), label: '홈'),
          BottomNavigationBarItem(
              icon: Icon(Icons.assignment_rounded), label: '내 지원'),
          BottomNavigationBarItem(
              icon: Icon(Icons.article_rounded), label: '게시판'),
        ],
      ),
    );
  }

  Widget _buildBody() {
    switch (_tabIndex) {
      case 0:
        return StudentHomeTab(
          userName: widget.userName,
          onViewApplications: () => setState(() => _tabIndex = 1),
        );
      case 2:
        return BoardTab(userRole: widget.userRole, userName: widget.userName);
      default:
        return Center(
          child: Semantics(
            label: '준비 중인 화면입니다.',
            child: const Text(
              '준비 중입니다.',
              style: TextStyle(fontSize: 15, color: Color(0xFF757575)),
            ),
          ),
        );
    }
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
