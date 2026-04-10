// 교사 전용 홈 대시보드 탭입니다.
//
// 구성:
//   [상단] 담당 반 카드 — 활성 강좌만 표시, 반이름/학생수/상세보기
//   [중단] 가입 승인 대기 — 내 강좌 신청 학생 목록, 팝업 처리
//   [하단] 구직 신청 대기 — 내가 올린 공고의 신청 목록, 승인/취소

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/utils/firestore_keys.dart';

class InstructorHomeTab extends StatefulWidget {
  const InstructorHomeTab({super.key});

  @override
  State<InstructorHomeTab> createState() => _InstructorHomeTabState();
}

class _InstructorHomeTabState extends State<InstructorHomeTab> {
  static const Color _blue = Color(0xFF1565C0);
  final _db = FirebaseFirestore.instance;

  String _uid = '';
  List<QueryDocumentSnapshot> _myCourses = [];
  List<QueryDocumentSnapshot> _allCourses = [];
  List<QueryDocumentSnapshot> _pendingStudents = [];
  List<QueryDocumentSnapshot> _pendingJobApps = [];
  Map<String, int> _courseStudentCounts = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    _loadData();
  }

  Future<void> _loadData() async {
    if (_uid.isEmpty) return;
    setState(() => _isLoading = true);
    try {
      // 담당 활성 강좌 로드
      final myCoursesSnap = await _db
          .collection(FsCol.courses)
          .where(FsCourse.teacherId, isEqualTo: _uid)
          .where(FsCourse.status, isEqualTo: FsCourse.statusActive)
          .get();
      _myCourses = myCoursesSnap.docs;

      // 전체 활성 강좌 로드 (승인 팝업 selectbox용)
      final allCoursesSnap = await _db
          .collection(FsCol.courses)
          .where(FsCourse.status, isEqualTo: FsCourse.statusActive)
          .orderBy(FsCourse.name)
          .get();
      _allCourses = allCoursesSnap.docs;

      if (_myCourses.isNotEmpty) {
        final courseIds = _myCourses.map((d) => d.id).toList();

        // 담당 강좌 승인 대기 학생 로드 (whereIn 최대 30개 제한)
        final pendingSnap = await _db
            .collection(FsCol.users)
            .where(FsUser.role, isEqualTo: FsUser.roleStudent)
            .where(FsUser.status, isEqualTo: FsUser.statusPending)
            .where(FsUser.courseId, whereIn: courseIds.take(30).toList())
            .orderBy(FsUser.createdAt, descending: true)
            .get();
        // 오늘 가입 신청 건만 필터 (created_at: yymmddHis 포맷 prefix 비교)
        final now = DateTime.now();
        final todayPrefix =
            '${now.year.toString().substring(2)}'
            '${now.month.toString().padLeft(2, '0')}'
            '${now.day.toString().padLeft(2, '0')}';
        _pendingStudents = pendingSnap.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final ca = data[FsUser.createdAt] as String? ?? '';
          return ca.startsWith(todayPrefix);
        }).toList();

        // 강좌별 승인된 학생 수 계산
        final counts = <String, int>{};
        for (final courseId in courseIds) {
          final countSnap = await _db
              .collection(FsCol.users)
              .where(FsUser.role, isEqualTo: FsUser.roleStudent)
              .where(FsUser.status, isEqualTo: FsUser.statusApproved)
              .where(FsUser.courseId, isEqualTo: courseId)
              .where(FsUser.isDeleted, isNotEqualTo: true)
              .get();
          counts[courseId] = countSnap.docs.length;
        }
        _courseStudentCounts = counts;
      } else {
        _pendingStudents = [];
        _courseStudentCounts = {};
      }

      // 내가 올린 구직 공고의 대기 신청 로드
      final jobAppsSnap = await _db
          .collection(FsCol.jobApplications)
          .where(FsJobApp.authorId, isEqualTo: _uid)
          .where(FsJobApp.status, isEqualTo: FsJobApp.statusPending)
          .orderBy(FsJobApp.appliedAt, descending: true)
          .get();
      _pendingJobApps = jobAppsSnap.docs;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('데이터 로드 실패: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: _loadData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('교사 대시보드',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF1A1A2E))),
            const SizedBox(height: 4),
            const Text('담당 반 현황과 처리 사항을 확인하세요.',
                style: TextStyle(fontSize: 14, color: Color(0xFF757575))),
            const SizedBox(height: 24),
            _buildCoursesSection(),
            const SizedBox(height: 24),
            _buildPendingStudentsSection(),
            const SizedBox(height: 24),
            _buildJobApplicationsSection(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // ── 담당 강좌 카드 섹션 ────────────────────────────────
  Widget _buildCoursesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('담당 반 현황',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E))),
        const SizedBox(height: 12),
        if (_myCourses.isEmpty)
          _emptyBox('담당 중인 진행 강좌가 없습니다.')
        else
          ...(_myCourses.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final courseName = data[FsCourse.name] as String? ?? '-';
            final studentCount = _courseStudentCounts[doc.id] ?? 0;
            return Semantics(
              label: '$courseName 반, 학생 $studentCount명',
              child: _CourseCard(
                courseName: courseName,
                studentCount: studentCount,
                onDetail: () => _showCourseDetail(courseName),
              ),
            );
          }).toList()),
      ],
    );
  }

  // ── 가입 승인 대기 섹션 ────────────────────────────────
  Widget _buildPendingStudentsSection() {
    return _SectionCard(
      title: '오늘 가입 승인 대기 (${_pendingStudents.length}건)',
      child: _pendingStudents.isEmpty
          ? _emptyText('승인 대기 중인 학생이 없습니다.')
          : Column(
              children: _pendingStudents.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final name = data[FsUser.name] as String? ?? '-';
                final courseId = data[FsUser.courseId] as String?;
                final courseName = _courseNameById(courseId);
                return Semantics(
                  label: '[$courseName] $name 학생 승인 대기 항목',
                  button: true,
                  child: _PendingStudentTile(
                    name: name,
                    courseName: courseName,
                    onTap: () => _showStudentApprovalDialog(doc),
                  ),
                );
              }).toList(),
            ),
    );
  }

  // ── 구직 신청 대기 섹션 ────────────────────────────────
  Widget _buildJobApplicationsSection() {
    return _SectionCard(
      title: '구직 신청 대기 (${_pendingJobApps.length}건)',
      child: _pendingJobApps.isEmpty
          ? _emptyText('대기 중인 구직 신청이 없습니다.')
          : ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: SingleChildScrollView(
                child: Column(
                  children: _pendingJobApps.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final jobTitle = data[FsJobApp.jobTitle] as String? ?? '-';
                    final name = data[FsJobApp.applicantName] as String? ?? '-';
                    final email = data[FsJobApp.applicantEmail] as String? ?? '-';
                    final courseName = data[FsJobApp.courseName] as String? ?? '-';
                    return Semantics(
                      label: '$jobTitle 공고에 [$courseName] $name 학생 신청',
                      child: _JobAppTile(
                        jobTitle: jobTitle,
                        applicantInfo: '[$courseName] $name($email)',
                        onApprove: () => _approveJobApp(doc),
                        onCancel: () => _cancelJobApp(doc),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
    );
  }

  // ── 승인 팝업 표시 ─────────────────────────────────────
  Future<void> _showStudentApprovalDialog(QueryDocumentSnapshot doc) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _StudentApprovalDialog(
        studentDoc: doc,
        allCourses: _allCourses,
        onApprove: _approveStudent,
        onReject: _rejectStudent,
        onResetPassword: _resetStudentPassword,
      ),
    );
    if (result == true) _loadData();
  }

  // 학생 승인 — status=approved, course_id 업데이트
  Future<void> _approveStudent(String studentUid, String courseId) async {
    await _db.collection(FsCol.users).doc(studentUid).update({
      FsUser.status: FsUser.statusApproved,
      FsUser.courseId: courseId,
    });
  }

  // 학생 거절 — delete_requests 문서 생성 → Cloud Function이 Auth+Firestore 삭제
  Future<void> _rejectStudent(String studentUid) async {
    await _db.collection(FsCol.deleteRequests).doc(studentUid).set({
      'requested_at': FieldValue.serverTimestamp(),
      'requested_by': _uid,
      'reason': 'rejected',
    });
  }

  // 학생 비밀번호 초기화 — is_temp_password: true 설정 → Cloud Function이 처리
  Future<void> _resetStudentPassword(String studentUid) async {
    await _db.collection(FsCol.users).doc(studentUid).update({
      FsUser.isTempPw: true,
      FsUser.tempPwPlain: FieldValue.delete(),
    });
  }

  // 구직 신청 승인
  Future<void> _approveJobApp(QueryDocumentSnapshot doc) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('구직 신청 승인'),
        content: const Text('승인하시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _blue),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('승인', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _db.collection(FsCol.jobApplications).doc(doc.id).update({
        FsJobApp.status: FsJobApp.statusApproved,
      });
      if (!mounted) return;
      setState(() => _pendingJobApps.removeWhere((d) => d.id == doc.id));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('승인 실패: $e'), backgroundColor: Colors.red),
      );
    }
  }

  // 구직 신청 취소
  Future<void> _cancelJobApp(QueryDocumentSnapshot doc) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('구직 신청 취소'),
        content: const Text('신청을 취소 처리하시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('닫기')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('취소 처리', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _db.collection(FsCol.jobApplications).doc(doc.id).update({
        FsJobApp.status: FsJobApp.statusCancelled,
      });
      if (!mounted) return;
      setState(() => _pendingJobApps.removeWhere((d) => d.id == doc.id));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('취소 실패: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _showCourseDetail(String courseName) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$courseName 상세 (준비 중)')),
    );
  }

  String _courseNameById(String? courseId) {
    if (courseId == null) return '미배정';
    final match = _allCourses.cast<QueryDocumentSnapshot?>().firstWhere(
      (d) => d?.id == courseId,
      orElse: () => null,
    );
    if (match == null) return '알 수 없음';
    final data = match.data() as Map<String, dynamic>;
    return data[FsCourse.name] as String? ?? '-';
  }

  Widget _emptyBox(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8)],
      ),
      child: Text(message, style: const TextStyle(color: Color(0xFF757575), fontSize: 14)),
    );
  }

  Widget _emptyText(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(message, style: const TextStyle(color: Color(0xFF757575), fontSize: 14)),
    );
  }
}

