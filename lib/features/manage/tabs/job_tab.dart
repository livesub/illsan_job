// 구직 등록 관리 탭입니다.
// SUPER_ADMIN: 전체 게시물 수정/삭제
// INSTRUCTOR : 본인 작성 게시물 등록/수정/삭제
//
// 데이터 로드 전략:
//   - 삭제되지 않은 게시물 전체를 최대 200건 로드
//   - 제목 검색은 클라이언트에서 처리
//   - 페이징도 클라이언트에서 처리

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cross_file/cross_file.dart';
import '../../../core/enums/user_role.dart';
import '../../../core/utils/firestore_keys.dart';

class JobTab extends StatefulWidget {
  final UserRole userRole;
  final String userName;
  const JobTab({super.key, required this.userRole, required this.userName});

  @override
  State<JobTab> createState() => _JobTabState();
}

class _JobTabState extends State<JobTab> {
  static const int _pageSize = 10;
  static const Color _blue = Color(0xFF1565C0);

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  List<QueryDocumentSnapshot> _allJobs      = [];
  List<QueryDocumentSnapshot> _filteredJobs = [];
  List<QueryDocumentSnapshot> _pagedJobs    = [];

  final TextEditingController _searchCtrl = TextEditingController();
  int _currentPage = 1;
  bool _hasMore    = false;
  bool _isLoading  = false;

  @override
  void initState() {
    super.initState();
    _loadAllJobs();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAllJobs() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection(FsCol.jobs)
          .where(FsJob.isDeleted, isEqualTo: false)
          .orderBy(FsJob.createdAt, descending: true)
          .limit(200)
          .get();
      if (!mounted) return;
      _allJobs = snap.docs;
      setState(() => _isLoading = false);
      _applyFilterAndPage();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('게시물 목록 불러오기 실패: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _applyFilterAndPage() {
    final search = _searchCtrl.text.trim().toLowerCase();
    final filtered = _allJobs.where((doc) {
      if (search.isEmpty) return true;
      final data  = doc.data() as Map<String, dynamic>;
      final title = (data[FsJob.title] as String? ?? '').toLowerCase();
      return title.contains(search);
    }).toList();

    _filteredJobs = filtered;
    final start = (_currentPage - 1) * _pageSize;
    final end   = start + _pageSize;
    setState(() {
      _pagedJobs = filtered.sublist(
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

  Future<void> _showAddDialog() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _JobFormDialog(
        userRole: widget.userRole,
        userName: widget.userName,
        authorUid: _uid,
      ),
    );
    if (result == true) await _loadAllJobs();
  }

  Future<void> _showEditDialog(QueryDocumentSnapshot doc) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _JobFormDialog(
        userRole: widget.userRole,
        userName: widget.userName,
        authorUid: _uid,
        editDoc: doc,
      ),
    );
    if (result == true) await _loadAllJobs();
  }

  Future<void> _deleteJob(QueryDocumentSnapshot doc) async {
    final data  = doc.data() as Map<String, dynamic>;
    final title = data[FsJob.title] as String? ?? '이 게시물';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(children: [
          Icon(Icons.delete_rounded, color: Color(0xFFD32F2F), size: 22),
          SizedBox(width: 8),
          Text('게시물 삭제',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        ]),
        content: Text('"$title"를 삭제하시겠습니까?',
            style: const TextStyle(fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD32F2F),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              minimumSize: Size.zero,
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child:
                const Text('삭제', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      // 지원자 존재 여부 확인 (알림 분기용)
      final appSnap = await FirebaseFirestore.instance
          .collection(FsCol.jobApplications)
          .where(FsJobApp.jobId, isEqualTo: doc.id)
          .limit(1)
          .get();
      final hasApplicants = appSnap.docs.isNotEmpty;

      // Storage Hard Delete — 인라인 이미지
      final imgPaths = (data[FsJob.inlineImgs] as List?)?.cast<String>() ?? [];
      for (final path in imgPaths) {
        try { await FirebaseStorage.instance.ref(path).delete(); } catch (_) {}
      }
      // Storage Hard Delete — 첨부파일
      final attachPaths = (data[FsJob.attachments] as List?)?.cast<String>() ?? [];
      for (final path in attachPaths) {
        try { await FirebaseStorage.instance.ref(path).delete(); } catch (_) {}
      }

      // DB Soft Delete (지원 내역 보존)
      await FirebaseFirestore.instance
          .collection(FsCol.jobs)
          .doc(doc.id)
          .update({FsJob.isDeleted: true});

      if (!mounted) return;
      final msg = hasApplicants ? '$title 은(는) 삭제 되었습니다' : '게시물이 삭제되었습니다.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red),
      );
      await _loadAllJobs();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('삭제 실패: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<int> _fetchApplicantCount(String jobId) async {
    final agg = await FirebaseFirestore.instance
        .collection(FsCol.jobApplications)
        .where(FsJobApp.jobId, isEqualTo: jobId)
        .count()
        .get();
    return agg.count ?? 0;
  }

  // 소프트 삭제된 댓글(is_deleted=true) 제외한 활성 댓글 수
  Future<int> _fetchCommentCount(String jobId) async {
    final snap = await FirebaseFirestore.instance
        .collection(FsCol.jobComments)
        .where(FsJobComment.jobId, isEqualTo: jobId)
        .get();
    return snap.docs.where((d) {
      final data = d.data() as Map<String, dynamic>;
      return data[FsJobComment.isDeleted] != true;
    }).length;
  }

  // INSTRUCTOR는 본인 작성 게시물만 수정/삭제 가능합니다.
  bool _canEdit(QueryDocumentSnapshot doc) {
    if (widget.userRole == UserRole.SUPER_ADMIN) return true;
    final data = doc.data() as Map<String, dynamic>;
    return data[FsJob.authorId] == _uid;
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
                    Text('구직 등록 관리',
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1A1A2E))),
                    SizedBox(height: 4),
                    Text('구직 게시물을 등록하고 관리합니다.',
                        style:
                            TextStyle(fontSize: 14, color: Color(0xFF757575))),
                  ],
                ),
              ),
              Semantics(
                label: '구직 게시물 등록 버튼입니다.',
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    minimumSize: Size.zero,
                  ),
                  onPressed: _showAddDialog,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('게시물 등록',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── 제목 검색 ─────────────────────────────────────
          Semantics(
            label: '게시물 제목 검색 입력란입니다.',
            child: TextField(
              controller: _searchCtrl,
              onChanged: (_) => _resetFilter(),
              decoration: InputDecoration(
                hintText: '제목으로 검색',
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
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── 목록 카드 ─────────────────────────────────────
          _buildJobList(),
          const SizedBox(height: 12),
          _buildPagination(),
        ],
      ),
    );
  }

