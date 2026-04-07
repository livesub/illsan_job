// 공지사항 관리 탭입니다.
// SUPER_ADMIN: 전체 공지사항 작성/수정/삭제
// INSTRUCTOR : 내 반 공지사항 작성/수정/삭제
//
// Firestore: notices 컬렉션
// - id         : String    // 공지 고유 ID
// - title      : String    // 공지 제목
// - content    : String    // 공지 내용
// - type       : String    // 'all' (전체) | 'class' (반별)
// - classId    : String?   // 반별 공지일 때 해당 강좌 ID
// - authorUid  : String    // 작성자 uid
// - created_at : Timestamp

import 'package:flutter/material.dart';

// 공지사항 관리 탭 위젯입니다.
class NoticeTab extends StatefulWidget {
  const NoticeTab({super.key});

  @override
  State<NoticeTab> createState() => _NoticeTabState();
}

class _NoticeTabState extends State<NoticeTab> {
  // 현재 선택된 공지 유형 필터입니다.
  String _selectedType = '전체';
  final List<String> _types = ['전체', '전체 공지', '반별 공지'];

  // TODO: Firestore notices 컬렉션에서 실제 데이터로 교체합니다.
  final List<Map<String, String>> _mockNotices = [
    {'title': '앱 점검 안내',            'type': 'all',   'date': '2026-04-05', 'author': '관리자'},
    {'title': '플러터 기초반 과제 안내',  'type': 'class', 'date': '2026-04-04', 'author': '최수아'},
    {'title': '5월 공휴일 휴강 공지',     'type': 'all',   'date': '2026-04-03', 'author': '관리자'},
    {'title': '웹 디자인반 발표 일정',    'type': 'class', 'date': '2026-04-01', 'author': '김태양'},
  ];

  @override
  Widget build(BuildContext context) {
    final filtered = _mockNotices.where((n) {
      if (_selectedType == '전체') return true;
      if (_selectedType == '전체 공지') return n['type'] == 'all';
      return n['type'] == 'class';
    }).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 페이지 제목 + 등록 버튼 ─────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('공지사항 관리', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF1A1A2E))),
                  SizedBox(height: 4),
                  Text('공지사항을 등록하고 관리합니다.', style: TextStyle(fontSize: 14, color: Color(0xFF757575))),
                ],
              ),
              Semantics(
                label: '공지사항 등록 버튼입니다.',
                child: ElevatedButton.icon(
                  onPressed: () => _showNoticeDialog(context),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('공지 등록'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1565C0),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── 유형 필터 칩 ─────────────────────────────────
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _types.map((t) {
                final bool isSelected = _selectedType == t;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(t),
                    selected: isSelected,
                    onSelected: (_) => setState(() => _selectedType = t),
                    selectedColor: const Color(0xFF1565C0),
                    labelStyle: TextStyle(color: isSelected ? Colors.white : const Color(0xFF1A1A2E), fontWeight: FontWeight.w600, fontSize: 13),
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFFE0E0E0)),
                    checkmarkColor: Colors.white,
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),
          _buildNoticeCard(filtered),
        ],
      ),
    );
  }

  // 공지 목록 카드를 구성합니다.
  Widget _buildNoticeCard(List<Map<String, String>> notices) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF1565C0),
              borderRadius: BorderRadius.only(topLeft: Radius.circular(14), topRight: Radius.circular(14)),
            ),
            child: Text('공지 목록 (${notices.length}건)', style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
          ),
          notices.isEmpty
              ? const Padding(padding: EdgeInsets.all(32), child: Text('등록된 공지사항이 없습니다.', style: TextStyle(color: Color(0xFF757575))))
              : Column(children: notices.map(_buildNoticeTile).toList()),
        ],
      ),
    );
  }

  // 공지 항목 한 행 위젯입니다.
  Widget _buildNoticeTile(Map<String, String> notice) {
    final bool isAll = notice['type'] == 'all';
    return Semantics(
      label: '${notice['title']}, ${isAll ? "전체 공지" : "반별 공지"}, 작성일: ${notice['date']}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0)))),
        child: Row(
          children: [
            // 공지 유형 배지
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: (isAll ? const Color(0xFF1565C0) : const Color(0xFFF57C00)).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                isAll ? '전체' : '반별',
                style: TextStyle(color: isAll ? const Color(0xFF1565C0) : const Color(0xFFF57C00), fontSize: 11, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(notice['title']!, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  Text('${notice['author']} · ${notice['date']}', style: const TextStyle(fontSize: 12, color: Color(0xFF757575))),
                ],
              ),
            ),
            Semantics(
              label: '${notice['title']} 수정 버튼입니다.',
              child: IconButton(icon: const Icon(Icons.edit_rounded, size: 18, color: Color(0xFF1565C0)), onPressed: () => _showNoticeDialog(context, notice: notice)),
            ),
            Semantics(
              label: '${notice['title']} 삭제 버튼입니다.',
              child: IconButton(icon: const Icon(Icons.delete_rounded, size: 18, color: Color(0xFFD32F2F)), onPressed: () {
                // TODO: Firestore notices/{id} 삭제
              }),
            ),
          ],
        ),
      ),
    );
  }

  // 공지 등록/수정 다이얼로그를 표시합니다.
  void _showNoticeDialog(BuildContext context, {Map<String, String>? notice}) {
    final titleController   = TextEditingController(text: notice?['title'] ?? '');
    final contentController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(notice == null ? '공지사항 등록' : '공지사항 수정', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: InputDecoration(
                  labelText: '제목',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF1565C0), width: 2)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: contentController,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: '내용',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF1565C0), width: 2)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          ElevatedButton(
            onPressed: () {
              // TODO: Firestore notices 컬렉션에 추가 또는 수정
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1565C0), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: Text(notice == null ? '등록' : '수정'),
          ),
        ],
      ),
    );
  }
}
