import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/utils/firestore_keys.dart';

class MemberTab extends StatefulWidget {
  const MemberTab({super.key});

  @override
  State<MemberTab> createState() => _MemberTabState();
}

class _MemberTabState extends State<MemberTab> {
  static const Color _blue = Color(0xFF1565C0);

  List<Map<String, String>> _courses = [];
  List<QueryDocumentSnapshot> _teachers = [];
  bool _teachersLoading = false;

  @override
  void initState() {
    super.initState();
    _loadCourses();
    _loadTeachers();
  }

  Future<void> _loadCourses() async {
    final snap = await FirebaseFirestore.instance
        .collection(FsCol.courses)
        .where(FsCourse.status, isEqualTo: FsCourse.statusActive)
        .orderBy(FsCourse.name)
        .get();
    if (!mounted) return;
    setState(() {
      _courses = snap.docs.map((d) => {
        'id': d.id,
        'name': (d.data()[FsCourse.name] ?? '') as String,
      }).toList();
    });
  }

  Future<void> _loadTeachers() async {
    setState(() => _teachersLoading = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection(FsCol.users)
          .where(FsUser.role, isEqualTo: FsUser.roleInstructor)
          .orderBy(FsUser.name)
          .get();
      if (!mounted) return;
      final docs = snap.docs.where((d) {
        final data = d.data() as Map<String, dynamic>;
        return data[FsUser.isDeleted] != true;
      }).toList();
      setState(() {
        _teachers = docs;
        _teachersLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _teachersLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            color: Colors.white,
            child: const TabBar(
              labelColor: _blue,
              unselectedLabelColor: Color(0xFF757575),
              indicatorColor: _blue,
              indicatorWeight: 3,
              labelStyle: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              unselectedLabelStyle: TextStyle(fontSize: 15, fontWeight: FontWeight.w400),
              tabs: [
                Tab(text: '교사 리스트'),
                Tab(text: '학생 리스트(강좌별)'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildTeacherTab(),
                _buildStudentTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTeacherTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('교사 리스트',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF1A1A2E))),
                    SizedBox(height: 4),
                    Text('등록된 교사 목록을 조회합니다.',
                        style: TextStyle(fontSize: 14, color: Color(0xFF757575))),
                  ],
                ),
              ),
              Semantics(
                label: '교사 등록 버튼입니다.',
                child: ElevatedButton.icon(
                  onPressed: () async {
                    await showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => _TeacherRegisterDialog(courses: _courses),
                    );
                    _loadTeachers();
                  },
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('교사 등록'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _blue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 4))],
            ),
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: const BoxDecoration(
                    color: _blue,
                    borderRadius: BorderRadius.only(topLeft: Radius.circular(14), topRight: Radius.circular(14)),
                  ),
                  child: Text('교사 목록 (${_teachers.length}명)',
                      style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                ),
                if (_teachersLoading)
                  const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
                else if (_teachers.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('등록된 교사가 없습니다.', style: TextStyle(color: Color(0xFF757575))),
                  )
                else
                  Column(children: _teachers.map(_buildTeacherTile).toList()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTeacherTile(QueryDocumentSnapshot doc) {
    final data     = doc.data() as Map<String, dynamic>;
    final name     = (data[FsUser.name]     as String?) ?? '이름 없음';
    final email    = (data[FsUser.email]    as String?) ?? '';
    final phone    = (data[FsUser.phone]    as String?) ?? '';
    final photoUrl = (data[FsUser.photoUrl] as String?) ?? '';

    return Semantics(
      label: '$name 교사 항목입니다. 클릭하면 정보를 수정합니다.',
      child: InkWell(
        onTap: () async {
          await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => _TeacherEditDialog(doc: doc, courses: _courses),
          );
          _loadTeachers();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0)))),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: _blue.withValues(alpha: 0.12),
                backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                child: photoUrl.isEmpty
                    ? const Icon(Icons.person_rounded, color: _blue, size: 22)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    Text('$email${phone.isNotEmpty ? ' · $phone' : ''}',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF757575)),
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFFBDBDBD), size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStudentTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('학생 리스트',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF1A1A2E))),
          const SizedBox(height: 4),
          const Text('강좌별 학생 목록을 조회합니다.',
              style: TextStyle(fontSize: 14, color: Color(0xFF757575))),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 4))],
            ),
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: const BoxDecoration(
                    color: _blue,
                    borderRadius: BorderRadius.only(topLeft: Radius.circular(14), topRight: Radius.circular(14)),
                  ),
                  child: const Text('학생 목록 (강좌별)',
                      style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                ),
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: Text('등록된 학생이 없습니다.', style: TextStyle(color: Color(0xFF757575)))),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── 교사 등록 다이얼로그 ──────────────────────────────────────
class _TeacherRegisterDialog extends StatefulWidget {
  final List<Map<String, String>> courses;
  const _TeacherRegisterDialog({required this.courses});

