// 교사 목록 + 교사 등록/수정/삭제 탭입니다. (SUPER_ADMIN 전용)
//
// 기능:
//   - 교사 목록 조회 (이름 검색 + 페이징)
//   - 교사 신규 등록 (7개 필드 + 이메일 중복확인)
//   - 교사 정보 수정 (기본정보 + 사진 + 비밀번호 초기화)
//   - 교사 삭제 방어 로직:
//       ① 진행 중 강좌 존재 여부 체크
//       ② 대기 학생 존재 여부 체크
//       → 연관 데이터 있으면 원클릭 인수인계 팝업 표시
//       → 없으면 일반 삭제 확인 후 Soft Delete
//   - 원클릭 인수인계 (Firestore 트랜잭션):
//       ① 진행 중 강좌의 teacher_id를 새 교사로 일괄 변경
//       ② 기존 교사 is_deleted: true 처리
//       ③ [8단계] Cloud Functions으로 Firebase Auth 계정 비활성화
//
// 데이터 로드 전략:
//   - 활성 교사 전체를 Firestore에서 로드 (최대 200명)
//   - 이름 검색은 클라이언트에서 처리
//   - 페이징도 클라이언트에서 처리
//   → course_tab.dart와 동일한 전략 (인덱스 부담 없음)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/utils/firestore_keys.dart';

// ─────────────────────────────────────────────────────────
// 교사 목록 탭
// ─────────────────────────────────────────────────────────
class TeacherTab extends StatefulWidget {
  const TeacherTab({super.key});

  @override
  State<TeacherTab> createState() => _TeacherTabState();
}

class _TeacherTabState extends State<TeacherTab> {
  static const int _pageSize = 10;
  static const Color _blue = Color(0xFF1565C0);

  // Firestore에서 로드한 전체 활성 교사 목록
  List<QueryDocumentSnapshot> _allTeachers = [];

  // 검색 적용 후 교사 목록
  List<QueryDocumentSnapshot> _filteredTeachers = [];

  // 현재 페이지에 표시할 교사 목록
  List<QueryDocumentSnapshot> _pagedTeachers = [];

  final TextEditingController _searchCtrl = TextEditingController();
  int _currentPage = 1;
  bool _hasMore = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadAllTeachers();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // 활성 교사 전체를 Firestore에서 로드합니다.
  Future<void> _loadAllTeachers() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      final snap = await FirebaseFirestore.instance
          .collection(FsCol.users)
          .where(FsUser.role, isEqualTo: FsUser.roleInstructor)
          .where(FsUser.isDeleted, isNotEqualTo: true)
          .orderBy(FsUser.name)
          .limit(200)
          .get();

