import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';
import '../../core/utils/firestore_keys.dart';

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
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked == null) return;
    setState(() => _isUploadingPhoto = true);
    try {
      final Uint8List bytes = await picked.readAsBytes();
      final ref = FirebaseStorage.instance.ref(StoragePath.profilePhotoPath(_uid));
      await ref.putData(bytes);
      final url = await ref.getDownloadURL();
      await _db.collection(FsCol.users).doc(_uid).update({FsUser.photoUrl: url});
      if (!mounted) return;
      setState(() {
        _photoUrl = url;
        _isUploadingPhoto = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUploadingPhoto = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('사진 업로드 실패: $e'), backgroundColor: Colors.red),
      );
    }
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
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
    );
  }
}
