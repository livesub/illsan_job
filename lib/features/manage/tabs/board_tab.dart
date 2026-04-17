// 게시판 탭 — 공지사항 캐러셀 + 구직 무한 스크롤 + 댓글 Q&A
// INSTRUCTOR/SUPER_ADMIN: 지원 버튼 숨김, 타인 댓글 삭제(가림 처리) 권한

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/enums/user_role.dart';
import '../../../core/utils/auth_service.dart';
import '../../../core/utils/firestore_keys.dart';
import '../../member/student_job_detail_page.dart';

class BoardTab extends StatefulWidget {
  final UserRole userRole;
  final String userName;
  final bool showNotices;
  const BoardTab({super.key, required this.userRole, required this.userName, this.showNotices = true});

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
        if (widget.showNotices && _notices.isNotEmpty)
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
                  index: i + 1,
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
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            widget.userRole == UserRole.STUDENT
                ? StudentJobDetailPage(jobDoc: doc, currentUid: _uid)
                : _JobDetailPage(jobDoc: doc, userRole: widget.userRole, currentUid: _uid),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// 구직 공고 카드 (리스트 아이템) — 순번·첨부·조회수 표시
// ─────────────────────────────────────────────────────────
class _JobCard extends StatelessWidget {
  final QueryDocumentSnapshot doc;
  final int index;
  final VoidCallback onTap;
  const _JobCard({required this.doc, required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final data        = doc.data() as Map<String, dynamic>;
    final title       = data[FsJob.title]       as String? ?? '-';
    final authorName  = data[FsJob.authorName]  as String? ?? '-';
    final period      = data[FsJob.period]      as String? ?? '-';
    final attachments = data[FsJob.attachments] as List?   ?? [];
    final viewCount   = data[FsJob.viewCount]   as int?    ?? 0;
    final hasAttach   = attachments.isNotEmpty;

    return Semantics(
      label: '$index번 $title, $authorName 등록, 기간 $period, 조회 $viewCount회'
          '${hasAttach ? ", 첨부파일 있음" : ""}',
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
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 2))
            ],
          ),
          child: Row(
            children: [
              // 순번
              SizedBox(
                width: 32,
                child: Text('$index',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFBDBDBD))),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 제목 + 첨부파일 아이콘
                    Row(
                      children: [
                        Expanded(
                          child: Text(title,
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF1A1A2E)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ),
                        if (hasAttach) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.attach_file_rounded,
                              size: 14, color: Color(0xFF757575)),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    // 등록자·기간 + 조회수
                    Row(
                      children: [
                        Expanded(
                          child: Text('$authorName · $period',
                              style: const TextStyle(
                                  fontSize: 12, color: Color(0xFF757575)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ),
                        Row(
                          children: [
                            const Icon(Icons.visibility_rounded,
                                size: 13, color: Color(0xFF9E9E9E)),
                            const SizedBox(width: 2),
                            Text('$viewCount',
                                style: const TextStyle(
                                    fontSize: 12, color: Color(0xFF9E9E9E))),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded,
                  color: Color(0xFF9E9E9E), size: 18),
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

  // 지원 문서 ID: {jobId}_{uid} 결정론적 키로 중복 지원 방지
  String get _appDocId => '${widget.jobDoc.id}_${widget.currentUid}';

  @override
  void initState() {
    super.initState();
    _incrementViewCount();
    if (_canApply) _checkApplied();
  }

  // 상세 진입 시 조회수 +1
  Future<void> _incrementViewCount() async {
    await FirebaseFirestore.instance
        .collection(FsCol.jobs)
        .doc(widget.jobDoc.id)
        .update({FsJob.viewCount: FieldValue.increment(1)});
  }

  // 결정론적 ID로 단건 조회 — 쿼리 없이 활성 지원 여부 확인
  Future<void> _checkApplied() async {
    final doc = await FirebaseFirestore.instance
        .collection(FsCol.jobApplications)
        .doc(_appDocId)
        .get();
    if (!mounted) return;
    final status = doc.data()?[FsJobApp.status] as String?;
    setState(() => _hasApplied =
        status == FsJobApp.statusPending || status == FsJobApp.statusApproved);
  }

  // 트랜잭션으로 중복 지원 방지 + 원자적 생성
  Future<void> _applyJob() async {
    setState(() => _applyLoading = true);
    try {
      final db      = FirebaseFirestore.instance;
      final appRef  = db.collection(FsCol.jobApplications).doc(_appDocId);
      final userDoc = await db.collection(FsCol.users).doc(widget.currentUid).get();
      final userData = userDoc.data() ?? {};
      final jobData  = widget.jobDoc.data() as Map<String, dynamic>;

      final courseId = userData[FsUser.courseId] as String? ?? '';
      String courseName = '';
      if (courseId.isNotEmpty) {
        final courseDoc = await db.collection(FsCol.courses).doc(courseId).get();
        courseName = courseDoc.data()?[FsCourse.name] as String? ?? '';
      }

      await db.runTransaction((txn) async {
        final existing = await txn.get(appRef);
        final existStatus = existing.data()?[FsJobApp.status] as String?;
        // 활성 지원이 이미 있으면 무시
        if (existStatus == FsJobApp.statusPending ||
            existStatus == FsJobApp.statusApproved) return;
        txn.set(appRef, {
          FsJobApp.jobId:          widget.jobDoc.id,
          FsJobApp.jobTitle:       jobData[FsJob.title],
          FsJobApp.authorId:       jobData[FsJob.authorId],
          FsJobApp.applicantId:    widget.currentUid,
          FsJobApp.applicantName:  userData[FsUser.name]  ?? '',
          FsJobApp.applicantEmail: userData[FsUser.email] ?? '',
          FsJobApp.courseId:       courseId,
          FsJobApp.courseName:     courseName,
          FsJobApp.status:         FsJobApp.statusPending,
          FsJobApp.appliedAt:      FieldValue.serverTimestamp(),
        });
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
      await FirebaseFirestore.instance
          .collection(FsCol.jobApplications)
          .doc(_appDocId)
          .update({FsJobApp.status: FsJobApp.statusCancelled});
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

  // 스트림 1회 생성 — 리빌드마다 재구독 방지
  late final Stream<QuerySnapshot> _commentStream;

  bool get _isInstructor =>
      widget.userRole == UserRole.INSTRUCTOR ||
      widget.userRole == UserRole.SUPER_ADMIN;

  @override
  void initState() {
    super.initState();
    _commentStream = FirebaseFirestore.instance
        .collection(FsCol.jobComments)
        .where(FsJobComment.jobId, isEqualTo: widget.jobId)
        .orderBy(FsJobComment.createdAt)
        .snapshots();
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    super.dispose();
  }

  // 이메일 앞 4자리 + *** 마스킹
  String _maskEmail(String email) {
    if (email.isEmpty) return '****';
    final prefix = email.contains('@') ? email.split('@').first : email;
    if (prefix.length <= 4) return '$prefix***';
    return '${prefix.substring(0, 4)}***';
  }

  Future<void> _sendComment() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      final user = AuthService.instance.currentUser;
      await FirebaseFirestore.instance.collection(FsCol.jobComments).add({
        FsJobComment.jobId:       widget.jobId,
        FsJobComment.content:     text,
        FsJobComment.authorId:    widget.currentUid,
        FsJobComment.authorName:  user?.name  ?? '',
        FsJobComment.authorEmail: user?.email ?? '',
        FsJobComment.authorRole:  widget.userRole.code,
        FsJobComment.parentId:    null,
        FsJobComment.isDeleted:   false,
        FsJobComment.createdAt:   StoragePath.nowCreatedAt(),
      });
      _inputCtrl.clear();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // Soft Delete — 통합 문구로 content 교체
  Future<void> _deleteComment(String commentId) async {
    await FirebaseFirestore.instance
        .collection(FsCol.jobComments)
        .doc(commentId)
        .update({
      FsJobComment.isDeleted: true,
      FsJobComment.content:   FsJobComment.deletedText,
    });
  }

  // 수정 — 대댓글 존재 시 차단
  Future<void> _editComment(String commentId, String currentContent) async {
    // 대댓글 존재 여부 확인
    final repliesSnap = await FirebaseFirestore.instance
        .collection(FsCol.jobComments)
        .where(FsJobComment.parentId, isEqualTo: commentId)
        .limit(1)
        .get();
    if (!mounted) return;
    if (repliesSnap.docs.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('대댓글이 있는 댓글은 수정할 수 없습니다.')),
      );
      return;
    }

    final ctrl   = TextEditingController(text: currentContent);
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
        StreamBuilder<QuerySnapshot>(
          stream: _commentStream,
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
                final data        = doc.data() as Map<String, dynamic>;
                final authorId    = data[FsJobComment.authorId]    as String? ?? '';
                final authorEmail = data[FsJobComment.authorEmail] as String? ?? '';
                final authorName  = data[FsJobComment.authorName]  as String? ?? '-';
                final content     = data[FsJobComment.content]     as String? ?? '';
                final isDeleted   = data[FsJobComment.isDeleted]   as bool?   ?? false;
                final isOwn       = authorId == widget.currentUid;
                // 이메일 있으면 마스킹, 없으면 이름 표시 (하위 호환)
                final displayName = authorEmail.isNotEmpty
                    ? _maskEmail(authorEmail)
                    : authorName;

                // 본인: 수정·삭제 / 교사·관리자: 추가로 타인 글 삭제 허용
                final canEdit   = !isDeleted && isOwn;
                final canDelete = !isDeleted && (isOwn || _isInstructor);

                return Semantics(
                  label: '$displayName 댓글: $content',
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
                              Text(displayName,
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
                                  fontStyle: isDeleted
                                      ? FontStyle.italic
                                      : FontStyle.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (canEdit)
                          Semantics(
                            label: '댓글 수정 버튼',
                            button: true,
                            child: IconButton(
                              icon: const Icon(Icons.edit_rounded,
                                  size: 16, color: Color(0xFF757575)),
                              padding: EdgeInsets.zero,
                              constraints:
                                  const BoxConstraints(minWidth: 32, minHeight: 32),
                              onPressed: () => _editComment(doc.id, content),
                            ),
                          ),
                        if (canDelete)
                          Semantics(
                            label: '댓글 삭제 버튼',
                            button: true,
                            child: IconButton(
                              icon: const Icon(Icons.delete_rounded,
                                  size: 16, color: Colors.red),
                              padding: EdgeInsets.zero,
                              constraints:
                                  const BoxConstraints(minWidth: 32, minHeight: 32),
                              onPressed: () => _deleteComment(doc.id),
                            ),
                          ),
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
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                minLines: 1,
                maxLines: 3,
                textInputAction: TextInputAction.newline,
              ),
            ),
            const SizedBox(width: 8),
            Semantics(
              label: '댓글 등록 버튼',
              button: true,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: _blue,
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 14)),
                onPressed: _sending ? null : _sendComment,
                child: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('등록'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