      if (!mounted) return;
      _allTeachers = snap.docs;
      setState(() => _isLoading = false);
      _applyFilterAndPage();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('교사 목록 불러오기 실패: $e'), backgroundColor: Colors.red),
      );
    }
  }

  // 이름 검색을 적용하고 페이징합니다.
  void _applyFilterAndPage() {
    final search = _searchCtrl.text.trim().toLowerCase();
    final filtered = _allTeachers.where((doc) {
      if (search.isEmpty) return true;
      final data = doc.data() as Map<String, dynamic>;
      final name = (data[FsUser.name] as String? ?? '').toLowerCase();
      return name.contains(search);
    }).toList();

    _filteredTeachers = filtered;

    final start = (_currentPage - 1) * _pageSize;
    final end = start + _pageSize;
    setState(() {
      _pagedTeachers = filtered.sublist(
        start.clamp(0, filtered.length),
        end.clamp(0, filtered.length),
      );
      _hasMore = end < filtered.length;
    });
  }

  void _resetFilter() {
    _currentPage = 1;
    _applyFilterAndPage();
  }

  void _nextPage() {
    if (!_hasMore) return;
    _currentPage++;
    _applyFilterAndPage();
  }

  void _prevPage() {
    if (_currentPage <= 1) return;
    _currentPage--;
    _applyFilterAndPage();
  }

  // 교사 등록 다이얼로그를 엽니다.
  Future<void> _showAddDialog() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _TeacherFormDialog(),
    );
    if (result == true) await _loadAllTeachers();
  }

  // 교사 수정 다이얼로그를 엽니다.
  Future<void> _showEditDialog(QueryDocumentSnapshot doc) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _TeacherEditDialog(teacherDoc: doc),
    );
    if (result == true) await _loadAllTeachers();
  }

  // ── 교사 삭제 방어 로직 ──────────────────────────────────
  // 삭제 전 진행 중 강좌 + 대기 학생을 체크합니다.
  // 연관 데이터가 있으면 인수인계 팝업, 없으면 일반 삭제 확인창을 표시합니다.
  Future<void> _handleDeleteTap(QueryDocumentSnapshot teacherDoc) async {
    final teacherUid = teacherDoc.id;
    final data = teacherDoc.data() as Map<String, dynamic>;
    final teacherName = data[FsUser.name] as String? ?? '이 교사';

    // 로딩 표시
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // ① 해당 교사가 담당인 '진행 중' 강좌 조회
      final activeCoursesSnap = await FirebaseFirestore.instance
          .collection(FsCol.courses)
          .where(FsCourse.teacherId, isEqualTo: teacherUid)
          .where(FsCourse.status, isEqualTo: FsCourse.statusActive)
          .get();

      final activeCourseIds = activeCoursesSnap.docs.map((d) => d.id).toList();

      // ② 해당 강좌들에 '승인 대기 중(pending)' 학생이 있는지 확인
      bool hasPendingStudents = false;
      if (activeCourseIds.isNotEmpty) {
        // Firestore whereIn은 최대 30개까지 지원합니다.
        final pendingSnap = await FirebaseFirestore.instance
            .collection(FsCol.users)
            .where(FsUser.courseId,
                whereIn: activeCourseIds.take(30).toList())
            .where(FsUser.status, isEqualTo: FsUser.statusPending)
            .limit(1)
            .get();
        hasPendingStudents = pendingSnap.docs.isNotEmpty;
      }

      if (!mounted) return;
      // 로딩 팝업 닫기
      Navigator.of(context).pop();

      // ③ 연관 데이터 존재 여부에 따라 분기
      final hasRelatedData =
          activeCoursesSnap.docs.isNotEmpty || hasPendingStudents;

      if (hasRelatedData) {
        // 연관 데이터 있음 → 인수인계 팝업 표시
        _showTransferDialog(
          teacherDoc: teacherDoc,
          activeCourses: activeCoursesSnap.docs,
        );
      } else {
        // 연관 데이터 없음 → 일반 삭제 확인
        _showSimpleDeleteConfirm(teacherDoc: teacherDoc, teacherName: teacherName);
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // 로딩 팝업 닫기
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('삭제 전 검사 실패: $e'), backgroundColor: Colors.red),
      );
    }
  }

  // ── 연관 데이터 없는 경우: 일반 삭제 확인 ────────────────
  Future<void> _showSimpleDeleteConfirm({
    required QueryDocumentSnapshot teacherDoc,
    required String teacherName,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(
          children: [
            Icon(Icons.delete_rounded, color: Color(0xFFD32F2F), size: 24),
            SizedBox(width: 8),
            Text('교사 삭제', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          ],
        ),
        content: Text(
          '"$teacherName" 교사를 삭제하시겠습니까?\n\n'
          '삭제된 교사는 목록에서 숨겨지고 로그인이 차단됩니다.\n'
          '(실제 계정 비활성화는 8단계 Cloud Functions 연동 후 완성됩니다.)',
          style: const TextStyle(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD32F2F),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    await _softDeleteTeacher(teacherDoc);
  }

  // ── 연관 데이터 있는 경우: 인수인계 팝업 표시 ────────────
  Future<void> _showTransferDialog({
    required QueryDocumentSnapshot teacherDoc,
    required List<QueryDocumentSnapshot> activeCourses,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _TransferDialog(
        teacherDoc: teacherDoc,
        activeCourses: activeCourses,
      ),
    );
    if (result == true) await _loadAllTeachers();
  }

  // ── Soft Delete 처리 ──────────────────────────────────────
  // is_deleted: true 를 설정하여 목록에서 숨기고 로그인 차단합니다.
  // 실제 Firebase Auth 계정 비활성화는 8단계 Cloud Functions에서 처리합니다.
  Future<void> _softDeleteTeacher(QueryDocumentSnapshot teacherDoc) async {
    final data = teacherDoc.data() as Map<String, dynamic>;
    final teacherName = data[FsUser.name] as String? ?? '이 교사';

    try {
      await FirebaseFirestore.instance
          .collection(FsCol.users)
          .doc(teacherDoc.id)
          .update({FsUser.isDeleted: true});

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"$teacherName" 교사가 삭제되었습니다.'),
          backgroundColor: Colors.red,
        ),
      );
      await _loadAllTeachers();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('삭제 실패: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 제목 + 등록 버튼 ─────────────────────────────
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('교사 목록',
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1A1A2E))),
                    SizedBox(height: 4),
                    Text('활동 중인 교사를 조회하고 새 교사를 등록합니다.',
                        style: TextStyle(fontSize: 14, color: Color(0xFF757575))),
                  ],
                ),
              ),
              Semantics(
                label: '교사 등록 버튼입니다.',
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    minimumSize: Size.zero,
                  ),
                  onPressed: _showAddDialog,
                  icon: const Icon(Icons.person_add_rounded, size: 18),
                  label: const Text('교사 등록',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── 이름 검색 필드 ───────────────────────────────
          Semantics(
            label: '교사 이름 검색 입력란입니다.',
            child: TextField(
              controller: _searchCtrl,
              onChanged: (_) => _resetFilter(),
              decoration: InputDecoration(
                hintText: '이름으로 검색',
                prefixIcon: const Icon(Icons.search_rounded, color: _blue),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          _resetFilter();
                        })
                    : null,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _blue, width: 2)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── 교사 목록 카드 ───────────────────────────────
          _buildTeacherList(),
          const SizedBox(height: 12),
          _buildPagination(),
        ],
      ),
    );
  }

  Widget _buildTeacherList() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: _blue,
              borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(14), topRight: Radius.circular(14)),
            ),
            child: Text(
              '교사 목록 (검색 결과 ${_filteredTeachers.length}명 / 전체 ${_allTeachers.length}명)',
              style: const TextStyle(
                  color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
          if (_isLoading)
            const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()))
          else if (_pagedTeachers.isEmpty)
            const Padding(
                padding: EdgeInsets.all(32),
                child: Text('등록된 교사가 없습니다.',
                    style: TextStyle(color: Color(0xFF757575))))
          else
            Column(children: _pagedTeachers.map(_buildTeacherTile).toList()),
        ],
      ),
    );
  }

  Widget _buildTeacherTile(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final name = data[FsUser.name] as String? ?? '이름 없음';
    final email = data[FsUser.email] as String? ?? '';
    final phone = data[FsUser.phone] as String? ?? '-';
    final photoUrl = data[FsUser.photoUrl] as String?;

    return Semantics(
      label: '교사 $name, 이메일: $email, 전화번호: $phone',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0)))),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: _blue.withValues(alpha: 0.12),
              backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
              child: photoUrl == null
                  ? Text(name.isNotEmpty ? name.substring(0, 1) : '?',
                      style: const TextStyle(
                          color: _blue, fontWeight: FontWeight.w700, fontSize: 16))
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700)),
                Text('$email · $phone',
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF757575)),
                    overflow: TextOverflow.ellipsis),
              ]),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: const Color(0xFF00897B).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20)),
              child: const Text('활성',
                  style: TextStyle(
                      color: Color(0xFF00897B),
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 4),
            // 수정 버튼
            Semantics(
              label: '$name 수정 버튼입니다.',
              child: IconButton(
                icon: const Icon(Icons.edit_rounded, size: 18, color: _blue),
                onPressed: () => _showEditDialog(doc),
                tooltip: '수정',
              ),
            ),
            // 삭제 버튼 — 방어 로직 포함
            Semantics(
              label: '$name 삭제 버튼입니다. 연관 데이터가 있으면 인수인계 팝업이 열립니다.',
              child: IconButton(
                icon: const Icon(Icons.delete_rounded,
                    size: 18, color: Color(0xFFD32F2F)),
                onPressed: () => _handleDeleteTap(doc),
                tooltip: '삭제',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPagination() {
    if (_filteredTeachers.isEmpty) return const SizedBox.shrink();
    final totalPages = ((_filteredTeachers.length - 1) ~/ _pageSize) + 1;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Semantics(
          label: '이전 페이지 버튼입니다.',
          child: IconButton(
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: _currentPage > 1 ? _prevPage : null,
            color: _blue,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration:
              BoxDecoration(color: _blue, borderRadius: BorderRadius.circular(8)),
          child: Text('$_currentPage / $totalPages 페이지',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w700)),
        ),
        Semantics(
          label: '다음 페이지 버튼입니다.',
          child: IconButton(
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: _hasMore ? _nextPage : null,
            color: _blue,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────
// 교사 신규 등록 다이얼로그 (2단계에서 구현한 폼)
// ─────────────────────────────────────────────────────────
class _TeacherFormDialog extends StatefulWidget {
  const _TeacherFormDialog();

  @override
  State<_TeacherFormDialog> createState() => _TeacherFormDialogState();
}

class _TeacherFormDialogState extends State<_TeacherFormDialog> {
  final _formKey    = GlobalKey<FormState>();
  final _nameCtrl   = TextEditingController();
  final _phoneCtrl  = TextEditingController();
  final _emailCtrl  = TextEditingController();
  final _pwCtrl     = TextEditingController();
  final _pwConfCtrl = TextEditingController();
  final _bioCtrl    = TextEditingController();

  bool _pwVisible     = false;
  bool _pwConfVisible = false;
  bool? _emailChecked;
  bool _emailChecking = false;
  bool _saving = false;

  Uint8List? _photoBytes;
  String? _photoFileName;

  static const Color _blue = Color(0xFF1565C0);

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _pwCtrl.dispose();
    _pwConfCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() {
      _photoBytes = bytes;
      _photoFileName = picked.name;
    });
  }

  Future<void> _checkEmail() async {
    final email = _emailCtrl.text.trim();
    if (!RegExp(r'^[\w.-]+@[\w.-]+\.\w{2,}$').hasMatch(email)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('올바른 이메일 형식을 입력해 주세요.'),
          backgroundColor: Colors.orange));
      return;
    }
    setState(() {
      _emailChecking = true;
      _emailChecked = null;
    });
    try {
      final snap = await FirebaseFirestore.instance
          .collection(FsCol.users)
          .where(FsUser.email, isEqualTo: email)
          .limit(1)
          .get();
      if (!mounted) return;
      setState(() {
        _emailChecked = snap.docs.isEmpty;
        _emailChecking = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              snap.docs.isEmpty ? '사용 가능한 이메일입니다.' : '이미 사용 중인 이메일입니다.'),
          backgroundColor:
              snap.docs.isEmpty ? const Color(0xFF00897B) : Colors.red));
    } catch (e) {
      if (!mounted) return;
      setState(() => _emailChecking = false);
    }
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return '비밀번호를 입력해 주세요.';
    if (value.length < 8) return '비밀번호는 최소 8자 이상이어야 합니다.';
    if (!RegExp(r'[A-Z]').hasMatch(value)) { return '대문자를 최소 1자 이상 포함해야 합니다.'; }
    if (!RegExp(r'[!@#\$%^&*(),.?":{}|<>]').hasMatch(value)) {
      return '특수문자를 최소 1자 이상 포함해야 합니다.';
    }
    if (RegExp(r'[가-힣ㄱ-ㅎㅏ-ㅣ]').hasMatch(value)) {
      return '비밀번호에 한글을 사용할 수 없습니다.';
    }
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_emailChecked != true) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('이메일 중복확인을 먼저 진행해 주세요.'),
          backgroundColor: Colors.orange));
      return;
    }
    setState(() => _saving = true);
    try {
      final credential =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
              email: _emailCtrl.text.trim(), password: _pwCtrl.text);
      final uid = credential.user!.uid;

      String? photoUrl;
      if (_photoBytes != null) {
        final ref = FirebaseStorage.instance
            .ref(StoragePath.profilePhotoPath(uid));
        await ref.putData(_photoBytes!,
            SettableMetadata(contentType: 'image/jpeg'));
        photoUrl = await ref.getDownloadURL();
      }

      await FirebaseFirestore.instance
          .collection(FsCol.users)
          .doc(uid)
          .set({
        FsUser.name: _nameCtrl.text.trim(),
        FsUser.email: _emailCtrl.text.trim(),
        FsUser.phone: _phoneCtrl.text.trim(),
        FsUser.role: FsUser.roleInstructor,
        FsUser.status: FsUser.statusApproved,
        FsUser.isDeleted: false,
        FsUser.isTempPw: true,
        FsUser.bio:
            _bioCtrl.text.trim().isEmpty ? null : _bioCtrl.text.trim(),
        FsUser.photoUrl: photoUrl,
        FsUser.createdAt: FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('교사 등록이 완료되었습니다.'),
          backgroundColor: Color(0xFF00897B)));
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.code == 'email-already-in-use'
              ? '이미 Auth에 등록된 이메일입니다.'
              : '계정 생성 실패: ${e.message}'),
          backgroundColor: Colors.red));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('저장 실패: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // 헤더
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            decoration: const BoxDecoration(
              color: _blue,
              borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16)),
            ),
            child: Row(children: [
              const Icon(Icons.person_add_rounded,
                  color: Colors.white, size: 22),
              const SizedBox(width: 10),
              const Expanded(
                  child: Text('교사 등록',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700))),
              IconButton(
                icon: const Icon(Icons.close_rounded,
                    color: Colors.white70),
                onPressed:
                    _saving ? null : () => Navigator.of(context).pop(false),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ]),
          ),
          // 폼
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildPhotoField(),
                      const SizedBox(height: 20),
                      _buildField(
                          ctrl: _nameCtrl,
                          label: '이름',
                          hint: '예) 홍길동',
                          required: true,
                          semantics: '교사 이름 입력란입니다.',
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? '이름을 입력해 주세요.'
                              : null),
                      const SizedBox(height: 16),
                      _buildField(
                          ctrl: _phoneCtrl,
                          label: '전화번호',
                          hint: '예) 01012345678',
                          required: true,
                          semantics: '전화번호 입력란입니다.',
                          keyboardType: TextInputType.phone,
                          formatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) { return '전화번호를 입력해 주세요.'; }
                            if (v.length < 9) { return '올바른 전화번호를 입력해 주세요.'; }
                            return null;
                          }),
                      const SizedBox(height: 16),
                      _buildEmailField(),
                      const SizedBox(height: 16),
                      _buildField(
                          ctrl: _pwCtrl,
                          label: '비밀번호',
                          hint: '8자+대문자+특수문자, 한글 제외',
                          required: true,
                          semantics: '비밀번호 입력란입니다.',
                          obscure: !_pwVisible,
                          suffix: IconButton(
                              icon: Icon(_pwVisible
                                  ? Icons.visibility_off_rounded
                                  : Icons.visibility_rounded,
                                  size: 20),
                              onPressed: () =>
                                  setState(() => _pwVisible = !_pwVisible)),
                          validator: _validatePassword),
                      const SizedBox(height: 16),
                      _buildField(
                          ctrl: _pwConfCtrl,
                          label: '비밀번호 확인',
                          hint: '비밀번호를 다시 입력해 주세요.',
                          required: true,
                          semantics: '비밀번호 확인 입력란입니다.',
                          obscure: !_pwConfVisible,
                          suffix: IconButton(
                              icon: Icon(_pwConfVisible
                                  ? Icons.visibility_off_rounded
                                  : Icons.visibility_rounded,
                                  size: 20),
                              onPressed: () => setState(
                                  () => _pwConfVisible = !_pwConfVisible)),
                          validator: (v) {
                            if (v == null || v.isEmpty) { return '비밀번호 확인을 입력해 주세요.'; }
                            if (v != _pwCtrl.text) { return '비밀번호가 일치하지 않습니다.'; }
                            return null;
                          }),
                      const SizedBox(height: 16),
                      _buildField(
                          ctrl: _bioCtrl,
                          label: '쓰고 싶은 말',
                          hint: '자기소개 등 자유롭게 입력해 주세요. (선택)',
                          required: false,
                          semantics: '쓰고 싶은 말 입력란입니다. 선택 항목입니다.',
                          maxLines: 4),
                      const SizedBox(height: 28),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: _blue,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              minimumSize: Size.zero),
                          onPressed: _saving ? null : _save,
                          child: _saving
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2.5))
                              : const Text('등록 완료',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildPhotoField() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('프로필 사진 (선택)',
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF424242))),
      const SizedBox(height: 8),
      Row(children: [
        CircleAvatar(
          radius: 36,
          backgroundColor: const Color(0xFFE3F2FD),
          backgroundImage:
              _photoBytes != null ? MemoryImage(_photoBytes!) : null,
          child: _photoBytes == null
              ? const Icon(Icons.person_rounded, size: 32, color: _blue)
              : null,
        ),
        const SizedBox(width: 16),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
                foregroundColor: _blue,
                side: const BorderSide(color: _blue),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10)),
            onPressed: _pickPhoto,
            icon: const Icon(Icons.upload_rounded, size: 16),
            label: const Text('사진 선택', style: TextStyle(fontSize: 13)),
          ),
          if (_photoFileName != null) ...[
            const SizedBox(height: 4),
            Text(_photoFileName!,
                style: const TextStyle(
                    fontSize: 11, color: Color(0xFF757575))),
          ],
        ]),
      ]),
    ]);
  }

  Widget _buildEmailField() {
    Color? borderColor;
    if (_emailChecked == true) borderColor = const Color(0xFF00897B);
    if (_emailChecked == false) borderColor = Colors.red;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      RichText(
          text: const TextSpan(
              text: '이메일',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF424242)),
              children: [
            TextSpan(
                text: ' *',
                style: TextStyle(
                    color: Colors.red, fontWeight: FontWeight.w700))
          ])),
      const SizedBox(height: 6),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: TextFormField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            onChanged: (_) => setState(() => _emailChecked = null),
            decoration: InputDecoration(
              hintText: '예) teacher@example.com',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                      color: borderColor ?? const Color(0xFFE0E0E0))),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                      color: borderColor ?? const Color(0xFFE0E0E0))),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                      BorderSide(color: borderColor ?? _blue, width: 2)),
              errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Colors.red)),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 14),
              suffixIcon: _emailChecked == true
                  ? const Icon(Icons.check_circle_rounded,
                      color: Color(0xFF00897B), size: 20)
                  : _emailChecked == false
                      ? const Icon(Icons.cancel_rounded,
                          color: Colors.red, size: 20)
                      : null,
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) { return '이메일을 입력해 주세요.'; }
              if (!RegExp(r'^[\w.-]+@[\w.-]+\.\w{2,}$').hasMatch(v)) {
                return '올바른 이메일 형식이 아닙니다.';
              }
              if (_emailChecked != true) return '이메일 중복확인을 해주세요.';
              return null;
            },
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: 50,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF455A64),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(horizontal: 14)),
            onPressed: _emailChecking ? null : _checkEmail,
            child: _emailChecking
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Text('중복확인',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ),
      ]),
    ]);
  }

  Widget _buildField({
    required TextEditingController ctrl,
    required String label,
    required String hint,
    required bool required,
    required String semantics,
    TextInputType? keyboardType,
    List<TextInputFormatter>? formatters,
    bool obscure = false,
    Widget? suffix,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      RichText(
          text: TextSpan(
              text: label,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF424242)),
              children: required
                  ? const [
                      TextSpan(
                          text: ' *',
                          style: TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.w700))
                    ]
                  : [])),
      const SizedBox(height: 6),
      Semantics(
        label: semantics,
        child: TextFormField(
          controller: ctrl,
          keyboardType: keyboardType,
          inputFormatters: formatters,
          obscureText: obscure,
          maxLines: maxLines,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle:
                const TextStyle(color: Color(0xFFBDBDBD), fontSize: 13),
            filled: true,
            fillColor: Colors.white,
            suffixIcon: suffix,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    const BorderSide(color: _blue, width: 2)),
            errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Colors.red)),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 14),
          ),
          validator: validator,
        ),
      ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────
