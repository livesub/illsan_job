// 관리자 대시보드 홈 탭입니다.
// Firestore 실시간 연동으로 통계 카드 3개와 처리 필요 알림을 표시합니다.
//
// 통계 항목:
//   - 활동 중인 교사 수 (role=INSTRUCTOR, is_deleted≠true)
//   - 진행 중인 강좌 수 (status=active)
//   - 전체 누적 수강생 수 (role=STUDENT)

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/utils/firestore_keys.dart';

// 관리 대시보드 홈 탭 위젯입니다.
class HomeTab extends StatelessWidget {
  const HomeTab({super.key});

  // Firestore 인스턴스 — 모든 DB 요청에 사용합니다.
  static final _db = FirebaseFirestore.instance;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 페이지 제목 ──────────────────────────────────
          const Text('관리 대시보드',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF1A1A2E))),
          const SizedBox(height: 4),
          const Text('전체 현황을 한눈에 확인하세요.',
              style: TextStyle(fontSize: 14, color: Color(0xFF757575))),
          const SizedBox(height: 20),

          // ── 통계 카드 3개 (Firestore 실시간) ──────────────
          LayoutBuilder(
            builder: (context, constraints) {
              final int cols = constraints.maxWidth > 700 ? 3 : 1;
              return GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: cols,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                childAspectRatio: constraints.maxWidth > 700 ? 2.2 : 3.5,
                children: [
                  // 활동 중인 교사 수
                  _FirestoreStatCard(
                    stream: _db
                        .collection(FsCol.users)
                        .where(FsUser.role, isEqualTo: 'INSTRUCTOR')
                        .where(FsUser.isDeleted, isNotEqualTo: true)
                        .snapshots(),
                    label: '활동 중인 교사',
                    icon: Icons.person_rounded,
                    color: const Color(0xFF1565C0),
                    unit: '명',
                  ),
                  // 진행 중인 강좌 수
                  _FirestoreStatCard(
                    stream: _db
                        .collection(FsCol.courses)
                        .where(FsCourse.status, isEqualTo: FsCourse.statusActive)
                        .snapshots(),
                    label: '진행 중인 강좌',
                    icon: Icons.school_rounded,
                    color: const Color(0xFF00897B),
                    unit: '개',
                  ),
                  // 전체 누적 수강생 수
                  _FirestoreStatCard(
                    stream: _db
                        .collection(FsCol.users)
                        .where(FsUser.role, isEqualTo: 'STUDENT')
                        .snapshots(),
                    label: '전체 누적 수강생',
                    icon: Icons.school_outlined,
                    color: const Color(0xFFF57C00),
                    unit: '명',
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 24),

          // ── 승인 대기 알림 (Firestore 실시간) ─────────────
          _buildPendingSection(),
        ],
      ),
    );
  }

  // 승인 대기 중인 학생 목록을 실시간으로 표시하는 섹션입니다.
  Widget _buildPendingSection() {
    return StreamBuilder<QuerySnapshot>(
      // 승인 대기(pending) 상태인 학생만 조회합니다.
      stream: _db
          .collection(FsCol.users)
          .where(FsUser.role, isEqualTo: 'STUDENT')
          .where(FsUser.status, isEqualTo: 'pending')
          .orderBy(FsUser.createdAt, descending: true)
          .limit(5) // 최대 5건만 표시합니다.
          .snapshots(),
      builder: (context, snapshot) {
        // 로딩 중일 때 표시합니다.
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _DashCard(
            title: '처리 필요 알림',
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final docs = snapshot.data?.docs ?? [];

        return _DashCard(
          title: '처리 필요 알림 (승인 대기: ${docs.length}건)',
          child: docs.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('처리 대기 중인 항목이 없습니다.',
                      style: TextStyle(color: Color(0xFF757575), fontSize: 14)),
                )
              : Column(
                  children: docs.map((doc) {
                    // Firestore 문서에서 이름 필드를 가져옵니다.
                    final data = doc.data() as Map<String, dynamic>;
                    final name = data[FsUser.name] ?? '이름 없음';
                    return _AlertTile(
                      icon: Icons.person_add_rounded,
                      color: const Color(0xFF1565C0),
                      text: '$name 학생이 가입 승인을 기다리고 있습니다.',
                    );
                  }).toList(),
                ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────
// Firestore 실시간 통계 카드
// stream에서 문서 수를 세어 숫자로 표시합니다.
// ─────────────────────────────────────────────────────────
// ─────────────────────────────────────────────────────────
// Firestore 실시간 통계 카드 (에러 처리 추가 버전)
// ─────────────────────────────────────────────────────────
class _FirestoreStatCard extends StatelessWidget {
  final Stream<QuerySnapshot> stream; 
  final String label;                 
  final IconData icon;                
  final Color color;                  
  final String unit;                  

  const _FirestoreStatCard({
    required this.stream,
    required this.label,
    required this.icon,
    required this.color,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (context, snapshot) {
        // 1. 에러가 발생한 경우 처리 (빨간색 에러 아이콘 표시)
        if (snapshot.hasError) {
          debugPrint('Firestore StatCard Error ($label): ${snapshot.error}'); // 콘솔에 에러 출력
          return _buildCardContainer(
            child: const Icon(Icons.error_outline, color: Colors.red, size: 28),
          );
        }

        // 2. 로딩 중인 경우 처리
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildCardContainer(
            child: SizedBox(
              width: 20, height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            ),
          );
        }

        // 3. 정상적으로 데이터를 가져온 경우
        final count = snapshot.data?.docs.length ?? 0;
        final displayValue = '$count$unit';

        return Semantics(
          label: '$label: $displayValue',
          child: _buildCardContainer(
            child: Text(displayValue,
                style: TextStyle(
                    fontSize: 28, fontWeight: FontWeight.w800, color: color)),
          ),
        );
      },
    );
  }

  // 카드 UI 디자인을 공통으로 빼낸 헬퍼 메서드입니다.
  Widget _buildCardContainer({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Row(
        children: [
          // 아이콘 배지
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          // 내용 (로딩, 에러, 혹은 숫자) + 레이블
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              child, // 이 자리에 숫자가 들어가거나 로딩바, 에러 아이콘이 들어갑니다.
              Text(label,
                  style: const TextStyle(
                      fontSize: 13, color: Color(0xFF757575), fontWeight: FontWeight.w500)),
            ],
          ),
        ],
      ),
    );
  }
}

// 카드 컨테이너 공통 위젯 — 파란 헤더 + 흰 본문 구조입니다.
class _DashCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _DashCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 파란 헤더
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

// 알림 항목 한 줄 위젯입니다.
class _AlertTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _AlertTile({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '알림: $text',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 14, color: Color(0xFF1A1A2E)))),
          ],
        ),
      ),
    );
  }
}
