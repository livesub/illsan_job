import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../enums/user_role.dart';
import 'auth_service.dart';
import 'firestore_keys.dart';
import '../../features/login/login_intro_page.dart';
import '../../features/manage/admin_dashboard_page.dart';
import '../../features/member/student_dashboard_page.dart';
import '../../features/member/change_password_page.dart';
import '../../features/member/pending_page.dart';
import '../../features/member/reapply_page.dart';

// 분기 규칙:
//   미로그인                         → LoginIntroPage
//   Firestore 문서 없음 / is_deleted → signOut + LoginIntroPage
//   status == pending                → signOut + 권한 없음 SnackBar
//   is_temp_password == true         → ChangePasswordPage
//   STUDENT + graduated/dropped      → ReapplyPage
//   STUDENT + active                 → StudentDashboardPage
//   INSTRUCTOR/SUPER_ADMIN + active  → AdminDashboardPage
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
        if (authSnap.data == null) return const LoginIntroPage();
        return _RoleRouter(uid: authSnap.data!.uid);
      },
    );
  }
}

class _RoleRouter extends StatefulWidget {
  final String uid;
  const _RoleRouter({required this.uid});

  @override
  State<_RoleRouter> createState() => _RoleRouterState();
}

class _RoleRouterState extends State<_RoleRouter> {
  late final Future<DocumentSnapshot> _userFuture;
  bool _redirecting = false;

  @override
  void initState() {
    super.initState();
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
        if (data == null) {
          _doSignOut();
          return const _Loading();
        }

        final roleStr   = data[FsUser.role]      as String? ?? FsUser.roleStudent;
        final userName  = data[FsUser.name]      as String? ?? '';
        final status    = data[FsUser.status]    as String? ?? FsUser.statusPending;
        final isDeleted = data[FsUser.isDeleted] as bool?   ?? false;
        final isTempPw  = data[FsUser.isTempPw]  as bool?   ?? false;
        final role      = roleStr.toUserRole();

        // 삭제 계정 차단
        if (isDeleted) {
          _doSignOut(showError: true);
          return const _Loading();
        }

        // 승인 대기 → 전용 대기 화면
        if (status == FsUser.statusPending) {
          return const PendingPage();
        }

        // 임시 비밀번호 → 강제 변경
        if (isTempPw) {
          return ChangePasswordPage(userRole: role, userName: userName);
        }

        if (role == UserRole.STUDENT) {
          // 졸업·중도탈락 → 재신청
          if (status == FsUser.statusGraduated ||
              status == FsUser.statusDropped) {
            return ReapplyPage(status: status, userName: userName);
          }
          // active 외 차단
          if (status != FsUser.statusActive) {
            _doSignOut(showError: true);
            return const _Loading();
          }
          return StudentDashboardPage(userRole: role, userName: userName);
        }

        // 교사·관리자: active만 허용
        if (status != FsUser.statusActive) {
          _doSignOut(showError: true);
          return const _Loading();
        }
        return AdminDashboardPage(userRole: role, userName: userName);
      },
    );
  }

  void _doSignOut({bool showError = false}) {
    if (_redirecting) return;
    _redirecting = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (showError && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('접근이 제한된 계정입니다.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
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
