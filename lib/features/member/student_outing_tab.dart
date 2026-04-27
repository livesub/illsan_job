import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/utils/firestore_keys.dart';
import '../../core/utils/outing_model.dart';

class StudentOutingTab extends StatefulWidget {
  final String userName;
  const StudentOutingTab({super.key, required this.userName});

  @override
  State<StudentOutingTab> createState() => _StudentOutingTabState();
}

class _StudentOutingTabState extends State<StudentOutingTab> {
  static const Color _blue = Color(0xFF1565C0);
  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  List<OutingModel> _outings = [];
  bool _loading = true;
  String _teacherName = '';

  @override
  void initState() {
    super.initState();
    _loadMyOutings();
  }

  Future<void> _loadMyOutings() async {
    final snap = await FirebaseFirestore.instance
        .collection(FsCol.outings)
        .where(FsOuting.uid, isEqualTo: _uid)
        .get();
    if (!mounted) return;
    // 클라이언트 정렬 (복합 인덱스 없이)
    final docs = List<DocumentSnapshot>.from(snap.docs);
    docs.sort((a, b) {
      final ta = (a.data() as Map)[FsOuting.createdAt] as Timestamp?;
      final tb = (b.data() as Map)[FsOuting.createdAt] as Timestamp?;
      if (ta == null && tb == null) return 0;
      if (ta == null) return 1;
      if (tb == null) return -1;
      return tb.seconds.compareTo(ta.seconds);
    });
    final outings = docs.map(OutingModel.fromDoc).toList();

    // 승인된 외출의 담당 교사명 조회
    String teacherName = '';
    final approvedList = outings.where((o) => o.status == FsOuting.statusApproved).toList();
    if (approvedList.isNotEmpty && approvedList.first.courseId.isNotEmpty) {
      final courseDoc = await FirebaseFirestore.instance
          .collection(FsCol.courses)
          .doc(approvedList.first.courseId)
          .get();
      if (!mounted) return;
      teacherName = (courseDoc.data()?[FsCourse.teacherName] as String?) ?? '';
    }

    setState(() {
      _outings = outings;
      _teacherName = teacherName;
      _loading = false;
    });
  }

  // 신청 전: 당월 출결 현황 + 경고 AlertDialog
  Future<void> _showAttendanceAlert() async {
    final db  = FirebaseFirestore.instance;
    final doc = await db.collection(FsCol.users).doc(_uid).get();
    if (!mounted) return;
    final data         = doc.data() ?? {};
    final lateCount    = (data[FsUser.monthlyLateCount]    as int?) ?? 0;
    final absenceCount = (data[FsUser.monthlyAbsenceCount] as int?) ?? 0;
    final phone        = (data[FsUser.phone]    as String?) ?? '';
    final courseId     = (data[FsUser.courseId] as String?) ?? '';

    // 반 명(강좌명) 조회
    String courseName = '';
    if (courseId.isNotEmpty) {
      final courseDoc = await db.collection(FsCol.courses).doc(courseId).get();
      courseName = (courseDoc.data()?[FsCourse.name] as String?) ?? '';
    }
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('이번 달 출결 현황',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              label: '조퇴 $lateCount회, 결석 $absenceCount회',
              child: Text(
                '조퇴: $lateCount회  /  결석: $absenceCount회',
                style: const TextStyle(fontSize: 15),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              '조퇴 3회는 결석 1회로 처리됩니다.',
              style: TextStyle(
                  color: Colors.red,
                  fontSize: 13,
                  fontWeight: FontWeight.w700),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('신청하기')),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _showApplyForm(initialCourseName: courseName, initialPhone: phone);
    }
  }