// 교사 정보 수정 다이얼로그
//
// 수정 가능 항목:
//   - 이름, 전화번호, 쓰고 싶은 말
//   - 프로필 사진 변경
//   - 비밀번호 초기화 (is_temp_password: true 설정)
//     ※ 실제 비밀번호 변경은 8단계 Cloud Functions에서 구현합니다.
// ─────────────────────────────────────────────────────────
class _TeacherEditDialog extends StatefulWidget {
  final QueryDocumentSnapshot teacherDoc;
  const _TeacherEditDialog({required this.teacherDoc});

  @override
  State<_TeacherEditDialog> createState() => _TeacherEditDialogState();
}

class _TeacherEditDialogState extends State<_TeacherEditDialog> {
  final _formKey   = GlobalKey<FormState>();
  final _nameCtrl  = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _bioCtrl   = TextEditingController();

  // 비밀번호 초기화 여부 (체크 시 is_temp_password: true 플래그 설정)
  bool _resetPassword = false;

  Uint8List? _newPhotoBytes;
  String? _existingPhotoUrl;
  bool _saving = false;

  static const Color _blue = Color(0xFF1565C0);

  @override
  void initState() {
    super.initState();
    // 기존 데이터를 폼에 채웁니다.
    final data = widget.teacherDoc.data() as Map<String, dynamic>;
    _nameCtrl.text  = data[FsUser.name]  as String? ?? '';
    _phoneCtrl.text = data[FsUser.phone] as String? ?? '';
    _bioCtrl.text   = data[FsUser.bio]   as String? ?? '';
    _existingPhotoUrl = data[FsUser.photoUrl] as String?;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  // 프로필 사진을 교체합니다.
  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() => _newPhotoBytes = bytes);
  }

  // 교사 정보를 Firestore에 저장합니다.
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final uid = widget.teacherDoc.id;
      String? photoUrl = _existingPhotoUrl;

      // 새 사진이 선택된 경우 Storage에 업로드합니다.
      // CLAUDE.md: 파일 교체 시 기존 파일을 먼저 Hard Delete 후 업로드
      if (_newPhotoBytes != null) {
        final ref = FirebaseStorage.instance
            .ref(StoragePath.profilePhotoPath(uid));
        // 기존 파일 삭제 (없어도 오류 무시)
        try { await ref.delete(); } catch (_) {}
        await ref.putData(
            _newPhotoBytes!, SettableMetadata(contentType: 'image/jpeg'));
        photoUrl = await ref.getDownloadURL();
      }

      // Firestore 교사 문서를 업데이트합니다.
      final updateData = <String, dynamic>{
        FsUser.name:     _nameCtrl.text.trim(),
        FsUser.phone:    _phoneCtrl.text.trim(),
        FsUser.bio:      _bioCtrl.text.trim().isEmpty ? null : _bioCtrl.text.trim(),
        FsUser.photoUrl: photoUrl,
      };

      // 비밀번호 초기화 체크 시 is_temp_password: true 설정
      // 교사가 다음 로그인 시 비밀번호 변경을 강제합니다.
      // ※ 8단계 Cloud Functions에서 실제 임시 비밀번호 발급이 구현됩니다.
      if (_resetPassword) {
        updateData[FsUser.isTempPw] = true;
      }

      await FirebaseFirestore.instance
          .collection(FsCol.users)
          .doc(uid)
          .update(updateData);

      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_resetPassword
              ? '교사 정보가 수정되었습니다. 다음 로그인 시 비밀번호 변경이 강제됩니다.'
              : '교사 정보가 수정되었습니다.'),
          backgroundColor: const Color(0xFF00897B)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('수정 실패: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    // 현재 표시할 사진 (새 사진 > 기존 URL > 기본 아이콘)
    final ImageProvider? displayPhoto = _newPhotoBytes != null
        ? MemoryImage(_newPhotoBytes!)
        : (_existingPhotoUrl != null
            ? NetworkImage(_existingPhotoUrl!) as ImageProvider
            : null);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // 헤더
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            decoration: const BoxDecoration(
              color: _blue,
              borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16), topRight: Radius.circular(16)),
            ),
            child: Row(children: [
              const Icon(Icons.edit_rounded, color: Colors.white, size: 22),
              const SizedBox(width: 10),
              const Expanded(
                  child: Text('교사 정보 수정',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700))),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white70),
                onPressed: _saving ? null : () => Navigator.of(context).pop(false),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ]),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── 프로필 사진 ──────────────────────────
                    const Text('프로필 사진',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF424242))),
                    const SizedBox(height: 8),
                    Row(children: [
                      CircleAvatar(
                          radius: 36,
                          backgroundColor: const Color(0xFFE3F2FD),
                          backgroundImage: displayPhoto,
                          child: displayPhoto == null
                              ? const Icon(Icons.person_rounded,
                                  size: 32, color: _blue)
                              : null),
                      const SizedBox(width: 16),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                            foregroundColor: _blue,
                            side: const BorderSide(color: _blue),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                            minimumSize: Size.zero,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10)),
                        onPressed: _pickPhoto,
                        icon: const Icon(Icons.upload_rounded, size: 16),
                        label: const Text('사진 변경',
                            style: TextStyle(fontSize: 13)),
                      ),
                    ]),
                    const SizedBox(height: 20),

                    // ── 이름 ─────────────────────────────────
                    _buildLabel('이름', required: true),
                    const SizedBox(height: 6),
                    Semantics(
                      label: '이름 입력란입니다.',
                      child: TextFormField(
                        controller: _nameCtrl,
                        decoration: _inputDeco('예) 홍길동'),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? '이름을 입력해 주세요.'
                            : null,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── 전화번호 ─────────────────────────────
                    _buildLabel('전화번호', required: true),
                    const SizedBox(height: 6),
                    Semantics(
                      label: '전화번호 입력란입니다.',
                      child: TextFormField(
                        controller: _phoneCtrl,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: _inputDeco('예) 01012345678'),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) { return '전화번호를 입력해 주세요.'; }
                          if (v.length < 9) { return '올바른 전화번호를 입력해 주세요.'; }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── 쓰고 싶은 말 ─────────────────────────
                    _buildLabel('쓰고 싶은 말', required: false),
                    const SizedBox(height: 6),
                    Semantics(
                      label: '쓰고 싶은 말 입력란입니다. 선택 항목입니다.',
                      child: TextFormField(
                        controller: _bioCtrl,
                        maxLines: 3,
                        decoration: _inputDeco('자기소개 등 자유롭게 입력해 주세요.'),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ── 비밀번호 초기화 ──────────────────────
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(children: [
                            Icon(Icons.lock_reset_rounded,
                                color: Colors.orange, size: 18),
                            SizedBox(width: 8),
                            Text('비밀번호 초기화',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.orange)),
                          ]),
                          const SizedBox(height: 6),
                          const Text(
                            '체크 시 해당 교사가 다음 로그인할 때 비밀번호 변경이 강제됩니다.\n'
                            '※ 실제 임시 비밀번호 발급은 8단계 Cloud Functions 연동 후 완성됩니다.',
                            style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF795548),
                                height: 1.5),
                          ),
                          const SizedBox(height: 8),
                          Semantics(
                            label: '비밀번호 초기화 체크박스입니다.',
                            child: CheckboxListTile(
                              value: _resetPassword,
                              onChanged: (v) =>
                                  setState(() => _resetPassword = v ?? false),
                              title: const Text(
                                  '다음 로그인 시 비밀번호 변경 강제 (is_temp_password: true)',
                                  style: TextStyle(fontSize: 13)),
                              controlAffinity: ListTileControlAffinity.leading,
                              contentPadding: EdgeInsets.zero,
                              activeColor: Colors.orange,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),

                    // ── 저장 버튼 ────────────────────────────
                    Semantics(
                      label: '교사 정보 수정 저장 버튼입니다.',
                      child: SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: _blue,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              minimumSize: Size.zero),
                          onPressed: _saving ? null : _save,
                          child: _saving
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2.5))
                              : const Text('수정 완료',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildLabel(String text, {bool required = false}) {
    return RichText(
        text: TextSpan(
            text: text,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF424242)),
            children: required
                ? const [
                    TextSpan(
                        text: ' *',
                        style: TextStyle(
                            color: Colors.red, fontWeight: FontWeight.w700))
                  ]
                : []));
  }

  InputDecoration _inputDeco(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFFBDBDBD), fontSize: 13),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _blue, width: 2)),
        errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Colors.red)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      );
}

