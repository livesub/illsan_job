import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/route_guard.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart'; // 스마트 에디터 번역 사전용

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
      
      // 🌟 [추가된 핵심 코드] 플러터 기본 위젯 및 스마트 에디터 다국어 번역 사전 등록
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        FlutterQuillLocalizations.delegate, // 스마트 에디터용 한국어 번역 사전
      ],
      // 🌟 [추가된 핵심 코드] 지원하는 언어 목록 명시 (한국어 최우선)
      supportedLocales: const [
        Locale('ko', 'KR'), // 한국어 설정
        Locale('en', 'US'), // 기본 영어 (대비용)
      ],
      
      home: const RouteGuard(),
    );
  }
}