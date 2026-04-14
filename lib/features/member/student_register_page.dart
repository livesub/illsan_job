import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/utils/firestore_keys.dart';

class StudentRegisterPage extends StatefulWidget {
  // SNS 가입 시 loginType = 'google' 등 전달, 기본값 'email'
  final String loginType;
  const StudentRegisterPage({super.key, this.loginType = FsUser.loginTypeEmail});

  @override
  State<StudentRegisterPage> createState() => _StudentRegisterPageState();
}

class _StudentRegisterPageState extends State<StudentRegisterPage> {
  static const Color _blue     = Color(0xFF1565C0);
  static const Color _textDark = Color(0xFF1A1A2E);
  static const Color _textGray = Color(0xFF757575);

  final _formKey    = GlobalKey<FormState>();
  final _nameCtrl   = TextEditingController();
  final _emailCtrl  = TextEditingController();
  final _pwCtrl     = TextEditingController();
  final _phoneCtrl  = TextEditingController();

  bool _isLoading   = false;
  bool _obscurePw   = true;

  // 강좌 Selectbox 데이터
  List<Map<String, String>> _courses = [];
  String? _selectedCourseId;

  bool get _isEmailLogin => widget.loginType == FsUser.loginTypeEmail;

  @override
  void initState() {
    super.initState();
    _loadCourses();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _pwCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  // 활성 강좌 목록 조회
  Future<void> _loadCourses() async {
    final snap = await FirebaseFirestore.instance
        .collection(FsCol.courses)
        .where(FsCourse.status, isEqualTo: FsCourse.statusActive)
        .get();
    if (!mounted) return;
    setState(() {
      _courses = snap.docs
          .map((d) => {'id': d.id, 'name': d.data()[FsCourse.name] as String? ?? ''})
          .toList();
    });
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCourseId == null) {
      _showError('소속 반을 선택해 주세요.');
      return;
    }
    setState(() => _isLoading = true);
    try {
      // 이메일 중복 검사 — 수료/중도퇴소 포함 전체 조회
      final dupSnap = await FirebaseFirestore.instance
          .collection(FsCol.users)
          .where(FsUser.email, isEqualTo: _emailCtrl.text.trim())
          .limit(1)
          .get();
      if (dupSnap.docs.isNotEmpty) {
        if (!mounted) return;
        _showError('이미 가입된 이메일입니다. 관리자에게 문의하세요.');
        return;
      }

      // Firebase Auth 계정 생성
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _isEmailLogin ? _pwCtrl.text : _generateTempPw(),
      );
      final uid = cred.user!.uid;

      // Firestore users 문서 등록 (status=pending, 관리자 승인 대기)
      await FirebaseFirestore.instance.collection(FsCol.users).doc(uid).set({
        FsUser.name:       _nameCtrl.text.trim(),
        FsUser.email:      _emailCtrl.text.trim(),
        FsUser.phone:      _phoneCtrl.text.trim(),
        FsUser.role:       FsUser.roleStudent,
        FsUser.status:     FsUser.statusPending,
        FsUser.courseId:   _selectedCourseId,
        FsUser.loginType:  widget.loginType,
        FsUser.isTempPw:   false,
        FsUser.isDeleted:  false,
        FsUser.createdAt:  StoragePath.nowCreatedAt(),
      });

      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      _showSuccess();
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      _showError(_authError(e.code));
    } catch (e) {
      if (!mounted) return;
      _showError('가입 실패: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // SNS 가입 시 Auth 계정 생성을 위한 내부용 임시 PW
  String _generateTempPw() => 'Temp!${DateTime.now().millisecondsSinceEpoch}';

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  void _showSuccess() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('가입 신청 완료'),
        content: const Text('회원가입 신청이 완료되었습니다.\n관리자 승인 후 로그인하실 수 있습니다.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop();
            },
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  String _authError(String code) {
    switch (code) {
      case 'email-already-in-use':
        return '이미 사용 중인 이메일입니다.';
      case 'invalid-email':
        return '유효하지 않은 이메일 형식입니다.';
      case 'weak-password':
        return '비밀번호가 너무 간단합니다.';
      default:
        return '회원가입 중 오류가 발생했습니다.';
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
              '학생 회원 가입',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: _textDark),
            ),
            centerTitle: true,
          ),
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 32),