  @override
  State<_TeacherRegisterDialog> createState() => _TeacherRegisterDialogState();
}

class _TeacherRegisterDialogState extends State<_TeacherRegisterDialog> {
  static const Color _blue = Color(0xFF1565C0);

  final _formKey       = GlobalKey<FormState>();
  final _nameCtrl      = TextEditingController();
  final _phoneCtrl     = TextEditingController();
  final _emailCtrl     = TextEditingController();
  final _pwCtrl        = TextEditingController();
  final _pwCfmCtrl     = TextEditingController();
  final _bioCtrl       = TextEditingController();

  PlatformFile? _photoFile;
  bool _isLoading    = false;
  bool _obscurePw    = true;
  bool _obscurePwCfm = true;

  @override
  void dispose() {
    _nameCtrl.dispose(); _phoneCtrl.dispose(); _emailCtrl.dispose();
    _pwCtrl.dispose();   _pwCfmCtrl.dispose(); _bioCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    if (result == null || result.files.isEmpty) return;
    setState(() => _photoFile = result.files.first);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _pwCtrl.text,
      );
      final uid = cred.user!.uid;

      String photoUrl = '';
      if (_photoFile?.bytes != null) {
        final ref = FirebaseStorage.instance.ref(StoragePath.profilePhotoPath(uid));
        await ref.putData(_photoFile!.bytes!, SettableMetadata(contentType: 'image/jpeg'));
        photoUrl = await ref.getDownloadURL();
      }