  Widget _buildJobList() {
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
              '구직 게시물 (검색 결과 ${_filteredJobs.length}건 / 전체 ${_allJobs.length}건)',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700),
            ),
          ),
          if (_isLoading)
            const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()))
          else if (_pagedJobs.isEmpty)
            const Padding(
                padding: EdgeInsets.all(32),
                child: Text('등록된 구직 게시물이 없습니다.',
                    style: TextStyle(color: Color(0xFF757575))))
          else
            Column(children: _pagedJobs.asMap().entries.map((e) => _buildJobTile(e.key, e.value)).toList()),
        ],
      ),
    );
  }

  Widget _buildJobTile(int index, QueryDocumentSnapshot doc) {
    final data    = doc.data() as Map<String, dynamic>;
    final title   = data[FsJob.title]  as String? ?? '제목 없음';
    final period  = data[FsJob.period] as String? ?? '-';
    final canEdit = _canEdit(doc);
    final seq     = (_currentPage - 1) * _pageSize + index + 1;

    return Semantics(
      label: '$seq번 $title, 기간: $period',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0)))),
        child: Row(children: [
          // 순번
          SizedBox(
            width: 28,
            child: Text('$seq',
                style: const TextStyle(fontSize: 13, color: Color(0xFF9E9E9E)),
                textAlign: TextAlign.center),
          ),
          const SizedBox(width: 8),
          // 제목 + 기간
          Expanded(
            child: GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => _JobDetailPage(
                    doc: doc,
                    userRole: widget.userRole,
                    userName: widget.userName,
                    authorUid: _uid,
                  ),
                ),
              ).then((_) => _loadAllJobs()),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _blue,
                          decoration: TextDecoration.underline,
                          decorationColor: _blue)),
                  const SizedBox(height: 2),
                  Text('기간: $period',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF757575))),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 지원자 수 + 댓글 수
          FutureBuilder<List<int>>(
            future: Future.wait([
              _fetchApplicantCount(doc.id),
              _fetchCommentCount(doc.id),
            ]),
            builder: (_, snap) {
              final applicants = snap.data?[0] ?? 0;
              final comments   = snap.data?[1] ?? 0;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.people_rounded, size: 13, color: Color(0xFF9E9E9E)),
                    const SizedBox(width: 2),
                    Text('$applicants', style: const TextStyle(fontSize: 12, color: Color(0xFF757575))),
                  ]),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.chat_bubble_outline_rounded, size: 13, color: Color(0xFF9E9E9E)),
                    const SizedBox(width: 2),
                    Text('$comments', style: const TextStyle(fontSize: 12, color: Color(0xFF757575))),
                  ]),
                ],
              );
            },
          ),
          if (canEdit) ...[
            Semantics(
              label: '$title 수정 버튼입니다.',
              child: IconButton(
                icon: const Icon(Icons.edit_rounded, size: 18, color: _blue),
                onPressed: () => _showEditDialog(doc),
                tooltip: '수정',
              ),
            ),
            Semantics(
              label: '$title 삭제 버튼입니다.',
              child: IconButton(
                icon: const Icon(Icons.delete_rounded, size: 18, color: Color(0xFFD32F2F)),
                onPressed: () => _deleteJob(doc),
                tooltip: '삭제',
              ),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _buildPagination() {
    if (_filteredJobs.isEmpty) return const SizedBox.shrink();
    final totalPages =
        ((_filteredJobs.length - 1) ~/ _pageSize) + 1;
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
          decoration: BoxDecoration(
              color: _blue, borderRadius: BorderRadius.circular(8)),
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
// 구직 게시물 등록/수정 다이얼로그
// ─────────────────────────────────────────────────────────
class _JobFormDialog extends StatefulWidget {
  final UserRole userRole;
  final String userName;
  final String authorUid;
  final QueryDocumentSnapshot? editDoc;

  const _JobFormDialog({
    required this.userRole,
    required this.userName,
    required this.authorUid,
    this.editDoc,
  });

  @override
  State<_JobFormDialog> createState() => _JobFormDialogState();
}

class _JobFormDialogState extends State<_JobFormDialog> {
  final _formKey     = GlobalKey<FormState>();
  final _titleCtrl   = TextEditingController();
  final _periodCtrl  = TextEditingController();
  final _contentCtrl = TextEditingController();

  bool _saving = false;
  bool get _isEdit => widget.editDoc != null;

  // 인라인 이미지
  final List<String> _imgPaths = [];
  final List<String> _imgUrls  = [];
  bool _uploadingImg = false;

  // 담당 반 목록 및 노출 대상 선택
  List<QueryDocumentSnapshot> _courses = [];
  bool _targetAll = true;
  final Set<String> _selectedCourseIds = {};
  bool _loadingCourses = true;

  // 첨부파일 — 기존(수정 시) + 신규
  final List<String>  _existAttachPaths = [];  // Storage 경로
  final List<String>  _existAttachNames = [];  // 파일명 표시용
  final List<XFile>   _newAttachFiles   = [];  // 업로드 대기 XFile
  // 수정 시 삭제된 기존 파일 경로 (저장 시 Hard Delete)
  final List<String>  _removedAttachPaths = [];

  static const int    _maxAttach    = 3;
  static const int    _maxBytes     = 3 * 1024 * 1024; // 3MB
  static const Color  _blue         = Color(0xFF1565C0);

  @override
  void initState() {
    super.initState();
    _loadCourses();
    if (_isEdit) {
      _prefillForm();
      _loadInlineImages();
      _loadExistAttachments();
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _periodCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  // 담당 반(active) 목록 로드
  Future<void> _loadCourses() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection(FsCol.courses)
          .where(FsCourse.teacherId, isEqualTo: widget.authorUid)
          .where(FsCourse.status, isEqualTo: FsCourse.statusActive)
          .get();
      if (!mounted) return;
      setState(() {
        _courses = snap.docs;
        _loadingCourses = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingCourses = false);
    }
  }

  void _prefillForm() {
    final data = widget.editDoc!.data() as Map<String, dynamic>;
    _titleCtrl.text   = data[FsJob.title]  as String? ?? '';
    _periodCtrl.text  = data[FsJob.period] as String? ?? '';
    _contentCtrl.text = data[FsJob.content] as String? ?? '';

    final tc = (data[FsJob.targetCourses] as List?)?.cast<String>() ?? [FsJob.targetAll];
    if (tc.contains(FsJob.targetAll)) {
      _targetAll = true;
    } else {
      _targetAll = false;
      _selectedCourseIds.addAll(tc);
    }
  }

  Future<void> _loadInlineImages() async {
    final data  = widget.editDoc!.data() as Map<String, dynamic>;
    final paths = (data[FsJob.inlineImgs] as List?)?.cast<String>() ?? [];
    for (final path in paths) {
      try {
        final url = await FirebaseStorage.instance.ref(path).getDownloadURL();
        if (!mounted) return;
        setState(() {
          _imgPaths.add(path);
          _imgUrls.add(url);
        });
      } catch (_) {}
    }
  }

  void _loadExistAttachments() {
    final data  = widget.editDoc!.data() as Map<String, dynamic>;
    final paths = (data[FsJob.attachments] as List?)?.cast<String>() ?? [];
    for (final p in paths) {
      _existAttachPaths.add(p);
      _existAttachNames.add(p.split('/').last);
    }
  }

  // 인라인 이미지 업로드
  Future<void> _pickAndUploadImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 80,
    );
    if (picked == null || !mounted) return;
    setState(() => _uploadingImg = true);
    try {
      final bytes = await picked.readAsBytes();
      final now   = DateTime.now();
      final path  =
          '${StoragePath.inlinePath(StoragePath.boardJob, now.year, now.month)}'
          '${now.millisecondsSinceEpoch}_${picked.name}';
      final ref = FirebaseStorage.instance.ref(path);
      await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      final url = await ref.getDownloadURL();
      if (!mounted) return;
      setState(() {
        _imgPaths.add(path);
        _imgUrls.add(url);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('이미지 업로드 실패: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _uploadingImg = false);
    }
  }

  Future<void> _removeImage(int index) async {
    final path = _imgPaths[index];
    try {
      await FirebaseStorage.instance.ref(path).delete();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _imgPaths.removeAt(index);
      _imgUrls.removeAt(index);
    });
  }

  // 첨부파일 선택 — XFile.length()로 3MB 체크 (웹/모바일 공통)
  Future<void> _pickAttachment() async {
    final total = _existAttachPaths.length + _newAttachFiles.length;
    if (total >= _maxAttach) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('첨부파일은 최대 3개까지 가능합니다.'), backgroundColor: Colors.orange),
      );
      return;
    }
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: false,
    );
    if (result == null || result.files.isEmpty || !mounted) return;

    final pf   = result.files.first;
    final xf   = XFile(pf.path ?? '', name: pf.name);
    final size = pf.size; // file_picker가 제공하는 size (웹/모바일 공통)

    if (size > _maxBytes) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('파일 크기는 3MB 이하만 첨부할 수 있습니다.'), backgroundColor: Colors.orange),
      );
      return;
    }
    setState(() => _newAttachFiles.add(xf));
  }

  // 기존 첨부파일 제거 (수정 시 — 저장 시 Hard Delete 예약)
  void _removeExistAttach(int index) {
    setState(() {
      _removedAttachPaths.add(_existAttachPaths[index]);
      _existAttachPaths.removeAt(index);
      _existAttachNames.removeAt(index);
    });
  }

  // 신규 첨부파일 제거 (아직 업로드 안 됨)
  void _removeNewAttach(int index) {
    setState(() => _newAttachFiles.removeAt(index));
  }

  void _wrapSelection(String open, String close) {
    final sel  = _contentCtrl.selection;
    if (!sel.isValid) return;
    final text     = _contentCtrl.text;
    final before   = text.substring(0, sel.start);
    final selected = text.substring(sel.start, sel.end);
    final after    = text.substring(sel.end);
    _contentCtrl.value = TextEditingValue(
      text: '$before$open$selected$close$after',
      selection: TextSelection.collapsed(
          offset: sel.start + open.length + selected.length + close.length),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_targetAll && _selectedCourseIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('노출할 반을 하나 이상 선택해 주세요.'), backgroundColor: Colors.orange),
      );
      return;
    }
    setState(() => _saving = true);

    try {
      final now = DateTime.now();

      // 신규 첨부파일 Storage 업로드
      final uploadedPaths = List<String>.from(_existAttachPaths);
      for (final xf in _newAttachFiles) {
        final bytes = await xf.readAsBytes();
        final path  =
            '${StoragePath.attachmentPath(StoragePath.boardJob, now.year, now.month)}'
            '${now.millisecondsSinceEpoch}_${xf.name}';
        final ref = FirebaseStorage.instance.ref(path);
        await ref.putData(bytes);
        uploadedPaths.add(path);
      }

      // 수정 시 제거된 기존 파일 Hard Delete
      for (final path in _removedAttachPaths) {
        try { await FirebaseStorage.instance.ref(path).delete(); } catch (_) {}
      }

      final targetCourses = _targetAll
          ? [FsJob.targetAll]
          : _selectedCourseIds.toList();

      final payload = <String, dynamic>{
        FsJob.title:         _titleCtrl.text.trim(),
        FsJob.period:        _periodCtrl.text.trim(),
        FsJob.content:       _contentCtrl.text.trim(),
        FsJob.inlineImgs:    _imgPaths,
        FsJob.attachments:   uploadedPaths,
        FsJob.targetCourses: targetCourses,
      };

      if (_isEdit) {
        await FirebaseFirestore.instance
            .collection(FsCol.jobs)
            .doc(widget.editDoc!.id)
            .update(payload);
      } else {
        await FirebaseFirestore.instance.collection(FsCol.jobs).add({
          ...payload,
          FsJob.authorId:         widget.authorUid,
          FsJob.authorName:       widget.userName,
          FsJob.isDeleted:        false,
          FsJob.createdAt:        StoragePath.nowCreatedAt(),
          FsJob.createdTimestamp: FieldValue.serverTimestamp(), // hidden 타임스탬프
        });
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_isEdit ? '게시물이 수정되었습니다.' : '게시물이 등록되었습니다.'),
        backgroundColor: const Color(0xFF00897B),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('저장 실패: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
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
              Icon(_isEdit ? Icons.edit_rounded : Icons.work_rounded,
                  color: Colors.white, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(_isEdit ? '구직 공고 수정' : '구직 공고 등록',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700)),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white70),
                onPressed: _saving ? null : () => Navigator.of(context).pop(false),
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
                    // 1. 노출 대상 반
                    _buildLabel('노출 대상 반', required: true),
                    const SizedBox(height: 8),
                    _buildCourseTargetSection(),
                    const SizedBox(height: 20),

                    // 2. 제목
                    _buildLabel('제목', required: true),
                    const SizedBox(height: 6),
                    Semantics(
                      label: '구직 공고 제목 입력란입니다. 필수 항목입니다.',
                      child: TextFormField(
                        controller: _titleCtrl,
                        decoration: _inputDeco('예) [삼성전자] 개발자 구함 지원하세요'),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? '제목을 입력해 주세요.'
                            : null,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // 3. 기간
                    _buildLabel('기간', required: true),
                    const SizedBox(height: 6),
                    Semantics(
                      label: '채용 기간 입력란입니다. 필수 항목입니다.',
                      child: TextFormField(
                        controller: _periodCtrl,
                        decoration: _inputDeco('예) 채용 시 마감, 2026-05-31까지'),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? '기간을 입력해 주세요.'
                            : null,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // 4. 내용 — 스마트 에디터
                    _buildLabel('내용', required: true),
                    const SizedBox(height: 6),
                    _buildSmartEditor(),
                    const SizedBox(height: 20),

                    // 5. 첨부파일
                    _buildLabel('첨부파일'),
                    const SizedBox(height: 4),
                    const Text('최대 3개 · 각 3MB 이하',
                        style: TextStyle(fontSize: 11, color: Color(0xFF9E9E9E))),
                    const SizedBox(height: 8),
                    _buildAttachSection(),
                    const SizedBox(height: 28),

                    // 저장 버튼
                    Semantics(
                      label: '${_isEdit ? "수정" : "등록"} 완료 버튼입니다.',
                      child: SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _blue,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            minimumSize: Size.zero,
                          ),
                          onPressed: _saving ? null : _save,
                          child: _saving
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2.5))
                              : Text(_isEdit ? '수정 완료' : '등록 완료',
                                  style: const TextStyle(
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

  // 노출 대상 반 선택 UI
  Widget _buildCourseTargetSection() {
    if (_loadingCourses) {
      return const SizedBox(
        height: 40,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE0E0E0)),
        borderRadius: BorderRadius.circular(10),
        color: Colors.white,
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 전체 반 라디오
          Semantics(
            label: '내가 담당한 전체 반에 노출 선택입니다.',
            child: RadioListTile<bool>(
              value: true,
              groupValue: _targetAll,
              onChanged: (v) => setState(() => _targetAll = true),
              title: const Text('내가 담당한 전체 반',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              dense: true,
              contentPadding: EdgeInsets.zero,
              activeColor: _blue,
            ),
          ),
          // 특정 반 라디오
          Semantics(
            label: '특정 반만 선택하여 노출 선택입니다.',
            child: RadioListTile<bool>(
              value: false,
              groupValue: _targetAll,
              onChanged: (v) => setState(() => _targetAll = false),
              title: const Text('특정 반만 선택',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              dense: true,
              contentPadding: EdgeInsets.zero,
              activeColor: _blue,
            ),
          ),
          // 특정 반 체크박스 목록
          if (!_targetAll) ...[
            const Divider(height: 12),
            if (_courses.isEmpty)
              const Text('담당 중인 활성 반이 없습니다.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF9E9E9E)))
            else
              ...(_courses.map((doc) {
                final id   = doc.id;
                final name = (doc.data() as Map<String, dynamic>)[FsCourse.name] as String? ?? id;
                return Semantics(
                  label: '$name 반 노출 선택 체크박스입니다.',
                  child: CheckboxListTile(
                    value: _selectedCourseIds.contains(id),
                    onChanged: (checked) {
                      setState(() {
                        if (checked == true) {
                          _selectedCourseIds.add(id);
                        } else {
                          _selectedCourseIds.remove(id);
                        }
                      });
                    },
                    title: Text(name,
                        style: const TextStyle(fontSize: 13)),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    activeColor: _blue,
                  ),
                );
              })),
          ],
        ],
      ),
    );
  }

  Widget _buildSmartEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F5F5),
            border: Border.all(color: const Color(0xFFE0E0E0)),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(10),
              topRight: Radius.circular(10),
            ),
          ),
          child: Row(children: [
            Semantics(
              label: '굵게 서식 버튼입니다.',
              child: IconButton(
                icon: const Icon(Icons.format_bold_rounded, size: 20),
                onPressed: () => _wrapSelection('<b>', '</b>'),
                tooltip: '굵게',
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                padding: EdgeInsets.zero,
              ),
            ),
            Semantics(
              label: '기울임 서식 버튼입니다.',
              child: IconButton(
                icon: const Icon(Icons.format_italic_rounded, size: 20),
                onPressed: () => _wrapSelection('<i>', '</i>'),
                tooltip: '기울임',
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                padding: EdgeInsets.zero,
              ),
            ),
            Semantics(
              label: '밑줄 서식 버튼입니다.',
              child: IconButton(
                icon: const Icon(Icons.format_underline_rounded, size: 20),
                onPressed: () => _wrapSelection('<u>', '</u>'),
                tooltip: '밑줄',
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                padding: EdgeInsets.zero,
              ),
            ),
            const VerticalDivider(width: 16, thickness: 1, color: Color(0xFFE0E0E0)),
            Semantics(
              label: '이미지 추가 버튼입니다.',
              child: _uploadingImg
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : IconButton(
                      icon: const Icon(Icons.image_rounded, size: 20, color: _blue),
                      onPressed: _pickAndUploadImage,
                      tooltip: '이미지 추가',
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      padding: EdgeInsets.zero,
                    ),
            ),
          ]),
        ),
        Semantics(
          label: '구직 공고 내용 입력란입니다. 필수 항목입니다.',
          child: TextFormField(
            controller: _contentCtrl,
            maxLines: 8,
            decoration: InputDecoration(
              hintText: '구직 공고 내용을 입력하세요.',
              hintStyle: const TextStyle(color: Color(0xFFBDBDBD), fontSize: 13),
              filled: true,
              fillColor: Colors.white,
              border: const OutlineInputBorder(
                borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(10),
                    bottomRight: Radius.circular(10)),
                borderSide: BorderSide(color: Color(0xFFE0E0E0)),
              ),
              enabledBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(10),
                    bottomRight: Radius.circular(10)),
                borderSide: BorderSide(color: Color(0xFFE0E0E0)),
              ),
              focusedBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(10),
                    bottomRight: Radius.circular(10)),
                borderSide: BorderSide(color: _blue, width: 2),
              ),
              errorBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(10),
                    bottomRight: Radius.circular(10)),
                borderSide: BorderSide(color: Colors.red),
              ),
              contentPadding: const EdgeInsets.all(14),
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? '내용을 입력해 주세요.' : null,
          ),
        ),
        if (_imgPaths.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text('본문 이미지',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF424242))),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(_imgPaths.length, (i) {
              return Stack(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    _imgUrls[i],
                    width: 80, height: 80, fit: BoxFit.cover,
                    loadingBuilder: (_, child, progress) => progress == null
                        ? child
                        : const SizedBox(
                            width: 80, height: 80,
                            child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
                    errorBuilder: (_, __, ___) => const SizedBox(
                        width: 80, height: 80,
                        child: Icon(Icons.broken_image_rounded, color: Colors.grey)),
                  ),
                ),
                Positioned(
                  top: 2, right: 2,
                  child: Semantics(
                    label: '이미지 삭제 버튼입니다.',
                    child: GestureDetector(
                      onTap: () => _removeImage(i),
                      child: Container(
                        decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                        padding: const EdgeInsets.all(2),
                        child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ]);
            }),
          ),
        ],
      ],
    );
  }

  // 첨부파일 섹션
  Widget _buildAttachSection() {
    final totalCount = _existAttachPaths.length + _newAttachFiles.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 기존 첨부파일 (수정 시)
        ..._existAttachPaths.asMap().entries.map((e) {
          return _buildAttachTile(
            name: _existAttachNames[e.key],
            onRemove: () => _removeExistAttach(e.key),
            isNew: false,
          );
        }),
        // 신규 선택 파일
        ..._newAttachFiles.asMap().entries.map((e) {
          return _buildAttachTile(
            name: e.value.name,
            onRemove: () => _removeNewAttach(e.key),
            isNew: true,
          );
        }),
        if (totalCount < _maxAttach)
          Semantics(
            label: '첨부파일 추가 버튼입니다.',
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: _blue,
                side: const BorderSide(color: _blue),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
              onPressed: _pickAttachment,
              icon: const Icon(Icons.attach_file_rounded, size: 16),
              label: Text('파일 추가 ($totalCount/$_maxAttach)',
                  style: const TextStyle(fontSize: 13)),
            ),
          ),
      ],
    );
  }

  Widget _buildAttachTile({required String name, required VoidCallback onRemove, required bool isNew}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        const Icon(Icons.insert_drive_file_rounded, size: 16, color: Color(0xFF757575)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(name,
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis),
        ),
        if (isNew)
          const Text('신규', style: TextStyle(fontSize: 10, color: Color(0xFF00897B))),
        const SizedBox(width: 4),
        Semantics(
          label: '$name 첨부파일 삭제 버튼입니다.',
          child: GestureDetector(
            onTap: onRemove,
            child: const Icon(Icons.close_rounded, size: 16, color: Color(0xFFD32F2F)),
          ),
        ),
      ]),
    );
  }

  Widget _buildLabel(String text, {bool required = false}) {
    return RichText(
      text: TextSpan(
        text: text,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF424242)),
        children: required
            ? const [TextSpan(text: ' *', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w700))]
            : [],
      ),
    );
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      );
}

