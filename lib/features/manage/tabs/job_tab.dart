// 구직 등록 관리 탭입니다.
// SUPER_ADMIN: 전체 구직 게시물 수정/삭제 가능
// INSTRUCTOR : 본인 강좌의 구직 게시물 등록/수정/삭제
//
// Firestore: jobs 컬렉션
// - id          : String    // 게시물 고유 ID
// - title       : String    // 게시물 제목
// - description : String    // 모집 내용
// - className   : String    // 관련 강좌명
// - headcount   : int       // 모집 인원
// - deadline    : Timestamp // 모집 마감일
// - authorUid   : String    // 작성 교사 uid
// - created_at  : Timestamp

import 'package:flutter/material.dart';

// 구직 등록 관리 탭 위젯입니다.
class JobTab extends StatefulWidget {
  const JobTab({super.key});

  @override
  State<JobTab> createState() => _JobTabState();
}

class _JobTabState extends State<JobTab> {
  // TODO: Firestore jobs 컬렉션에서 실제 데이터로 교체합니다.
  final List<Map<String, String>> _mockJobs = [
    {'title': '플러터 앱 개발자 모집',    'class': '플러터 기초반', 'headcount': '3명', 'deadline': '2026-05-01', 'author': '최수아'},
    {'title': '웹 UI 디자이너 모집',      'class': '웹 디자인반',   'headcount': '2명', 'deadline': '2026-04-20', 'author': '김태양'},
    {'title': 'AI 데이터 입력 보조 모집', 'class': 'AI 활용반',     'headcount': '5명', 'deadline': '2026-04-30', 'author': '이지은'},
  ];

  @override
  Widget build(BuildContext context) {
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
                  Text('구직 등록 관리', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF1A1A2E))),
                  SizedBox(height: 4),
                  Text('구직 게시물을 등록하고 관리합니다.', style: TextStyle(fontSize: 14, color: Color(0xFF757575))),
                ],
              ),
              Semantics(
                label: '구직 게시물 등록 버튼입니다.',
                child: ElevatedButton.icon(
                  onPressed: () => _showJobDialog(context),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('게시물 등록'),
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
          _buildJobCard(),
        ],
      ),
    );
  }

  // 구직 목록 카드를 구성합니다.
  Widget _buildJobCard() {
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
            child: Text('구직 게시물 (${_mockJobs.length}건)', style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
          ),
          _mockJobs.isEmpty
              ? const Padding(padding: EdgeInsets.all(32), child: Text('등록된 구직 게시물이 없습니다.', style: TextStyle(color: Color(0xFF757575))))
              : Column(children: _mockJobs.map(_buildJobTile).toList()),
        ],
      ),
    );
  }

  // 구직 게시물 한 항목의 행 위젯입니다.
  Widget _buildJobTile(Map<String, String> job) {
    return Semantics(
      label: '${job['title']}, ${job['class']}, 모집인원: ${job['headcount']}, 마감일: ${job['deadline']}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0)))),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: const Color(0xFF1565C0).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.work_rounded, color: Color(0xFF1565C0), size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(job['title']!, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  Text('${job['class']} · 모집 ${job['headcount']} · 마감 ${job['deadline']}', style: const TextStyle(fontSize: 12, color: Color(0xFF757575))),
                ],
              ),
            ),
            Semantics(
              label: '${job['title']} 수정 버튼입니다.',
              child: IconButton(icon: const Icon(Icons.edit_rounded, size: 18, color: Color(0xFF1565C0)), onPressed: () => _showJobDialog(context, job: job)),
            ),
            Semantics(
              label: '${job['title']} 삭제 버튼입니다.',
              child: IconButton(icon: const Icon(Icons.delete_rounded, size: 18, color: Color(0xFFD32F2F)), onPressed: () {
                // TODO: Firestore jobs/{id} 문서 삭제 (Storage 연관 파일도 Hard Delete)
              }),
            ),
          ],
        ),
      ),
    );
  }

  // 구직 게시물 등록/수정 다이얼로그를 표시합니다.
  void _showJobDialog(BuildContext context, {Map<String, String>? job}) {
    final titleController    = TextEditingController(text: job?['title'] ?? '');
    final headcountController = TextEditingController(text: job?['headcount'] ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(job == null ? '구직 게시물 등록' : '구직 게시물 수정', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: InputDecoration(
                  labelText: '게시물 제목',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF1565C0), width: 2)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: headcountController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: '모집 인원',
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
              // TODO: Firestore jobs 컬렉션에 추가 또는 수정
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1565C0), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: Text(job == null ? '등록' : '수정'),
          ),
        ],
      ),
    );
  }
}