      await FirebaseFirestore.instance.collection(FsCol.users).doc(uid).set({
        FsUser.name:      _nameCtrl.text.trim(),
        FsUser.email:     _emailCtrl.text.trim(),
        FsUser.phone:     _phoneCtrl.text.trim(),
        FsUser.bio:       _bioCtrl.text.trim(),
        FsUser.role:      FsUser.roleInstructor,
        FsUser.status:    FsUser.statusApproved,
        FsUser.isDeleted: false,
        FsUser.isTempPw:  false,
        FsUser.loginType: FsUser.loginTypeEmail,
        FsUser.photoUrl:  photoUrl,
        FsUser.createdAt: FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('교사가 등록되었습니다.')),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_authError(e.code)), backgroundColor: Colors.red),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('등록 실패: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _authError(String code) {
    switch (code) {
      case 'email-already-in-use': return '이미 사용 중인 이메일입니다.';
      case 'invalid-email':        return '올바른 이메일 형식이 아닙니다.';
      case 'weak-password':        return '비밀번호는 6자 이상이어야 합니다.';
      default:                     return '계정 생성 중 오류가 발생했습니다.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('교사 등록',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: GestureDetector(
                        onTap: _pickPhoto,
                        child: Semantics(
                          label: '프로필 사진 선택 버튼입니다.',
                          child: CircleAvatar(
                            radius: 40,
                            backgroundColor: const Color(0xFFE3F2FD),
                            backgroundImage: _photoFile?.bytes != null
                                ? MemoryImage(_photoFile!.bytes!)
                                : null,
                            child: _photoFile == null
                                ? const Icon(Icons.add_a_photo_rounded, color: _blue, size: 28)
                                : null,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _field('이름', _nameCtrl,
                        validator: (v) => (v == null || v.trim().isEmpty) ? '이름을 입력해 주세요.' : null),
                    const SizedBox(height: 14),
                    _field('전화번호', _phoneCtrl, keyboardType: TextInputType.phone,
                        validator: (v) => (v == null || v.trim().isEmpty) ? '전화번호를 입력해 주세요.' : null),
                    const SizedBox(height: 14),
                    _field('이메일', _emailCtrl, keyboardType: TextInputType.emailAddress,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return '이메일을 입력해 주세요.';
                          if (!v.contains('@')) return '올바른 이메일 형식이 아닙니다.';
                          return null;
                        }),
                    const SizedBox(height: 14),
                    _pwField('비밀번호', _pwCtrl, _obscurePw,
                        () => setState(() => _obscurePw = !_obscurePw),
                        validator: (v) {
                          if (v == null || v.isEmpty) return '비밀번호를 입력해 주세요.';
                          if (v.length < 6) return '6자 이상 입력해 주세요.';
                          return null;
                        }),
                    const SizedBox(height: 14),
                    _pwField('비밀번호 확인', _pwCfmCtrl, _obscurePwCfm,
                        () => setState(() => _obscurePwCfm = !_obscurePwCfm),
                        validator: (v) => v != _pwCtrl.text ? '비밀번호가 일치하지 않습니다.' : null),
                    const SizedBox(height: 14),
                    _field('쓰고 싶은 말', _bioCtrl, maxLines: 3, required: false),
                    const SizedBox(height: 24),
                    Semantics(
                      label: '교사 등록 완료 버튼입니다.',
                      child: SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _blue,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: _isLoading ? null : _submit,
                          child: const Text('등록', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_isLoading) ...[
              const ModalBarrier(dismissible: false, color: Colors.black26),
              const Center(child: CircularProgressIndicator(color: _blue)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl, {
    TextInputType? keyboardType,
    int maxLines = 1,
    bool required = true,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E))),
        const SizedBox(height: 6),
        TextFormField(
          controller: ctrl,
          keyboardType: keyboardType,
          maxLines: maxLines,
          decoration: _deco(),
          validator: validator ?? (required
              ? (v) => (v == null || v.trim().isEmpty) ? '$label을(를) 입력해 주세요.' : null
              : null),
        ),
      ],
    );
  }

  Widget _pwField(String label, TextEditingController ctrl, bool obscure,
      VoidCallback toggle, {String? Function(String?)? validator}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E))),
        const SizedBox(height: 6),
        TextFormField(
          controller: ctrl,
          obscureText: obscure,
          decoration: _deco().copyWith(
            suffixIcon: IconButton(
              icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  size: 20, color: const Color(0xFF757575)),
              onPressed: toggle,
            ),
          ),
          validator: validator,
        ),
      ],
    );
  }

  InputDecoration _deco() => InputDecoration(
    filled: true,
    fillColor: const Color(0xFFF8F9FA),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _blue, width: 2)),
    errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.red)),
    focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.red, width: 2)),
  );
}

// ── 교사 정보 수정 다이얼로그 ────────────────────────────────
class _TeacherEditDialog extends StatefulWidget {
  final QueryDocumentSnapshot doc;
  final List<Map<String, String>> courses;
  const _TeacherEditDialog({required this.doc, required this.courses});

  @override
  State<_TeacherEditDialog> createState() => _TeacherEditDialogState();
}

class _TeacherEditDialogState extends State<_TeacherEditDialog> {
  static const Color _blue = Color(0xFF1565C0);

  final _formKey   = GlobalKey<FormState>();
  final _nameCtrl  = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _bioCtrl   = TextEditingController();