// ─────────────────────────────────────────────────────────
// 구직 공고 상세 페이지
// ─────────────────────────────────────────────────────────
class _JobDetailPage extends StatefulWidget {
  final QueryDocumentSnapshot doc;
  final UserRole userRole;
  final String userName;
  final String authorUid;

  const _JobDetailPage({
    required this.doc,
    required this.userRole,
    required this.userName,
    required this.authorUid,
  });

  @override
  State<_JobDetailPage> createState() => _JobDetailPageState();
}

class _JobDetailPageState extends State<_JobDetailPage> {
  static const Color _blue = Color(0xFF1565C0);

  // 첨부파일 Storage URL 캐시
  final Map<String, String> _attachUrls = {};

  // Q&A 댓글 입력 상태
  final _commentCtrl       = TextEditingController();
  String? _replyTargetId;    // null=최상위 댓글, 값=대댓글 대상 댓글ID
  String? _replyTargetAuthor;
  bool    _submittingComment = false;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAttachUrls(List<String> paths) async {
    for (final p in paths) {
      if (_attachUrls.containsKey(p)) continue;
      try {
        final url = await FirebaseStorage.instance.ref(p).getDownloadURL();
        if (mounted) setState(() => _attachUrls[p] = url);
      } catch (_) {}
    }
  }

