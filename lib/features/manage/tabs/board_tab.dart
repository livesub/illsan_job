// 게시판 탭 — 공지사항 캐러셀 + 구직 무한 스크롤 + 댓글 Q&A
// INSTRUCTOR/SUPER_ADMIN: 지원 버튼 숨김, 타인 댓글 삭제(가림 처리) 권한

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/enums/user_role.dart';
import '../../../core/utils/auth_service.dart';
import '../../../core/utils/firestore_keys.dart';

class BoardTab extends StatefulWidget {
  final UserRole userRole;
  final String userName;
  const BoardTab({super.key, required this.userRole, required this.userName});

  @override
  State<BoardTab> createState() => _BoardTabState();
}

class _BoardTabState extends State<BoardTab> {
  static const Color _blue = Color(0xFF1565C0);
  static const int _jobPageSize = 15;

  final _db = FirebaseFirestore.instance;
  final _scrollCtrl = ScrollController();
  final _pageCtrl = PageController();

  List<QueryDocumentSnapshot> _notices = [];
  int _pageIndex = 0;
  Timer? _carouselTimer;

  List<QueryDocumentSnapshot> _jobs = [];
  DocumentSnapshot? _lastJobDoc;
  bool _hasMore = true;
  bool _loadingJobs = false;
  bool _initialLoading = true;

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _loadNotices();
    _loadJobs();
  }

  @override
  void dispose() {
    _carouselTimer?.cancel();
    _pageCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 300) {
      _loadJobs();
    }
  }

  Future<void> _loadNotices() async {
    // createdAt 단일 인덱스 사용, isDeleted 클라이언트 필터로 복합 인덱스 회피
    final snap = await _db
        .collection(FsCol.notices)
        .orderBy(FsNotice.createdAt, descending: true)
        .limit(20)
        .get();
    if (!mounted) return;
    final filtered = snap.docs.where((d) {
      final data = d.data() as Map<String, dynamic>;
      return !((data[FsNotice.isDeleted] as bool?) ?? false);
    }).take(5).toList();
    setState(() => _notices = filtered);
    if (_notices.length > 1) _startCarouselTimer();
  }

  void _startCarouselTimer() {
    _carouselTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || _notices.isEmpty) return;
      final next = (_pageIndex + 1) % _notices.length;
      _pageCtrl.animateToPage(next,
          duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
    });
  }

  Future<void> _loadJobs() async {
    if (_loadingJobs || !_hasMore) return;
    setState(() => _loadingJobs = true);
    try {
      var query = _db
          .collection(FsCol.jobs)
          .orderBy(FsJob.createdAt, descending: true)
          .limit(_jobPageSize);
      if (_lastJobDoc != null) query = query.startAfterDocument(_lastJobDoc!);
      final snap = await query.get();
      if (!mounted) return;
      final newDocs = snap.docs.where((d) {
        final data = d.data() as Map<String, dynamic>;
        return !((data[FsJob.isDeleted] as bool?) ?? false);
      }).toList();
      setState(() {
        _jobs.addAll(newDocs);
        if (snap.docs.isNotEmpty) _lastJobDoc = snap.docs.last;
        _hasMore = snap.docs.length == _jobPageSize;
        _loadingJobs = false;
        _initialLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loadingJobs = false; _initialLoading = false; });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('구직 목록 로드 실패: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_initialLoading) return const Center(child: CircularProgressIndicator());
    return CustomScrollView(
      controller: _scrollCtrl,
      slivers: [
        const SliverToBoxAdapter(child: SizedBox(height: 20)),
        // 공지사항 캐러셀
        if (_notices.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('공지사항',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E))),
                  const SizedBox(height: 12),
                  _buildCarousel(),
                ],
              ),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
        // 구직 공고 헤더
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Text('구직 공고',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E))),
                const SizedBox(width: 8),
                Text('(${_jobs.length}건)',
                    style: const TextStyle(fontSize: 13, color: Color(0xFF757575))),
              ],
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
        // 구직 공고 리스트
        if (_jobs.isEmpty && !_loadingJobs)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Center(
                child: Text('등록된 구직 공고가 없습니다.',
                    style: TextStyle(color: Color(0xFF757575), fontSize: 14)),
              ),
            ),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (_, i) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _JobCard(
                  doc: _jobs[i],
                  onTap: () => _openJobDetail(_jobs[i]),
                ),
              ),
              childCount: _jobs.length,
            ),
          ),
        // 로딩 / 끝 표시
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: _loadingJobs
                ? const Center(child: CircularProgressIndicator())
                : !_hasMore && _jobs.isNotEmpty
                    ? const Center(
                        child: Text('모든 공고를 불러왔습니다.',
                            style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 13)))
                    : const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }

  Widget _buildCarousel() {
    return Container(
      height: 88,
      decoration: BoxDecoration(
        color: _blue.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _blue.withValues(alpha: 0.2)),
      ),
      child: Stack(
        children: [
          PageView.builder(
            controller: _pageCtrl,
            itemCount: _notices.length,
            onPageChanged: (i) => setState(() => _pageIndex = i),
            itemBuilder: (_, i) {
              final data = _notices[i].data() as Map<String, dynamic>;
              final title = data[FsNotice.title] as String? ?? '-';
              return Semantics(
                label: '공지사항: $title',
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 22),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _blue,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('공지',
                            style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(title,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E)),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          // 페이지 도트
          Positioned(
            bottom: 8,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _notices.length,
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: _pageIndex == i ? 16 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: _pageIndex == i ? _blue : _blue.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openJobDetail(QueryDocumentSnapshot doc) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _JobDetailPage(
          jobDoc: doc,
          userRole: widget.userRole,
          currentUid: _uid,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// 구직 공고 카드 (리스트 아이템)
// ─────────────────────────────────────────────────────────
class _JobCard extends StatelessWidget {
  final QueryDocumentSnapshot doc;
  final VoidCallback onTap;
  const _JobCard({required this.doc, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final data = doc.data() as Map<String, dynamic>;
    final title      = data[FsJob.title]      as String? ?? '-';
    final authorName = data[FsJob.authorName] as String? ?? '-';
    final period     = data[FsJob.period]     as String? ?? '-';

    return Semantics(
      label: '$title 구직 공고, $authorName 등록, 기간: $period',
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2))],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF00897B).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.work_rounded, color: Color(0xFF00897B), size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Text('$authorName · $period',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF757575))),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFF9E9E9E), size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// 구직 공고 상세 페이지 (지원하기 + 묻고 답하기)
// ─────────────────────────────────────────────────────────
class _JobDetailPage extends StatefulWidget {
  final QueryDocumentSnapshot jobDoc;
  final UserRole userRole;
  final String currentUid;
  const _JobDetailPage({
    required this.jobDoc,
    required this.userRole,
    required this.currentUid,
  });

  @override
  State<_JobDetailPage> createState() => _JobDetailPageState();
}

class _JobDetailPageState extends State<_JobDetailPage> {
  static const Color _blue = Color(0xFF1565C0);

  bool _hasApplied  = false;
  bool _applyLoading = false;

  // INSTRUCTOR/SUPER_ADMIN은 지원 버튼 자체를 숨김
  bool get _canApply => widget.userRole == UserRole.STUDENT;

  @override
  void initState() {
    super.initState();
    if (_canApply) _checkApplied();
  }

  Future<void> _checkApplied() async {
    final snap = await FirebaseFirestore.instance
        .collection(FsCol.jobApplications)
        .where(FsJobApp.jobId, isEqualTo: widget.jobDoc.id)
        .where(FsJobApp.applicantId, isEqualTo: widget.currentUid)
        .where(FsJobApp.status, whereIn: [FsJobApp.statusPending, FsJobApp.statusApproved])
        .limit(1)
        .get();
    if (!mounted) return;
    setState(() => _hasApplied = snap.docs.isNotEmpty);
  }

  Future<void> _applyJob() async {
    setState(() => _applyLoading = true);
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection(FsCol.users)
          .doc(widget.currentUid)
          .get();
      final userData = userDoc.data()!;
      final jobData  = widget.jobDoc.data() as Map<String, dynamic>;

      // 소속 강좌명 조회
      final courseId = userData[FsUser.courseId] as String? ?? '';
      String courseName = '';
      if (courseId.isNotEmpty) {
        final courseDoc = await FirebaseFirestore.instance
            .collection(FsCol.courses)
            .doc(courseId)
            .get();
        courseName = (courseDoc.data()?[FsCourse.name] as String?) ?? '';
      }

      await FirebaseFirestore.instance.collection(FsCol.jobApplications).add({
        FsJobApp.jobId:          widget.jobDoc.id,
        FsJobApp.jobTitle:       jobData[FsJob.title],
        FsJobApp.authorId:       jobData[FsJob.authorId],
        FsJobApp.applicantId:    widget.currentUid,
        FsJobApp.applicantName:  userData[FsUser.name] ?? '',
        FsJobApp.applicantEmail: userData[FsUser.email] ?? '',
        FsJobApp.courseId:       courseId,
        FsJobApp.courseName:     courseName,
        FsJobApp.status:         FsJobApp.statusPending,
        FsJobApp.appliedAt:      FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      setState(() { _hasApplied = true; _applyLoading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() => _applyLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('지원 실패: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _cancelApply() async {
    setState(() => _applyLoading = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection(FsCol.jobApplications)
          .where(FsJobApp.jobId, isEqualTo: widget.jobDoc.id)
          .where(FsJobApp.applicantId, isEqualTo: widget.currentUid)
          .where(FsJobApp.status, isEqualTo: FsJobApp.statusPending)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection(FsCol.jobApplications)
            .doc(snap.docs.first.id)
            .update({FsJobApp.status: FsJobApp.statusCancelled});
      }
      if (!mounted) return;
      setState(() { _hasApplied = false; _applyLoading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() => _applyLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data       = widget.jobDoc.data() as Map<String, dynamic>;
    final title      = data[FsJob.title]      as String? ?? '-';
    final authorName = data[FsJob.authorName] as String? ?? '-';
    final period     = data[FsJob.period]     as String? ?? '-';
    final content    = data[FsJob.content]    as String? ?? '';
    // HTML 태그 제거 후 평문 표시
    final plainText  = content.replaceAll(RegExp(r'<[^>]*>'), '').trim();

    return Scaffold(
      appBar: AppBar(
        title: Text(title, overflow: TextOverflow.ellipsis),
        backgroundColor: _blue,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 공고 메타
            Semantics(
              label: '등록자: $authorName, 기간: $period',
              child: Row(
                children: [
                  Text(authorName,
                      style: const TextStyle(fontSize: 13, color: Color(0xFF757575))),
                  const Text(' · ', style: TextStyle(color: Color(0xFF9E9E9E))),
                  Text('기간: $period',
                      style: const TextStyle(fontSize: 13, color: Color(0xFF757575))),
                ],
              ),
            ),
            const Divider(height: 24),
            // 공고 내용
            Text(plainText,
                style: const TextStyle(fontSize: 14, height: 1.7, color: Color(0xFF1A1A2E))),
            const SizedBox(height: 24),
            // 지원하기 / 지원 취소하기 버튼 — INSTRUCTOR/SUPER_ADMIN 에게는 렌더링 안 함
            if (_canApply)
              Semantics(
                label: _hasApplied ? '지원 취소하기 버튼' : '지원하기 버튼',
                button: true,
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _hasApplied ? Colors.grey : _blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: _applyLoading ? null : (_hasApplied ? _cancelApply : _applyJob),
                    child: _applyLoading
                        ? const SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(_hasApplied ? '지원 취소하기' : '지원하기',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 16),
            const Text('묻고 답하기',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E))),
            const SizedBox(height: 12),
            _CommentSection(
              jobId: widget.jobDoc.id,
              userRole: widget.userRole,
              currentUid: widget.currentUid,
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// 댓글(묻고 답하기) 섹션
// 권한: INSTRUCTOR/SUPER_ADMIN — 타인 글 삭제(가림) + 본인 글 수정/삭제
//       그 외 — 권한 없음 (읽기 전용)
// ─────────────────────────────────────────────────────────
class _CommentSection extends StatefulWidget {
  final String jobId;
  final UserRole userRole;
  final String currentUid;
  const _CommentSection({
    required this.jobId,
    required this.userRole,
    required this.currentUid,
  });

  @override
  State<_CommentSection> createState() => _CommentSectionState();
}

class _CommentSectionState extends State<_CommentSection> {
  static const Color _blue = Color(0xFF1565C0);
  final _inputCtrl = TextEditingController();
  bool _sending = false;

  bool get _isInstructor =>
      widget.userRole == UserRole.INSTRUCTOR || widget.userRole == UserRole.SUPER_ADMIN;

  @override
  void dispose() {
    _inputCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendComment() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      final authorName = AuthService.instance.currentUser?.name ?? '';
      await FirebaseFirestore.instance.collection(FsCol.jobComments).add({
        FsJobComment.jobId:      widget.jobId,
        FsJobComment.content:    text,
        FsJobComment.authorId:   widget.currentUid,
        FsJobComment.authorName: authorName,
        FsJobComment.parentId:   null,
        FsJobComment.isDeleted:  false,
        FsJobComment.createdAt:  StoragePath.nowCreatedAt(),
      });
      _inputCtrl.clear();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // 가림 처리 — 본인 글: deletedBySelf, 타인 글(교사 모더레이션): deletedByRule
  Future<void> _deleteComment(String commentId, bool isOwn) async {
    final replaceText = isOwn
        ? FsJobComment.deletedBySelf
        : FsJobComment.deletedByRule;
    await FirebaseFirestore.instance
        .collection(FsCol.jobComments)
        .doc(commentId)
        .update({
      FsJobComment.isDeleted: true,
      FsJobComment.content:   replaceText,
    });
  }

  Future<void> _editComment(String commentId, String currentContent) async {
    final ctrl = TextEditingController(text: currentContent);
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('댓글 수정'),
        content: TextField(
          controller: ctrl,
          maxLines: 4,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _blue),
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('수정', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (result == null || result.isEmpty) return;
    await FirebaseFirestore.instance
        .collection(FsCol.jobComments)
        .doc(commentId)
        .update({FsJobComment.content: result});
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 댓글 스트림
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection(FsCol.jobComments)
              .where(FsJobComment.jobId, isEqualTo: widget.jobId)
              .orderBy(FsJobComment.createdAt)
              .snapshots(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: CircularProgressIndicator(),
              );
            }
            final docs = snap.data?.docs ?? [];
            if (docs.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('아직 댓글이 없습니다.',
                    style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 13)),
              );
            }
            return Column(
              children: docs.map((doc) {
                final data       = doc.data() as Map<String, dynamic>;
                final authorId   = data[FsJobComment.authorId]   as String? ?? '';
                final authorName = data[FsJobComment.authorName] as String? ?? '-';
                final content    = data[FsJobComment.content]    as String? ?? '';
                final isDeleted  = data[FsJobComment.isDeleted]  as bool?   ?? false;
                final isOwn      = authorId == widget.currentUid;

                // 교사/관리자: 타인 댓글 삭제 + 본인 댓글 수정/삭제
                // 그 외: 권한 없음
                final canDelete = _isInstructor;
                final canEdit   = _isInstructor && isOwn;

                return Semantics(
                  label: '$authorName 댓글: $content',
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F9FA),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(authorName,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF1565C0))),
                              const SizedBox(height: 4),
                              Text(
                                content,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isDeleted
                                      ? const Color(0xFF9E9E9E)
                                      : const Color(0xFF1A1A2E),
                                  fontStyle: isDeleted ? FontStyle.italic : FontStyle.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!isDeleted) ...[
                          if (canEdit)
                            Semantics(
                              label: '댓글 수정',
                              button: true,
                              child: IconButton(
                                icon: const Icon(Icons.edit_rounded, size: 16, color: Color(0xFF757575)),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                onPressed: () => _editComment(doc.id, content),
                              ),
                            ),
                          if (canDelete)
                            Semantics(
                              label: '댓글 삭제',
                              button: true,
                              child: IconButton(
                                icon: const Icon(Icons.delete_rounded, size: 16, color: Colors.red),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                onPressed: () => _deleteComment(doc.id, isOwn),
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
        const SizedBox(height: 12),
        // 댓글 입력창
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _inputCtrl,
                decoration: const InputDecoration(
                  hintText: '댓글을 입력하세요...',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                minLines: 1,
                maxLines: 3,
                textInputAction: TextInputAction.newline,
              ),
            ),
            const SizedBox(width: 8),
            Semantics(
              label: '댓글 등록',
              button: true,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: _blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14)),
                onPressed: _sending ? null : _sendComment,
                child: _sending
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('등록'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