// ─────────────────────────────────────────────────────────
// 교사 원클릭 인수인계 다이얼로그
//
// 표시 조건:
//   - 퇴직 교사의 진행 중 강좌가 있거나
//   - 해당 강좌에 대기 학생이 있는 경우
//
// 처리 (Firestore 트랜잭션):
//   ① 진행 중인 강좌의 teacher_id / teacher_name 새 교사로 일괄 변경
//   ② 퇴직 교사의 is_deleted: true 처리
//   ③ [8단계] Cloud Functions로 Firebase Auth 계정 비활성화
// ─────────────────────────────────────────────────────────
class _TransferDialog extends StatefulWidget {
  final QueryDocumentSnapshot teacherDoc;
  // 퇴직 교사가 담당 중인 진행 중 강좌 목록
  final List<QueryDocumentSnapshot> activeCourses;

  const _TransferDialog({
    required this.teacherDoc,
    required this.activeCourses,
  });

  @override
  State<_TransferDialog> createState() => _TransferDialogState();
}

class _TransferDialogState extends State<_TransferDialog> {
  // 인수받을 교사 목록 (퇴직 교사 본인 제외)
  List<Map<String, String>> _otherTeachers = [];

  // 선택된 인수 교사 uid
  String? _selectedTeacherId;
  String? _selectedTeacherName;

