import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/auth_service.dart';

// 승인 대기(status=pending) 전용 화면
// 뒤로 가기 완전 차단 / 로그아웃만 허용
class PendingPage extends StatelessWidget {
  const PendingPage({super.key});

  Future<void> _logout(BuildContext context) async {
    AuthService.instance.clear();
    await FirebaseAuth.instance.signOut();
    // signOut 시 RouteGuard StreamBuilder가 LoginIntroPage로 자동 라우팅
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          automaticallyImplyLeading: false,
          title: const Text(
            'Job 알리미',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          centerTitle: true,
          actions: [
            Semantics(
              label: '로그아웃 버튼',
              button: true,
              child: IconButton(
                icon: const Icon(Icons.logout_rounded),
                tooltip: '로그아웃',
                onPressed: () => _logout(context),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Semantics(
                          label: '승인 대기 상태 아이콘',
                          child: const Icon(
                            Icons.hourglass_top_rounded,
                            size: 80,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(height: 28),
                        Semantics(
                          header: true,
                          child: const Text(
                            '승인 확인 중입니다',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          '회원가입 신청이 완료되었습니다.\n관리자 승인 후 서비스를 이용하실 수 있습니다.\n승인 완료 시 재로그인해 주세요.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            color: AppColors.textSecondary,
                            height: 1.7,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // 비밀번호 초기화 요청 안내 — 하단 상시 노출
              Semantics(
                label: '비밀번호 초기화 요청 안내입니다.',
                child: Container(
                  width: double.infinity,
                  color: const Color(0xFFF0F4FF),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: const Text(
                    '비밀번호를 잊으셨나요?\n관리자에게 비밀번호 초기화를 요청하시면 임시 비밀번호를 안내해 드립니다.',
                    style: TextStyle(
                        fontSize: 13,
                        color: AppColors.primary,
                        height: 1.6),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
