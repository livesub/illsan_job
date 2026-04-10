import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/route_guard.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const JobAlrimiApp());
}

class JobAlrimiApp extends StatelessWidget {
  const JobAlrimiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Job 알리미',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      // RouteGuard: 인증+권한 검사 후 화면 분기
      home: const RouteGuard(),
    );
  }
}