  // 외출 신청 폼 다이얼로그
  Future<void> _showApplyForm({
    String initialCourseName = '',
    String initialPhone      = '',
  }) async {
    final formKey      = GlobalKey<FormState>();
    final jobTypeCtrl  = TextEditingController(text: initialCourseName);
    final reasonCtrl   = TextEditingController();
    final contactCtrl  = TextEditingController(text: initialPhone);
    DateTime? startTime;
    DateTime? endTime;

    String fmtDt(DateTime? dt) => dt == null
        ? '날짜/시간 선택'
        : '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDS) {
          Future<void> pickDt({required bool isStart}) async {
            final now  = DateTime.now();
            final date = await showDatePicker(
              context: ctx,
              initialDate: now,
              firstDate: now.subtract(const Duration(days: 1)),
              lastDate: now.add(const Duration(days: 30)),
            );
            if (date == null) return;
            if (!ctx.mounted) return;
            final time = await showTimePicker(
              context: ctx,
              initialTime: TimeOfDay.fromDateTime(now),
            );
            if (time == null) return;
            final dt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
            setDS(() => isStart ? startTime = dt : endTime = dt);
          }

          return AlertDialog(
            title: const Text('외출 신청',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            content: SizedBox(
              width: 320,
              child: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 성명 (read-only)
                      TextFormField(
                        initialValue: widget.userName,
                        readOnly: true,
                        decoration: const InputDecoration(labelText: '성명'),
                      ),
                      const SizedBox(height: 12),
                      // 직종
                      TextFormField(
                        controller: jobTypeCtrl,
                        decoration: const InputDecoration(labelText: '직종'),
                        validator: (v) => (v == null || v.trim().isEmpty) ? '직종을 입력하세요' : null,
                      ),
                      const SizedBox(height: 12),
                      // 사유
                      TextFormField(
                        controller: reasonCtrl,
                        decoration: const InputDecoration(labelText: '사유'),
                        maxLines: 2,
                        validator: (v) => (v == null || v.trim().isEmpty) ? '사유를 입력하세요' : null,
                      ),
                      const SizedBox(height: 12),
                      // 기간 시작
                      Semantics(
                        label: '외출 시작 일시 선택',
                        button: true,
                        child: GestureDetector(
                          onTap: () => pickDt(isStart: true),
                          child: InputDecorator(
                            decoration: const InputDecoration(labelText: '시작 일시'),
                            child: Text(
                              fmtDt(startTime),
                              style: TextStyle(
                                  color: startTime == null
                                      ? Colors.grey
                                      : Colors.black87),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // 기간 종료
                      Semantics(
                        label: '외출 종료 일시 선택',
                        button: true,
                        child: GestureDetector(
                          onTap: () => pickDt(isStart: false),
                          child: InputDecorator(
                            decoration: const InputDecoration(labelText: '종료 일시'),
                            child: Text(
                              fmtDt(endTime),
                              style: TextStyle(
                                  color: endTime == null
                                      ? Colors.grey
                                      : Colors.black87),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // 연락처
                      TextFormField(
                        controller: contactCtrl,
                        decoration: const InputDecoration(labelText: '연락처(휴대폰)'),
                        keyboardType: TextInputType.phone,
                        validator: (v) => (v == null || v.trim().isEmpty) ? '연락처를 입력하세요' : null,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('취소')),
              TextButton(
                onPressed: () async {
                  if (!formKey.currentState!.validate()) return;
                  if (startTime == null || endTime == null) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('기간을 선택하세요')),
                    );
                    return;
                  }
                  final hasOverlap = await _hasTimeOverlap(startTime!, endTime!);
                  if (!ctx.mounted) return;
                  if (hasOverlap) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(
                        content: Text('해당 시간대에 이미 신청 중이거나 승인된 외출 건이 있습니다.'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }
                  Navigator.pop(ctx);
                  await _submitOuting(
                    jobType:   jobTypeCtrl.text.trim(),
                    reason:    reasonCtrl.text.trim(),
                    startTime: startTime!,
                    endTime:   endTime!,
                    contact:   contactCtrl.text.trim(),
                  );
                },
                child: const Text('저장'),
              ),
            ],
          );
        },
      ),
    );
  }

  // status가 pending/approved인 기존 신청과 시간 겹침 여부 확인
  Future<bool> _hasTimeOverlap(DateTime newStart, DateTime newEnd) async {
    final snap = await FirebaseFirestore.instance
        .collection(FsCol.outings)
        .where(FsOuting.uid, isEqualTo: _uid)
        .get();
    for (final doc in snap.docs) {
      final data = doc.data();
      final status = (data[FsOuting.status] as String?) ?? '';
      if (status == FsOuting.statusRejected) continue;
      final existStart = (data[FsOuting.startTime] as Timestamp?)?.toDate();
      final existEnd   = (data[FsOuting.endTime]   as Timestamp?)?.toDate();
      if (existStart == null || existEnd == null) continue;
      if (newStart.isBefore(existEnd) && newEnd.isAfter(existStart)) return true;
    }
    return false;
  }

  // Firestore outings 컬렉션에 저장
  Future<void> _submitOuting({
    required String jobType,
    required String reason,
    required DateTime startTime,
    required DateTime endTime,
    required String contact,
  }) async {
    // 학생 소속 강좌 ID 조회 (교사 필터링용 비정규화)
    final userDoc = await FirebaseFirestore.instance
        .collection(FsCol.users)
        .doc(_uid)
        .get();
    final courseId = (userDoc.data()?[FsUser.courseId] as String?) ?? '';

    final model = OutingModel(
      id:        '',
      uid:       _uid,
      userName:  widget.userName,
      courseId:  courseId,
      jobType:   jobType,
      reason:    reason,
      startTime: startTime,
      endTime:   endTime,
      contact:   contact,
      status:    FsOuting.statusPending,
    );
    await FirebaseFirestore.instance
        .collection(FsCol.outings)
        .add(model.toMap());
    if (!mounted) return;
    setState(() {
      _outings.clear();
      _loading = true;
    });
    await _loadMyOutings();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _outings.isEmpty
              ? Semantics(
                  label: '외출 신청 내역이 없습니다.',
                  child: const Center(
                    child: Text('외출 신청 내역이 없습니다.',
                        style: TextStyle(fontSize: 15, color: Color(0xFF757575))),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () async {
                    setState(() {
                      _outings.clear();
                      _loading = true;
                    });
                    await _loadMyOutings();
                  },
                  child: Builder(
                    builder: (_) {
                      final approved = _outings
                          .where((o) => o.status == FsOuting.statusApproved)
                          .toList();
                      final latestApproved = approved.isEmpty ? null : approved.first;
                      final rest = latestApproved == null
                          ? _outings
                          : _outings.where((o) => o.id != latestApproved.id).toList();
                      return ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          if (latestApproved != null)
                            _buildOutingCertificate(latestApproved),
                          ...rest.map(_buildOutingTile),
                        ],
                      );
                    },
                  ),
                ),
      floatingActionButton: Semantics(
        label: '외출 신청 버튼',
        button: true,
        child: FloatingActionButton(
          backgroundColor: _blue,
          onPressed: _showAttendanceAlert,
          tooltip: '외출 신청',
          child: const Icon(Icons.add, color: Colors.white),
        ),
      ),
    );
  }

  // 최신 승인 건: (외출·외박) 허가증 형태 카드
  Widget _buildOutingCertificate(OutingModel m) {
    String pad2(int v) => v.toString().padLeft(2, '0');

    return Semantics(
      label: '승인된 외출증: ${m.userName}, 사유: ${m.reason}',
      child: Container(
        margin: const EdgeInsets.only(bottom: 20),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.black87, width: 1.5),
          borderRadius: BorderRadius.circular(4),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 8,
              offset: const Offset(2, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(
              child: Text(
                '( 외 출 · 외 박 )  허  가  증',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
            ),
            const SizedBox(height: 28),
            Row(children: [
              const Text('1. 직  종 : ', style: TextStyle(fontSize: 14)),
              Expanded(child: Text(m.jobType, style: const TextStyle(fontSize: 14))),
              const SizedBox(width: 8),
              const Text('2. 성  명 : ', style: TextStyle(fontSize: 14)),
              Expanded(child: Text(m.userName, style: const TextStyle(fontSize: 14))),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              const Text('3. 호  실 : ', style: TextStyle(fontSize: 14)),
              const Expanded(child: SizedBox()),
              const SizedBox(width: 8),
              const Text('(전 화)  ', style: TextStyle(fontSize: 14)),
              Expanded(child: Text(m.contact, style: const TextStyle(fontSize: 14))),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              const Text('4. 사  유 : ', style: TextStyle(fontSize: 14)),
              Expanded(
                child: Text(m.reason, style: const TextStyle(fontSize: 14), softWrap: true),
              ),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              const Text('5. 기  간 : ', style: TextStyle(fontSize: 14)),
              Expanded(
                child: Text(
                  '${m.startTime.month}월 ${m.startTime.day}일 ${pad2(m.startTime.hour)}시부터'
                  '  ${m.endTime.month}월 ${m.endTime.day}일 ${pad2(m.endTime.hour)}시까지',
                  style: const TextStyle(fontSize: 14),
                  softWrap: true,
                ),
              ),
            ]),
            const SizedBox(height: 28),
            const Center(
              child: Text(
                '위와 같은 사유로 (외출·외박)을 허가함',
                style: TextStyle(fontSize: 14),
              ),
            ),
            const SizedBox(height: 22),
            Center(
              child: Text(
                '${m.startTime.year}년  ${m.startTime.month}월  ${m.startTime.day}일',
                style: const TextStyle(fontSize: 14),
              ),
            ),
            const SizedBox(height: 22),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('담 당 교 사', style: TextStyle(fontSize: 14)),
                const SizedBox(width: 12),
                Text(_teacherName, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 8),
                Container(width: 64, height: 1, color: Colors.black54),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOutingTile(OutingModel m) {
    final (label, color) = switch (m.status) {
      FsOuting.statusApproved => ('승인', const Color(0xFF2E7D32)),
      FsOuting.statusRejected => ('반려', const Color(0xFFD32F2F)),
      _                       => ('대기', const Color(0xFFEF6C00)),
    };
    String fmtDt(DateTime dt) =>
        '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

    return Semantics(
      label: '${m.jobType}, ${m.reason}, ${fmtDt(m.startTime)} ~ ${fmtDt(m.endTime)}, 상태: $label',
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
                offset: const Offset(0, 2)),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(m.jobType,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1A1A2E))),
                  const SizedBox(height: 4),
                  Text(m.reason,
                      style: const TextStyle(
                          fontSize: 13, color: Color(0xFF444444)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(
                    '${fmtDt(m.startTime)} ~ ${fmtDt(m.endTime)}',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF757575)),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: color)),
            ),
          ],
        ),
      ),
    );
  }
}
