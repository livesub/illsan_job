// 앱 전체에서 사용하는 색상, 텍스트 스타일, 테마를 한곳에서 관리하는 파일입니다.
// 이 파일만 수정하면 앱 전체 디자인이 일관되게 바뀝니다.

import 'package:flutter/material.dart';

// ──────────────────────────────────────────────
// 앱 컬러 팔레트 (basic_img.png 기준)
// ──────────────────────────────────────────────
class AppColors {
  AppColors._(); // 인스턴스 생성 방지 (상수 모음 클래스)

  // 주요 파란색 — 로그인 버튼, 포인트 컬러
  static const Color primary = Color(0xFF1565C0);

  // 조금 밝은 파란색 — 호버, 포커스 상태
  static const Color primaryLight = Color(0xFF1976D2);

  // 배경색 — 흰색
  static const Color background = Color(0xFFFFFFFF);

  // 카드/서피스 색 — 연한 회색
  static const Color surface = Color(0xFFF5F5F5);

  // 기본 텍스트 색 — 거의 검정
  static const Color textPrimary = Color(0xFF1A1A2E);

  // 보조 텍스트 색 — 중간 회색
  static const Color textSecondary = Color(0xFF616161);

  // 아웃라인 버튼 테두리 색
  static const Color outline = Color(0xFF1565C0);

  // 에러 색
  static const Color error = Color(0xFFD32F2F);

  // 고대비 모드용 — 검정 배경
  static const Color highContrastBg = Color(0xFF000000);

  // 고대비 모드용 — 노란 포인트
  static const Color highContrastAccent = Color(0xFFFFEB3B);
}

// ──────────────────────────────────────────────
// 앱 텍스트 스타일
// ──────────────────────────────────────────────
class AppTextStyles {
  AppTextStyles._();

  // 앱 타이틀 "Job 알리미" — 매우 크고 굵은 글씨
  static const TextStyle appTitle = TextStyle(
    fontSize: 36,
    fontWeight: FontWeight.w900,
    color: AppColors.textPrimary,
    letterSpacing: -0.5,
  );

  // 부제목 — "장애인을 위한 희망 일자리 알림"
  static const TextStyle subtitle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    height: 1.5,
  );

  // 버튼 텍스트 — 크고 가독성 좋게
  static const TextStyle button = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.5,
  );

  // 상단 로고 기관명 텍스트
  static const TextStyle logoOrg = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
    height: 1.4,
  );
}

// ──────────────────────────────────────────────
// MaterialApp 에 전달하는 전체 테마
// ──────────────────────────────────────────────
class AppTheme {
  AppTheme._();

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.light,
          surface: AppColors.surface,
          primary: AppColors.primary,
          error: AppColors.error,
        ),
        scaffoldBackgroundColor: AppColors.background,

        // 채워진(Filled) 버튼 — 로그인 버튼에 사용
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            textStyle: AppTextStyles.button,
            minimumSize: const Size(double.infinity, 56), // 접근성: 최소 높이 56
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30), // 둥근 모서리
            ),
            elevation: 0,
          ),
        ),

        // 아웃라인 버튼 — 회원가입 버튼에 사용
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            textStyle: AppTextStyles.button,
            minimumSize: const Size(double.infinity, 56), // 접근성: 최소 높이 56
            side: const BorderSide(color: AppColors.outline, width: 2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
            ),
          ),
        ),
      );
}
