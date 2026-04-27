import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart'; // ignore: unused_import
import 'package:image_picker/image_picker.dart'; // ignore: unused_import
import 'dart:typed_data'; // ignore: unused_import
import '../../core/utils/firestore_keys.dart';
import '../login/login_intro_page.dart';

class InstructorProfilePage extends StatefulWidget {
  const InstructorProfilePage({super.key});

  @override
  State<InstructorProfilePage> createState() => _InstructorProfilePageState();
}

class _InstructorProfilePageState extends State<InstructorProfilePage> {
  static const Color _blue = Color(0xFF1565C0);
  final _db = FirebaseFirestore.instance;
  final _formKey = GlobalKey<FormState>();

  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();

  String _email = '';
  String _photoUrl = '';
  String _uid = '';
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isUploadingPhoto = false;

  @override
  void initState() {
    super.initState();
    _uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    _loadProfile();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    if (_uid.isEmpty) return;
    final doc = await _db.collection(FsCol.users).doc(_uid).get();
    if (!mounted) return;
    final data = doc.data() ?? {};
    setState(() {
      _email = data[FsUser.email] as String? ?? '';
      _nameCtrl.text = data[FsUser.name] as String? ?? '';
      _phoneCtrl.text = data[FsUser.phone] as String? ?? '';
      _bioCtrl.text = data[FsUser.bio] as String? ?? '';
      _photoUrl = data[FsUser.photoUrl] as String? ?? '';
      _isLoading = false;
    });
  }