                          // 소속 반
                          _label('소속 반'),
                          const SizedBox(height: 8),
                          Semantics(
                            label: '소속 반 선택 목록입니다. 필수 항목입니다.',
                            child: DropdownButtonFormField<String>(
                              value: _selectedCourseId,
                              hint: const Text('반을 선택해 주세요.'),
                              decoration: _inputDeco('', Icons.class_outlined),
                              items: _courses.map((c) => DropdownMenuItem(
                                value: c['id'],
                                child: Text(c['name']!),
                              )).toList(),
                              onChanged: _isLoading
                                  ? null
                                  : (v) => setState(() => _selectedCourseId = v),
                            ),
                          ),
                          const SizedBox(height: 20),

                          // 이름
                          _label('이름'),
                          const SizedBox(height: 8),
                          Semantics(
                            label: '이름 입력란입니다. 필수 항목입니다.',
                            child: TextFormField(
                              controller: _nameCtrl,
                              textInputAction: TextInputAction.next,
                              enabled: !_isLoading,
                              decoration: _inputDeco('이름을 입력해 주세요.', Icons.person_outline),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) return '이름을 입력해 주세요.';
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(height: 20),

                          // 이메일
                          _label('이메일(ID)'),
                          const SizedBox(height: 8),
                          Semantics(
                            label: '이메일 입력란입니다. 필수 항목입니다.',
                            child: TextFormField(
                              controller: _emailCtrl,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              enabled: !_isLoading,
                              decoration: _inputDeco('example@email.com', Icons.email_outlined),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) return '이메일을 입력해 주세요.';
                                if (!RegExp(r'^[\w\.\+\-]+@[\w\-]+\.[a-zA-Z]{2,}$').hasMatch(v.trim())) {
                                  return '올바른 이메일 형식이 아닙니다.';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(height: 20),

                          // 비밀번호 — SNS 가입 시 숨김
                          if (_isEmailLogin) ...[
                            _label('비밀번호'),
                            const SizedBox(height: 8),
                            Semantics(
                              label: '비밀번호 입력란입니다. 필수 항목입니다.',
                              child: TextFormField(
                                controller: _pwCtrl,
                                obscureText: _obscurePw,
                                textInputAction: TextInputAction.next,
                                enabled: !_isLoading,
                                decoration: _inputDeco(
                                  '비밀번호를 입력해 주세요.',
                                  Icons.lock_outline_rounded,
                                ).copyWith(
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
                                      onPressed: () => setState(() => _obscurePw = !_obscurePw),
                                    ),
                                  ),
                                ),
                                validator: (v) {
                                  if (v == null || v.isEmpty) return '비밀번호를 입력해 주세요.';
                                  if (v.length < 8) return '8자 이상 입력해 주세요.';
                                  if (!RegExp(r'[A-Z]').hasMatch(v)) return '대문자를 1자 이상 포함해야 합니다.';
                                  if (!RegExp(r'''[!@#\$%^&*()\-_=+\[\]{};:\'",.<>?/\\|`~]''').hasMatch(v)) {
                                    return '특수문자를 1자 이상 포함해야 합니다.';
                                  }
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(height: 20),
                          ],

                          // 전화번호
                          _label('전화번호'),
                          const SizedBox(height: 8),
                          Semantics(
                            label: '전화번호 입력란입니다.',
                            child: TextFormField(
                              controller: _phoneCtrl,
                              keyboardType: TextInputType.number,
                              textInputAction: TextInputAction.done,
                              enabled: !_isLoading,
                              decoration: _inputDeco('전화번호를 입력해 주세요.', Icons.phone_outlined),
                            ),
                          ),
                          const SizedBox(height: 32),

                          // 가입 신청 버튼
                          Semantics(
                            label: '가입 신청 버튼입니다.',
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
                                  disabledBackgroundColor: _blue.withValues(alpha: 0.6),
                                ),
                                onPressed: _isLoading ? null : _register,
                                child: const Text('가입 신청',
                                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
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
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    child: const Text(
                      '비밀번호를 잊으셨나요?\n관리자에게 비밀번호 초기화를 요청하시면 임시 비밀번호를 안내해 드립니다.',
                      style: TextStyle(fontSize: 13, color: _blue, height: 1.6),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // 로딩 오버레이
        if (_isLoading) ...[
          const ModalBarrier(dismissible: false, color: Colors.black26),
          const Center(child: CircularProgressIndicator(color: _blue)),
        ],
      ],
    );
  }

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _textDark),
      );

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
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      );
}