// ─────────────────────────────────────────────────────────
// 담당 반 카드
// ─────────────────────────────────────────────────────────
class _CourseCard extends StatelessWidget {
  final String courseName;
  final int studentCount;
  final VoidCallback onDetail;
  const _CourseCard({required this.courseName, required this.studentCount, required this.onDetail});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF1565C0).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.class_rounded, color: Color(0xFF1565C0), size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(courseName,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E))),
                const SizedBox(height: 2),
                Text('학생 $studentCount명',
                    style: const TextStyle(fontSize: 13, color: Color(0xFF757575))),
              ],
            ),
          ),
          Semantics(
            label: '$courseName 자세히 보기',
            button: true,
            child: TextButton(
              onPressed: onDetail,
              child: const Text('자세히 보기', style: TextStyle(fontSize: 13, color: Color(0xFF1565C0))),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// 섹션 카드 공통 컨테이너 (파란 헤더 + 흰 본문)
// ─────────────────────────────────────────────────────────
class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF1565C0),
              borderRadius: BorderRadius.only(topLeft: Radius.circular(14), topRight: Radius.circular(14)),
            ),
            child: Text(title,
                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
          ),
          Padding(padding: const EdgeInsets.all(12), child: child),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// 승인 대기 학생 목록 타일
// ─────────────────────────────────────────────────────────
class _PendingStudentTile extends StatelessWidget {
  final String name;
  final String courseName;
  final VoidCallback onTap;
  const _PendingStudentTile({required this.name, required this.courseName, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            const Icon(Icons.person_add_rounded, color: Color(0xFF1565C0), size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '[$courseName] $name',
                style: const TextStyle(fontSize: 14, color: Color(0xFF1A1A2E)),
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFF9E9E9E), size: 18),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// 구직 신청 목록 타일
// ─────────────────────────────────────────────────────────
class _JobAppTile extends StatelessWidget {
  final String jobTitle;
  final String applicantInfo;
  final VoidCallback onApprove;
  final VoidCallback onCancel;
  const _JobAppTile({
    required this.jobTitle,
    required this.applicantInfo,
    required this.onApprove,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Row(
        children: [
          const Icon(Icons.work_rounded, color: Color(0xFF00897B), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(jobTitle,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E)),
                    overflow: TextOverflow.ellipsis),
                Text(applicantInfo,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF757575)),
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Semantics(
            label: '승인',
            button: true,
            child: TextButton(
              onPressed: onApprove,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                minimumSize: const Size(48, 32),
              ),
              child: const Text('승인', style: TextStyle(color: Color(0xFF1565C0), fontSize: 13)),
            ),
          ),
          Semantics(
            label: '취소',
            button: true,
            child: TextButton(
              onPressed: onCancel,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                minimumSize: const Size(48, 32),
              ),
              child: const Text('취소', style: TextStyle(color: Colors.red, fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// 학생 승인/거절 팝업 다이얼로그
// ─────────────────────────────────────────────────────────
class _StudentApprovalDialog extends StatefulWidget {
  final QueryDocumentSnapshot studentDoc;
  final List<QueryDocumentSnapshot> allCourses;
  final Future<void> Function(String uid, String courseId) onApprove;
  final Future<void> Function(String uid) onReject;
  final Future<void> Function(String uid) onResetPassword;

  const _StudentApprovalDialog({
    required this.studentDoc,
    required this.allCourses,
    required this.onApprove,
    required this.onReject,
    required this.onResetPassword,
  });

  @override
  State<_StudentApprovalDialog> createState() => _StudentApprovalDialogState();
}

class _StudentApprovalDialogState extends State<_StudentApprovalDialog> {
  static const Color _blue = Color(0xFF1565C0);

  late String _selectedCourseId;
  bool _isProcessing = false;
  bool _isResetting = false;

  @override
  void initState() {
    super.initState();
    final data = widget.studentDoc.data() as Map<String, dynamic>;
    // 학생이 선택한 강좌를 기본값으로 설정
    _selectedCourseId = data[FsUser.courseId] as String? ?? '';
    // 목록에 없는 경우 첫 번째 강좌로 초기화
    if (_selectedCourseId.isNotEmpty &&
        !widget.allCourses.any((d) => d.id == _selectedCourseId)) {
      _selectedCourseId = '';
    }
    if (_selectedCourseId.isEmpty && widget.allCourses.isNotEmpty) {
      _selectedCourseId = widget.allCourses.first.id;
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.studentDoc.data() as Map<String, dynamic>;
    final studentUid = widget.studentDoc.id;
    final name = data[FsUser.name] as String? ?? '-';
    final email = data[FsUser.email] as String? ?? '-';
    final phone = data[FsUser.phone] as String? ?? '-';
    final loginType = data[FsUser.loginType] as String?;
    // loginType 미설정 또는 'email'이면 이메일 가입 사용자
    final isEmailUser = loginType == null || loginType == FsUser.loginTypeEmail;

    return AlertDialog(
      title: Semantics(
        header: true,
        child: const Text('가입 신청 확인', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      ),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _InfoRow(label: '이름', value: name),
              _InfoRow(label: '이메일', value: email),
              _InfoRow(label: '전화번호', value: phone),
              const SizedBox(height: 12),
              // 반 선택 Selectbox
              Semantics(
                label: '강좌 선택',
                child: DropdownButtonFormField<String>(
                  value: _selectedCourseId.isEmpty ? null : _selectedCourseId,
                  decoration: const InputDecoration(
                    labelText: '배정할 반',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  items: widget.allCourses.map((doc) {
                    final d = doc.data() as Map<String, dynamic>;
                    final cName = d[FsCourse.name] as String? ?? '-';
                    return DropdownMenuItem(value: doc.id, child: Text(cName));
                  }).toList(),
                  onChanged: _isProcessing
                      ? null
                      : (val) => setState(() => _selectedCourseId = val ?? ''),
                ),
              ),

              // 비밀번호 초기화 섹션 (이메일 가입자만 표시)
              if (isEmailUser) ...[
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                StreamBuilder<DocumentSnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection(FsCol.users)
                      .doc(studentUid)
                      .snapshots(),
                  builder: (context, snap) {
                    final sData = snap.data?.data() as Map<String, dynamic>?;
                    final tempPw = sData?[FsUser.tempPwPlain] as String?;

                    if (_isResetting && tempPw == null) {
                      return const Row(
                        children: [
                          SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 10),
                          Text('비밀번호 초기화 중...', style: TextStyle(fontSize: 13)),
                        ],
                      );
                    }

                    if (tempPw != null && _isResetting) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('비밀번호가 초기화되었습니다.',
                              style: TextStyle(fontSize: 13, color: Color(0xFF1565C0), fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          const Text('[복사하기] 버튼을 눌러 학생에게 전달하세요.',
                              style: TextStyle(fontSize: 12, color: Color(0xFF757575))),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF5F5F5),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(tempPw,
                                      style: const TextStyle(
                                          fontSize: 14, fontWeight: FontWeight.w600, fontFamily: 'monospace')),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Semantics(
                                label: '임시 비밀번호 클립보드 복사',
                                button: true,
                                child: IconButton(
                                  icon: const Icon(Icons.copy_rounded, size: 20),
                                  tooltip: '복사하기',
                                  onPressed: () {
                                    Clipboard.setData(ClipboardData(text: tempPw));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('클립보드에 복사되었습니다.')),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    }

                    // 초기 상태 — 초기화 버튼 표시
                    return Semantics(
                      label: '비밀번호 초기화 버튼',
                      button: true,
                      child: OutlinedButton.icon(
                        onPressed: _isProcessing ? null : () => _doResetPassword(studentUid),
                        icon: const Icon(Icons.lock_reset_rounded, size: 18),
                        label: const Text('비밀번호 초기화', style: TextStyle(fontSize: 13)),
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        // 거절 버튼
        Semantics(
          label: '가입 거절 버튼',
          button: true,
          child: TextButton(
            onPressed: _isProcessing ? null : () => _doReject(studentUid, name),
            child: const Text('거절 하기', style: TextStyle(color: Colors.red)),
          ),
        ),
        // 승인 버튼
        Semantics(
          label: '가입 승인 버튼',
          button: true,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _blue),
            onPressed: (_isProcessing || _selectedCourseId.isEmpty)
                ? null
                : () => _doApprove(studentUid),
            child: _isProcessing
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('승인 하기', style: TextStyle(color: Colors.white)),
          ),
        ),
      ],
    );
  }

  Future<void> _doApprove(String uid) async {
    if (_selectedCourseId.isEmpty) return;
    setState(() => _isProcessing = true);
    try {
      await widget.onApprove(uid, _selectedCourseId);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _doReject(String uid, String name) async {
    // 거절 대상 강좌명 표시용
    final courseDoc = widget.allCourses.cast<QueryDocumentSnapshot?>().firstWhere(
      (d) => d?.id == _selectedCourseId,
      orElse: () => null,
    );
    final courseName = courseDoc != null
        ? ((courseDoc.data() as Map<String, dynamic>)[FsCourse.name] as String? ?? '-')
        : '-';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('가입 거절'),
        content: Text('$courseName 반을 선택하신 $name 님의 승인이 거절됩니다.\n\n계정 정보가 완전히 삭제됩니다. 계속하시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('거절 하기', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _isProcessing = true);
    try {
      await widget.onReject(uid);
      if (!mounted) return;
      // "OOO반 선택 하신 OOO님 승인이 거절 되었습니다" 알림
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$courseName 반을 선택하신 $name 님의 승인이 거절 되었습니다.')),
      );
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _doResetPassword(String uid) async {
    setState(() => _isResetting = true);
    try {
      await widget.onResetPassword(uid);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isResetting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('초기화 실패: $e'), backgroundColor: Colors.red),
      );
    }
  }
}

// 정보 행 공통 위젯
class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Semantics(
        label: '$label: $value',
        child: Row(
          children: [
            SizedBox(
              width: 70,
              child: Text(label,
                  style: const TextStyle(fontSize: 13, color: Color(0xFF757575), fontWeight: FontWeight.w500)),
            ),
            Expanded(
              child: Text(value,
                  style: const TextStyle(fontSize: 14, color: Color(0xFF1A1A2E))),
            ),
          ],
        ),
      ),
    );
  }
}
