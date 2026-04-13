// 공지사항 관리 탭입니다.
// SUPER_ADMIN: 전체·반별 공지 등록/수정/삭제
// INSTRUCTOR : 반별 공지 등록, 본인 작성 공지만 수정/삭제
//
// 데이터 로드 전략:
//   - 삭제되지 않은 공지 전체를 최대 200건 로드
//   - 제목 검색 + 유형 필터는 클라이언트에서 처리
//   - 페이징도 클라이언트에서 처리

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/enums/user_role.dart';
import '../../../core/utils/firestore_keys.dart';

class NoticeTab extends StatefulWidget {
  final UserRole userRole;
  final String userName;
  const NoticeTab({super.key, required this.userRole, required this.userName});

  @override
  State<NoticeTab> createState() => _NoticeTabState();
}

class _NoticeTabState extends State<NoticeTab> {
  static const int _pageSize = 10;
  static const Color _blue = Color(0xFF1565C0);

  final String _uid = FirebaseAuth.instance.currentUser!.uid;

  List<QueryDocumentSnapshot> _allNotices      = [];
  List<QueryDocumentSnapshot> _filteredNotices = [];
  List<QueryDocumentSnapshot> _pagedNotices    = [];

  final TextEditingController _searchCtrl = TextEditingController();
  // null=전체, FsNotice.targetAll='all', FsNotice.targetCourse='course'
  String? _typeFilter;
  int _currentPage = 1;
  bool _hasMore    = false;
  bool _isLoading  = false;

