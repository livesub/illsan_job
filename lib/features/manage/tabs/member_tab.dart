// 전체 회원 관리 탭입니다.
// Firestore users 컬렉션에서 전체 회원을 불러옵니다.
//
// 기능:
//   - 상단: 강좌 선택(Selectbox) + 이름 검색
//   - 상태 필터 칩 (전체/승인대기/승인완료/거절)
//   - 회원 목록 (10명씩 페이징)
//   - 학생 항목: 수정/삭제/초기화 버튼 숨김 (Read-only)
//   - 교사 항목: 수정/삭제 버튼 노출

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/utils/firestore_keys.dart';

// 전체 회원 관리 탭 위젯입니다.
class MemberTab extends StatefulWidget {
  const MemberTab({super.key});

  @override
  State<MemberTab> createState() => _MemberTabState();
}

class _MemberTabState extends State<MemberTab> {
  // ── 상수 ─────────────────────────────────────────────────
  static const int _pageSize = 10;       // 한 페이지에 표시할 회원 수
  static const Color _blue = Color(0xFF1565C0);

  // ── 상태 변수 ─────────────────────────────────────────────
  final TextEditingController _searchCtrl = TextEditingController();

  // 현재 선택된 상태 필터 ('전체' | 'pending' | 'approved' | 'rejected')
  String _statusFilter = '전체';

  // 현재 선택된 강좌 ID ('전체'이면 필터 없음)
  String _courseFilter = '전체';

  // 강좌 목록 (Selectbox에 표시할 데이터)
  List<Map<String, String>> _courses = [];

  // 현재 페이지의 회원 목록
  List<QueryDocumentSnapshot> _members = [];

  // 페이지 커서 스택 — 이전 페이지로 돌아가기 위해 저장합니다.
  // index 0 = 1페이지 시작, index n = (n+1)페이지 시작 커서
  final List<DocumentSnapshot?> _cursors = [null];

  // 현재 페이지 번호 (1부터 시작)
  int _currentPage = 1;

  // 다음 페이지가 존재하는지 여부
  bool _hasMore = false;

  // 로딩 중 여부
  bool _isLoading = false;

  // 필터 선택지 목록
  final List<Map<String, String>> _statusFilters = [
    {'label': '전체',    'value': '전체'},
    {'label': '승인 대기', 'value': 'pending'},
    {'label': '승인 완료', 'value': 'approved'},
    {'label': '거절',    'value': 'rejected'},
  ];