  bool _loadingTeachers = true;
  bool _processing = false;

  static const Color _blue = Color(0xFF1565C0);

  @override
  void initState() {
    super.initState();
    _loadOtherTeachers();
  }

  // 퇴직 교사를 제외한 다른 활성 교사 목록을 가져옵니다.
  Future<void> _loadOtherTeachers() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection(FsCol.users)
          .where(FsUser.role, isEqualTo: FsUser.roleInstructor)
          .where(FsUser.isDeleted, isNotEqualTo: true)
          .orderBy(FsUser.name)
          .get();

      if (!mounted) return;
      setState(() {
        // 퇴직 교사 본인은 목록에서 제외합니다.
        _otherTeachers = snap.docs
            .where((d) => d.id != widget.teacherDoc.id)
            .map((d) {
          final data = d.data();
          return {
            'uid': d.id,
            'name': data[FsUser.name] as String? ?? '이름 없음',
          };
        }).toList();
        _loadingTeachers = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingTeachers = false);
    }
  }

  // 인수인계 + 퇴직 처리를 Firestore 트랜잭션으로 실행합니다.
  Future<void> _applyTransfer() async {
    if (_selectedTeacherId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('인수받을 교사를 선택해 주세요.'),
          backgroundColor: Colors.orange));
      return;
    }
    setState(() => _processing = true);

    try {
      final db = FirebaseFirestore.instance;

      // Firestore 트랜잭션으로 강좌 이관 + 교사 비활성화를 동시에 처리합니다.
      // 트랜잭션은 원자적(Atomic)으로 실행됩니다 — 하나라도 실패 시 전체 롤백
      await db.runTransaction((tx) async {
        // ① 진행 중인 강좌들의 담당 교사를 새 교사로 변경합니다.
        for (final courseDoc in widget.activeCourses) {
          tx.update(courseDoc.reference, {
            FsCourse.teacherId:   _selectedTeacherId,
            FsCourse.teacherName: _selectedTeacherName,
          });
        }

        // ② 퇴직 교사의 is_deleted를 true로 설정합니다.
        tx.update(
          db.collection(FsCol.users).doc(widget.teacherDoc.id),
          {FsUser.isDeleted: true},
        );
      });

      // ③ [8단계 TODO] Firebase Auth 계정 비활성화
      // Cloud Functions Callable Function으로 구현 예정:
      //   await FirebaseFunctions.instance
      //       .httpsCallable('disableAuthUser')
      //       .call({'uid': widget.teacherDoc.id});

      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '인수인계 완료! ${widget.activeCourses.length}개 강좌가 $_selectedTeacherName 교사에게 이관되었습니다.'),
          backgroundColor: const Color(0xFF00897B)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _processing = false);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('인수인계 실패: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.teacherDoc.data() as Map<String, dynamic>;
    final teacherName = data[FsUser.name] as String? ?? '이 교사';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // 경고 헤더 (주황색)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            decoration: BoxDecoration(
              color: Colors.orange.shade700,
              borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16), topRight: Radius.circular(16)),
            ),
            child: Row(children: [
              const Icon(Icons.warning_amber_rounded,
                  color: Colors.white, size: 24),
              const SizedBox(width: 10),
              const Expanded(
                  child: Text('중도 퇴직 — 원클릭 인수인계',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w700))),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white70),
                onPressed:
                    _processing ? null : () => Navigator.of(context).pop(false),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ]),
          ),
          // 본문
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 경고 메시지 (CLAUDE.md 명시 문구)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(children: [
                            Icon(Icons.error_outline_rounded,
                                color: Colors.red, size: 18),
                            SizedBox(width: 6),
                            Text('삭제 차단됨',
                                style: TextStyle(
                                    color: Colors.red,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13)),
                          ]),
                          const SizedBox(height: 6),
                          Text(
                            '"$teacherName" 교사가 담당 중인 반과 대기 학생이 있습니다.\n'
                            '먼저 다른 교사에게 [반 배정 이전]을 하시거나 반을 [종료] 처리해야 삭제할 수 있습니다.',
                            style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF7B1FA2),
                                height: 1.5),
                          ),
                        ]),
                  ),
                  const SizedBox(height: 20),

                  // 진행 중 강좌 목록
                  Text(
                    '진행 중인 강좌 (${widget.activeCourses.length}개) — 인계 대상',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF424242)),
                  ),
                  const SizedBox(height: 8),
                  ...widget.activeCourses.map((courseDoc) {
                    final cd = courseDoc.data() as Map<String, dynamic>;
                    final courseName =
                        cd[FsCourse.name] as String? ?? '강좌명 없음';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(children: [
                        const Icon(Icons.school_rounded,
                            size: 16, color: _blue),
                        const SizedBox(width: 6),
                        Text(courseName,
                            style: const TextStyle(fontSize: 13)),
                      ]),
                    );
                  }),
                  const SizedBox(height: 20),

                  // 인수받을 교사 선택 Selectbox
                  const Text(
                    '인수받을 교사 선택 *',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF424242)),
                  ),
                  const SizedBox(height: 8),
                  _loadingTeachers
                      ? const Center(child: CircularProgressIndicator())
                      : _otherTeachers.isEmpty
                          ? Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border:
                                    Border.all(color: Colors.red.shade200),
                              ),
                              child: const Text(
                                '인수받을 수 있는 다른 교사가 없습니다.\n먼저 새 교사를 등록하거나 진행 중인 강좌를 종료해 주세요.',
                                style: TextStyle(
                                    color: Colors.red, fontSize: 13),
                              ),
                            )
                          : Semantics(
                              label: '인수받을 교사 선택 드롭다운입니다.',
                              child: DropdownButtonFormField<String>(
                                // ignore: deprecated_member_use
                                value: _selectedTeacherId,
                                isExpanded: true,
                                decoration: InputDecoration(
                                  hintText: '교사를 선택해 주세요.',
                                  filled: true,
                                  fillColor: Colors.white,
                                  border: OutlineInputBorder(
                                      borderRadius:
                                          BorderRadius.circular(10),
                                      borderSide: const BorderSide(
                                          color: Color(0xFFE0E0E0))),
                                  enabledBorder: OutlineInputBorder(
                                      borderRadius:
                                          BorderRadius.circular(10),
                                      borderSide: const BorderSide(
                                          color: Color(0xFFE0E0E0))),
                                  focusedBorder: OutlineInputBorder(
                                      borderRadius:
                                          BorderRadius.circular(10),
                                      borderSide: const BorderSide(
                                          color: _blue, width: 2)),
                                  contentPadding:
                                      const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 14),
                                ),
                                items: _otherTeachers
                                    .map((t) => DropdownMenuItem<String>(
                                          value: t['uid'],
                                          child: Text(t['name']!,
                                              style: const TextStyle(
                                                  fontSize: 14)),
                                        ))
                                    .toList(),
                                onChanged: (uid) => setState(() {
                                  _selectedTeacherId = uid;
                                  _selectedTeacherName = _otherTeachers
                                      .firstWhere((t) => t['uid'] == uid)['name'];
                                }),
                              ),
                            ),
                  const SizedBox(height: 28),

                  // 인수인계 + 퇴직 적용 버튼
                  Semantics(
                    label: '인수인계 및 퇴직 적용 버튼입니다.',
                    child: SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _otherTeachers.isEmpty
                              ? Colors.grey
                              : Colors.orange.shade700,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          minimumSize: Size.zero,
                        ),
                        onPressed: (_processing || _otherTeachers.isEmpty)
                            ? null
                            : _applyTransfer,
                        child: _processing
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2.5))
                            : const Text('인수인계 및 퇴직 적용',
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Center(
                    child: Text(
                      '※ 강좌 이관 후 해당 교사 계정은 즉시 비활성화됩니다.\n(Auth 계정 비활성화는 8단계 완료 후 자동 적용)',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: Color(0xFF9E9E9E)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