  @override
  void initState() {
    super.initState();
    _loadAllNotices();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // 삭제되지 않은 공지 전체를 Firestore에서 로드합니다.
  Future<void> _loadAllNotices() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection(FsCol.notices)
          .where(FsNotice.isDeleted, isNotEqualTo: true)
          .orderBy(FsNotice.createdAt, descending: true)
          .limit(200)
          .get();
      if (!mounted) return;
      _allNotices = snap.docs;
      setState(() => _isLoading = false);
      _applyFilterAndPage();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('공지 목록 불러오기 실패: $e'), backgroundColor: Colors.red),
      );
    }
  }

  // 타겟 값 → 배지 텍스트
  static String _badgeLabel(String target) {
    switch (target) {
      case FsNotice.targetTeachers:  return '교사';
      case FsNotice.targetStudents:  return '학생';
      case FsNotice.targetCourse:    return '특정반';
      case FsNotice.targetCourseAll: return '전체반';
      default: return '전체';
    }
  }

  // 타겟 값 → 배지 색상
  static Color _badgeColor(String target) {
    switch (target) {
      case FsNotice.targetTeachers:  return const Color(0xFF00796B);
      case FsNotice.targetStudents:  return const Color(0xFF388E3C);
      case FsNotice.targetCourse:
      case FsNotice.targetCourseAll: return const Color(0xFFF57C00);
      default: return _blue;
    }
  }

  void _applyFilterAndPage() {
    final search = _searchCtrl.text.trim().toLowerCase();
    List<QueryDocumentSnapshot> filtered = _allNotices.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      if (_typeFilter != null) {
        final t = data[FsNotice.target] as String? ?? '';
        // '전체 공지' 필터: all / teachers / students 포함
        final isGlobal = t == FsNotice.targetAll || t == FsNotice.targetTeachers || t == FsNotice.targetStudents;
        if (_typeFilter == FsNotice.targetAll && !isGlobal) return false;
        if (_typeFilter == FsNotice.targetCourse && isGlobal) return false;
      }
      if (search.isNotEmpty) {
        final title = (data[FsNotice.title] as String? ?? '').toLowerCase();
        if (!title.contains(search)) return false;
      }
      return true;
    }).toList();

    _filteredNotices = filtered;
    final start = (_currentPage - 1) * _pageSize;
    final end   = start + _pageSize;
    setState(() {
      _pagedNotices = filtered.sublist(
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
      builder: (_) => _NoticeFormDialog(
        userRole: widget.userRole,
        userName: widget.userName,
        authorUid: _uid,
      ),
    );
    if (result == true) await _loadAllNotices();
  }

  Future<void> _showEditDialog(QueryDocumentSnapshot doc) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _NoticeFormDialog(
        userRole: widget.userRole,
        userName: widget.userName,
        authorUid: _uid,
        editDoc: doc,
      ),
    );
    if (result == true) await _loadAllNotices();
  }

  // 공지 삭제: is_deleted: true + Storage 이미지 Hard Delete
  Future<void> _deleteNotice(QueryDocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;
    final title = data[FsNotice.title] as String? ?? '이 공지';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(children: [
          Icon(Icons.delete_rounded, color: Color(0xFFD32F2F), size: 22),
          SizedBox(width: 8),
          Text('공지 삭제', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
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

    try {
      // 인라인 이미지 + 첨부파일 Storage Hard Delete
      final imgPaths    = (data[FsNotice.inlineImgs]  as List?)?.cast<String>() ?? [];
      final attachPaths = (data[FsNotice.attachments] as List?)?.cast<String>() ?? [];
      for (final path in [...imgPaths, ...attachPaths]) {
        try { await FirebaseStorage.instance.ref(path).delete(); } catch (_) {}
      }
      await FirebaseFirestore.instance
          .collection(FsCol.notices)
          .doc(doc.id)
          .update({FsNotice.isDeleted: true});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('공지가 삭제되었습니다.'), backgroundColor: Colors.red),
      );
      await _loadAllNotices();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('삭제 실패: $e'), backgroundColor: Colors.red),
      );
    }
  }

  // INSTRUCTOR는 본인 작성 공지만 수정/삭제 가능합니다.
  bool _canEdit(QueryDocumentSnapshot doc) {
    if (widget.userRole == UserRole.SUPER_ADMIN) return true;
    final data = doc.data() as Map<String, dynamic>;
    return data[FsNotice.authorId] == _uid;
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
                    Text('공지사항 관리',
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1A1A2E))),
                    SizedBox(height: 4),
                    Text('공지사항을 등록하고 관리합니다.',
                        style: TextStyle(fontSize: 14, color: Color(0xFF757575))),
                  ],
                ),
              ),
              Semantics(
                label: '공지사항 등록 버튼입니다.',
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    minimumSize: Size.zero,
                  ),
                  onPressed: _showAddDialog,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('공지 등록',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── 제목 검색 ─────────────────────────────────────
          Semantics(
            label: '공지 제목 검색 입력란입니다.',
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
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── 유형 필터 칩 ─────────────────────────────────
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip('전체', null),
                const SizedBox(width: 8),
                _buildFilterChip('전체 공지', FsNotice.targetAll),
                const SizedBox(width: 8),
                _buildFilterChip('반별 공지', FsNotice.targetCourse),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── 목록 카드 ─────────────────────────────────────
          _buildNoticeList(),
          const SizedBox(height: 12),
          _buildPagination(),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String? value) {
    final bool isSelected = _typeFilter == value;
    return Semantics(
      label: '$label 필터 버튼입니다.',
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) {
          _typeFilter = value;
          _resetFilter();
        },
        selectedColor: _blue,
        labelStyle: TextStyle(
            color: isSelected ? Colors.white : const Color(0xFF1A1A2E),
            fontWeight: FontWeight.w600,
            fontSize: 13),
        backgroundColor: Colors.white,
        side: const BorderSide(color: Color(0xFFE0E0E0)),
        checkmarkColor: Colors.white,
      ),
    );
  }

  Widget _buildNoticeList() {
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
              '공지 목록 (검색 결과 ${_filteredNotices.length}건 / 전체 ${_allNotices.length}건)',
              style: const TextStyle(
                  color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
          if (_isLoading)
            const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()))
          else if (_pagedNotices.isEmpty)
            const Padding(
                padding: EdgeInsets.all(32),
                child: Text('등록된 공지사항이 없습니다.',
                    style: TextStyle(color: Color(0xFF757575))))
          else
            Column(children: _pagedNotices.map(_buildNoticeTile).toList()),
        ],
      ),
    );
  }

  Widget _buildNoticeTile(QueryDocumentSnapshot doc) {
    final data       = doc.data() as Map<String, dynamic>;
    final title      = data[FsNotice.title]      as String? ?? '제목 없음';
    final target     = data[FsNotice.target]     as String? ?? FsNotice.targetAll;
    final author     = data[FsNotice.authorName] as String? ?? '';
    final created    = data[FsNotice.createdAt]  as String? ?? '';
    final badgeLabel = _badgeLabel(target);
    final badgeColor = _badgeColor(target);
    final canEdit    = _canEdit(doc);

    // created_at: yymmddHis → 표시용 포맷 (26-04-05)
    String dateStr = created;
    if (created.length >= 6) {
      dateStr = '20${created.substring(0, 2)}-${created.substring(2, 4)}-${created.substring(4, 6)}';
    }

    return Semantics(
      label: '$title, $badgeLabel 공지, 작성자: $author, 작성일: $dateStr',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0)))),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              badgeLabel,
              style: TextStyle(
                  color: badgeColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              Text('$author · $dateStr',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF757575))),
            ]),
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
                icon: const Icon(Icons.delete_rounded,
                    size: 18, color: Color(0xFFD32F2F)),
                onPressed: () => _deleteNotice(doc),
                tooltip: '삭제',
              ),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _buildPagination() {
    if (_filteredNotices.isEmpty) return const SizedBox.shrink();
    final totalPages = ((_filteredNotices.length - 1) ~/ _pageSize) + 1;
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
// 공지사항 등록/수정 다이얼로그
// ─────────────────────────────────────────────────────────
class _NoticeFormDialog extends StatefulWidget {
  final UserRole userRole;
  final String userName;
  final String authorUid;
  final QueryDocumentSnapshot? editDoc;

  const _NoticeFormDialog({
    required this.userRole,
    required this.userName,
    required this.authorUid,
    this.editDoc,
  });

  @override
  State<_NoticeFormDialog> createState() => _NoticeFormDialogState();
}

class _NoticeFormDialogState extends State<_NoticeFormDialog> {
  final _formKey    = GlobalKey<FormState>();
  final _titleCtrl  = TextEditingController();
  final _contentCtrl = TextEditingController();

  // 공지 유형: 'all' | 'course'
  String _target = FsNotice.targetAll;

  // 반별 공지 선택 강좌
  String? _selectedCourseId;
  String? _selectedCourseName;

  List<Map<String, String>> _activeCourses = [];
  bool _loadingCourses = true;
  bool _saving = false;

  bool get _isEdit => widget.editDoc != null;

  // 인라인 이미지 Storage 경로 + URL 목록
  final List<String> _imgPaths = [];
  final List<String> _imgUrls  = [];
  bool _uploadingImg = false;

  // 첨부파일 — 기존(수정 시) + 신규
  final List<String> _existAttachPaths   = [];
  final List<String> _existAttachNames   = [];
  final List<XFile>  _newAttachFiles     = [];
  final List<String> _removedAttachPaths = []; // 수정 시 삭제 예약

  static const int   _maxAttach = 3;
  static const int   _maxBytes  = 3 * 1024 * 1024; // 3MB
  static const Color _blue      = Color(0xFF1565C0);

  @override
  void initState() {
    super.initState();
    _loadActiveCourses();
    if (_isEdit) {
      _prefillForm();
      _loadInlineImages();
      _loadExistAttachments();
    }
    // INSTRUCTOR 기본: 담당 반 전체 공지
    if (widget.userRole == UserRole.INSTRUCTOR) {
      _target = FsNotice.targetCourseAll;
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
    _titleCtrl.text   = data[FsNotice.title]   as String? ?? '';
    _contentCtrl.text = data[FsNotice.content] as String? ?? '';
    _target = data[FsNotice.target] as String? ?? FsNotice.targetAll;
    _selectedCourseId   = data[FsNotice.courseId] as String?;
  }

  // 활성 강좌 목록을 Firestore에서 가져옵니다.
  Future<void> _loadActiveCourses() async {
    try {
      Query query = FirebaseFirestore.instance
          .collection(FsCol.courses)
          .where(FsCourse.status, isEqualTo: FsCourse.statusActive);
      // INSTRUCTOR는 본인 담당 강좌만 표시합니다.
      if (widget.userRole == UserRole.INSTRUCTOR) {
        query = query.where(FsCourse.teacherId, isEqualTo: widget.authorUid);
      }
      final snap = await query.orderBy(FsCourse.name).get();
      if (!mounted) return;
      final courses = snap.docs.map((d) {
        final data = d.data() as Map<String, dynamic>;
        return {
          'id':   d.id,
          'name': data[FsCourse.name] as String? ?? '강좌명 없음',
        };
      }).toList();
      setState(() {
        _activeCourses = courses;
        _loadingCourses = false;
        // 수정 모드에서 강좌명 복원
        if (_selectedCourseId != null) {
          final match = courses.where((c) => c['id'] == _selectedCourseId);
          _selectedCourseName = match.isNotEmpty ? match.first['name'] : null;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingCourses = false);
    }
  }

  // 수정 모드: 기존 인라인 이미지 URL을 Storage에서 로드합니다.
  Future<void> _loadInlineImages() async {
    final data = widget.editDoc!.data() as Map<String, dynamic>;
    final paths = (data[FsNotice.inlineImgs] as List?)?.cast<String>() ?? [];
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
      final now = DateTime.now();
      final path =
          '${StoragePath.inlinePath(StoragePath.boardNotice, now.year, now.month)}'
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
    try { await FirebaseStorage.instance.ref(path).delete(); } catch (_) {}
    if (!mounted) return;
    setState(() {
      _imgPaths.removeAt(index);
      _imgUrls.removeAt(index);
    });
  }

  void _loadExistAttachments() {
    final data  = widget.editDoc!.data() as Map<String, dynamic>;
    final paths = (data[FsNotice.attachments] as List?)?.cast<String>() ?? [];
    for (final p in paths) {
      _existAttachPaths.add(p);
      _existAttachNames.add(p.split('/').last);
    }
  }

  // file_picker size 속성 사용 — dart:io File 금지 (웹 크래시 방지)
  Future<void> _pickAttachment() async {
    final total = _existAttachPaths.length + _newAttachFiles.length;
    if (total >= _maxAttach) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('첨부파일은 최대 3개까지 가능합니다.'),
            backgroundColor: Colors.orange),
      );
      return;
    }
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: false,
    );
    if (result == null || result.files.isEmpty || !mounted) return;

    final pf   = result.files.first;
    final size = pf.size; // file_picker 제공 size (웹/모바일 공통)

    if (size > _maxBytes) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: const Row(children: [
            Icon(Icons.warning_rounded, color: Colors.orange, size: 22),
            SizedBox(width: 8),
            Text('용량 초과', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          ]),
          content: const Text('파일 용량은 3MB를 초과할 수 없습니다.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('확인'),
            ),
          ],
        ),
      );
      return;
    }
    setState(() => _newAttachFiles.add(XFile(pf.path ?? '', name: pf.name)));
  }

  void _removeExistAttach(int index) {
    setState(() {
      _removedAttachPaths.add(_existAttachPaths[index]);
      _existAttachPaths.removeAt(index);
      _existAttachNames.removeAt(index);
    });
  }

  void _removeNewAttach(int index) {
    setState(() => _newAttachFiles.removeAt(index));
  }

  void _wrapSelection(String open, String close) {
    final sel  = _contentCtrl.selection;
    if (!sel.isValid) return;
    final text = _contentCtrl.text;
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
    if (_target == FsNotice.targetCourse && _selectedCourseId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('대상 강좌를 선택해 주세요.'), backgroundColor: Colors.orange));
      return;
    }
    setState(() => _saving = true);

    try {
      final now = DateTime.now();

      // 신규 첨부파일 Storage 업로드
      final uploadedPaths = List<String>.from(_existAttachPaths);
      for (final xf in _newAttachFiles) {
        final bytes = await xf.readAsBytes();
        final path =
            '${StoragePath.attachmentPath(StoragePath.boardNotice, now.year, now.month)}'
            '${now.millisecondsSinceEpoch}_${xf.name}';
        await FirebaseStorage.instance.ref(path).putData(bytes);
        uploadedPaths.add(path);
      }

      // 수정 시 제거된 파일 Hard Delete
      for (final path in _removedAttachPaths) {
        try { await FirebaseStorage.instance.ref(path).delete(); } catch (_) {}
      }

      final payload = <String, dynamic>{
        FsNotice.title:       _titleCtrl.text.trim(),
        FsNotice.content:     _contentCtrl.text.trim(),
        FsNotice.target:      _target,
        FsNotice.courseId:    _target == FsNotice.targetCourse ? _selectedCourseId : null,
        FsNotice.inlineImgs:  _imgPaths,
        FsNotice.attachments: uploadedPaths,
      };

      if (_isEdit) {
        await FirebaseFirestore.instance
            .collection(FsCol.notices)
            .doc(widget.editDoc!.id)
            .update(payload);
      } else {
        await FirebaseFirestore.instance.collection(FsCol.notices).add({
          ...payload,
          FsNotice.authorId:   widget.authorUid,
          FsNotice.authorName: widget.userName,
          FsNotice.isDeleted:  false,
          FsNotice.createdAt:  StoragePath.nowCreatedAt(),
        });
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_isEdit ? '공지가 수정되었습니다.' : '공지가 등록되었습니다.'),
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
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
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
              Icon(_isEdit ? Icons.edit_rounded : Icons.campaign_rounded,
                  color: Colors.white, size: 22),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(_isEdit ? '공지 수정' : '공지 등록',
                      style: const TextStyle(
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
                      label: '공지 제목 입력란입니다. 필수 항목입니다.',
                      child: TextFormField(
                        controller: _titleCtrl,
                        decoration: _inputDeco('예) 5월 공휴일 휴강 안내'),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? '제목을 입력해 주세요.' : null,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // 2. 공지 유형 (SUPER_ADMIN만 전체 공지 선택 가능)
                    _buildLabel('공지 유형', required: true),
                    const SizedBox(height: 6),
                    _buildTargetSelector(),
                    const SizedBox(height: 20),

                    // 3. 대상 강좌 (반별 공지일 때만 표시)
                    if (_target == FsNotice.targetCourse) ...[
                      _buildLabel('대상 강좌', required: true),
                      const SizedBox(height: 6),
                      _buildCourseDropdown(),
                      const SizedBox(height: 20),
                    ],

                    // 4. 내용 — 스마트 에디터
                    _buildLabel('내용', required: true),
                    const SizedBox(height: 6),
                    _buildSmartEditor(),
                    const SizedBox(height: 20),

                    // 5. 첨부파일 (숨김)
                    if (false) ...[
                      _buildLabel('첨부파일'),
                      const SizedBox(height: 4),
                      const Text('최대 3개 · 각 3MB 이하',
                          style: TextStyle(fontSize: 11, color: Color(0xFF9E9E9E))),
                      const SizedBox(height: 8),
                      _buildAttachSection(),
                    ],
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
                                      fontSize: 16, fontWeight: FontWeight.w700)),
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

  // 공지 대상 선택 (역할별 분기)
  Widget _buildTargetSelector() {
    // INSTRUCTOR: 담당 반 전체 / 특정 반
    if (widget.userRole == UserRole.INSTRUCTOR) {
      return Row(children: [
        Expanded(
          child: Semantics(
            label: '담당 반 전체 선택 버튼입니다.',
            child: _TargetChip(
              label: '담당 반 전체',
              icon: Icons.groups_rounded,
              selected: _target == FsNotice.targetCourseAll,
              enabled: true,
              onTap: () => setState(() => _target = FsNotice.targetCourseAll),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Semantics(
            label: '특정 반 선택 버튼입니다.',
            child: _TargetChip(
              label: '특정 반',
              icon: Icons.school_rounded,
              selected: _target == FsNotice.targetCourse,
              enabled: true,
              onTap: () => setState(() => _target = FsNotice.targetCourse),
            ),
          ),
        ),
      ]);
    }
    // SUPER_ADMIN: 전체(교사+학생) / 전체 교사 / 전체 학생
    return Row(children: [
      Expanded(
        child: Semantics(
          label: '전체 대상 공지 선택 버튼입니다.',
          child: _TargetChip(
            label: '전체',
            icon: Icons.public_rounded,
            selected: _target == FsNotice.targetAll,
            enabled: true,
            onTap: () => setState(() => _target = FsNotice.targetAll),
          ),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Semantics(
          label: '전체 교사 대상 선택 버튼입니다.',
          child: _TargetChip(
            label: '전체 교사',
            icon: Icons.person_rounded,
            selected: _target == FsNotice.targetTeachers,
            enabled: true,
            onTap: () => setState(() => _target = FsNotice.targetTeachers),
          ),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Semantics(
          label: '전체 학생 대상 선택 버튼입니다.',
          child: _TargetChip(
            label: '전체 학생',
            icon: Icons.school_rounded,
            selected: _target == FsNotice.targetStudents,
            enabled: true,
            onTap: () => setState(() => _target = FsNotice.targetStudents),
          ),
        ),
      ),
    ]);
  }

  Widget _buildCourseDropdown() {
    if (_loadingCourses) {
      return Container(
        height: 50,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFE0E0E0)),
          borderRadius: BorderRadius.circular(10),
          color: Colors.white,
        ),
        child: const Row(children: [
          SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 10),
          Text('강좌 목록 불러오는 중...',
              style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 13)),
        ]),
      );
    }
    if (_activeCourses.isEmpty) {
      return Container(
        height: 50,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.red.shade200),
          borderRadius: BorderRadius.circular(10),
          color: Colors.red.shade50,
        ),
        child: const Text('활성 강좌가 없습니다.',
            style: TextStyle(color: Colors.red, fontSize: 13)),
      );
    }
    return Semantics(
      label: '대상 강좌 선택 드롭다운입니다. 필수 항목입니다.',
      child: DropdownButtonFormField<String>(
        // ignore: deprecated_member_use
        value: _selectedCourseId,
        isExpanded: true,
        decoration: _inputDeco('강좌를 선택해 주세요.'),
        items: _activeCourses
            .map((c) => DropdownMenuItem<String>(
                  value: c['id'],
                  child: Text(c['name']!, style: const TextStyle(fontSize: 14)),
                ))
            .toList(),
        onChanged: (id) => setState(() {
          _selectedCourseId   = id;
          _selectedCourseName = _activeCourses
              .firstWhere((c) => c['id'] == id)['name'];
        }),
        validator: (v) => v == null ? '강좌를 선택해 주세요.' : null,
      ),
    );
  }

  // 서식 툴바 + 내용 입력 + 인라인 이미지 섹션
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
            Semantics(
              label: '텍스트 색상 선택 버튼입니다.',
              child: PopupMenuButton<String>(
                tooltip: '텍스트 색상',
                offset: const Offset(0, 36),
                icon: const Icon(Icons.format_color_text_rounded, size: 20),
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                padding: EdgeInsets.zero,
                onSelected: (hex) =>
                    _wrapSelection('<font color="$hex">', '</font>'),
                itemBuilder: (_) {
                  final items = [
                    ('빨강', '#D32F2F', const Color(0xFFD32F2F)),
                    ('파랑', '#1565C0', const Color(0xFF1565C0)),
                    ('초록', '#2E7D32', const Color(0xFF2E7D32)),
                    ('주황', '#E65100', const Color(0xFFE65100)),
                    ('보라', '#6A1B9A', const Color(0xFF6A1B9A)),
                    ('검정', '#212121', const Color(0xFF212121)),
                  ];
                  return items
                      .map((c) => PopupMenuItem<String>(
                            value: c.$2,
                            child: Row(children: [
                              Container(
                                width: 16,
                                height: 16,
                                decoration: BoxDecoration(
                                    color: c.$3,
                                    borderRadius: BorderRadius.circular(3)),
                              ),
                              const SizedBox(width: 8),
                              Text(c.$1,
                                  style: const TextStyle(fontSize: 13)),
                            ]),
                          ))
                      .toList();
                },
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
                      constraints:
                          const BoxConstraints(minWidth: 36, minHeight: 36),
                      padding: EdgeInsets.zero,
                    ),
            ),
          ]),
        ),
        Semantics(
          label: '공지 내용 입력란입니다. 필수 항목입니다.',
          child: TextFormField(
            controller: _contentCtrl,
            maxLines: 8,
            decoration: InputDecoration(
              hintText: '공지 내용을 입력하세요.\n서식 버튼으로 굵게·기울임·밑줄을 적용할 수 있습니다.',
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
        // 미리보기 영역
        const SizedBox(height: 12),
        Row(children: const [
          Icon(Icons.preview_rounded, size: 14, color: Color(0xFF757575)),
          SizedBox(width: 4),
          Text('미리보기',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF757575))),
        ]),
        const SizedBox(height: 4),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _contentCtrl,
          builder: (_, val, __) => _buildPreviewBox(val.text),
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
                    loadingBuilder: (_, child, progress) =>
                        progress == null
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

  Widget _buildPreviewBox(String text) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 60),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE0E0E0)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: text.trim().isEmpty
          ? const Text('내용을 입력하면 미리보기가 표시됩니다.',
              style: TextStyle(color: Color(0xFFBDBDBD), fontSize: 13))
          : RichText(
              text: TextSpan(
                style: const TextStyle(
                    color: Color(0xFF1A1A2E), fontSize: 14, height: 1.6),
                children: _parseHtmlSpans(text),
              ),
            ),
    );
  }

  // `<b>`, `<i>`, `<u>`, `<font color>` 태그를 파싱해 InlineSpan 목록으로 변환
  List<InlineSpan> _parseHtmlSpans(String html) {
    final spans = <InlineSpan>[];
    final tagRe = RegExp(r'<(/?)(\w+)([^>]*)>', caseSensitive: false);
    int boldDepth = 0, italicDepth = 0, underlineDepth = 0;
    final colorStack = <Color?>[];

    void addText(String text) {
      if (text.isEmpty) return;
      spans.add(TextSpan(
        text: text,
        style: TextStyle(
          fontWeight: boldDepth > 0 ? FontWeight.bold : FontWeight.normal,
          fontStyle: italicDepth > 0 ? FontStyle.italic : FontStyle.normal,
          decoration:
              underlineDepth > 0 ? TextDecoration.underline : TextDecoration.none,
          color: colorStack.isNotEmpty ? colorStack.last : null,
        ),
      ));
    }

    int pos = 0;
    for (final m in tagRe.allMatches(html)) {
      addText(html.substring(pos, m.start));
      pos = m.end;
      final closing = m.group(1) == '/';
      final tag = m.group(2)!.toLowerCase();
      final attrs = m.group(3) ?? '';
      if (!closing) {
        switch (tag) {
          case 'b':
            boldDepth++;
          case 'i':
            italicDepth++;
          case 'u':
            underlineDepth++;
          case 'font':
            final cm =
                RegExp(r'color="([^"]+)"', caseSensitive: false).firstMatch(attrs);
            if (cm != null) {
              final hex = cm.group(1)!.replaceAll('#', '');
              try {
                colorStack.add(Color(int.parse('FF$hex', radix: 16)));
              } catch (_) {
                colorStack.add(null);
              }
            } else {
              colorStack.add(null);
            }
        }
      } else {
        switch (tag) {
          case 'b':
            if (boldDepth > 0) boldDepth--;
          case 'i':
            if (italicDepth > 0) italicDepth--;
          case 'u':
            if (underlineDepth > 0) underlineDepth--;
          case 'font':
            if (colorStack.isNotEmpty) colorStack.removeLast();
        }
      }
    }
    addText(html.substring(pos));
    return spans;
  }

  Widget _buildAttachSection() {
    final totalCount = _existAttachPaths.length + _newAttachFiles.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ..._existAttachPaths.asMap().entries.map((e) => _buildAttachTile(
              name: _existAttachNames[e.key],
              onRemove: () => _removeExistAttach(e.key),
              isNew: false,
            )),
        ..._newAttachFiles.asMap().entries.map((e) => _buildAttachTile(
              name: e.value.name,
              onRemove: () => _removeNewAttach(e.key),
              isNew: true,
            )),
        if (totalCount < _maxAttach)
          Semantics(
            label: '첨부파일 추가 버튼입니다.',
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: _blue,
                side: const BorderSide(color: _blue),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                minimumSize: Size.zero,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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

  Widget _buildAttachTile(
      {required String name,
      required VoidCallback onRemove,
      required bool isNew}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        const Icon(Icons.insert_drive_file_rounded,
            size: 16, color: Color(0xFF757575)),
        const SizedBox(width: 6),
        Expanded(
            child: Text(name,
                style: const TextStyle(fontSize: 12),
                overflow: TextOverflow.ellipsis)),
        if (isNew)
          const Text('신규',
              style: TextStyle(fontSize: 10, color: Color(0xFF00897B))),
        const SizedBox(width: 4),
        Semantics(
          label: '$name 첨부파일 삭제 버튼입니다.',
          child: GestureDetector(
            onTap: onRemove,
            child: const Icon(Icons.close_rounded,
                size: 16, color: Color(0xFFD32F2F)),
          ),
        ),
      ]),
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

// 공지 유형 선택 칩 위젯
class _TargetChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;

  const _TargetChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.enabled,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color activeColor = const Color(0xFF1565C0);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? activeColor : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: selected ? activeColor : const Color(0xFFE0E0E0)),
          boxShadow: selected
              ? [BoxShadow(color: activeColor.withValues(alpha: 0.2), blurRadius: 6)]
              : [],
        ),
        child: Column(children: [
          Icon(icon,
              size: 22,
              color: selected
                  ? Colors.white
                  : (enabled ? const Color(0xFF757575) : const Color(0xFFBDBDBD))),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? Colors.white
                      : (enabled
                          ? const Color(0xFF424242)
                          : const Color(0xFFBDBDBD)))),
        ]),
      ),
    );
  }
}