  @override
  void initState() {
    super.initState();
    _loadCourses(); // 강좌 목록 로드
    _loadPage();    // 첫 페이지 로드
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────
  // Firestore에서 강좌 목록을 불러옵니다. (Selectbox용)
  // ─────────────────────────────────────────────────────────
  Future<void> _loadCourses() async {
    final snap = await FirebaseFirestore.instance
        .collection(FsCol.courses)
        .where(FsCourse.status, isEqualTo: FsCourse.statusActive)
        .orderBy(FsCourse.name)
        .get();

    if (!mounted) return;
    setState(() {
      _courses = snap.docs.map((d) => {
        'id': d.id,
        'name': (d.data()[FsCourse.name] ?? '') as String,
      }).toList();
    });
  }

  // ─────────────────────────────────────────────────────────
  // Firestore에서 현재 페이지의 회원 목록을 불러옵니다.
  // ─────────────────────────────────────────────────────────
  Future<void> _loadPage() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      // 기본 쿼리를 구성합니다.
      Query query = FirebaseFirestore.instance.collection(FsCol.users);

      // 상태 필터 적용
      if (_statusFilter != '전체') {
        query = query.where(FsUser.status, isEqualTo: _statusFilter);
      }

      // 강좌 필터 적용
      if (_courseFilter != '전체') {
        query = query.where(FsUser.courseId, isEqualTo: _courseFilter);
      }

      // 이름 검색 (prefix 검색 방식)
      // Firestore는 LIKE 검색을 지원하지 않으므로 범위 쿼리로 구현합니다.
      final search = _searchCtrl.text.trim();
      if (search.isNotEmpty) {
        query = query
            .where(FsUser.name, isGreaterThanOrEqualTo: search)
            .where(FsUser.name, isLessThanOrEqualTo: '$search\uf8ff');
      }

      // 정렬 및 페이징 적용
      query = query.orderBy(FsUser.name).limit(_pageSize + 1);

      // 현재 페이지 시작 커서가 있으면 적용합니다.
      final cursor = _cursors[_currentPage - 1];
      if (cursor != null) {
        query = query.startAfterDocument(cursor);
      }

      final snapshot = await query.get();
      final docs = snapshot.docs;

      // _pageSize + 1개를 가져와서 다음 페이지 존재 여부를 판단합니다.
      final hasMore = docs.length > _pageSize;
      final pageDocs = hasMore ? docs.sublist(0, _pageSize) : docs;

      if (!mounted) return;
      setState(() {
        _members = pageDocs;
        _hasMore = hasMore;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('회원 목록 불러오기 실패: $e'), backgroundColor: Colors.red),
      );
    }
  }

  // 필터/검색 변경 시 첫 페이지부터 다시 로드합니다.
  void _resetAndLoad() {
    _cursors
      ..clear()
      ..add(null);
    _currentPage = 1;
    _loadPage();
  }

  // 다음 페이지로 이동합니다.
  void _nextPage() {
    if (!_hasMore || _members.isEmpty) return;
    // 현재 마지막 문서를 다음 페이지 커서로 저장합니다.
    if (_cursors.length <= _currentPage) {
      _cursors.add(_members.last);
    }
    setState(() => _currentPage++);
    _loadPage();
  }

  // 이전 페이지로 이동합니다.
  void _prevPage() {
    if (_currentPage <= 1) return;
    setState(() => _currentPage--);
    _loadPage();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 페이지 제목 ──────────────────────────────────
          const Text('전체 회원 관리',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF1A1A2E))),
          const SizedBox(height: 4),
          const Text('가입된 전체 회원을 조회합니다. 학생 항목은 조회만 가능합니다.',
              style: TextStyle(fontSize: 14, color: Color(0xFF757575))),
          const SizedBox(height: 20),

          // ── 검색/필터 영역 ───────────────────────────────
          _buildFilters(),
          const SizedBox(height: 16),

          // ── 회원 목록 ────────────────────────────────────
          _buildMemberList(),
          const SizedBox(height: 12),

          // ── 페이징 버튼 ──────────────────────────────────
          _buildPagination(),
        ],
      ),
    );
  }

  // 검색창 + 강좌 Selectbox + 상태 필터 칩을 구성합니다.
  Widget _buildFilters() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 첫 줄: 이름 검색 + 강좌 선택
        Row(
          children: [
            // 이름 검색창
            Expanded(
              flex: 2,
              child: Semantics(
                label: '회원 이름 검색 입력란입니다.',
                child: TextField(
                  controller: _searchCtrl,
                  onSubmitted: (_) => _resetAndLoad(),
                  decoration: InputDecoration(
                    hintText: '이름으로 검색 (Enter)',
                    prefixIcon: const Icon(Icons.search_rounded, color: _blue),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: () {
                              _searchCtrl.clear();
                              _resetAndLoad();
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _blue, width: 2)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // 강좌 선택 Selectbox
            Expanded(
              flex: 2,
              child: Semantics(
                label: '강좌 선택 드롭다운입니다.',
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE0E0E0)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _courseFilter,
                      isExpanded: true,
                      items: [
                        const DropdownMenuItem(value: '전체', child: Text('전체 강좌')),
                        ..._courses.map((c) => DropdownMenuItem(
                              value: c['id']!,
                              child: Text(c['name']!, overflow: TextOverflow.ellipsis),
                            )),
                      ],
                      onChanged: (val) {
                        if (val == null) return;
                        setState(() => _courseFilter = val);
                        _resetAndLoad();
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // 상태 필터 칩
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _statusFilters.map((f) {
              final bool isSelected = _statusFilter == f['value'];
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Semantics(
                  label: '${f['label']} 상태 필터 버튼입니다.',
                  selected: isSelected,
                  child: FilterChip(
                    label: Text(f['label']!),
                    selected: isSelected,
                    onSelected: (_) {
                      setState(() => _statusFilter = f['value']!);
                      _resetAndLoad();
                    },
                    selectedColor: _blue,
                    labelStyle: TextStyle(
                        color: isSelected ? Colors.white : const Color(0xFF1A1A2E),
                        fontWeight: FontWeight.w600,
                        fontSize: 13),
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFFE0E0E0)),
                    checkmarkColor: Colors.white,
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  // 회원 목록 카드를 구성합니다.
  Widget _buildMemberList() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          // 파란 카드 헤더
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: _blue,
              borderRadius: BorderRadius.only(topLeft: Radius.circular(14), topRight: Radius.circular(14)),
            ),
            child: Text('회원 목록 (${_members.length}명 표시)',
                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
          ),
          // 로딩 중
          if (_isLoading)
            const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
          // 결과 없음
          else if (_members.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Text('해당 조건의 회원이 없습니다.', style: TextStyle(color: Color(0xFF757575))),
            )
          // 회원 목록
          else
            Column(children: _members.map(_buildMemberTile).toList()),
        ],
      ),
    );
  }

  // 회원 한 명의 행 위젯입니다.
  // 학생(STUDENT)이면 수정/삭제 버튼을 숨깁니다. (Read-only)
  Widget _buildMemberTile(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final name      = data[FsUser.name]   ?? '이름 없음';
    final role      = data[FsUser.role]   ?? 'STUDENT';
    final status    = data[FsUser.status] ?? 'pending';
    final email     = data[FsUser.email]  ?? '';
    final isStudent = role == 'STUDENT';
    final statusColor = _statusColor(status);

    return Semantics(
      label: '$name, ${_roleKo(role)}, ${_statusKo(status)}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0)))),
        child: Row(
          children: [
            // 아바타
            CircleAvatar(
              radius: 18,
              backgroundColor: _blue.withValues(alpha: 0.12),
              child: Text(
                name.isNotEmpty ? name.substring(0, 1) : '?',
                style: const TextStyle(color: _blue, fontWeight: FontWeight.w700, fontSize: 14),
              ),
            ),
            const SizedBox(width: 12),
            // 이름 + 이메일
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                Text('${_roleKo(role)} · $email',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF757575)),
                    overflow: TextOverflow.ellipsis),
              ]),
            ),
            // 상태 배지
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
              child: Text(_statusKo(status),
                  style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.w700)),
            ),
            // 학생이 아닐 때(교사)만 수정/삭제 버튼 표시
            if (!isStudent) ...[
              const SizedBox(width: 4),
              Semantics(
                label: '$name 수정 버튼입니다.',
                child: IconButton(
                  icon: const Icon(Icons.edit_rounded, size: 18, color: _blue),
                  onPressed: () {
                    // TODO: 2단계 — 교사 정보 수정 다이얼로그 열기
                  },
                  tooltip: '수정',
                ),
              ),
              Semantics(
                label: '$name 삭제 버튼입니다.',
                child: IconButton(
                  icon: const Icon(Icons.delete_rounded, size: 18, color: Color(0xFFD32F2F)),
                  onPressed: () {
                    // TODO: 5단계 — 교사 삭제 방어 로직 (진행중 강좌/대기 학생 확인 후 소프트 삭제)
                  },
                  tooltip: '삭제',
                ),
              ),
            ],
            // 학생 대기 중이면 승인/거절 버튼 표시
            if (isStudent && status == 'pending') ...[
              const SizedBox(width: 4),
              Semantics(
                label: '$name 승인 버튼입니다.',
                child: TextButton(
                  onPressed: () async {
                    // Firestore users/{uid} status → 'approved' 업데이트
                    await FirebaseFirestore.instance
                        .collection(FsCol.users)
                        .doc(doc.id)
                        .update({FsUser.status: 'approved'});
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('승인 완료되었습니다.')));
                    }
                    _loadPage();
                  },
                  style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF00897B),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      minimumSize: Size.zero),
                  child: const Text('승인', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                ),
              ),
              Semantics(
                label: '$name 거절 버튼입니다.',
                child: TextButton(
                  onPressed: () async {
                    // Firestore users/{uid} status → 'rejected' 업데이트
                    await FirebaseFirestore.instance
                        .collection(FsCol.users)
                        .doc(doc.id)
                        .update({FsUser.status: 'rejected'});
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('거절 처리되었습니다.')));
                    }
                    _loadPage();
                  },
                  style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFD32F2F),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      minimumSize: Size.zero),
                  child: const Text('거절', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // 페이징 버튼 영역입니다.
  Widget _buildPagination() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 이전 페이지 버튼
        Semantics(
          label: '이전 페이지 버튼입니다.',
          child: IconButton(
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: _currentPage > 1 ? _prevPage : null,
            color: _blue,
          ),
        ),
        // 현재 페이지 번호
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(color: _blue, borderRadius: BorderRadius.circular(8)),
          child: Text('$_currentPage 페이지',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        ),
        // 다음 페이지 버튼
        Semantics(
          label: '다음 페이지 버튼입니다.',
          child: IconButton(
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: _hasMore ? _nextPage : null,
            color: _blue,
          ),
        ),
      ],
    );
  }

  String _statusKo(String s) {
    switch (s) {
      case 'pending':  return '승인 대기';
      case 'approved': return '승인 완료';
      case 'rejected': return '거절';
      default:         return s;
    }
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'pending':  return const Color(0xFFF57C00);
      case 'approved': return const Color(0xFF00897B);
      case 'rejected': return const Color(0xFFD32F2F);
      default:         return Colors.grey;
    }
  }

  String _roleKo(String r) {
    switch (r) {
      case 'SUPER_ADMIN': return '최고 관리자';
      case 'INSTRUCTOR':  return '교사';
      case 'STUDENT':     return '학생';
      default:            return r;
    }
  }
}
