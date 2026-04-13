// 라우팅 가드 — 인증 상태 + 권한(Role)을 검사하여 화면을 분기합니다.
//
// 분기 규칙:
//   미로그인              → LoginIntroPage
//   Firestore 문서 없음   → signOut + LoginIntroPage
//   STUDENT 이하 권한     → "권한이 없습니다" SnackBar + signOut → LoginIntroPage
//   INSTRUCTOR, SUPER_ADMIN → AdminDashboardPage

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../enums/user_role.dart';
import 'auth_service.dart';
import 'firestore_keys.dart';
import '../../features/login/login_intro_page.dart';
import '../../features/manage/admin_dashboard_page.dart';

class RouteGuard extends StatelessWidget {
  const RouteGuard({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnap) {
        if (authSnap.connectionState == ConnectionState.waiting) {
          return const _Loading();
        }
        final user = authSnap.data;
        if (user == null) return const LoginIntroPage();

        // 로그인 상태: Firestore role 확인 후 분기
        return _RoleRouter(uid: user.uid);
      },
    );
  }
}

// Role 조회 + 권한 분기 위젯 (Future 캐싱으로 중복 조회 방지)
class _RoleRouter extends StatefulWidget {
  final String uid;
  const _RoleRouter({required this.uid});

  @override
  State<_RoleRouter> createState() => _RoleRouterState();
}

class _RoleRouterState extends State<_RoleRouter> {
  late final Future<DocumentSnapshot> _userFuture;
  bool _redirecting = false; // 중복 리다이렉트 방지

  @override
  void initState() {
    super.initState();
    // AuthService에 현재 사용자 캐시 + 문서 스냅샷을 동시에 활용
    _userFuture = AuthService.instance.loadUser(widget.uid).then((_) {
      return FirebaseFirestore.instance
          .collection(FsCol.users)
          .doc(widget.uid)
          .get();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      future: _userFuture,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const _Loading();
        }

        final data = snap.data?.data() as Map<String, dynamic>?;

        // Firestore 문서 없음 → 로그아웃 + 로그인 화면
        if (data == null) {
          _redirectUnregistered();
          return const _Loading();
        }

        final roleStr  = data[FsUser.role]  as String? ?? FsUser.roleStudent;
        final userName = data[FsUser.name]  as String? ?? '';
        final role     = roleStr.toUserRole();

        // STUDENT: 관리자 페이지 접근 차단
        if (role == UserRole.STUDENT) {
          _redirectUnauthorized();
          return const _Loading();
        }

        return AdminDashboardPage(userRole: role, userName: userName);
      },
    );
  }

  // Firestore 미등록 계정 처리
  void _redirectUnregistered() {
    if (_redirecting) return;
    _redirecting = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      AuthService.instance.clear();
      await FirebaseAuth.instance.signOut();
    });
  }

  void _redirectUnauthorized() {
    if (_redirecting) return;
    _redirecting = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('권한이 없습니다.'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
      AuthService.instance.clear();
      await FirebaseAuth.instance.signOut();
    });
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
