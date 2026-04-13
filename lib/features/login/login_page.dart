// 이메일/비밀번호 로그인 화면
// 로그인 성공 시 Navigator.pop() → main.dart StreamBuilder가 대시보드로 라우팅

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/enums/user_role.dart';
import '../../core/utils/firestore_keys.dart';
import '../manage/admin_dashboard_page.dart';
import '../member/change_password_page.dart';
import '../member/reapply_page.dart';
import '../member/student_dashboard_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  static const Color _blue     = Color(0xFF1565C0);
  static const Color _textDark = Color(0xFF1A1A2E);
  static const Color _textGray = Color(0xFF757575);

  final _formKey   = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _pwCtrl    = TextEditingController();

  bool _isLoading = false;
  bool _obscurePw = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _pwCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      // 1. Firebase Auth 인증
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _pwCtrl.text,
      );

      // 2. Firestore users 문서에서 role 확인
      final uid = cred.user!.uid;
      final doc = await FirebaseFirestore.instance
          .collection(FsCol.users)
          .doc(uid)
          .get();

      if (!mounted) return;

      if (!doc.exists || doc.data() == null) {
        // DB 미등록 계정 → 로그아웃 후 차단
        await FirebaseAuth.instance.signOut();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('등록되지 않은 계정입니다. 관리자에게 문의하세요.'),
              backgroundColor: Colors.red),
        );
        return;
      }

      final data      = doc.data()!;
      final roleStr   = data[FsUser.role]      as String? ?? FsUser.roleStudent;
      final userName  = data[FsUser.name]      as String? ?? '';
      final status    = data[FsUser.status]    as String? ?? FsUser.statusPending;
      final isDeleted = data[FsUser.isDeleted] as bool?   ?? false;
      final isTempPw  = data[FsUser.isTempPw]  as bool?   ?? false;
      final role      = roleStr.toUserRole();

      // 삭제·승인 대기 계정 차단
      if (isDeleted || status == FsUser.statusPending) {
        await FirebaseAuth.instance.signOut();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('접근이 제한된 계정입니다. 관리자에게 문의하세요.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // 임시 비밀번호 → 비밀번호 변경 강제
      if (isTempPw) {
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) =>
                ChangePasswordPage(userRole: role, userName: userName),
          ),
          (_) => false,
        );
        return;
      }

      // 학생 졸업·중도탈락 → 재신청 화면
      if (role == UserRole.STUDENT &&
          (status == FsUser.statusGraduated ||
              status == FsUser.statusDropped)) {
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => ReapplyPage(status: status, userName: userName),
          ),
          (_) => false,
        );
        return;
      }

      // active 아닌 경우 차단
      if (status != FsUser.statusActive) {
        await FirebaseAuth.instance.signOut();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('접근이 제한된 계정입니다. 관리자에게 문의하세요.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // 역할별 대시보드 이동
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => role == UserRole.STUDENT
              ? StudentDashboardPage(userRole: role, userName: userName)
              : AdminDashboardPage(userRole: role, userName: userName),
        ),
        (_) => false,
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_authError(e.code)), backgroundColor: Colors.red),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('로그인 실패: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Firebase Auth 에러 코드 → 한글 메시지
  String _authError(String code) {
    switch (code) {
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return '이메일 또는 비밀번호가 올바르지 않습니다.';
      case 'user-disabled':
        return '비활성화된 계정입니다. 관리자에게 문의하세요.';
      case 'too-many-requests':
        return '로그인 시도가 너무 많습니다. 잠시 후 다시 시도해 주세요.';
      default:
        return '로그인 중 오류가 발생했습니다.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: Colors.white,
            foregroundColor: _textDark,
            elevation: 0,
            leading: Semantics(
              label: '뒤로 가기 버튼입니다.',
              child: const BackButton(),
            ),
            title: const Text(
              '로그인',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: _textDark),
            ),
            centerTitle: true,
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 48),

                    // 헤더
                    const Text('다시 만나서 반가워요!',
                        style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: _textDark)),
                    const SizedBox(height: 6),
                    const Text('계정 정보를 입력해 주세요.',
                        style: TextStyle(fontSize: 14, color: _textGray)),
                    const SizedBox(height: 40),

                    // 이메일
                    const Text('이메일',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _textDark)),
                    const SizedBox(height: 8),
                    Semantics(
                      label: '이메일 입력란입니다. 필수 항목입니다.',
                      child: TextFormField(
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        enabled: !_isLoading,
                        decoration: _inputDeco('example@email.com',
                            Icons.email_outlined),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return '이메일을 입력해 주세요.';
                          }
                          if (!v.contains('@')) return '올바른 이메일 형식이 아닙니다.';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(height: 20),

                    // 비밀번호
                    const Text('비밀번호',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _textDark)),
                    const SizedBox(height: 8),
                    Semantics(
                      label: '비밀번호 입력란입니다. 필수 항목입니다.',
                      child: TextFormField(
                        controller: _pwCtrl,
                        obscureText: _obscurePw,
                        textInputAction: TextInputAction.done,
                        enabled: !_isLoading,
                        onFieldSubmitted: (_) => _login(),
                        decoration: _inputDeco('비밀번호를 입력해 주세요.',
                            Icons.lock_outline_rounded).copyWith(
                          suffixIcon: Semantics(
                            label: _obscurePw ? '비밀번호 표시 버튼입니다.' : '비밀번호 숨기기 버튼입니다.',
                            child: IconButton(
                              icon: Icon(
                                _obscurePw
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                color: _textGray,
                                size: 20,
                              ),
                              onPressed: () =>
                                  setState(() => _obscurePw = !_obscurePw),
                            ),
                          ),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) return '비밀번호를 입력해 주세요.';
                          if (v.length < 8) return '8자 이상 입력해 주세요.';
                          if (RegExp(r'[가-힣ㄱ-ㅎㅏ-ㅣ]').hasMatch(v)) return '한글은 사용할 수 없습니다.';
                          if (!RegExp(r'[A-Z]').hasMatch(v)) return '대문자를 1자 이상 포함해야 합니다.';
                          if (!RegExp(r'[!@#\$%^&*()\-_=+\[\]{};:\'",.<>?/\\|`~]').hasMatch(v)) return '특수문자를 1자 이상 포함해야 합니다.';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(height: 40),

                    // 로그인 버튼
                    Semantics(
                      label: '로그인 버튼입니다.',
                      child: SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _blue,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30)),
                            disabledBackgroundColor:
                                _blue.withValues(alpha: 0.6),
                          ),
                          onPressed: _isLoading ? null : _login,
                          child: const Text(
                            '로그인',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),
        ),

        // 로딩 오버레이 — 처리 중 입력·버튼 전체 차단
        if (_isLoading) ...[
          const ModalBarrier(dismissible: false, color: Colors.black26),
          const Center(
            child: CircularProgressIndicator(color: _blue),
          ),
        ],
      ],
    );
  }

  InputDecoration _inputDeco(String hint, IconData icon) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFFBDBDBD), fontSize: 14),
        prefixIcon: Icon(icon, color: _textGray, size: 20),
        filled: true,
        fillColor: const Color(0xFFF8F9FA),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _blue, width: 2)),
        errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Colors.red)),
        focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Colors.red, width: 2)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      );
}
