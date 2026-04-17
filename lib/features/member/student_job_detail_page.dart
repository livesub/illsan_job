import 'dart:convert';
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

  // 댓글 입력 컨트롤러 / 포커스노드 / 인라인 대댓글 상태
  final _commentCtrl      = TextEditingController();
  final _replyCtrl        = TextEditingController();
  final _commentFocusNode = FocusNode();
  String? _activeReplyId; // 인라인 대댓글 입력 중인 부모 댓글 ID
  bool _commentLoading = false;

  // 스트림을 build() 밖에서 1회만 생성 — 재구독으로 인한 레이아웃 미완료 hit-test 버그 방지
  late final Stream<QuerySnapshot> _commentStream;

  // 결정론적 지원 문서 ID: {jobId}_{uid} — 중복 지원 방지
  String get _appDocId => '${widget.jobDoc.id}_${widget.currentUid}';

  @override
  void dispose() {
    _commentCtrl.dispose();
    _replyCtrl.dispose();
    _commentFocusNode.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // orderBy 제거 — where+orderBy 복합 인덱스 없이도 동작하도록 클라이언트 정렬로 전환
    _commentStream = _db
        .collection(FsCol.jobComments)
        .where(FsJobComment.jobId, isEqualTo: widget.jobDoc.id)
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
    // final attachments =
    //     List<String>.from(data[FsJob.attachments] as List? ?? []); // 차후 개발
    final plainText = _extractPlainText(content);

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
      body: SingleChildScrollView(
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

            // 첨부파일 — 차후 개발
            // _buildSection(
            //   title: '첨부파일',
            //   child: attachments.isEmpty
            //       ? const Text('첨부파일이 없습니다.',
            //           style: TextStyle(
            //               fontSize: 14, color: AppColors.textSecondary))
            //       : Column(
            //           children: attachments
            //               .asMap()
            //               .entries
            //               .map((e) => _buildAttachRow(e.key + 1, e.value))
            //               .toList(),
            //         ),
            // ),
            const SizedBox(height: 32),

            // 지원하기 / 신청 취소 버튼
            _buildApplyButton(),
            const SizedBox(height: 16),

            // Q&A 댓글/대댓글 섹션
            _buildCommentSection(),
            const SizedBox(height: 32),
          ],
        ),
      ),
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

  // 첨부파일 행 — 차후 개발
  // Widget _buildAttachRow(int no, String path) {
  //   final fileName = path.split('/').last;
  //   return Semantics(
  //     label: '첨부파일 $no번: $fileName',
  //     child: Padding(
  //       padding: const EdgeInsets.symmetric(vertical: 6),
  //       child: Row(
  //         children: [
  //           const Icon(Icons.insert_drive_file_rounded,
  //               size: 18, color: AppColors.primary),
  //           const SizedBox(width: 8),
  //           Expanded(
  //             child: Text(fileName,
  //                 style: const TextStyle(
  //                     fontSize: 13, color: AppColors.textPrimary),
  //                 overflow: TextOverflow.ellipsis),
  //           ),
  //           Semantics(
  //             label: '다운로드 버튼',
  //             button: true,
  //             child: TextButton.icon(
  //               onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
  //                 const SnackBar(
  //                     content: Text('다운로드 기능은 준비 중입니다.'),
  //                     duration: Duration(seconds: 2)),
  //               ),
  //               icon: const Icon(Icons.download_rounded,
  //                   size: 16, color: AppColors.primary),
  //               label: const Text('다운로드',
  //                   style: TextStyle(
  //                       fontSize: 12, color: AppColors.primary)),
  //               style: TextButton.styleFrom(
  //                   padding: const EdgeInsets.symmetric(
  //                       horizontal: 8, vertical: 4)),
  //             ),
  //           ),
  //         ],
  //       ),
  //     ),
  //   );
  // }

  // Quill Delta JSON → 평문 변환
  static String _extractPlainText(String raw) {
    try {
      final ops = jsonDecode(raw) as List;
      final buf = StringBuffer();
      for (final op in ops) {
        final insert = (op as Map)['insert'];
        if (insert is String) buf.write(insert);
      }
      return buf.toString().trim();
    } catch (_) {
      return raw.replaceAll(RegExp(r'<[^>]*>'), '').trim();
    }
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

  // 최상위 댓글 등록
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
        FsJobComment.authorRole:  'STUDENT',
        FsJobComment.parentId:    null,
        FsJobComment.isDeleted:   false,
        FsJobComment.createdAt:   StoragePath.nowCreatedAt(),
      });
      if (!mounted) return;
      _commentCtrl.clear();
      setState(() => _commentLoading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _commentLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('등록 실패: $e'), backgroundColor: Colors.red),
      );
    }
  }

  // 인라인 대댓글 등록
  Future<void> _addReply(String parentId) async {
    final text = _replyCtrl.text.trim();
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
        FsJobComment.authorRole:  'STUDENT',
        FsJobComment.parentId:    parentId,
        FsJobComment.isDeleted:   false,
        FsJobComment.createdAt:   StoragePath.nowCreatedAt(),
      });
      if (!mounted) return;
      _replyCtrl.clear();
      setState(() {
        _activeReplyId  = null;
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

  // 하위 답변 있으면 Soft Delete, 없으면 Hard Delete
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
    final hasReplies = await _checkHasReplies(commentId);
    if (hasReplies) {
      await _db.collection(FsCol.jobComments).doc(commentId).update({
        FsJobComment.content:   FsJobComment.deletedText,
        FsJobComment.isDeleted: true,
      });
    } else {
      await _db.collection(FsCol.jobComments).doc(commentId).delete();
    }
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

  // Q&A 섹션 — 루트 입력창 + StreamBuilder (인라인 대댓글 포함)
  Widget _buildCommentSection() {
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
          const Text('Q&A',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          const Divider(height: 20),
          // 루트 댓글 입력창 — StreamBuilder 외부 독립 배치
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _commentCtrl,
                  focusNode: _commentFocusNode,
                  maxLines: 3,
                  minLines: 1,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: '댓글을 입력하세요.',
                    hintStyle: const TextStyle(fontSize: 13),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppColors.primary),
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
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                  onPressed: _commentLoading ? null : _addComment,
                  child: _commentLoading
                      ? const SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('등록', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
          // 댓글 목록 — StreamBuilder
          StreamBuilder<QuerySnapshot>(
            stream: _commentStream,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
                return const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                );
              }
              if (snap.hasError) {
                debugPrint('[Q&A] 스트림 에러: ${snap.error}');
                return Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text('댓글을 불러올 수 없습니다. (${snap.error})',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                );
              }
              // createdAt 기준 클라이언트 정렬
              final docs = List<QueryDocumentSnapshot>.of(
                  snap.data?.docs ?? const <QueryDocumentSnapshot>[])
                ..sort((a, b) {
                  final ad = (a.data() as Map)[FsJobComment.createdAt] as String? ?? '';
                  final bd = (b.data() as Map)[FsJobComment.createdAt] as String? ?? '';
                  return ad.compareTo(bd);
                });
              final hasRoot = docs.any((d) =>
                  (d.data() as Map)[FsJobComment.parentId] == null);
              if (!hasRoot) {
                return const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: Text('첫 댓글을 남겨보세요.',
                      style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 24),
                  _buildCommentNode(null, docs, 0),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCommentNode(
      String? parentId, List<QueryDocumentSnapshot> all, int depth) {
    final children = all
        .where((d) => (d.data() as Map)[FsJobComment.parentId] == parentId)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children.map((doc) {
        final data         = doc.data() as Map<String, dynamic>;
        final isDeleted    = data[FsJobComment.isDeleted]  as bool?   ?? false;
        final content      = data[FsJobComment.content]    as String? ?? '';
        final authorId     = data[FsJobComment.authorId]   as String? ?? '';
        final authorName   = data[FsJobComment.authorName] as String? ?? '';
        final authorRole   = (data[FsJobComment.authorRole] as String? ?? '').toUpperCase();
        final createdAt    = data[FsJobComment.createdAt]  as String? ?? '';
        final isInstructor = authorRole == 'INSTRUCTOR' || authorRole == 'SUPER_ADMIN'
            || authorRole == 'TEACHER';
        final isOwn        = authorId == widget.currentUid;
        final displayName  = isInstructor ? '$authorName(교사)' : authorName;
        final isReplyActive = _activeReplyId == doc.id;
        final dateStr      = createdAt.length >= 10 ? createdAt.substring(0, 10) : createdAt;

        return Padding(
          padding: EdgeInsets.only(left: depth * 16.0, bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: EdgeInsets.only(left: depth > 0 ? 8.0 : 0),
                decoration: BoxDecoration(
                  color: isReplyActive ? const Color(0xFFF0F4FF) : null,
                  border: depth > 0
                      ? const Border(
                          left: BorderSide(color: Color(0xFFE0E0E0), width: 1))
                      : null,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  displayName,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textSecondary),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (dateStr.isNotEmpty) ...[
                                const SizedBox(width: 6),
                                Text(dateStr,
                                    style: const TextStyle(
                                        fontSize: 10, color: Color(0xFFBDBDBD))),
                              ],
                            ],
                          ),
                        ),
                        if (isOwn && !isDeleted) ...[
                          Semantics(
                            label: '댓글 수정 버튼',
                            button: true,
                            child: InkWell(
                              onTap: () => _editComment(doc.id, content),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                child: Text('수정',
                                    style: TextStyle(fontSize: 11, color: AppColors.primary)),
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
                                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                child: Text('삭제',
                                    style: TextStyle(fontSize: 11, color: Colors.red)),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      content,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: isDeleted ? AppColors.textSecondary : AppColors.textPrimary,
                        fontStyle: isDeleted ? FontStyle.italic : FontStyle.normal,
                      ),
                    ),
                    if (!isDeleted)
                      isReplyActive
                          ? _buildInlineReplyInput(doc.id)
                          : Semantics(
                              label: '답글 달기 버튼',
                              button: true,
                              child: TextButton.icon(
                                style: ButtonStyle(
                                  foregroundColor: WidgetStateProperty.resolveWith((s) =>
                                      s.contains(WidgetState.hovered) ||
                                              s.contains(WidgetState.pressed)
                                          ? AppColors.primary
                                          : const Color(0xFFBDBDBD)),
                                  minimumSize: WidgetStateProperty.all(Size.zero),
                                  padding: WidgetStateProperty.all(
                                      const EdgeInsets.symmetric(
                                          horizontal: 0, vertical: 4)),
                                  overlayColor:
                                      WidgetStateProperty.all(Colors.transparent),
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                onPressed: () {
                                  _replyCtrl.clear();
                                  setState(() => _activeReplyId = doc.id);
                                },
                                icon: const Icon(Icons.reply_rounded, size: 13),
                                label: const Text('답글',
                                    style: TextStyle(fontSize: 11)),
                              ),
                            ),
                  ],
                ),
              ),
              _buildCommentNode(doc.id, all, depth + 1),
              if (depth == 0) const Divider(height: 16),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildInlineReplyInput(String parentId) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, left: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const Icon(Icons.subdirectory_arrow_right_rounded,
              size: 14, color: AppColors.primary),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: _replyCtrl,
              autofocus: true,
              maxLines: 2,
              minLines: 1,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: '대댓글을 입력하세요.',
                hintStyle: const TextStyle(fontSize: 13),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.primary),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Semantics(
            label: '대댓글 등록 버튼',
            button: true,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(0, 36),
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                elevation: 0,
              ),
              onPressed: _commentLoading ? null : () => _addReply(parentId),
              child: const Text('등록', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(width: 4),
          Semantics(
            label: '대댓글 취소 버튼',
            button: true,
            child: TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              ),
              onPressed: () => setState(() => _activeReplyId = null),
              child: const Text('취소', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ),
          ),
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
