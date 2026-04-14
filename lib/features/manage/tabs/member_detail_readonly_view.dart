import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/utils/firestore_keys.dart';

// 교사(INSTRUCTOR) 역할 전용 — 교사 정보 읽기 전용 다이얼로그
class MemberDetailReadonlyView extends StatefulWidget {
  final QueryDocumentSnapshot doc;
  final List<Map<String, String>> courses;
  const MemberDetailReadonlyView({super.key, required this.doc, required this.courses});

  @override
  State<MemberDetailReadonlyView> createState() => _MemberDetailReadonlyViewState();
}

class _MemberDetailReadonlyViewState extends State<MemberDetailReadonlyView> {
  static const Color _blue = Color(0xFF1565C0);

  List<String> _assignedCourseNames = [];

  @override
  void initState() {
    super.initState();
    // 현재 강좌 목록에서 이 교사에게 배정된 반만 필터
    _assignedCourseNames = widget.courses
        .where((c) => c['teacherId'] == widget.doc.id)
        .map((c) => c['name'] ?? '')
        .where((n) => n.isNotEmpty)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final data     = widget.doc.data() as Map<String, dynamic>;
    final name     = (data[FsUser.name]  as String?) ?? '-';
    final phone    = (data[FsUser.phone] as String?) ?? '-';
    final bio      = (data[FsUser.bio]   as String?) ?? '';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('교사 정보',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                Semantics(
                  label: '닫기 버튼입니다.',
                  child: IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ]),
              const SizedBox(height: 20),
              _infoRow('이름', name),
              const SizedBox(height: 14),
              _infoRow('전화번호', phone.isNotEmpty ? phone : '-'),
              const SizedBox(height: 14),
              _infoRow('쓰고 싶은 말', bio.isNotEmpty ? bio : '-', multiLine: true),
              const SizedBox(height: 20),
              const Text('담당 반',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E))),
              const SizedBox(height: 8),
              _assignedCourseNames.isEmpty
                  ? const Text('배정된 반이 없습니다.',
                      style: TextStyle(fontSize: 14, color: Color(0xFF757575)))
                  : Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFE0E0E0)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        children: _assignedCourseNames.map((courseName) {
                          return Semantics(
                            label: '$courseName 반',
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              decoration: const BoxDecoration(
                                  border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0)))),
                              child: Row(children: [
                                const Icon(Icons.class_rounded, size: 16, color: _blue),
                                const SizedBox(width: 8),
                                Text(courseName, style: const TextStyle(fontSize: 14)),
                              ]),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
              const SizedBox(height: 28),
              Semantics(
                label: '닫기 버튼입니다.',
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: _blue),
                      foregroundColor: _blue,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('닫기', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value, {bool multiLine = false}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E))),
      const SizedBox(height: 6),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F9FA),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE0E0E0)),
        ),
        child: Text(value,
            style: const TextStyle(fontSize: 14, color: Color(0xFF1A1A2E)),
            maxLines: multiLine ? null : 1,
            overflow: multiLine ? null : TextOverflow.ellipsis),
      ),
    ]);
  }
}
