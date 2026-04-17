import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/firestore_keys.dart';

class StudentMyPage extends StatefulWidget {
  const StudentMyPage({super.key});

  @override
  State<StudentMyPage> createState() => _StudentMyPageState();
}

class _StudentMyPageState extends State<StudentMyPage> {
  final _db       = FirebaseFirestore.instance;
  final _phoneCtrl = TextEditingController();

  String _name       = '';
  String _email      = '';
  String _phone      = '';
  String _courseName = '';
  bool   _isTempPw   = false;
  bool   _loading    = true;
  bool   _saving     = false;

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadUserInfo() async {
    final doc  = await _db.collection(FsCol.users).doc(_uid).get();
    final data = doc.data() ?? {};

    final courseId = data[FsUser.courseId] as String? ?? '';
    String courseName = '';
    if (courseId.isNotEmpty) {
      final courseDoc = await _db.collection(FsCol.courses).doc(courseId).get();
      courseName = courseDoc.data()?[FsCourse.name] as String? ?? '';
    }

    if (!mounted) return;
    final phone = data[FsUser.phone] as String? ?? '';
    setState(() {
      _name       = data[FsUser.name]  as String? ?? '';
      _email      = data[FsUser.email] as String? ?? '';
      _phone      = phone;
      _courseName = courseName.isEmpty ? '반 미배정' : courseName;
      _isTempPw   = data[FsUser.isTempPw] as bool? ?? false;
      _loading    = false;
      _phoneCtrl.text = phone;
    });
  }