  // 지원자 상태 DB 즉시 업데이트
  Future<void> _updateAppStatus(String appId, String status) async {
    try {
      await FirebaseFirestore.instance
          .collection(FsCol.jobApplications)
          .doc(appId)
          .update({FsJobApp.status: status});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('처리 실패: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _openEditDialog() async {
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _JobFormDialog(
        userRole: widget.userRole,
        userName: widget.userName,
        authorUid: widget.authorUid,
        editDoc: widget.doc,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('구직 공고 상세',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
        backgroundColor: _blue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection(FsCol.jobs)
            .doc(widget.doc.id)
            .snapshots(),
        builder: (ctx, jobSnap) {
          if (!jobSnap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final jobData     = jobSnap.data!.data() as Map<String, dynamic>? ?? {};
          final title       = jobData[FsJob.title]       as String? ?? '';
          final content     = jobData[FsJob.content]     as String? ?? '';
          final period      = jobData[FsJob.period]      as String? ?? '-';
          final attachPaths = (jobData[FsJob.attachments] as List?)?.cast<String>() ?? [];
          final authorId    = jobData[FsJob.authorId]    as String? ?? '';
          final canEdit     = widget.userRole == UserRole.SUPER_ADMIN ||
                              widget.authorUid == authorId;

          if (attachPaths.isNotEmpty) _loadAttachUrls(attachPaths);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoCard(
                  title: title,
                  content: content,
                  period: period,
                  attachPaths: attachPaths,
                  canEdit: canEdit,
                ),
                const SizedBox(height: 20),
                _buildApplicantSection(),
                const SizedBox(height: 20),
                _buildQnaSection(),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildInfoCard({
    required String title,
    required String content,
    required String period,
    required List<String> attachPaths,
    required bool canEdit,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 4))],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(title,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ),
            if (canEdit)
              Semantics(
                label: '공고 수정 버튼입니다.',
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _blue,
                    foregroundColor: Colors.white,
                    minimumSize: Size.zero,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: _openEditDialog,
                  icon: const Icon(Icons.edit_rounded, size: 16),
                  label: const Text('수정', style: TextStyle(fontSize: 13)),
                ),
              ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            const Icon(Icons.schedule_rounded, size: 14, color: Color(0xFF9E9E9E)),
            const SizedBox(width: 4),
            Text('기간: $period',
                style: const TextStyle(fontSize: 13, color: Color(0xFF757575))),
          ]),
          const Divider(height: 24),
          Text(content, style: const TextStyle(fontSize: 14, height: 1.6)),
          if (attachPaths.isNotEmpty) ...[
            const Divider(height: 24),
            const Text('첨부파일',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            ...attachPaths.map((p) {
              final name = p.split('/').last;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  const Icon(Icons.insert_drive_file_rounded, size: 16, color: Color(0xFF757575)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(name,
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis),
                  ),
                ]),
              );
            }),
          ],
        ],
      ),
    );
  }

  // StreamBuilder로 지원자 현황 실시간 구독
  Widget _buildApplicantSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('지원자 현황',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection(FsCol.jobApplications)
              .where(FsJobApp.jobId, isEqualTo: widget.doc.id)
              .orderBy(FsJobApp.appliedAt)
              .snapshots(),
          builder: (ctx, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final docs = snap.data?.docs ?? [];
            return Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 3))],
              ),
              child: docs.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(
                        child: Text('지원한 학생이 없습니다.',
                            style: TextStyle(color: Color(0xFF757575))),
                      ),
                    )
                  : Column(children: docs.map(_buildApplicantTile).toList()),
            );
          },
        ),
      ],
    );
  }

  // ── Q&A 댓글 저장 (최상위 or 대댓글)
  Future<void> _submitComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _submittingComment = true);
    try {
      await FirebaseFirestore.instance.collection(FsCol.jobComments).add({
        FsJobComment.jobId:      widget.doc.id,
        FsJobComment.content:    text,
        FsJobComment.authorId:   widget.authorUid,
        FsJobComment.authorName: widget.userName,
        FsJobComment.parentId:   _replyTargetId,   // null=최상위
        FsJobComment.isDeleted:  false,
        FsJobComment.createdAt:  StoragePath.nowCreatedAt(),
      });
      if (!mounted) return;
      _commentCtrl.clear();
      setState(() {
        _replyTargetId     = null;
        _replyTargetAuthor = null;
        _submittingComment = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _submittingComment = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('등록 실패: $e'), backgroundColor: Colors.red),
      );
    }
  }

  // ── 댓글 Soft Delete — 본인: "삭제된 글입니다", 타인: "규정에 의해 삭제된 댓글입니다"
  Future<void> _softDeleteComment(String commentId, bool isMine) async {
    final msg = isMine
        ? FsJobComment.deletedBySelf
        : FsJobComment.deletedByRule;
    await FirebaseFirestore.instance
        .collection(FsCol.jobComments)
        .doc(commentId)
        .update({
      FsJobComment.content:   msg,
      FsJobComment.isDeleted: true,
    });
  }

  // ── 본인 댓글 수정 다이얼로그
  Future<void> _editComment(String commentId, String current) async {
    final ctrl = TextEditingController(text: current);
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('댓글 수정', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctrl,
          maxLines: 4,
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.all(12),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _blue, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (saved == null || saved.isEmpty) return;
    await FirebaseFirestore.instance
        .collection(FsCol.jobComments)
        .doc(commentId)
        .update({FsJobComment.content: saved});
  }

  // ── Q&A 섹션 (StreamBuilder)
  Widget _buildQnaSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('묻고 답하기',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection(FsCol.jobComments)
              .where(FsJobComment.jobId, isEqualTo: widget.doc.id)
              .orderBy(FsJobComment.createdAt)
              .snapshots(),
          builder: (ctx, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final all      = snap.data?.docs ?? [];
            final topLevel = all.where((d) {
              final data = d.data() as Map<String, dynamic>;
              return data[FsJobComment.parentId] == null;
            }).toList();

            return Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 8,
                        offset: const Offset(0, 3))],
                  ),
                  child: topLevel.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(
                            child: Text('등록된 질문이 없습니다.',
                                style: TextStyle(color: Color(0xFF757575))),
                          ),
                        )
                      : Column(
                          children: topLevel
                              .map((td) => _buildCommentBlock(td, all))
                              .toList(),
                        ),
                ),
                const SizedBox(height: 16),
                _buildCommentInput(),
              ],
            );
          },
        ),
      ],
    );
  }

  // ── 최상위 댓글 + 그 대댓글 블록
  Widget _buildCommentBlock(
      QueryDocumentSnapshot topDoc, List<QueryDocumentSnapshot> all) {
    final replies = all.where((d) {
      final data = d.data() as Map<String, dynamic>;
      return data[FsJobComment.parentId] == topDoc.id;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCommentTile(topDoc, isReply: false),
        ...replies.map((r) => _buildCommentTile(r, isReply: true)),
        // 답변 달기 버튼 (삭제된 최상위 댓글에는 미노출)
        Builder(builder: (_) {
          final data = topDoc.data() as Map<String, dynamic>;
          if (data[FsJobComment.isDeleted] == true) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(left: 48, bottom: 4),
            child: Semantics(
              label: '이 댓글에 답변 달기 버튼입니다.',
              child: TextButton.icon(
                style: TextButton.styleFrom(
                    foregroundColor: _blue,
                    minimumSize: Size.zero,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
                onPressed: () {
                  final author = data[FsJobComment.authorName] as String? ?? '';
                  setState(() {
                    _replyTargetId     = topDoc.id;
                    _replyTargetAuthor = author;
                  });
                },
                icon: const Icon(Icons.reply_rounded, size: 16),
                label: const Text('답변 달기', style: TextStyle(fontSize: 12)),
              ),
            ),
          );
        }),
        const Divider(height: 1, color: Color(0xFFF5F5F5)),
      ],
    );
  }

  // ── 댓글/대댓글 타일
  Widget _buildCommentTile(QueryDocumentSnapshot doc, {required bool isReply}) {
    final data       = doc.data() as Map<String, dynamic>;
    final content    = data[FsJobComment.content]    as String? ?? '';
    final authorId   = data[FsJobComment.authorId]   as String? ?? '';
    final authorName = data[FsJobComment.authorName] as String? ?? '';
    final isDeleted  = data[FsJobComment.isDeleted]  == true;
    final isMine     = authorId == widget.authorUid;

    final leftPad = isReply ? 40.0 : 16.0;

    return Semantics(
      label: '$authorName의 댓글: $content',
      child: Container(
        padding: EdgeInsets.fromLTRB(leftPad, 12, 16, 12),
        decoration: BoxDecoration(
          color: isReply ? const Color(0xFFF9F9F9) : Colors.white,
          border: const Border(bottom: BorderSide(color: Color(0xFFF0F0F0))),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isReply)
              const Padding(
                padding: EdgeInsets.only(right: 6, top: 2),
                child: Icon(Icons.subdirectory_arrow_right_rounded,
                    size: 16, color: Color(0xFFBDBDBD)),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(authorName,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: isMine ? _blue : const Color(0xFF424242))),
                    if (isMine) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: _blue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('교사',
                            style: TextStyle(fontSize: 9, color: _blue, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 4),
                  Text(
                    content,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDeleted ? const Color(0xFF9E9E9E) : const Color(0xFF212121),
                      fontStyle: isDeleted ? FontStyle.italic : FontStyle.normal,
                    ),
                  ),
                ],
              ),
            ),
            // 권한별 버튼
            if (!isDeleted) ...[
              if (isMine)
                Semantics(
                  label: '댓글 수정 버튼입니다.',
                  child: IconButton(
                    icon: const Icon(Icons.edit_rounded, size: 15, color: Color(0xFF9E9E9E)),
                    onPressed: () => _editComment(doc.id, content),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ),
              const SizedBox(width: 4),
              Semantics(
                label: isMine ? '댓글 삭제 버튼입니다.' : '규정 위반 댓글 삭제 버튼입니다.',
                child: IconButton(
                  icon: const Icon(Icons.close_rounded, size: 15, color: Color(0xFFBDBDBD)),
                  onPressed: () => _softDeleteComment(doc.id, isMine),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── 댓글 입력 폼
  Widget _buildCommentInput() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 3))],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_replyTargetId != null) ...[
            Row(children: [
              const Icon(Icons.reply_rounded, size: 14, color: Color(0xFF9E9E9E)),
              const SizedBox(width: 4),
              Text('$_replyTargetAuthor 에게 답변',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF757575))),
              const Spacer(),
              Semantics(
                label: '답변 달기 취소 버튼입니다.',
                child: GestureDetector(
                  onTap: () => setState(() {
                    _replyTargetId     = null;
                    _replyTargetAuthor = null;
                  }),
                  child: const Icon(Icons.close_rounded, size: 16, color: Color(0xFF9E9E9E)),
                ),
              ),
            ]),
            const SizedBox(height: 8),
          ],
          Row(children: [
            Expanded(
              child: Semantics(
                label: _replyTargetId != null ? '답변 내용 입력란입니다.' : '질문 내용 입력란입니다.',
                child: TextField(
                  controller: _commentCtrl,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: _replyTargetId != null ? '답변을 입력하세요.' : '질문을 입력하세요.',
                    hintStyle: const TextStyle(color: Color(0xFFBDBDBD), fontSize: 13),
                    filled: true,
                    fillColor: const Color(0xFFF9F9F9),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: _blue, width: 2)),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Semantics(
              label: '댓글 등록 버튼입니다.',
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _blue,
                  foregroundColor: Colors.white,
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _submittingComment ? null : _submitComment,
                child: _submittingComment
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('등록', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _buildApplicantTile(QueryDocumentSnapshot appDoc) {
    final data       = appDoc.data() as Map<String, dynamic>;
    final name       = data[FsJobApp.applicantName] as String? ?? '-';
    final courseName = data[FsJobApp.courseName]    as String? ?? '-';
    final status     = data[FsJobApp.status]        as String? ?? FsJobApp.statusPending;

    Color statusColor;
    String statusLabel;
    switch (status) {
      case FsJobApp.statusApproved:
        statusColor = const Color(0xFF00897B);
        statusLabel = '승인됨';
        break;
      case FsJobApp.statusCancelled:
        statusColor = const Color(0xFF9E9E9E);
        statusLabel = '취소됨';
        break;
      default:
        statusColor = const Color(0xFFF57C00);
        statusLabel = '대기중';
    }

    return Semantics(
      label: '$courseName 반 $name, 상태: $statusLabel',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0)))),
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('[$courseName] $name',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(statusLabel,
                    style: TextStyle(fontSize: 12, color: statusColor, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          // pending·cancelled → 지원 승인
          if (status != FsJobApp.statusApproved)
            Semantics(
              label: '$name 지원 승인 버튼입니다.',
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF00897B),
                  side: const BorderSide(color: Color(0xFF00897B)),
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                onPressed: () => _updateAppStatus(appDoc.id, FsJobApp.statusApproved),
                child: const Text('지원 승인', style: TextStyle(fontSize: 12)),
              ),
            ),
          const SizedBox(width: 6),
          // pending·approved → 취소
          if (status != FsJobApp.statusCancelled)
            Semantics(
              label: '$name 취소 버튼입니다.',
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF9E9E9E),
                  side: const BorderSide(color: Color(0xFF9E9E9E)),
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                onPressed: () => _updateAppStatus(appDoc.id, FsJobApp.statusCancelled),
                child: const Text('취소', style: TextStyle(fontSize: 12)),
              ),
            ),
        ]),
      ),
    );
  }
}
