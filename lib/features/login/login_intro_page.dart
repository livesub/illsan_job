// 앱 최초 진입 시 보여주는 인트로 화면입니다.
// basic_img.png 디자인을 Flutter 코드로 직접 구현한 화면입니다.
// Image.asset 사용 금지 — 모든 UI 요소를 코드로 구성합니다.

import 'package:flutter/material.dart';

// 앱의 첫 화면입니다.
// 상태 변경이 없으므로 StatelessWidget으로 구현합니다.
class LoginIntroPage extends StatelessWidget {
  const LoginIntroPage({super.key});

  // ── 디자인 상수 ─────────────────────────────────────────
  // 기획서(basic_img.png) 기준 색상값입니다.

  // 주요 파란색 — 로그인 버튼 배경, 포인트 텍스트
  static const Color _primaryBlue = Color(0xFF1565C0);

  // 진한 텍스트 색 — 타이틀, 일반 글씨
  static const Color _textDark = Color(0xFF1A1A2E);

  // 보조 텍스트 색 — 부제목, 기관명
  static const Color _textGray = Color(0xFF757575);

  // 버튼 라운드 값 — 기획서의 둥근 버튼 모양
  static const double _buttonRadius = 30.0;

  // 버튼 최소 높이 — 접근성 기준 최소 터치 영역
  static const double _buttonHeight = 56.0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 1. 배경: 깨끗한 흰색
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          // 좌우 여백 — 터치 실수 방지 및 가독성 향상
          padding: const EdgeInsets.symmetric(horizontal: 32.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 40),

              // ── 2. 상단 기관 로고 영역 ──────────────────
              _buildLogoArea(),

              const SizedBox(height: 32),

              // ── 3. 앱 타이틀 + 부제목 ───────────────────
              _buildTitleArea(),

              const SizedBox(height: 24),

              // ── 4. 일러스트 플레이스홀더 ─────────────────
              // TODO: 실제 일러스트 이미지가 준비되면 여기에 Image.asset으로 교체합니다.
              //       현재는 공간만 확보해 둡니다.
              _buildIllustrationPlaceholder(),

              // 남은 공간을 채워 버튼을 항상 하단에 위치시킵니다.
              const Spacer(),

              // ── 5. 하단 버튼 영역 ────────────────────────
              _buildButtons(context),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // 상단 기관 로고 영역
  // 기획서: "한국장애인고용공단 / 직업능력개발" 텍스트 + 우측 로고 아이콘
  // ─────────────────────────────────────────────────────────
  Widget _buildLogoArea() {
    return Semantics(
      label: '한국장애인고용공단 직업능력개발 로고입니다.',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 기관명 텍스트 2줄
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 첫째 줄: "한국장애인고용공단"
              Text(
                '한국장애인고용공단',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _textGray,
                  height: 1.5,
                ),
              ),
              // 둘째 줄: "직업능력개발"
              Text(
                '직업능력개발',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _textGray,
                  height: 1.5,
                ),
              ),
            ],
          ),

          const SizedBox(width: 10),

          // 로고 아이콘 — 실제 로고 이미지가 없으므로 Container 도형으로 표현합니다.
          // 기획서의 공단 심볼 마크를 파란 원형 + 접근성 아이콘으로 대체합니다.
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              // 파란 원형 배경
              color: _primaryBlue,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              // 장애인 접근성을 상징하는 아이콘 (기본 Material 아이콘)
              Icons.accessibility_new_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // 앱 타이틀 + 부제목
  // 기획서: "Job 알리미" (대형 볼드) + "장애인을 위한 희망 일자리 알림" (소형)
  // ─────────────────────────────────────────────────────────
  Widget _buildTitleArea() {
    return Semantics(
      label: 'Job 알리미. 장애인을 위한 희망 일자리 알림 앱입니다.',
      excludeSemantics: true, // 자식 Text 위젯이 중복 읽히지 않도록 통합
      child: Column(
        children: [
          // 타이틀: "Job 알리미"
          // "Job"은 파란색, "알리미"는 진한 텍스트 색으로 구분합니다.
          RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              children: [
                // "Job" — 파란색 강조
                TextSpan(
                  text: 'Job ',
                  style: TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.w900,
                    color: _primaryBlue,
                    letterSpacing: -1.0,
                  ),
                ),
                // "알리미" — 진한 텍스트 색
                TextSpan(
                  text: '알리미',
                  style: TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.w900,
                    color: _textDark,
                    letterSpacing: -1.0,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // 부제목: "장애인을 위한 희망 일자리 알림"
          Text(
            '장애인을 위한 희망 일자리 알림',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w400,
              color: _textGray,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // 일러스트 이미지 영역
  // bb.png — 세 명의 장애인 근무 일러스트를 사용합니다.
  // LayoutBuilder로 화면 너비를 감지하여 앱/웹/iOS에 맞게 크기를 자동 조절합니다.
  // ─────────────────────────────────────────────────────────
  Widget _buildIllustrationPlaceholder() {
    return Semantics(
      label: '휠체어를 탄 장애인, 안내견과 함께하는 장애인, 책상에서 근무하는 직원 일러스트입니다.',
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 화면 너비에 따라 일러스트 높이를 다르게 설정합니다.
          // 모바일(~600px): 240px / 태블릿·웹(600px~): 340px
          final double illustHeight = constraints.maxWidth < 600 ? 240 : 340;

          return SizedBox(
            height: illustHeight,
            child: Image.asset(
              // 장애인 근무 일러스트 (doc/bb.png → assets/images/illust_center.png)
              'assets/images/illust_center.png',
              fit: BoxFit.contain,      // 비율 유지하며 영역에 맞게 표시
              alignment: Alignment.center,
            ),
          );
        },
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // 하단 버튼 영역
  // 기획서: 로그인(파란 배경 + 흰 글씨), 회원가입(흰 배경 + 파란 테두리)
  // ─────────────────────────────────────────────────────────
  Widget _buildButtons(BuildContext context) {
    return Column(
      children: [
        // ── 로그인 버튼 ─────────────────────────────────
        // ElevatedButton: 파란 배경(#1565C0), 흰 글씨, 라운드 30
        Semantics(
          label: '로그인 버튼입니다. 누르면 로그인 화면으로 이동합니다.',
          child: SizedBox(
            width: double.infinity, // 좌우 꽉 채움
            height: _buttonHeight,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryBlue,       // 파란 배경
                foregroundColor: Colors.white,        // 흰 글씨
                elevation: 0,                         // 그림자 없음
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(_buttonRadius),
                ),
              ),
              onPressed: () {
                // TODO: 로그인 페이지로 이동
                // Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginPage()));
              },
              child: const Text(
                '로그인',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                ),
              ),
            ),
          ),
        ),

        const SizedBox(height: 14),

        // ── 회원가입 버튼 ───────────────────────────────
        // OutlinedButton: 흰 배경, 파란 테두리(#1565C0), 파란 글씨, 라운드 30
        Semantics(
          label: '회원가입 버튼입니다. 누르면 회원가입 화면으로 이동합니다.',
          child: SizedBox(
            width: double.infinity, // 좌우 꽉 채움
            height: _buttonHeight,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                backgroundColor: Colors.white,        // 흰 배경
                foregroundColor: _primaryBlue,        // 파란 글씨
                side: const BorderSide(
                  color: _primaryBlue,                // 파란 테두리
                  width: 2.0,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(_buttonRadius),
                ),
              ),
              onPressed: () {
                // TODO: 회원가입 페이지로 이동
                // Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterPage()));
              },
              child: const Text(
                '회원가입',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