  PlatformFile? _newPhotoFile;
  String _existPhotoUrl = '';
  List<String> _assignedCourseIds = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final data = widget.doc.data() as Map<String, dynamic>;
    _nameCtrl.text  = (data[FsUser.name]     as String?) ?? '';
    _phoneCtrl.text = (data[FsUser.phone]    as String?) ?? '';
    _bioCtrl.text   = (data[FsUser.bio]      as String?) ?? '';
    _existPhotoUrl  = (data[FsUser.photoUrl] as String?) ?? '';
    _loadAssignedCourses();
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _phoneCtrl.dispose(); _bioCtrl.dispose();
    super.dispose();
  }

  // 이 교사에게 현재 배정된 강좌 ID 목록을 로드합니다.
  Future<void> _loadAssignedCourses() async {
    final snap = await FirebaseFirestore.instance
        .collection(FsCol.courses)
        .where(FsCourse.teacherId, isEqualTo: widget.doc.id)
        .get();
    if (!mounted) return;
    setState(() {
      _assignedCourseIds = snap.docs.map((d) => d.id).toList();
    });
  }

  Future<void> _pickPhoto() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    if (result == null || result.files.isEmpty) return;
    setState(() => _newPhotoFile = result.files.first);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final uid = widget.doc.id;
      final teacherName = _nameCtrl.text.trim();
      String photoUrl = _existPhotoUrl;

      if (_newPhotoFile?.bytes != null) {
        final ref = FirebaseStorage.instance.ref(StoragePath.profilePhotoPath(uid));
        await ref.putData(_newPhotoFile!.bytes!, SettableMetadata(contentType: 'image/jpeg'));
        photoUrl = await ref.getDownloadURL();
      }

      await FirebaseFirestore.instance.collection(FsCol.users).doc(uid).update({
        FsUser.name:     teacherName,
        FsUser.phone:    _phoneCtrl.text.trim(),
        FsUser.bio:      _bioCtrl.text.trim(),
        FsUser.photoUrl: photoUrl,
      });

      // 강좌 배정 batch 업데이트
      final batch = FirebaseFirestore.instance.batch();
      final prevSnap = await FirebaseFirestore.instance
          .collection(FsCol.courses)
          .where(FsCourse.teacherId, isEqualTo: uid)
          .get();
      for (final d in prevSnap.docs) {
        if (!_assignedCourseIds.contains(d.id)) {
          batch.update(d.reference, {FsCourse.teacherId: '', FsCourse.teacherName: ''});
        }
      }
      for (final courseId in _assignedCourseIds) {
        batch.update(
          FirebaseFirestore.instance.collection(FsCol.courses).doc(courseId),
          {FsCourse.teacherId: uid, FsCourse.teacherName: teacherName},
        );
      }
      await batch.commit();

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('정보가 수정되었습니다.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('수정 실패: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 임시 비밀번호 생성 → Firestore 업데이트 → Cloud Function이 Auth에 반영합니다.
  Future<void> _resetPassword() async {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789';
    final rand   = Random.secure();
    final tempPw = List.generate(8, (_) => chars[rand.nextInt(chars.length)]).join();

    setState(() => _isLoading = true);
    try {
      await FirebaseFirestore.instance.collection(FsCol.users).doc(widget.doc.id).update({
        FsUser.isTempPw:    true,
        FsUser.tempPwPlain: tempPw,
        FsUser.tempPwAt:    FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: const Text('임시 비밀번호 발급'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('아래 임시 비밀번호를 교사에게 전달하세요.\n교사는 첫 로그인 후 비밀번호를 변경해야 합니다.',
                  style: TextStyle(fontSize: 14)),
              const SizedBox(height: 16),
              SelectableText(tempPw,
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800,
                      letterSpacing: 3, color: _blue)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('확인')),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('초기화 실패: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('교사 정보 수정',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: GestureDetector(
                        onTap: _pickPhoto,
                        child: Semantics(
                          label: '프로필 사진 변경 버튼입니다.',
                          child: Stack(
                            children: [
                              CircleAvatar(
                                radius: 40,
                                backgroundColor: const Color(0xFFE3F2FD),
                                backgroundImage: _newPhotoFile?.bytes != null
                                    ? MemoryImage(_newPhotoFile!.bytes!) as ImageProvider
                                    : (_existPhotoUrl.isNotEmpty
                                        ? NetworkImage(_existPhotoUrl)
                                        : null),
                                child: (_newPhotoFile == null && _existPhotoUrl.isEmpty)
                                    ? const Icon(Icons.person_rounded, color: _blue, size: 36)
                                    : null,
                              ),
                              Positioned(
                                bottom: 0, right: 0,
                                child: Container(
                                  width: 24, height: 24,
                                  decoration: const BoxDecoration(color: _blue, shape: BoxShape.circle),
                                  child: const Icon(Icons.edit_rounded, color: Colors.white, size: 14),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _field('이름', _nameCtrl,
                        validator: (v) => (v == null || v.trim().isEmpty) ? '이름을 입력해 주세요.' : null),
                    const SizedBox(height: 14),
                    _field('전화번호', _phoneCtrl, keyboardType: TextInputType.phone),
                    const SizedBox(height: 14),
                    _field('쓰고 싶은 말', _bioCtrl, maxLines: 3, required: false),
                    const SizedBox(height: 20),

                    // 반 배정 멀티 선택
                    const Text('반 배정',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E))),
                    const SizedBox(height: 8),
                    widget.courses.isEmpty
                        ? const Text('등록된 강좌가 없습니다.',
                            style: TextStyle(fontSize: 13, color: Color(0xFF757575)))
                        : Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: const Color(0xFFE0E0E0)),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                              children: widget.courses.map((c) {
                                final isSelected = _assignedCourseIds.contains(c['id']);
                                return Semantics(
                                  label: '${c['name']} 반 배정 체크박스입니다.',
                                  checked: isSelected,
                                  child: CheckboxListTile(
                                    dense: true,
                                    title: Text(c['name']!, style: const TextStyle(fontSize: 14)),
                                    value: isSelected,
                                    activeColor: _blue,
                                    onChanged: (checked) {
                                      setState(() {
                                        if (checked == true) {
                                          _assignedCourseIds.add(c['id']!);
                                        } else {
                                          _assignedCourseIds.remove(c['id']!);
                                        }
                                      });
                                    },
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                    const SizedBox(height: 16),

                    // 비밀번호 초기화
                    Semantics(
                      label: '비밀번호 초기화 버튼입니다.',
                      child: OutlinedButton.icon(
                        onPressed: _isLoading ? null : _resetPassword,
                        icon: const Icon(Icons.lock_reset_rounded, size: 18),
                        label: const Text('비밀번호 초기화'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFD32F2F),
                          side: const BorderSide(color: Color(0xFFD32F2F)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Semantics(
                      label: '교사 정보 저장 버튼입니다.',
                      child: SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _blue,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: _isLoading ? null : _save,
                          child: const Text('저장', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_isLoading) ...[
              const ModalBarrier(dismissible: false, color: Colors.black26),
              const Center(child: CircularProgressIndicator(color: _blue)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl, {
    TextInputType? keyboardType,
    int maxLines = 1,
    bool required = true,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E))),
        const SizedBox(height: 6),
        TextFormField(
          controller: ctrl,
          keyboardType: keyboardType,
          maxLines: maxLines,
          decoration: _deco(),
          validator: validator ?? (required
              ? (v) => (v == null || v.trim().isEmpty) ? '$label을(를) 입력해 주세요.' : null
              : null),
        ),
      ],
    );
  }

  InputDecoration _deco() => InputDecoration(
    filled: true,
    fillColor: const Color(0xFFF8F9FA),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _blue, width: 2)),
    errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.red)),
    focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.red, width: 2)),
  );
}
