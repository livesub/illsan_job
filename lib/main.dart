// 앱의 진입점(Entry Point)입니다.
// Firebase 초기화 후 MyApp 위젯을 실행합니다.

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'core/theme/app_theme.dart';
import 'core/enums/user_role.dart';
// import 'features/login/login_intro_page.dart'; // 테스트 후 주석 해제
import 'features/manage/admin_dashboard_page.dart';

// 앱 시작 함수입니다.
// async/await를 사용하므로 WidgetsFlutterBinding.ensureInitialized() 를 먼저 호출해야 합니다.
void main() async {
  // Flutter 엔진과 위젯 바인딩을 초기화합니다. (Firebase 초기화 전 필수)
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase 서비스를 초기화합니다. (firebase_options.dart에 플랫폼별 설정이 있습니다)
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // 앱을 실행합니다.
  runApp(const JobAlrimiApp());
}

// 앱의 루트 위젯입니다.
// MaterialApp 설정(테마, 라우팅 등)을 담당합니다.
class JobAlrimiApp extends StatelessWidget {
  const JobAlrimiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // 앱 이름 (OS 작업 관리자, 접근성 서비스 등에서 사용됩니다)
      title: 'Job 알리미',

      // 디버그 배너 숨김
      debugShowCheckedModeBanner: false,

      // CLAUDE.md 기준 앱 테마 적용 (lib/core/theme/app_theme.dart)
      theme: AppTheme.light,

      // TODO: 테스트 완료 후 아래를 LoginIntroPage()로 되돌리세요.
      // home: const LoginIntroPage(),

      // 임시 — 관리자 페이지 바로 진입 (테스트용)
      home: const AdminDashboardPage(
        userRole: UserRole.SUPER_ADMIN,
        userName: '테스트 관리자',
      ),
    );
  }
}
