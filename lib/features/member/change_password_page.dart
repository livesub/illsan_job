import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../core/enums/user_role.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/firestore_keys.dart';
import '../manage/admin_dashboard_page.dart';
import 'student_dashboard_page.dart';

// 임시 비밀번호 로그인 후 강제 비밀번호 변경 화면
class ChangePasswordPage extends StatefulWidget {
  final UserRole userRole;
  final String userName;
  const ChangePasswordPage({
    super.key,
    required this.userRole,
    required this.userName,
  });

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final _formKey     = GlobalKey<FormState>();
  final _newPwCtrl   = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _isLoading      = false;
  bool _obscureNew     = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _newPwCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser!;
      // Firebase Auth 비밀번호 변경
      await user.updatePassword(_newPwCtrl.text);
      // Firestore is_temp_password = false
      await FirebaseFirestore.instance
          .collection(FsCol.users)
          .doc(user.uid)
          .update({FsUser.isTempPw: false});

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => widget.userRole == UserRole.STUDENT
              ? StudentDashboardPage(
                  userRole: widget.userRole, userName: widget.userName)
              : AdminDashboardPage(
                  userRole: widget.userRole, userName: widget.userName),
        ),
        (_) => false,
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.code == 'requires-recent-login'
              ? '보안을 위해 다시 로그인해 주세요.'
              : '비밀번호 변경에 실패했습니다.'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // login_page와 동일한 PW 규칙
  String? _validatePw(String? v) {
    if (v == null || v.isEmpty) return '비밀번호를 입력해 주세요.';
    if (v.length < 8) return '8자 이상 입력해 주세요.';
    if (RegExp(r'[가-힣ㄱ-ㅎㅏ-ㅣ]').hasMatch(v)) return '한글은 사용할 수 없습니다.';
    if (!RegExp(r'[A-Z]').hasMatch(v)) return '대문자를 1자 이상 포함해야 합니다.';
    if (!RegExp(r'[!@#\$%^&*()\-_=+\[\]{};:\'",.<>?/\\|`~]').hasMatch(v)) {
      return '특수문자를 1자 이상 포함해야 합니다.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            automaticallyImplyLeading: false,
            title: const Text(
              '비밀번호 변경',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary),
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
                    const SizedBox(height: 40),
                    Semantics(
                      label: '임시 비밀번호 사용 안내입니다.',
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF3E0),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          '임시 비밀번호로 로그인하셨습니다.\n보안을 위해 새 비밀번호를 설정해 주세요.',
                          style: TextStyle(
                              fontSize: 14,
                              color: Color(0xFFE65100),
                              height: 1.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    const Text('새 비밀번호',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary)),
                    const SizedBox(height: 8),
                    Semantics(
                      label: '새 비밀번호 입력란. 8자 이상, 대문자·특수문자 포함 필수.',
                      child: TextFormField(
                        controller: _newPwCtrl,
                        obscureText: _obscureNew,
                        textInputAction: TextInputAction.next,
                        enabled: !_isLoading,
                        decoration: _inputDeco('새 비밀번호').copyWith(
                          suffixIcon: Semantics(
                            label: _obscureNew ? '비밀번호 표시' : '비밀번호 숨기기',
                            child: IconButton(
                              icon: Icon(
                                _obscureNew
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                color: AppColors.textSecondary,
                                size: 20,
                              ),
                              onPressed: () =>
                                  setState(() => _obscureNew = !_obscureNew),
                            ),
                          ),
                        ),
                        validator: _validatePw,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text('비밀번호 확인',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary)),
                    const SizedBox(height: 8),
                    Semantics(
                      label: '비밀번호 확인 입력란.',
                      child: TextFormField(
                        controller: _confirmCtrl,
                        obscureText: _obscureConfirm,
                        textInputAction: TextInputAction.done,
                        enabled: !_isLoading,
                        onFieldSubmitted: (_) => _submit(),
                        decoration: _inputDeco('새 비밀번호를 다시 입력해 주세요.').copyWith(
                          suffixIcon: Semantics(
                            label: _obscureConfirm ? '비밀번호 표시' : '비밀번호 숨기기',
                            child: IconButton(
                              icon: Icon(
                                _obscureConfirm
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                color: AppColors.textSecondary,
                                size: 20,
                              ),
                              onPressed: () => setState(
                                  () => _obscureConfirm = !_obscureConfirm),
                            ),
                          ),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) return '비밀번호를 다시 입력해 주세요.';
                          if (v != _newPwCtrl.text) return '비밀번호가 일치하지 않습니다.';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(height: 40),
                    Semantics(
                      label: '비밀번호 변경 버튼',
                      child: SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _submit,
                          child: const Text('비밀번호 변경'),
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
        if (_isLoading) ...[
          const ModalBarrier(dismissible: false, color: Colors.black26),
          const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
        ],
      ],
    );
  }

  InputDecoration _inputDeco(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFFBDBDBD), fontSize: 14),
        prefixIcon: const Icon(Icons.lock_outline_rounded,
            color: AppColors.textSecondary, size: 20),
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
            borderSide: const BorderSide(color: AppColors.primary, width: 2)),
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