  Future<void> _savePhone() async {
    final phone = _phoneCtrl.text.trim();
    if (phone == _phone) return;
    setState(() => _saving = true);
    try {
      await _db.collection(FsCol.users).doc(_uid).update({FsUser.phone: phone});
      if (!mounted) return;
      setState(() { _phone = phone; _saving = false; });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('전화번호가 저장되었습니다.'), backgroundColor: Color(0xFF2E7D32)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('저장 실패: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _showPasswordDialog() {
    showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PasswordChangeDialog(uid: _uid, email: _email),
    ).then((changed) {
      if (changed == true) setState(() => _isTempPw = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      appBar: AppBar(
        title: const Text('마이페이지',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_isTempPw) ...[
                    _buildTempPwBanner(),
                    const SizedBox(height: 16),
                  ],
                  _buildInfoCard(),
                  const SizedBox(height: 16),
                  _buildPhoneCard(),
                  const SizedBox(height: 16),
                  _buildSecurityCard(),
                ],
              ),
            ),
    );
  }

  Widget _buildTempPwBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFB300), width: 1.2),
      ),
      child: Row(children: const [
        Icon(Icons.warning_amber_rounded, color: Color(0xFFE65100), size: 20),
        SizedBox(width: 10),
        Expanded(
          child: Text('임시 비밀번호를 사용 중입니다. 아래에서 비밀번호를 변경해 주세요.',
              style: TextStyle(fontSize: 13, color: Color(0xFFE65100), height: 1.4)),
        ),
      ]),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _cardDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('기본 정보',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const Divider(height: 20),
          _infoRow(Icons.person_outline_rounded, '이름', _name),
          const SizedBox(height: 12),
          _infoRow(Icons.email_outlined, '이메일', _email),
          const SizedBox(height: 12),
          _infoRow(Icons.class_outlined, '소속 반', _courseName),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(children: [
      Icon(icon, size: 16, color: AppColors.primary),
      const SizedBox(width: 8),
      Text('$label  ',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
      Expanded(
        child: Text(value,
            style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
            overflow: TextOverflow.ellipsis),
      ),
    ]);
  }

  Widget _buildPhoneCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _cardDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('전화번호',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const Divider(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Semantics(
                  label: '전화번호 입력란',
                  child: TextField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: '010-0000-0000',
                      hintStyle: const TextStyle(fontSize: 13, color: Color(0xFFBDBDBD)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppColors.primary),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Semantics(
                label: '전화번호 저장 버튼',
                button: true,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                  onPressed: _saving ? null : _savePhone,
                  child: _saving
                      ? const SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('저장', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSecurityCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _cardDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('보안',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const Divider(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('비밀번호 변경',
                  style: TextStyle(fontSize: 13, color: AppColors.textPrimary)),
              Semantics(
                label: '비밀번호 변경 버튼',
                button: true,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    minimumSize: Size.zero,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                  onPressed: _showPasswordDialog,
                  child: const Text('변경', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  BoxDecoration _cardDeco() => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      );
}

// ─────────────────────────────────────────────────────────
// 비밀번호 변경 다이얼로그
// ─────────────────────────────────────────────────────────
class _PasswordChangeDialog extends StatefulWidget {
  final String uid;
  final String email;
  const _PasswordChangeDialog({required this.uid, required this.email});

  @override
  State<_PasswordChangeDialog> createState() => _PasswordChangeDialogState();
}

class _PasswordChangeDialogState extends State<_PasswordChangeDialog> {
  final _currentCtrl  = TextEditingController();
  final _newCtrl      = TextEditingController();
  final _confirmCtrl  = TextEditingController();

  bool   _obscureCurrent = true;
  bool   _obscureNew     = true;
  bool   _obscureConfirm = true;
  bool   _saving         = false;
  String _errorMsg       = '';

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  String _validate() {
    if (_currentCtrl.text.isEmpty) return '현재 비밀번호를 입력해 주세요.';
    final pw = _newCtrl.text;
    if (pw.length < 8) return '새 비밀번호는 8자 이상이어야 합니다.';
    if (!RegExp(r'[A-Z]').hasMatch(pw)) return '대문자를 1자 이상 포함해야 합니다.';
    if (!RegExp(r'[!@#\$%^&*(),.?":{}|<>_\-]').hasMatch(pw)) return '특수문자를 1자 이상 포함해야 합니다.';
    if (pw != _confirmCtrl.text) return '새 비밀번호가 일치하지 않습니다.';
    return '';
  }

  Future<void> _save() async {
    final err = _validate();
    if (err.isNotEmpty) {
      setState(() => _errorMsg = err);
      return;
    }
    setState(() { _saving = true; _errorMsg = ''; });
    try {
      final user = FirebaseAuth.instance.currentUser!;
      final cred = EmailAuthProvider.credential(
          email: widget.email, password: _currentCtrl.text);
      await user.reauthenticateWithCredential(cred);
      await user.updatePassword(_newCtrl.text);
      // isTempPw 해제
      await FirebaseFirestore.instance
          .collection(FsCol.users)
          .doc(widget.uid)
          .update({FsUser.isTempPw: false});
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('비밀번호가 변경되었습니다.'),
            backgroundColor: Color(0xFF2E7D32)),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      final msg = (e.code == 'wrong-password' || e.code == 'invalid-credential')
          ? '현재 비밀번호가 올바르지 않습니다.'
          : '변경 실패: ${e.message}';
      setState(() { _saving = false; _errorMsg = msg; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _saving = false; _errorMsg = '변경 실패: $e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: EdgeInsets.zero,
      title: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: const BoxDecoration(
          color: AppColors.primary,
          borderRadius:
              BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
        ),
        child: const Row(children: [
          Icon(Icons.lock_outline_rounded, color: Colors.white, size: 20),
          SizedBox(width: 8),
          Text('비밀번호 변경',
              style: TextStyle(
                  color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
        ]),
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _pwField(
              label: '현재 비밀번호',
              ctrl: _currentCtrl,
              obscure: _obscureCurrent,
              onToggle: () => setState(() => _obscureCurrent = !_obscureCurrent),
            ),
            const SizedBox(height: 14),
            _pwField(
              label: '새 비밀번호',
              hint: '8자 이상, 대문자, 특수문자 포함',
              ctrl: _newCtrl,
              obscure: _obscureNew,
              onToggle: () => setState(() => _obscureNew = !_obscureNew),
              onChanged: (_) => setState(() => _errorMsg = ''),
            ),
            const SizedBox(height: 14),
            _pwField(
              label: '새 비밀번호 확인',
              ctrl: _confirmCtrl,
              obscure: _obscureConfirm,
              onToggle: () => setState(() => _obscureConfirm = !_obscureConfirm),
              onChanged: (_) => setState(() => _errorMsg = ''),
            ),
            if (_errorMsg.isNotEmpty) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(_errorMsg,
                    style: const TextStyle(fontSize: 12, color: Colors.red)),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('취소', style: TextStyle(color: Colors.grey)),
        ),
        Semantics(
          label: '비밀번호 저장 버튼',
          button: true,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('저장', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }

  Widget _pwField({
    required String label,
    required TextEditingController ctrl,
    required bool obscure,
    required VoidCallback onToggle,
    String hint = '',
    ValueChanged<String>? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary)),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          obscureText: obscure,
          onChanged: onChanged,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(fontSize: 12, color: Color(0xFFBDBDBD)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.primary),
            ),
            suffixIcon: IconButton(
              icon: Icon(
                  obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                  size: 18,
                  color: const Color(0xFF9E9E9E)),
              onPressed: onToggle,
            ),
          ),
        ),
      ],
    );
  }
}
