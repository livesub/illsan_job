import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/firestore_keys.dart';

// 학생 전용 구직 공고 상세 페이지
// - 공고 본문·기간·첨부파일 표시
// - 진입 시 조회수 +1
// - 지원 이력 확인 → 지원하기 / 신청 취소 버튼
class StudentJobDetailPage extends StatefulWidget {
  final QueryDocumentSnapshot jobDoc;
  final String currentUid;
  const StudentJobDetailPage({
    super.key,
    required this.jobDoc,
    required this.currentUid,
  });

  @override
  State<StudentJobDetailPage> createState() => _StudentJobDetailPageState();
}

class _StudentJobDetailPageState extends State<StudentJobDetailPage> {
  final _db = FirebaseFirestore.instance;

  bool _hasApplied   = false;
  bool _applyLoading = false;
  bool _checkLoading = true;

  // 댓글 입력 컨트롤러 / 대댓글 대상 상태
  final _commentCtrl = TextEditingController();
  String? _replyToId;
  String? _replyToAuthor;
  bool _commentLoading = false;

  // 스트림을 build() 밖에서 1회만 생성 — 재구독으로 인한 레이아웃 미완료 hit-test 버그 방지
  late final Stream<QuerySnapshot> _commentStream;

  // 결정론적 지원 문서 ID: {jobId}_{uid} — 중복 지원 방지
  String get _appDocId => '${widget.jobDoc.id}_${widget.currentUid}';

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _commentStream = _db
        .collection(FsCol.jobComments)
        .where(FsJobComment.jobId, isEqualTo: widget.jobDoc.id)
        .orderBy(FsJobComment.createdAt)
        .snapshots();
    _incrementViewCount();
    _checkApplied();
  }

  // 상세 진입 시 조회수 +1
  Future<void> _incrementViewCount() async {
    await _db
        .collection(FsCol.jobs)
        .doc(widget.jobDoc.id)
        .update({FsJob.viewCount: FieldValue.increment(1)});
  }

  // 결정론적 ID 단건 조회 — 지원 여부 확인
  Future<void> _checkApplied() async {
    final doc = await _db
        .collection(FsCol.jobApplications)
        .doc(_appDocId)
        .get();
    if (!mounted) return;
    final status = doc.data()?[FsJobApp.status] as String?;
    setState(() {
      _hasApplied = status == FsJobApp.statusPending ||
          status == FsJobApp.statusApproved;
      _checkLoading = false;
    });
  }

  // 지원하기 — 트랜잭션으로 중복 지원 방지 + 원자적 생성
  Future<void> _applyJob() async {
    setState(() => _applyLoading = true);
    try {
      final appRef  = _db.collection(FsCol.jobApplications).doc(_appDocId);
      final userDoc = await _db.collection(FsCol.users)
          .doc(widget.currentUid)
          .get();
      final userData = userDoc.data() ?? {};
      final jobData  = widget.jobDoc.data() as Map<String, dynamic>;

      final courseId = userData[FsUser.courseId] as String? ?? '';
      String courseName = '';
      if (courseId.isNotEmpty) {
        final courseDoc =
            await _db.collection(FsCol.courses).doc(courseId).get();
        courseName = courseDoc.data()?[FsCourse.name] as String? ?? '';
      }

      await _db.runTransaction((txn) async {
        final existing   = await txn.get(appRef);
        final existStatus =
            existing.data()?[FsJobApp.status] as String?;
        // 활성 지원이 이미 있으면 무시
        if (existStatus == FsJobApp.statusPending ||
            existStatus == FsJobApp.statusApproved) return;
        txn.set(appRef, {
          FsJobApp.jobId:          widget.jobDoc.id,
          FsJobApp.jobTitle:       jobData[FsJob.title]      ?? '',
          FsJobApp.authorId:       jobData[FsJob.authorId]   ?? '',
          FsJobApp.applicantId:    widget.currentUid,
          FsJobApp.applicantName:  userData[FsUser.name]     ?? '',
          FsJobApp.applicantEmail: userData[FsUser.email]    ?? '',
          FsJobApp.courseId:       courseId,
          FsJobApp.courseName:     courseName,
          FsJobApp.status:         FsJobApp.statusPending,
          FsJobApp.appliedAt:      FieldValue.serverTimestamp(),
        });
      });

      if (!mounted) return;
      setState(() {
        _hasApplied  = true;
        _applyLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('지원이 완료되었습니다.'),
            backgroundColor: Color(0xFF2E7D32)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _applyLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('지원 실패: $e'), backgroundColor: Colors.red),
      );
    }
  }

  // 신청 취소 — status를 cancelled로 업데이트
  Future<void> _cancelApply() async {
    // 취소 확인 다이얼로그
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('지원 취소'),
        content: const Text('지원을 취소하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('아니오'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child:
                const Text('취소하기', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _applyLoading = true);
    try {
      await _db
          .collection(FsCol.jobApplications)
          .doc(_appDocId)
          .update({FsJobApp.status: FsJobApp.statusCancelled});
      if (!mounted) return;
      setState(() {
        _hasApplied  = false;
        _applyLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('지원이 취소되었습니다.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _applyLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('취소 실패: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final data        = widget.jobDoc.data() as Map<String, dynamic>;
    final title       = data[FsJob.title]       as String? ?? '-';
    final authorName  = data[FsJob.authorName]  as String? ?? '-';
    final period      = data[FsJob.period]       as String? ?? '-';
    final viewCount   = data[FsJob.viewCount]    as int?    ?? 0;
    final content     = data[FsJob.content]      as String? ?? '';
    final attachments =
        List<String>.from(data[FsJob.attachments] as List? ?? []);
    // HTML 태그 제거 후 평문 표시
    final plainText =
        content.replaceAll(RegExp(r'<[^>]*>'), '').trim();

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      appBar: AppBar(
        title: Text(title,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: RepaintBoundary(
        child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 공고 메타 카드
            _buildMetaCard(authorName, period, viewCount),
            const SizedBox(height: 16),

            // 공고 본문
            _buildSection(
              title: '공고 내용',
              child: plainText.isEmpty
                  ? const Text('내용이 없습니다.',
                      style: TextStyle(
                          fontSize: 14, color: AppColors.textSecondary))
                  : Text(plainText,
                      style: const TextStyle(
                          fontSize: 14,
                          height: 1.75,
                          color: AppColors.textPrimary)),
            ),
            const SizedBox(height: 16),

            // 모집 기간
            _buildSection(
              title: '모집 기간',
              child: Row(
                children: [
                  const Icon(Icons.calendar_today_rounded,
                      size: 16, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text(period,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 첨부파일
            _buildSection(
              title: '첨부파일',
              child: attachments.isEmpty
                  ? const Text('첨부파일이 없습니다.',
                      style: TextStyle(
                          fontSize: 14, color: AppColors.textSecondary))
                  : Column(
                      children: attachments
                          .asMap()
                          .entries
                          .map((e) => _buildAttachRow(e.key + 1, e.value))
                          .toList(),
                    ),
            ),
            const SizedBox(height: 32),

            // 지원하기 / 신청 취소 버튼
            _buildApplyButton(),
            const SizedBox(height: 16),

            // Q&A 댓글/대댓글 섹션
            _buildCommentSection(),
            const SizedBox(height: 32),
          ],
        ),
      )),
    );
  }

  // 공고 메타 정보 카드
  Widget _buildMetaCard(String authorName, String period, int viewCount) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          _metaRow(Icons.person_outline_rounded, '등록자', authorName),
          const SizedBox(height: 10),
          _metaRow(Icons.calendar_month_rounded, '기간', period),
          const SizedBox(height: 10),
          _metaRow(Icons.visibility_outlined, '조회수', '$viewCount회'),
        ],
      ),
    );
  }

  Widget _metaRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.primary),
        const SizedBox(width: 8),
        Text('$label: ',
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary)),
        Expanded(
          child: Text(value,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textPrimary),
              overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }

  // 섹션 카드 (제목 + 내용)
  Widget _buildSection({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          const Divider(height: 20),
          child,
        ],
      ),
    );
  }

  // 첨부파일 행 — 파일명 표시 + 다운로드 안내
  Widget _buildAttachRow(int no, String path) {
    final fileName = path.split('/').last;
    return Semantics(
      label: '첨부파일 $no번: $fileName',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            const Icon(Icons.insert_drive_file_rounded,
                size: 18, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(fileName,
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textPrimary),
                  overflow: TextOverflow.ellipsis),
            ),
            Semantics(
              label: '다운로드 버튼',
              button: true,
              child: TextButton.icon(
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('다운로드 기능은 준비 중입니다.'),
                      duration: Duration(seconds: 2)),
                ),
                icon: const Icon(Icons.download_rounded,
                    size: 16, color: AppColors.primary),
                label: const Text('다운로드',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.primary)),
                style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 이메일 앞 4자 노출, 나머지 마스킹
  String _maskEmail(String email) {
    final parts = email.split('@');
    if (parts.length != 2) return email;
    final local   = parts[0];
    final domain  = parts[1];
    final visible = local.length >= 4 ? local.substring(0, 4) : local;
    return '$visible***@$domain';
  }

  // 대댓글 존재 여부 — 수정 차단 판단
  Future<bool> _checkHasReplies(String commentId) async {
    final snap = await _db
        .collection(FsCol.jobComments)
        .where(FsJobComment.parentId, isEqualTo: commentId)
        .limit(1)
        .get();
    return snap.docs.isNotEmpty;
  }

  // 댓글/대댓글 등록
  Future<void> _addComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _commentLoading = true);
    try {
      final userDoc  = await _db.collection(FsCol.users).doc(widget.currentUid).get();
      final userData = userDoc.data() ?? {};
      await _db.collection(FsCol.jobComments).add({
        FsJobComment.jobId:       widget.jobDoc.id,
        FsJobComment.content:     text,
        FsJobComment.authorId:    widget.currentUid,
        FsJobComment.authorName:  userData[FsUser.name]  ?? '',
        FsJobComment.authorEmail: userData[FsUser.email] ?? '',
        FsJobComment.parentId:    _replyToId,
        FsJobComment.isDeleted:   false,
        FsJobComment.createdAt:   StoragePath.nowCreatedAt(),
      });
      if (!mounted) return;
      _commentCtrl.clear();
      setState(() {
        _replyToId      = null;
        _replyToAuthor  = null;
        _commentLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _commentLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('등록 실패: $e'), backgroundColor: Colors.red),
      );
    }
  }

  // Soft Delete — content 교체 + is_deleted=true (물리 삭제 금지)
  Future<void> _deleteComment(String commentId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('댓글 삭제'),
        content: const Text('삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('아니오'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await _db.collection(FsCol.jobComments).doc(commentId).update({
      FsJobComment.content:   FsJobComment.deletedText,
      FsJobComment.isDeleted: true,
    });
  }

  // 수정 — 대댓글 1개 이상 존재 시 완벽 차단
  Future<void> _editComment(String commentId, String currentText) async {
    final hasReplies = await _checkHasReplies(commentId);
    if (!mounted) return;
    if (hasReplies) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('대댓글이 달린 댓글은 수정할 수 없습니다.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }
    final ctrl   = TextEditingController(text: currentText);
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
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('수정'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (result == null || result.isEmpty) return;
    await _db.collection(FsCol.jobComments).doc(commentId).update({
      FsJobComment.content: result,
    });
  }

  // Q&A 섹션 — StreamBuilder 실시간
  Widget _buildCommentSection() {
    return StreamBuilder<QuerySnapshot>(
      stream: _commentStream,
      builder: (context, snap) {
        final docs    = snap.data?.docs ?? [];
        final parents = docs.where((d) {
          return (d.data() as Map<String, dynamic>)[FsJobComment.parentId] == null;
        }).toList();
        final replies = docs.where((d) {
          return (d.data() as Map<String, dynamic>)[FsJobComment.parentId] != null;
        }).toList();

        return _buildSection(
          title: 'Q&A (${docs.length})',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 대댓글 대상 표시 배너
              if (_replyToAuthor != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '$_replyToAuthor 님에게 대댓글 작성 중',
                          style: const TextStyle(fontSize: 12, color: AppColors.primary),
                        ),
                      ),
                      Semantics(
                        label: '대댓글 작성 취소 버튼',
                        button: true,
                        child: GestureDetector(
                          onTap: () => setState(() {
                            _replyToId     = null;
                            _replyToAuthor = null;
                          }),
                          child: const Icon(Icons.close, size: 16, color: AppColors.primary),
                        ),
                      ),
                    ],
                  ),
                ),
              // 입력창
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _commentCtrl,
                      maxLines: 3,
                      minLines: 1,
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: '댓글을 입력하세요.',
                        hintStyle: const TextStyle(fontSize: 13),
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              const BorderSide(color: AppColors.primary),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Semantics(
                    label: '댓글 등록 버튼',
                    button: true,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        elevation: 0,
                      ),
                      onPressed: _commentLoading ? null : _addComment,
                      child: _commentLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('등록',
                              style: TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
              if (parents.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: Text('첫 댓글을 남겨보세요.',
                      style: TextStyle(
                          fontSize: 13, color: AppColors.textSecondary)),
                )
              else ...[
                const Divider(height: 24),
                ...parents.map((parentDoc) {
                  final parentData = parentDoc.data() as Map<String, dynamic>;
                  final childDocs  = replies.where((r) {
                    final rd = r.data() as Map<String, dynamic>;
                    return rd[FsJobComment.parentId] == parentDoc.id;
                  }).toList();
                  return _buildCommentItem(
                    doc: parentDoc,
                    data: parentData,
                    isReply: false,
                    childDocs: childDocs,
                  );
                }),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildCommentItem({
    required QueryDocumentSnapshot doc,
    required Map<String, dynamic> data,
    required bool isReply,
    List<QueryDocumentSnapshot> childDocs = const [],
  }) {
    final isDeleted   = data[FsJobComment.isDeleted]   as bool?   ?? false;
    final content     = data[FsJobComment.content]     as String? ?? '';
    final authorId    = data[FsJobComment.authorId]    as String? ?? '';
    final authorName  = data[FsJobComment.authorName]  as String? ?? '';
    final authorEmail = data[FsJobComment.authorEmail] as String? ?? '';
    final isOwn       = authorId == widget.currentUid;
    final maskedEmail = _maskEmail(authorEmail);

    return Padding(
      padding: EdgeInsets.only(left: isReply ? 24 : 0, bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 작성자 행
          Row(
            children: [
              Icon(
                isReply
                    ? Icons.subdirectory_arrow_right_rounded
                    : Icons.chat_bubble_outline_rounded,
                size: 14,
                color: AppColors.primary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '$authorName ($maskedEmail)',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isOwn && !isDeleted) ...[
                Semantics(
                  label: '댓글 수정 버튼',
                  button: true,
                  child: InkWell(
                    onTap: () => _editComment(doc.id, content),
                    child: const Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      child: Text('수정',
                          style: TextStyle(
                              fontSize: 11, color: AppColors.primary)),
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                Semantics(
                  label: '댓글 삭제 버튼',
                  button: true,
                  child: InkWell(
                    onTap: () => _deleteComment(doc.id),
                    child: const Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      child: Text('삭제',
                          style:
                              TextStyle(fontSize: 11, color: Colors.red)),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          // 본문
          Text(
            content,
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: isDeleted
                  ? AppColors.textSecondary
                  : AppColors.textPrimary,
              fontStyle:
                  isDeleted ? FontStyle.italic : FontStyle.normal,
            ),
          ),
          // 대댓글 버튼 (최상위 + 미삭제 댓글만)
          if (!isReply && !isDeleted)
            Semantics(
              label: '대댓글 작성 버튼',
              button: true,
              child: GestureDetector(
                onTap: () => setState(() {
                  _replyToId     = doc.id;
                  _replyToAuthor = authorName;
                }),
                child: const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text('대댓글',
                      style: TextStyle(
                          fontSize: 11,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600)),
                ),
              ),
            ),
          // 대댓글 목록
          if (childDocs.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                children: childDocs
                    .map((replyDoc) => _buildCommentItem(
                          doc: replyDoc,
                          data: replyDoc.data() as Map<String, dynamic>,
                          isReply: true,
                        ))
                    .toList(),
              ),
            ),
          const Divider(height: 16),
        ],
      ),
    );
  }

  // 지원 버튼 (지원 이력 확인 후 분기)
  Widget _buildApplyButton() {
    if (_checkLoading) {
      return const SizedBox(
        width: double.infinity,
        height: 56, 
        child: Center(child: CircularProgressIndicator()),
      );
    }
    
    return Semantics(
      label: _hasApplied ? '신청 취소 버튼' : '지원하기 버튼',
      button: true,
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: _hasApplied ? Colors.grey[600] : AppColors.primary,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: _applyLoading
              ? null
              : (_hasApplied ? _cancelApply : _applyJob),
          child: _applyLoading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: Colors.white))
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _hasApplied
                          ? Icons.cancel_outlined
                          : Icons.send_rounded,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _hasApplied ? '신청 취소' : '지원하기',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

// 미로그인 방어용 — 현재 사용자 UID 헬퍼
extension _CurrentUser on FirebaseAuth {
  String get safeUid => currentUser?.uid ?? '';
}
