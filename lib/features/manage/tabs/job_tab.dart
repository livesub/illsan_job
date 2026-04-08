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

  final String _uid = FirebaseAuth.instance.currentUser!.uid;

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
          .where(FsJob.isDeleted, isNotEqualTo: true)
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
      // 인라인 이미지 Storage Hard Delete
      final imgPaths =
          (data[FsJob.inlineImgs] as List?)?.cast<String>() ?? [];
      for (final path in imgPaths) {
        try {
          await FirebaseStorage.instance.ref(path).delete();
        } catch (_) {}
      }
      await FirebaseFirestore.instance
          .collection(FsCol.jobs)
          .doc(doc.id)
          .update({FsJob.isDeleted: true});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('게시물이 삭제되었습니다.'), backgroundColor: Colors.red),
      );
      await _loadAllJobs();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('삭제 실패: $e'), backgroundColor: Colors.red),
      );
    }
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
            Column(children: _pagedJobs.map(_buildJobTile).toList()),
        ],
      ),
    );
  }

  Widget _buildJobTile(QueryDocumentSnapshot doc) {
    final data    = doc.data() as Map<String, dynamic>;
    final title   = data[FsJob.title]      as String? ?? '제목 없음';
    final author  = data[FsJob.authorName] as String? ?? '';
    final created = data[FsJob.createdAt]  as String? ?? '';
    final canEdit = _canEdit(doc);

    String dateStr = created;
    if (created.length >= 6) {
      dateStr =
          '20${created.substring(0, 2)}-${created.substring(2, 4)}-${created.substring(4, 6)}';
    }

    return Semantics(
      label: '$title, 작성자: $author, 작성일: $dateStr',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: const BoxDecoration(
            border:
                Border(bottom: BorderSide(color: Color(0xFFF0F0F0)))),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: _blue.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.work_rounded, color: _blue, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                  Text('$author · $dateStr',
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF757575))),
                ]),
          ),
          if (canEdit) ...[
            Semantics(
              label: '$title 수정 버튼입니다.',
              child: IconButton(
                icon: const Icon(Icons.edit_rounded,
                    size: 18, color: _blue),
                onPressed: () => _showEditDialog(doc),
                tooltip: '수정',
              ),
            ),
            Semantics(
              label: '$title 삭제 버튼입니다.',
              child: IconButton(
                icon: const Icon(Icons.delete_rounded,
                    size: 18, color: Color(0xFFD32F2F)),
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
  final _contentCtrl = TextEditingController();

  bool _saving = false;

  bool get _isEdit => widget.editDoc != null;

  // 인라인 이미지 Storage 경로 + URL 목록
  final List<String> _imgPaths = [];
  final List<String> _imgUrls  = [];
  bool _uploadingImg = false;

  static const Color _blue = Color(0xFF1565C0);

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      _prefillForm();
      _loadInlineImages();
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  void _prefillForm() {
    final data = widget.editDoc!.data() as Map<String, dynamic>;
    _titleCtrl.text   = data[FsJob.title]   as String? ?? '';
    _contentCtrl.text = data[FsJob.content] as String? ?? '';
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
        SnackBar(
            content: Text('이미지 업로드 실패: $e'), backgroundColor: Colors.red),
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
    setState(() => _saving = true);

    final payload = <String, dynamic>{
      FsJob.title:      _titleCtrl.text.trim(),
      FsJob.content:    _contentCtrl.text.trim(),
      FsJob.inlineImgs: _imgPaths,
    };

    try {
      if (_isEdit) {
        await FirebaseFirestore.instance
            .collection(FsCol.jobs)
            .doc(widget.editDoc!.id)
            .update(payload);
      } else {
        await FirebaseFirestore.instance.collection(FsCol.jobs).add({
          ...payload,
          FsJob.authorId:    widget.authorUid,
          FsJob.authorName:  widget.userName,
          FsJob.attachments: [],
          FsJob.isDeleted:   false,
          FsJob.createdAt:   StoragePath.nowCreatedAt(),
        });
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_isEdit ? '게시물이 수정되었습니다.' : '게시물이 등록되었습니다.'),
          backgroundColor: const Color(0xFF00897B)));
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
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            decoration: const BoxDecoration(
              color: _blue,
              borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16)),
            ),
            child: Row(children: [
              Icon(_isEdit ? Icons.edit_rounded : Icons.work_rounded,
                  color: Colors.white, size: 22),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(_isEdit ? '게시물 수정' : '게시물 등록',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700))),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white70),
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
                    // 1. 제목
                    _buildLabel('제목', required: true),
                    const SizedBox(height: 6),
                    Semantics(
                      label: '게시물 제목 입력란입니다. 필수 항목입니다.',
                      child: TextFormField(
                        controller: _titleCtrl,
                        decoration: _inputDeco('예) 플러터 앱 개발자 모집'),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? '제목을 입력해 주세요.'
                            : null,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // 2. 내용 — 스마트 에디터
                    _buildLabel('내용', required: true),
                    const SizedBox(height: 6),
                    _buildSmartEditor(),
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
                              minimumSize: Size.zero),
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
                constraints:
                    const BoxConstraints(minWidth: 36, minHeight: 36),
                padding: EdgeInsets.zero,
              ),
            ),
            Semantics(
              label: '기울임 서식 버튼입니다.',
              child: IconButton(
                icon: const Icon(Icons.format_italic_rounded, size: 20),
                onPressed: () => _wrapSelection('<i>', '</i>'),
                tooltip: '기울임',
                constraints:
                    const BoxConstraints(minWidth: 36, minHeight: 36),
                padding: EdgeInsets.zero,
              ),
            ),
            Semantics(
              label: '밑줄 서식 버튼입니다.',
              child: IconButton(
                icon: const Icon(Icons.format_underline_rounded, size: 20),
                onPressed: () => _wrapSelection('<u>', '</u>'),
                tooltip: '밑줄',
                constraints:
                    const BoxConstraints(minWidth: 36, minHeight: 36),
                padding: EdgeInsets.zero,
              ),
            ),
            const VerticalDivider(
                width: 16, thickness: 1, color: Color(0xFFE0E0E0)),
            Semantics(
              label: '이미지 추가 버튼입니다.',
              child: _uploadingImg
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : IconButton(
                      icon: const Icon(Icons.image_rounded,
                          size: 20, color: _blue),
                      onPressed: _pickAndUploadImage,
                      tooltip: '이미지 추가',
                      constraints: const BoxConstraints(
                          minWidth: 36, minHeight: 36),
                      padding: EdgeInsets.zero,
                    ),
            ),
          ]),
        ),
        Semantics(
          label: '게시물 내용 입력란입니다. 필수 항목입니다.',
          child: TextFormField(
            controller: _contentCtrl,
            maxLines: 8,
            decoration: InputDecoration(
              hintText: '구직 공고 내용을 입력하세요.\n서식 버튼으로 굵게·기울임·밑줄을 적용할 수 있습니다.',
              hintStyle:
                  const TextStyle(color: Color(0xFFBDBDBD), fontSize: 13),
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
          const Text('첨부 이미지',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF424242))),
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
                    width: 80,
                    height: 80,
                    fit: BoxFit.cover,
                    loadingBuilder: (_, child, progress) => progress == null
                        ? child
                        : const SizedBox(
                            width: 80,
                            height: 80,
                            child: Center(
                                child: CircularProgressIndicator(
                                    strokeWidth: 2))),
                    errorBuilder: (_, __, ___) => const SizedBox(
                        width: 80,
                        height: 80,
                        child: Icon(Icons.broken_image_rounded,
                            color: Colors.grey)),
                  ),
                ),
                Positioned(
                  top: 2,
                  right: 2,
                  child: Semantics(
                    label: '이미지 삭제 버튼입니다.',
                    child: GestureDetector(
                      onTap: () => _removeImage(i),
                      child: Container(
                        decoration: const BoxDecoration(
                            color: Colors.red, shape: BoxShape.circle),
                        padding: const EdgeInsets.all(2),
                        child: const Icon(Icons.close_rounded,
                            size: 14, color: Colors.white),
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
            : [],
      ),
    );
  }

  InputDecoration _inputDeco(String hint) => InputDecoration(
        hintText: hint,
        hintStyle:
            const TextStyle(color: Color(0xFFBDBDBD), fontSize: 13),
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
