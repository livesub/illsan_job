// 공지사항 관리 탭입니다.
// SUPER_ADMIN: 전체·반별 공지 등록/수정/삭제
// INSTRUCTOR : 반별 공지 등록, 본인 작성 공지만 수정/삭제
//
// 데이터 로드 전략:
//   - 삭제되지 않은 공지 전체를 최대 200건 로드
//   - 제목 검색 + 유형 필터는 클라이언트에서 처리
//   - 페이징도 클라이언트에서 처리

import 'dart:convert'; // 🌟 JSON 데이터 인코딩/디코딩용
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_quill/flutter_quill.dart'; // 🌟 스마트 에디터용

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

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

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
      case FsNotice.targetTeachers:  return '전체 교사';
      case FsNotice.targetStudents:  return '전체 학생';
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
        if (t != _typeFilter) return false;
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
      // 인라인 이미지 + 첨부파일 Storage Hard Delete (기존에 저장되어 있을 수 있는 파일들)
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
                _buildFilterChip('전체 교사', FsNotice.targetTeachers),
                const SizedBox(width: 8),
                _buildFilterChip('전체 학생', FsNotice.targetStudents),
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
          setState(() {
            _typeFilter = value;
            _resetFilter();
          });
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
// 공지사항 등록/수정 다이얼로그 (스마트 에디터 + 푸시 알림 발송 적용)
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
  final _formKey   = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();

  // 🌟 스마트 에디터 컨트롤러
  late QuillController _quillController;

  // 공지 유형: 'all' | 'course'
  String _target = FsNotice.targetAll;

  // 반별 공지 선택 강좌
  String? _selectedCourseId;

  List<Map<String, String>> _activeCourses = [];
  bool _loadingCourses = true;
  bool _saving = false;

  bool get _isEdit => widget.editDoc != null;

  /* 🌟 [차후 개발 보존] 첨부파일 및 이미지 변수 완전 주석 처리
  final List<String> _existAttachPaths   = [];
  final List<String> _existAttachNames   = [];
  final List<XFile>  _newAttachFiles     = [];
  final List<String> _removedAttachPaths = [];
  static const int   _maxAttach = 3;
  static const int   _maxBytes  = 3 * 1024 * 1024;
  
  final List<String> _imgPaths = [];
  final List<String> _imgUrls  = [];
  bool _uploadingImg = false;
  */

  static const Color _blue = Color(0xFF1565C0);

  @override
  void initState() {
    super.initState();
    _loadActiveCourses();
    _initFormAndEditor();
    
    // INSTRUCTOR 기본: 담당 반 전체 공지
    if (widget.userRole == UserRole.INSTRUCTOR && !_isEdit) {
      _target = FsNotice.targetCourseAll;
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _quillController.dispose();
    super.dispose();
  }

  // 🌟 핵심 로직: 기존 데이터를 불러와 폼과 에디터에 채웁니다.
  void _initFormAndEditor() {
    Document doc = Document(); // 빈 문서 생성

    if (_isEdit) {
      final data = widget.editDoc!.data() as Map<String, dynamic>;
      _titleCtrl.text = data[FsNotice.title] as String? ?? '';
      _target = data[FsNotice.target] as String? ?? FsNotice.targetAll;
      _selectedCourseId = data[FsNotice.courseId] as String?;

      // 공지 내용 불러오기 (JSON Delta 또는 일반 텍스트 호환)
      final content = data[FsNotice.content] as String? ?? '';
      if (content.isNotEmpty) {
        try {
          final decoded = jsonDecode(content);
          doc = Document.fromJson(decoded);
        } catch (e) {
          doc.insert(0, content);
        }
      }
    }

    // 컨트롤러 초기화
    _quillController = QuillController(
      document: doc,
      selection: const TextSelection.collapsed(offset: 0),
    );
  }

  // 활성 강좌 목록 로드
  Future<void> _loadActiveCourses() async {
    try {
      Query query = FirebaseFirestore.instance
          .collection(FsCol.courses)
          .where(FsCourse.status, isEqualTo: FsCourse.statusActive);
          
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
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingCourses = false);
    }
  }

  // 공지유형 → FCM topic 매핑 후 fcm_tasks 컬렉션에 write
  // Cloud Function onFcmTaskCreated 가 Admin SDK로 topic 발송 처리
  Future<void> _sendPushNotification(String noticeTitle) async {
    try {
      // 공지유형 → topic 변환 (클라이언트 FCM 직접 호출 불가 → Firestore write 방식)
      String topic;
      if (_target == FsNotice.targetTeachers) {
        topic = 'role_INSTRUCTOR';
      } else if (_target == FsNotice.targetStudents) {
        topic = 'role_STUDENT';
      } else if (_target == FsNotice.targetCourse) {
        // 특정 강좌 수강생 대상 — courseId 미선택 시 발송 중단
        if (_selectedCourseId == null || _selectedCourseId!.isEmpty) {
          debugPrint('[FCM] ❌ targetCourse인데 courseId 없음 → 발송 중단');
          return;
        }
        topic = 'course_$_selectedCourseId';
      } else if (_target == FsNotice.targetCourseAll) {
        // 담당 반 전체: CF가 authorId로 강좌 목록 조회 후 각 course_* topic 발송
        topic = 'courseAll';
      } else {
        // FsNotice.targetAll (전체)
        topic = 'all';
      }

      debugPrint('[FCM] 발송 요청 시작 → target: $_target | topic: $topic | title: $noticeTitle');

      // Firestore fcm_tasks write → Cloud Function이 Admin SDK로 FCM topic 발송
      final docRef = await FirebaseFirestore.instance.collection('fcm_tasks').add({
        'topic':     topic,
        'title':     '새 공지사항: $noticeTitle',
        'body':      'Job 알리미에 새로운 공지사항이 등록되었습니다.',
        'target':    _target,
        'courseId':  _selectedCourseId,
        'authorId':  widget.authorUid,
        'status':    'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });

      debugPrint('[FCM] ✅ fcm_tasks 저장 완료 → docId: ${docRef.id} | topic: $topic');
    } catch (e) {
      debugPrint('[FCM] ❌ 발송 요청 실패: $e');
    }
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
      // 🌟 에디터 내용을 JSON Delta 문자열로 변환
      final contentJson = jsonEncode(_quillController.document.toDelta().toJson());

      final payload = <String, dynamic>{
        FsNotice.title:       _titleCtrl.text.trim(),
        FsNotice.content:     contentJson, 
        FsNotice.target:      _target,
        FsNotice.courseId:    _target == FsNotice.targetCourse ? _selectedCourseId : null,
        FsNotice.inlineImgs:  [], 
        FsNotice.attachments: [], 
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

        // 🌟 [푸시 알림 발송] 공지 신규 등록이 성공적으로 완료되면 백그라운드에서 푸시를 발송합니다.
        // 수정(_isEdit)일 때는 알림이 가지 않도록 새 글 등록일 때만 호출합니다.
        _sendPushNotification(_titleCtrl.text.trim());
      }
      if (!mounted) return;

      // 🌟 마우스 트래커 에러 방지용 포커스 해제
      FocusManager.instance.primaryFocus?.unfocus();
      Future.delayed(const Duration(milliseconds: 50), () {
        if (!mounted) return;
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(_isEdit ? '공지가 수정되었습니다.' : '공지가 등록되었습니다.'),
            backgroundColor: const Color(0xFF00897B)));
      });
      
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
                onPressed: () {
                  // 닫기 버튼 누를 때도 포커스 해제
                  FocusManager.instance.primaryFocus?.unfocus();
                  final nav = Navigator.of(context);
                  Future.delayed(const Duration(milliseconds: 50), () {
                    if (!mounted) return;
                    nav.pop();
                  });
                },
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

                    // 2. 공지 유형
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

                    // 4. 내용 — 스마트 에디터 영역
                    _buildLabel('내용', required: true),
                    const SizedBox(height: 6),
                    _buildQuillEditor(),
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

  // 🌟 스마트 에디터 UI 구성 (이미지 버튼 완전 주석 처리, 툴바 분리 방식 적용)
  Widget _buildQuillEditor() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300), 
        borderRadius: BorderRadius.circular(8)
      ),
      child: Column(
        children: [
          // 1. 툴바 영역 (v11.5.0 방식에 맞춰 가로 스크롤 이슈 방지를 위해 Expanded 감쌈)
          Row(
            children: [
              // 기본 툴바 (왼쪽 차지)
              Expanded(
                child: QuillSimpleToolbar(
                  controller: _quillController,
                ),
              ),
              
              /* 🌟 [차후 개발 보존] 커스텀 이미지 버튼 완전 주석 처리 (스크린샷 요청 적용)
              Container(
                decoration: BoxDecoration(
                  border: Border(left: BorderSide(color: Colors.grey.shade300))
                ),
                child: IconButton(
                  icon: const Icon(Icons.image_rounded, color: _blue),
                  tooltip: '이미지 첨부',
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('이미지 저장은 차후 개발에 적용 됩니다.'),
                        backgroundColor: Colors.orange,
                      ),
                    );
                  },
                ),
              ),
              */
            ],
          ),
          const Divider(height: 1, thickness: 1),
          // 2. 입력창 영역
          Container(
            height: 300,
            padding: const EdgeInsets.all(12),
            child: QuillEditor.basic(
              controller: _quillController,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTargetSelector() {
    if (widget.userRole == UserRole.INSTRUCTOR) {
      return Row(children: [
        Expanded(
          child: _TargetChip(
            label: '담당 반 전체',
            icon: Icons.groups_rounded,
            selected: _target == FsNotice.targetCourseAll,
            enabled: true,
            onTap: () => setState(() => _target = FsNotice.targetCourseAll),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _TargetChip(
            label: '특정 반',
            icon: Icons.school_rounded,
            selected: _target == FsNotice.targetCourse,
            enabled: true,
            onTap: () => setState(() => _target = FsNotice.targetCourse),
          ),
        ),
      ]);
    }
    return Row(children: [
      Expanded(
        child: _TargetChip(
          label: '전체',
          icon: Icons.public_rounded,
          selected: _target == FsNotice.targetAll,
          enabled: true,
          onTap: () => setState(() => _target = FsNotice.targetAll),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: _TargetChip(
          label: '전체 교사',
          icon: Icons.person_rounded,
          selected: _target == FsNotice.targetTeachers,
          enabled: true,
          onTap: () => setState(() => _target = FsNotice.targetTeachers),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: _TargetChip(
          label: '전체 학생',
          icon: Icons.school_rounded,
          selected: _target == FsNotice.targetStudents,
          enabled: true,
          onTap: () => setState(() => _target = FsNotice.targetStudents),
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
          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 10),
          Text('강좌 목록 불러오는 중...', style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 13)),
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
        child: const Text('활성 강좌가 없습니다.', style: TextStyle(color: Colors.red, fontSize: 13)),
      );
    }
    return DropdownButtonFormField<String>(
      initialValue: _selectedCourseId,
      isExpanded: true,
      decoration: _inputDeco('강좌를 선택해 주세요.'),
      items: _activeCourses
          .map((c) => DropdownMenuItem<String>(
                value: c['id'],
                child: Text(c['name']!, style: const TextStyle(fontSize: 14)),
              ))
          .toList(),
      onChanged: (id) => setState(() {
        _selectedCourseId = id;
      }),
      validator: (v) => v == null ? '강좌를 선택해 주세요.' : null,
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