  Future<void> _pickAndUploadPhoto() async {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        content: const Text('차후 업데이트 예정입니다'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('확인'),
          ),
        ],
      ),
    );
    // final picker = ImagePicker();
    // final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    // if (picked == null) return;
    // setState(() => _isUploadingPhoto = true);
    // try {
    //   final Uint8List bytes = await picked.readAsBytes();
    //   final ref = FirebaseStorage.instance.ref(StoragePath.profilePhotoPath(_uid));
    //   await ref.putData(bytes);
    //   final url = await ref.getDownloadURL();
    //   await _db.collection(FsCol.users).doc(_uid).update({FsUser.photoUrl: url});
    //   if (!mounted) return;
    //   setState(() {
    //     _photoUrl = url;
    //     _isUploadingPhoto = false;
    //   });
    // } catch (e) {
    //   if (!mounted) return;
    //   setState(() => _isUploadingPhoto = false);
    //   ScaffoldMessenger.of(context).showSnackBar(
    //     SnackBar(content: Text('사진 업로드 실패: $e'), backgroundColor: Colors.red),
    //   );
    // }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      await _db.collection(FsCol.users).doc(_uid).update({
        FsUser.name: _nameCtrl.text.trim(),
        FsUser.phone: _phoneCtrl.text.trim(),
        FsUser.bio: _bioCtrl.text.trim(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('저장되었습니다.')),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('저장 실패: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // 교사(INSTRUCTOR) 전용 — 비밀번호 변경 바텀시트
  Future<void> _showPasswordChangeSheet() async {
    final currentPwCtrl = TextEditingController();
    final newPwCtrl = TextEditingController();
    final confirmPwCtrl = TextEditingController();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        bool obscureCurrent = true;
        bool obscureNew = true;
        bool obscureConfirm = true;
        String? errorMsg;
        bool isLoading = false;

        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            Future<void> validate() async {
              final newPw = newPwCtrl.text.trim();
              final confirmPw = confirmPwCtrl.text.trim();

              if (currentPwCtrl.text.trim().isEmpty) {
                setSheetState(() => errorMsg = '현재 비밀번호를 입력하세요.');
                return;
              }
              if (newPw.length < 8) {
                setSheetState(() => errorMsg = '비밀번호는 8자 이상이어야 합니다.');
                return;
              }
              if (!RegExp(r'[A-Z]').hasMatch(newPw)) {
                setSheetState(() => errorMsg = '대문자를 포함해야 합니다.');
                return;
              }
              if (!RegExp(r'[!@#\$%^&*(),.?":{}|<>_\-+=\[\]\\\/]').hasMatch(newPw)) {
                setSheetState(() => errorMsg = '특수문자를 포함해야 합니다.');
                return;
              }
              if (newPw != confirmPw) {
                setSheetState(() => errorMsg = '새 비밀번호가 일치하지 않습니다.');
                return;
              }

              setSheetState(() => isLoading = true);
              try {
                final user = FirebaseAuth.instance.currentUser!;
                await user.reauthenticateWithCredential(
                  EmailAuthProvider.credential(
                    email: user.email!,
                    password: currentPwCtrl.text.trim(),
                  ),
                );
                await user.updatePassword(newPw);
                await FirebaseAuth.instance.signOut();
                if (!mounted) return;
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginIntroPage()),
                  (_) => false,
                );
              } on FirebaseAuthException catch (e) {
                setSheetState(() {
                  isLoading = false;
                  errorMsg = e.code == 'wrong-password'
                      ? '현재 비밀번호가 올바르지 않습니다.'
                      : '오류: ${e.message}';
                });
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 24,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('비밀번호 변경',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 16),

                  Semantics(
                    label: '현재 비밀번호 입력란',
                    child: TextField(
                      controller: currentPwCtrl,
                      obscureText: obscureCurrent,
                      decoration: InputDecoration(
                        labelText: '현재 비밀번호',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(obscureCurrent ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setSheetState(() => obscureCurrent = !obscureCurrent),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  Semantics(
                    label: '새 비밀번호 입력란',
                    child: TextField(
                      controller: newPwCtrl,
                      obscureText: obscureNew,
                      decoration: InputDecoration(
                        labelText: '새 비밀번호',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(obscureNew ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setSheetState(() => obscureNew = !obscureNew),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '※ 비밀번호는 대문자, 특수문자 포함 8자리 입니다',
                    style: TextStyle(color: Colors.red, fontSize: 12),
                  ),
                  const SizedBox(height: 12),

                  Semantics(
                    label: '새 비밀번호 확인 입력란',
                    child: TextField(
                      controller: confirmPwCtrl,
                      obscureText: obscureConfirm,
                      decoration: InputDecoration(
                        labelText: '새 비밀번호 확인',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(obscureConfirm ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setSheetState(() => obscureConfirm = !obscureConfirm),
                        ),
                      ),
                    ),
                  ),

                  if (errorMsg != null) ...[
                    const SizedBox(height: 8),
                    Text(errorMsg!,
                        style: const TextStyle(color: Colors.red, fontSize: 13)),
                  ],
                  const SizedBox(height: 16),

                  ElevatedButton(
                    onPressed: isLoading ? null : validate,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: _blue, foregroundColor: Colors.white),
                    child: isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('변경 완료'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    currentPwCtrl.dispose();
    newPwCtrl.dispose();
    confirmPwCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      appBar: AppBar(
        backgroundColor: _blue,
        foregroundColor: Colors.white,
        title: const Text('마이페이지',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        elevation: 0,
        actions: [
          Semantics(
            label: '저장 버튼',
            button: true,
            child: TextButton(
              onPressed: _isSaving ? null : _save,
              child: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('저장',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15)),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    // 프로필 사진
                    Semantics(
                      label: '프로필 사진 변경 버튼',
                      button: true,
                      child: GestureDetector(
                        onTap: _isUploadingPhoto ? null : _pickAndUploadPhoto,
                        child: Stack(
                          alignment: Alignment.bottomRight,
                          children: [
                            CircleAvatar(
                              radius: 48,
                              backgroundColor: Colors.grey.shade200,
                              backgroundImage: _photoUrl.isNotEmpty
                                  ? NetworkImage(_photoUrl)
                                  : null,
                              child: _isUploadingPhoto
                                  ? const CircularProgressIndicator()
                                  : (_photoUrl.isEmpty
                                      ? const Icon(Icons.person_rounded,
                                          size: 48, color: Colors.grey)
                                      : null),
                            ),
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: const BoxDecoration(
                                  color: _blue, shape: BoxShape.circle),
                              child: const Icon(Icons.camera_alt_rounded,
                                  color: Colors.white, size: 16),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // 이메일(ID) — Read-only
                    Semantics(
                      label: '이메일(ID): $_email, 수정 불가',
                      child: TextFormField(
                        initialValue: _email,
                        readOnly: true,
                        decoration: InputDecoration(
                          labelText: '이메일(ID)',
                          filled: true,
                          fillColor: Colors.grey.shade100,
                          border: const OutlineInputBorder(),
                          suffixIcon: const Tooltip(
                            message: '이메일은 수정할 수 없습니다.',
                            child: Icon(Icons.lock_rounded, color: Colors.grey),
                          ),
                        ),
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 이름
                    Semantics(
                      label: '이름 입력란',
                      child: TextFormField(
                        controller: _nameCtrl,
                        decoration: const InputDecoration(
                          labelText: '이름',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? '이름을 입력하세요.' : null,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 전화번호
                    Semantics(
                      label: '전화번호 입력란',
                      child: TextFormField(
                        controller: _phoneCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: '전화번호',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 자기소개
                    Semantics(
                      label: '자기소개 입력란',
                      child: TextFormField(
                        controller: _bioCtrl,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: '자기소개',
                          border: OutlineInputBorder(),
                          alignLabelWithHint: true,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 교사(INSTRUCTOR) 전용 — 비밀번호 변경
                    Semantics(
                      label: '비밀번호 변경하기 버튼',
                      button: true,
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: _showPasswordChangeSheet,
                          child: const Text('비밀번호 변경하기'),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
    );
  }
}
