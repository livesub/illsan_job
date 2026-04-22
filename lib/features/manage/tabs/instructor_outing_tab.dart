import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/utils/firestore_keys.dart';
import '../../../core/utils/outing_model.dart';

class InstructorOutingTab extends StatefulWidget {
  const InstructorOutingTab({super.key});

  @override
  State<InstructorOutingTab> createState() => _InstructorOutingTabState();
}

class _InstructorOutingTabState extends State<InstructorOutingTab> {
  static const Color _blue = Color(0xFF1565C0);
  final _db  = FirebaseFirestore.instance;
  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  List<OutingModel> _outings = [];
  List<String>      _courseIds = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      // 담당 활성 강좌 IDs
      final courseSnap = await _db
          .collection(FsCol.courses)
          .where(FsCourse.teacherId, isEqualTo: _uid)
          .where(FsCourse.status, isEqualTo: FsCourse.statusActive)
          .get();
      _courseIds = courseSnap.docs.map((d) => d.id).toList();

      if (_courseIds.isEmpty) {
        setState(() { _outings = []; _loading = false; });
        return;
      }

      // 담당 반 외출 신청 (복합 인덱스 회피: status 클라이언트 필터)
      final outingSnap = await _db
          .collection(FsCol.outings)
          .where(FsOuting.courseId, whereIn: _courseIds.take(30).toList())
          .get();

      final docs = outingSnap.docs.toList();

      // pending 우선, 이후 최신순
      docs.sort((a, b) {
        final sA = (a.data() as Map)[FsOuting.status] as String? ?? '';
        final sB = (b.data() as Map)[FsOuting.status] as String? ?? '';
        final pA = sA == FsOuting.statusPending ? 0 : 1;
        final pB = sB == FsOuting.statusPending ? 0 : 1;
        if (pA != pB) return pA.compareTo(pB);
        final ta = (a.data() as Map)[FsOuting.createdAt] as Timestamp?;
        final tb = (b.data() as Map)[FsOuting.createdAt] as Timestamp?;
        if (ta == null && tb == null) return 0;
        if (ta == null) return 1;
        if (tb == null) return -1;
        return tb.seconds.compareTo(ta.seconds);
      });

      setState(() {
        _outings = docs.map(OutingModel.fromDoc).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('로드 실패: $e'), backgroundColor: Colors.red),
      );
    }
  }

  // 거절 버튼 클릭: status → rejected 업데이트
  Future<void> _rejectOuting(OutingModel outing) async {
    try {
      await _db.collection(FsCol.outings).doc(outing.id).update({
        FsOuting.status: FsOuting.statusRejected,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('거절 처리되었습니다.')),
      );
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('거절 실패: $e'), backgroundColor: Colors.red),
      );
    }
  }

  // 승인 버튼 클릭: 출결 현황 팝업 → 확인 → Transaction
  Future<void> _showApproveDialog(OutingModel outing) async {
    // 현재 학생 출결 현황 조회
    final userDoc = await _db.collection(FsCol.users).doc(outing.uid).get();
    if (!mounted) return;
    final data       = userDoc.data() ?? {};
    final lateCount  = (data[FsUser.monthlyLateCount]    as int?) ?? 0;
    final absCount   = (data[FsUser.monthlyAbsenceCount] as int?) ?? 0;
    // 이번 승인으로 3회 도달 여부
    final willConvert = (lateCount + 1) >= 3;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Semantics(
          header: true,
          child: Text('${outing.userName} 출결 현황',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              label: '조퇴 $lateCount회, 결석 $absCount회',
              child: Text(
                '조퇴: $lateCount회  /  결석: $absCount회',
                style: const TextStyle(fontSize: 15),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              willConvert
                  ? '승인 시 조퇴 3회 달성 → 결석 1회로 전환됩니다.'
                  : '승인 시 조퇴 ${lateCount + 1}회가 됩니다.',
              style: TextStyle(
                color: willConvert ? Colors.red : const Color(0xFF444444),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _blue),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('승인', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    await _runApproveTransaction(outing);
  }

  // [핵심] 조퇴 3회 → 결석 1회 원자적 트랜잭션 + 외출 상태 승인
  Future<void> _runApproveTransaction(OutingModel outing) async {
    try {
      await _db.runTransaction((tx) async {
        final userRef   = _db.collection(FsCol.users).doc(outing.uid);
        final outingRef = _db.collection(FsCol.outings).doc(outing.id);
        final snap = await tx.get(userRef);
        int late = (snap.data()?[FsUser.monthlyLateCount]    as int?) ?? 0;
        int abs  = (snap.data()?[FsUser.monthlyAbsenceCount] as int?) ?? 0;
        late += 1;
        if (late >= 3) {
          late = 0;   // 조퇴 리셋
          abs  += 1;  // 결석 1회 추가
        }
        tx.update(userRef, {
          FsUser.monthlyLateCount:    late,
          FsUser.monthlyAbsenceCount: abs,
        });
        tx.update(outingRef, {FsOuting.status: FsOuting.statusApproved});
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('승인 완료되었습니다.')),
      );
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('승인 실패: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _loadData,
      child: _outings.isEmpty
          ? ListView(
              children: const [
                SizedBox(height: 80),
                Center(
                  child: Text('외출 신청 내역이 없습니다.',
                      style: TextStyle(fontSize: 15, color: Color(0xFF757575))),
                ),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _outings.length,
              itemBuilder: (_, i) => _buildOutingCard(_outings[i]),
            ),
    );
  }

  Widget _buildOutingCard(OutingModel m) {
    String fmtDt(DateTime dt) =>
        '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

    final isPending = m.status == FsOuting.statusPending;
    final (statusLabel, statusColor) = switch (m.status) {
      FsOuting.statusApproved => ('승인', const Color(0xFF2E7D32)),
      FsOuting.statusRejected => ('거절', const Color(0xFFD32F2F)),
      _ => ('대기', const Color(0xFFEF6C00)),
    };

    return Semantics(
      label: '${m.userName}, ${m.jobType}, ${m.reason}, 기간: ${fmtDt(m.startTime)} ~ ${fmtDt(m.endTime)}, 상태: $statusLabel',
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${m.userName}  ·  ${m.jobType}',
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A1A2E)),
                  ),
                ),
                if (isPending) ...[
                  Semantics(
                    label: '${m.userName} 외출 신청 거절 버튼',
                    button: true,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        minimumSize: const Size(48, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () => _rejectOuting(m),
                      child: const Text('거절',
                          style: TextStyle(color: Colors.red, fontSize: 13)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Semantics(
                    label: '${m.userName} 외출 신청 승인 버튼',
                    button: true,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _blue,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        minimumSize: const Size(48, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () => _showApproveDialog(m),
                      child: const Text('승인',
                          style: TextStyle(color: Colors.white, fontSize: 13)),
                    ),
                  ),
                ] else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(statusLabel,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: statusColor)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '사유: ${m.reason}',
              style: const TextStyle(fontSize: 13, color: Color(0xFF444444)),
              softWrap: true,
            ),
            const SizedBox(height: 4),
            Text(
              '기간: ${fmtDt(m.startTime)} ~ ${fmtDt(m.endTime)}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF757575)),
            ),
            const SizedBox(height: 2),
            Text(
              '연락처: ${m.contact}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF757575)),
            ),
          ],
        ),
      ),
    );
  }
}
