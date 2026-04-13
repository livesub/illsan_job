// 강좌 관리 탭입니다. (SUPER_ADMIN 전용)
//
// 기능:
//   - 강좌 목록 Firestore 연동 (이름 검색 + 상태 필터 + 페이징)
//   - 강좌 개설 (활성 교사 1명 이상일 때만 버튼 활성화)
//   - 강좌 수정 (강좌명 / 담당교사 / 종료일 / 내용)
//   - 수동 종료 (active → closed 상태 변경)
//   - 강좌 삭제 (status = 'deleted' 처리)
//   - 등록 시각 yymmddHis 자동 생성
//
// 데이터 로드 전략:
//   - 삭제되지 않은 강좌 전체를 Firestore에서 로드 (최대 200개)
//   - 이름 검색 + 상태 필터는 클라이언트에서 처리
//   - 페이징은 필터링된 결과에서 클라이언트로 처리
//   → Firestore 복합 인덱스 생성 부담 없이 관리자 도구에 적합
//
// [7단계 완료] 강좌 내용 영역: 서식 툴바(B/I/U) + 인라인 이미지 업로드 스마트 에디터

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/utils/firestore_keys.dart';

// ─────────────────────────────────────────────────────────
// 강좌 관리 탭 — 목록 + 검색 + 상태 필터 + 등록/수정/삭제
// ─────────────────────────────────────────────────────────
class CourseTab extends StatefulWidget {
  const CourseTab({super.key});

  @override
  State<CourseTab> createState() => _CourseTabState();
}

class _CourseTabState extends State<CourseTab> {
  // 한 페이지에 표시할 강좌 수
  static const int _pageSize = 10;
  // 파란색 포인트 컬러
  static const Color _blue = Color(0xFF1565C0);

  // Firestore에서 로드한 전체 비삭제 강좌 목록
  List<QueryDocumentSnapshot> _allCourses = [];

  // 검색/필터 적용 후 화면에 표시할 강좌 목록
  List<QueryDocumentSnapshot> _filteredCourses = [];

  // 현재 페이지에서 보여줄 강좌 (페이징 적용)
  List<QueryDocumentSnapshot> _pagedCourses = [];

  // 이름 검색 컨트롤러
  final TextEditingController _searchCtrl = TextEditingController();

  // 현재 선택된 상태 필터
  // null: 전체 / 'active': 진행 중 / 'closed': 종료
  String? _statusFilter;

  // 현재 페이지 번호 (1부터 시작)
  int _currentPage = 1;

  // 다음 페이지 존재 여부
  bool _hasMore = false;

  // 전체 강좌 로딩 중 여부
  bool _isLoading = false;

  // 활성 교사 수 (0명이면 개설 버튼 비활성화)
  int _activeTeacherCount = 0;

  // 활성 교사 수 로딩 중 여부
  bool _teacherCountLoading = true;

  @override
  void initState() {
    super.initState();
    _loadActiveTeacherCount();
    _loadAllCourses();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // 활성 교사 수를 Firestore에서 가져옵니다.
  Future<void> _loadActiveTeacherCount() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection(FsCol.users)
          .where(FsUser.role, isEqualTo: FsUser.roleInstructor)
          .where(FsUser.isDeleted, isNotEqualTo: true)
          .get();
      if (!mounted) return;
      setState(() {
        _activeTeacherCount = snap.docs.length;
        _teacherCountLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _teacherCountLoading = false);
    }
  }

  // 삭제되지 않은 강좌 전체를 Firestore에서 로드합니다.
  // 이후 검색/필터/페이징은 클라이언트에서 처리합니다.
  Future<void> _loadAllCourses() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      final snap = await FirebaseFirestore.instance
          .collection(FsCol.courses)
          .where(FsCourse.status, whereIn: [
            FsCourse.statusActive,
            FsCourse.statusClosed,
          ])
          .orderBy(FsCourse.createdAt, descending: true)
          .limit(200) // 관리자 도구 특성상 200개 이상은 거의 없습니다
          .get();

      if (!mounted) return;
      _allCourses = snap.docs;
      setState(() => _isLoading = false);
      _applyFilterAndPage();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('강좌 목록 불러오기 실패: $e'), backgroundColor: Colors.red),
      );
    }
  }

  // 이름 검색 + 상태 필터를 적용하고 현재 페이지 목록을 갱신합니다.
  void _applyFilterAndPage() {
    final searchText = _searchCtrl.text.trim();

    // 1. 상태 필터 적용
    List<QueryDocumentSnapshot> filtered = _allCourses.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final status = data[FsCourse.status] as String? ?? '';
      if (_statusFilter != null && status != _statusFilter) return false;
      return true;
    }).toList();

    // 2. 이름 검색 적용 (포함 검색)
    if (searchText.isNotEmpty) {
      filtered = filtered.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final name = (data[FsCourse.name] as String? ?? '').toLowerCase();
        return name.contains(searchText.toLowerCase());
      }).toList();
    }

    _filteredCourses = filtered;

    // 3. 페이징 적용
    final start = (_currentPage - 1) * _pageSize;
    final end = start + _pageSize;
    setState(() {
      _pagedCourses = filtered.sublist(
        start.clamp(0, filtered.length),
        end.clamp(0, filtered.length),
      );
      _hasMore = end < filtered.length;
    });
  }

  // 검색어 또는 필터 변경 시 1페이지부터 다시 적용합니다.
  void _resetFilter() {
    _currentPage = 1;
    _applyFilterAndPage();
  }

  void _nextPage() {
    if (!_hasMore) return;
    _currentPage++;
    _applyFilterAndPage();
  }

  void _prevPage() {
    if (_currentPage <= 1) return;
    _currentPage--;
    _applyFilterAndPage();
  }

  // 강좌 개설 다이얼로그를 엽니다.
  Future<void> _showAddDialog() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _CourseFormDialog(),
    );
    if (result == true) {
      _loadActiveTeacherCount();
      await _loadAllCourses();
    }
  }

  // 강좌 수정 다이얼로그를 엽니다.
  Future<void> _showEditDialog(QueryDocumentSnapshot doc) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CourseFormDialog(editDoc: doc),
    );
    if (result == true) await _loadAllCourses();
  }

  // 강좌 수동 종료 확인 다이얼로그를 표시합니다.
  // 확인 시 status를 'closed'로 변경합니다.
  Future<void> _showCloseConfirm(QueryDocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;
    final name = data[FsCourse.name] as String? ?? '이 강좌';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 24),
            SizedBox(width: 8),
            Text('강좌 종료', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          ],
        ),
        content: Text(
          '"$name" 강좌를 종료 처리하시겠습니까?\n\n'
          '종료 후에는 학생들이 해당 강좌에 신규 가입할 수 없습니다.\n'
          '종료된 강좌는 목록에는 유지되며 언제든 확인할 수 있습니다.',
          style: const TextStyle(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('종료 처리', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      // status를 'closed'로 업데이트합니다.
      await FirebaseFirestore.instance
          .collection(FsCol.courses)
          .doc(doc.id)
          .update({FsCourse.status: FsCourse.statusClosed});

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"$name" 강좌가 종료되었습니다.'),
          backgroundColor: Colors.orange,
        ),
      );
      await _loadAllCourses();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('종료 처리 실패: $e'), backgroundColor: Colors.red),
      );
    }
  }

  // 강좌 삭제 확인 다이얼로그를 표시합니다.
  // 확인 시 status를 'deleted'로 변경합니다. (Soft Delete)
  Future<void> _showDeleteConfirm(QueryDocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;
    final name = data[FsCourse.name] as String? ?? '이 강좌';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(
          children: [
            Icon(Icons.delete_rounded, color: Color(0xFFD32F2F), size: 24),
            SizedBox(width: 8),
            Text('강좌 삭제', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          ],
        ),
        content: Text(
          '"$name" 강좌를 삭제하시겠습니까?\n\n'
          '삭제된 강좌는 목록에서 완전히 숨겨집니다.\n'
          '소속 학생 데이터는 유지되므로 별도로 확인해 주세요.',
          style: const TextStyle(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD32F2F),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      // status를 'deleted'로 설정합니다. (물리적 삭제 없이 목록에서만 숨깁니다)
      // ⚠️ 7단계: 강좌에 첨부된 파일이 있으면 Storage Hard Delete가 추가됩니다.
      await FirebaseFirestore.instance
          .collection(FsCol.courses)
          .doc(doc.id)
          .update({FsCourse.status: FsCourse.statusDeleted});

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"$name" 강좌가 삭제되었습니다.'),
          backgroundColor: Colors.red,
        ),
      );
      await _loadAllCourses();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('삭제 실패: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool canCreate = !_teacherCountLoading && _activeTeacherCount > 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 페이지 제목 + 강좌 개설 버튼 ────────────────
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '강좌 관리',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '강좌를 개설하고 관리합니다.',
                      style: TextStyle(fontSize: 14, color: Color(0xFF757575)),
                    ),
                  ],
                ),
              ),
              Semantics(
                label: canCreate
                    ? '강좌 개설 버튼입니다.'
                    : '강좌 개설 버튼입니다. 활성 교사가 없어 비활성화되어 있습니다.',
                child: Tooltip(
                  message: canCreate ? '' : '활성 교사가 없습니다. 먼저 교사를 등록해 주세요.',
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: canCreate ? _blue : Colors.grey.shade400,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      minimumSize: Size.zero,
                    ),
                    onPressed: canCreate ? _showAddDialog : null,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: Text(
                      _teacherCountLoading
                          ? '확인 중...'
                          : canCreate
                              ? '강좌 개설 (교사 $_activeTeacherCount명)'
                              : '강좌 개설 불가',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── 검색 필드 ────────────────────────────────────
          Semantics(
            label: '강좌명 검색 입력란입니다.',
            child: TextField(
              controller: _searchCtrl,
              onChanged: (_) => _resetFilter(),
              decoration: InputDecoration(
                hintText: '강좌명으로 검색',
                prefixIcon: const Icon(Icons.search_rounded, color: _blue),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          _resetFilter();
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _blue, width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── 상태 필터 버튼 ───────────────────────────────
          _buildStatusFilterRow(),
          const SizedBox(height: 16),

          // ── 강좌 목록 카드 ───────────────────────────────
          _buildCourseList(),
          const SizedBox(height: 12),
          _buildPagination(),
        ],
      ),
    );
  }

  // 상태 필터 버튼 행 (전체 / 진행 중 / 종료)
  Widget _buildStatusFilterRow() {
    // 각 필터별 강좌 수를 계산합니다.
    final totalCount  = _allCourses.length;
    final activeCount = _allCourses.where((d) {
      final data = d.data() as Map<String, dynamic>;
      return data[FsCourse.status] == FsCourse.statusActive;
    }).length;
    final closedCount = _allCourses.where((d) {
      final data = d.data() as Map<String, dynamic>;
      return data[FsCourse.status] == FsCourse.statusClosed;
    }).length;

    return Wrap(
      spacing: 8,
      children: [
        _filterChip(label: '전체 ($totalCount)', value: null),
        _filterChip(label: '진행 중 ($activeCount)', value: FsCourse.statusActive),
        _filterChip(label: '종료 ($closedCount)', value: FsCourse.statusClosed),
      ],
    );
  }

  // 개별 필터 칩 버튼을 만듭니다.
  Widget _filterChip({required String label, required String? value}) {
    final bool isSelected = _statusFilter == value;
    return Semantics(
      label: '$label 필터 버튼입니다. ${isSelected ? "현재 선택됨" : ""}',
      child: FilterChip(
        label: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
            color: isSelected ? Colors.white : const Color(0xFF424242),
          ),
        ),
        selected: isSelected,
        selectedColor: _blue,
        backgroundColor: Colors.white,
        checkmarkColor: Colors.white,
        side: BorderSide(color: isSelected ? _blue : const Color(0xFFE0E0E0)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        onSelected: (_) {
          setState(() => _statusFilter = value);
          _resetFilter();
        },
      ),
    );
  }

  // 강좌 목록 카드 컨테이너
  Widget _buildCourseList() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // 카드 헤더
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: _blue,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(14),
                topRight: Radius.circular(14),
              ),
            ),
            child: Text(
              '강좌 목록 (검색 결과 ${_filteredCourses.length}개 / 전체 ${_allCourses.length}개)',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_pagedCourses.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Text('해당하는 강좌가 없습니다.', style: TextStyle(color: Color(0xFF757575))),
            )
          else
            Column(children: _pagedCourses.map(_buildCourseTile).toList()),
        ],
      ),
    );
  }

  // 개별 강좌 행 타일
  Widget _buildCourseTile(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final name        = data[FsCourse.name]        as String? ?? '이름 없음';
    final teacherName = data[FsCourse.teacherName] as String? ?? '-';
    final status      = data[FsCourse.status]      as String? ?? FsCourse.statusActive;
    final endDate     = (data[FsCourse.endDate]    as Timestamp?)?.toDate();

    final endDateStr = endDate != null
        ? '${endDate.year}.${endDate.month.toString().padLeft(2, '0')}.${endDate.day.toString().padLeft(2, '0')} 종료'
        : '종료일 미설정';

    // 진행 중인 강좌만 수동 종료 버튼을 표시합니다.
    final bool isActive = status == FsCourse.statusActive;

    return Semantics(
      label: '강좌 $name, 담당교사: $teacherName, 상태: ${_statusLabel(status)}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0))),
        ),
        child: Row(
          children: [
            // 강좌 아이콘
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.school_rounded, color: _blue, size: 20),
            ),
            const SizedBox(width: 12),
            // 강좌명 + 교사 / 종료일
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  Text(
                    '담당: $teacherName · $endDateStr',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF757575)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            // 상태 뱃지
            _buildStatusBadge(status),
            const SizedBox(width: 4),
            // 수동 종료 버튼 — 진행 중인 강좌에만 표시
            if (isActive)
              Semantics(
                label: '$name 강좌 수동 종료 버튼입니다.',
                child: Tooltip(
                  message: '강좌 종료 처리',
                  child: IconButton(
                    icon: const Icon(Icons.stop_circle_rounded, size: 20, color: Colors.orange),
                    onPressed: () => _showCloseConfirm(doc),
                  ),
                ),
              ),
            // 수정 버튼
            Semantics(
              label: '$name 수정 버튼입니다.',
              child: IconButton(
                icon: const Icon(Icons.edit_rounded, size: 18, color: _blue),
                onPressed: () => _showEditDialog(doc),
                tooltip: '수정',
              ),
            ),
            // 삭제 버튼
            Semantics(
              label: '$name 삭제 버튼입니다.',
              child: IconButton(
                icon: const Icon(Icons.delete_rounded, size: 18, color: Color(0xFFD32F2F)),
                onPressed: () => _showDeleteConfirm(doc),
                tooltip: '삭제',
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 상태 뱃지 위젯
  Widget _buildStatusBadge(String status) {
    late Color bgColor;
    late Color textColor;

    switch (status) {
      case FsCourse.statusActive:
        bgColor   = const Color(0xFF00897B).withValues(alpha: 0.12);
        textColor = const Color(0xFF00897B);
      case FsCourse.statusClosed:
        bgColor   = Colors.grey.withValues(alpha: 0.15);
        textColor = Colors.grey.shade600;
      default:
        bgColor   = Colors.red.withValues(alpha: 0.1);
        textColor = Colors.red.shade700;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(20)),
      child: Text(
        _statusLabel(status),
        style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }

  // 상태값을 한글로 변환합니다.
  String _statusLabel(String status) {
    switch (status) {
      case FsCourse.statusActive: return '진행 중';
      case FsCourse.statusClosed: return '종료';
      default: return '삭제';
    }
  }

  // 하단 페이지 이동 버튼
  Widget _buildPagination() {
    if (_filteredCourses.isEmpty) return const SizedBox.shrink();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Semantics(
          label: '이전 페이지 버튼입니다.',
          child: IconButton(
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: _currentPage > 1 ? _prevPage : null,
            color: _blue,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(color: _blue, borderRadius: BorderRadius.circular(8)),
          child: Text(
            '$_currentPage / ${((_filteredCourses.length - 1) ~/ _pageSize) + 1} 페이지',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
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
}

// ─────────────────────────────────────────────────────────
// 강좌 등록/수정 다이얼로그 위젯
//
// editDoc이 null이면 신규 등록, 있으면 수정 모드로 동작합니다.
//
// 4개 필드:
//   1. 강좌명 (필수)
//   2. 담당 교사 선택 (필수, 활성 교사 Selectbox)
//   3. 과정 종료일 end_date (필수, DatePicker)
//   4. 강좌 내용 (필수, 기본 textarea — 7단계 스마트 에디터로 교체 예정)
// ─────────────────────────────────────────────────────────
class _CourseFormDialog extends StatefulWidget {
  // 수정 모드일 때 기존 문서를 받습니다. null이면 등록 모드입니다.
  final QueryDocumentSnapshot? editDoc;

  const _CourseFormDialog({this.editDoc});

  @override
  State<_CourseFormDialog> createState() => _CourseFormDialogState();
}

class _CourseFormDialogState extends State<_CourseFormDialog> {
  final _formKey    = GlobalKey<FormState>();
  final _nameCtrl   = TextEditingController();
  final _contentCtrl = TextEditingController();

  List<Map<String, String>> _teachers = [];
  String? _selectedTeacherId;
  String? _selectedTeacherName;
  DateTime? _endDate;
  bool _loadingTeachers = true;
  bool _saving = false;

  // 인라인 이미지 Storage 경로 목록 (Hard Delete 기준)
  final List<String> _inlineImgPaths = [];
  // 인라인 이미지 다운로드 URL 목록 (화면 표시용)
  final List<String> _inlineImgUrls  = [];
  bool _uploadingImg = false;

  // 수정 모드 여부를 나타냅니다.
  bool get _isEdit => widget.editDoc != null;

  static const Color _blue = Color(0xFF1565C0);

  @override
  void initState() {
    super.initState();
    _loadActiveTeachers();
    if (_isEdit) {
      _prefillForm();
      _loadInlineImages();
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  // 수정 모드: 기존 강좌 데이터를 각 필드에 미리 채웁니다.
  void _prefillForm() {
    final data = widget.editDoc!.data() as Map<String, dynamic>;
    _nameCtrl.text    = data[FsCourse.name]    as String? ?? '';
    _contentCtrl.text = data[FsCourse.content] as String? ?? '';
    _selectedTeacherId   = data[FsCourse.teacherId]   as String?;
    _selectedTeacherName = data[FsCourse.teacherName] as String?;
    final ts = data[FsCourse.endDate] as Timestamp?;
    _endDate = ts?.toDate();
  }

  // 수정 모드: 기존 인라인 이미지의 다운로드 URL을 Storage에서 로드합니다.
  Future<void> _loadInlineImages() async {
    final data = widget.editDoc!.data() as Map<String, dynamic>;
    final paths = (data[FsCourse.inlineImgs] as List?)?.cast<String>() ?? [];
    for (final path in paths) {
      try {
        final url = await FirebaseStorage.instance.ref(path).getDownloadURL();
        if (!mounted) return;
        setState(() {
          _inlineImgPaths.add(path);
          _inlineImgUrls.add(url);
        });
      } catch (_) {}
    }
  }

  // 이미지를 선택하고 Storage에 업로드한 뒤 목록에 추가합니다.
  Future<void> _pickAndUploadImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 80,
    );
    if (picked == null || !mounted) return;
    setState(() => _uploadingImg = true);
    try {
      final bytes = await picked.readAsBytes();
      final now = DateTime.now();
      final path =
          '${StoragePath.inlinePath(StoragePath.boardCourse, now.year, now.month)}'
          '${now.millisecondsSinceEpoch}_${picked.name}';
      final ref = FirebaseStorage.instance.ref(path);
      await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      final url = await ref.getDownloadURL();
      if (!mounted) return;
      setState(() {
        _inlineImgPaths.add(path);
        _inlineImgUrls.add(url);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('이미지 업로드 실패: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _uploadingImg = false);
    }
  }

  // 인라인 이미지를 Storage에서 Hard Delete하고 목록에서 제거합니다.
  Future<void> _removeImage(int index) async {
    final path = _inlineImgPaths[index];
    try {
      await FirebaseStorage.instance.ref(path).delete();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _inlineImgPaths.removeAt(index);
      _inlineImgUrls.removeAt(index);
    });
  }

  // 선택된 텍스트를 HTML 태그로 감쌉니다. (Bold/Italic/Underline)
  void _wrapSelection(String open, String close) {
    final sel = _contentCtrl.selection;
    if (!sel.isValid) return;
    final text = _contentCtrl.text;
    final before   = text.substring(0, sel.start);
    final selected = text.substring(sel.start, sel.end);
    final after    = text.substring(sel.end);
    _contentCtrl.value = TextEditingValue(
      text: '$before$open$selected$close$after',
      selection: TextSelection.collapsed(
          offset: sel.start + open.length + selected.length + close.length),
    );
  }

  // 활성 교사 목록을 Firestore에서 가져옵니다.
  Future<void> _loadActiveTeachers() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection(FsCol.users)
          .where(FsUser.role, isEqualTo: FsUser.roleInstructor)
          .where(FsUser.isDeleted, isNotEqualTo: true)
          .orderBy(FsUser.name)
          .get();

      if (!mounted) return;
      final teachers = snap.docs.map((doc) {
        final data = doc.data();
        return {'uid': doc.id, 'name': data[FsUser.name] as String? ?? '이름 없음'};
      }).toList();

      setState(() {
        _teachers = teachers;
        _loadingTeachers = false;
        // 수정 모드에서 기존 교사가 목록에 없으면 선택값 초기화
        if (_selectedTeacherId != null) {
          final exists = teachers.any((t) => t['uid'] == _selectedTeacherId);
          if (!exists) _selectedTeacherId = null;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingTeachers = false);
    }
  }

  // 달력으로 종료일을 선택합니다.
  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: '강좌 종료일 선택',
      cancelText: '취소',
      confirmText: '선택',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: _blue, onPrimary: Colors.white),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _endDate = picked);
  }

  // 강좌 저장 처리 (신규 등록 또는 수정)
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('과정 종료일을 선택해 주세요.'), backgroundColor: Colors.orange),
      );
      return;
    }
    setState(() => _saving = true);

    // 저장할 데이터 맵을 구성합니다.
    final payload = {
      FsCourse.name:        _nameCtrl.text.trim(),
      FsCourse.teacherId:   _selectedTeacherId,
      FsCourse.teacherName: _selectedTeacherName,
      FsCourse.content:     _contentCtrl.text.trim(),
      FsCourse.endDate:     Timestamp.fromDate(_endDate!),
      FsCourse.inlineImgs:  _inlineImgPaths,
    };

    try {
      if (_isEdit) {
        // 수정 모드: 기존 문서를 업데이트합니다.
        await FirebaseFirestore.instance
            .collection(FsCol.courses)
            .doc(widget.editDoc!.id)
            .update(payload);
      } else {
        // 신규 등록: 새 문서를 추가합니다.
        await FirebaseFirestore.instance.collection(FsCol.courses).add({
          ...payload,
          FsCourse.status:      FsCourse.statusActive,
          FsCourse.attachments: [],
          FsCourse.createdAt:   StoragePath.nowCreatedAt(),
        });
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isEdit ? '강좌가 수정되었습니다.' : '강좌가 개설되었습니다.'),
          backgroundColor: const Color(0xFF00897B),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('저장 실패: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 헤더
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              decoration: const BoxDecoration(
                color: _blue,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _isEdit ? Icons.edit_rounded : Icons.school_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _isEdit ? '강좌 수정' : '강좌 개설',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Semantics(
                    label: '다이얼로그 닫기 버튼입니다.',
                    child: IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white70),
                      onPressed: _saving ? null : () => Navigator.of(context).pop(false),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ),
                ],
              ),
            ),
            // 폼
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. 강좌명
                      _buildLabel('강좌명', required: true),
                      const SizedBox(height: 6),
                      Semantics(
                        label: '강좌명 입력란입니다. 필수 항목입니다.',
                        child: TextFormField(
                          controller: _nameCtrl,
                          decoration: _inputDeco('예) 플러터 기초반 2기'),
                          validator: (v) => (v == null || v.trim().isEmpty) ? '강좌명을 입력해 주세요.' : null,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // 2. 담당 교사 선택
                      _buildLabel('담당 교사', required: true),
                      const SizedBox(height: 6),
                      _buildTeacherDropdown(),
                      const SizedBox(height: 20),

                      // 3. 과정 종료일
                      _buildLabel('과정 종료일', required: true),
                      const SizedBox(height: 6),
                      _buildEndDateField(),
                      const SizedBox(height: 20),

                      // 4. 강좌 내용 — 스마트 에디터 (7단계)
                      _buildLabel('강좌 내용', required: true),
                      const SizedBox(height: 6),
                      _buildSmartEditor(),
                      const SizedBox(height: 28),

                      // 저장 버튼
                      Semantics(
                        label: '${_isEdit ? "수정" : "개설"} 완료 버튼입니다.',
                        child: SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _blue,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              minimumSize: Size.zero,
                            ),
                            onPressed: _saving ? null : _save,
                            child: _saving
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                                  )
                                : Text(
                                    _isEdit ? '수정 완료' : '개설 완료',
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 담당 교사 Selectbox
  Widget _buildTeacherDropdown() {
    if (_loadingTeachers) {
      return Container(
        height: 50,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFE0E0E0)),
          borderRadius: BorderRadius.circular(10),
          color: Colors.white,
        ),
        child: const Row(children: [
          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 10),
          Text('교사 목록 불러오는 중...', style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 13)),
        ]),
      );
    }
    if (_teachers.isEmpty) {
      return Container(
        height: 50,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.red.shade200),
          borderRadius: BorderRadius.circular(10),
          color: Colors.red.shade50,
        ),
        child: const Text('활성 교사가 없습니다.', style: TextStyle(color: Colors.red, fontSize: 13)),
      );
    }
    return Semantics(
      label: '담당 교사 선택 드롭다운입니다. 필수 항목입니다.',
      child: DropdownButtonFormField<String>(
        // ignore: deprecated_member_use
        value: _selectedTeacherId,
        isExpanded: true,
        decoration: _inputDeco('교사를 선택해 주세요.'),
        items: _teachers.map((t) => DropdownMenuItem<String>(
          value: t['uid'],
          child: Text(t['name']!, style: const TextStyle(fontSize: 14)),
        )).toList(),
        onChanged: (uid) => setState(() {
          _selectedTeacherId   = uid;
          _selectedTeacherName = _teachers.firstWhere((t) => t['uid'] == uid)['name'];
        }),
        validator: (v) => v == null ? '담당 교사를 선택해 주세요.' : null,
      ),
    );
  }

  // 종료일 선택 필드
  Widget _buildEndDateField() {
    final dateStr = _endDate != null
        ? '${_endDate!.year}년 ${_endDate!.month}월 ${_endDate!.day}일'
        : '날짜를 선택해 주세요.';

    return Semantics(
      label: '과정 종료일 선택 버튼입니다. 현재: ${_endDate != null ? dateStr : "미선택"}',
      child: GestureDetector(
        onTap: _pickEndDate,
        child: Container(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xFFE0E0E0)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(Icons.calendar_month_rounded,
                  color: _endDate != null ? _blue : Colors.grey, size: 20),
              const SizedBox(width: 10),
              Text(
                dateStr,
                style: TextStyle(
                  fontSize: 14,
                  color: _endDate != null ? const Color(0xFF1A1A2E) : const Color(0xFFBDBDBD),
                ),
              ),
              const Spacer(),
              if (_endDate != null)
                GestureDetector(
                  onTap: () => setState(() => _endDate = null),
                  child: const Icon(Icons.clear_rounded, size: 18, color: Colors.grey),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // 서식 툴바 + 내용 입력 + 미리보기 섹션
  Widget _buildSmartEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 서식 툴바
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F5F5),
            border: Border.all(color: const Color(0xFFE0E0E0)),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(10),
              topRight: Radius.circular(10),
            ),
          ),
          child: Row(children: [
            Semantics(
              label: '굵게 서식 버튼입니다.',
              child: IconButton(
                icon: const Icon(Icons.format_bold_rounded, size: 20),
                onPressed: () => _wrapSelection('<b>', '</b>'),
                tooltip: '굵게',
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                padding: EdgeInsets.zero,
              ),
            ),
            Semantics(
              label: '기울임 서식 버튼입니다.',
              child: IconButton(
                icon: const Icon(Icons.format_italic_rounded, size: 20),
                onPressed: () => _wrapSelection('<i>', '</i>'),
                tooltip: '기울임',
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                padding: EdgeInsets.zero,
              ),
            ),
            Semantics(
              label: '밑줄 서식 버튼입니다.',
              child: IconButton(
                icon: const Icon(Icons.format_underline_rounded, size: 20),
                onPressed: () => _wrapSelection('<u>', '</u>'),
                tooltip: '밑줄',
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                padding: EdgeInsets.zero,
              ),
            ),
            if (false) ...[
              const VerticalDivider(width: 16, thickness: 1, color: Color(0xFFE0E0E0)),
              Semantics(
                label: '이미지 추가 버튼입니다.',
                child: _uploadingImg
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : IconButton(
                        icon: const Icon(Icons.image_rounded, size: 20, color: _blue),
                        onPressed: _pickAndUploadImage,
                        tooltip: '이미지 추가',
                        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                        padding: EdgeInsets.zero,
                      ),
              ),
            ],
          ]),
        ),
        // 내용 입력 영역
        Semantics(
          label: '강좌 내용 입력란입니다. 필수 항목입니다.',
          child: TextFormField(
            controller: _contentCtrl,
            maxLines: 8,
            decoration: InputDecoration(
              hintText: '강좌 소개, 커리큘럼 등을 자유롭게 입력하세요.\n서식 버튼으로 굵게·기울임·밑줄을 적용할 수 있습니다.',
              hintStyle: const TextStyle(color: Color(0xFFBDBDBD), fontSize: 13),
              filled: true,
              fillColor: Colors.white,
              border: const OutlineInputBorder(
                borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(10),
                    bottomRight: Radius.circular(10)),
                borderSide: BorderSide(color: Color(0xFFE0E0E0)),
              ),
              enabledBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(10),
                    bottomRight: Radius.circular(10)),
                borderSide: BorderSide(color: Color(0xFFE0E0E0)),
              ),
              focusedBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(10),
                    bottomRight: Radius.circular(10)),
                borderSide: BorderSide(color: _blue, width: 2),
              ),
              errorBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(10),
                    bottomRight: Radius.circular(10)),
                borderSide: BorderSide(color: Colors.red),
              ),
              contentPadding: const EdgeInsets.all(14),
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? '강좌 내용을 입력해 주세요.' : null,
          ),
        ),
        // 미리보기 영역
        const SizedBox(height: 12),
        Row(children: const [
          Icon(Icons.preview_rounded, size: 14, color: Color(0xFF757575)),
          SizedBox(width: 4),
          Text('미리보기',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF757575))),
        ]),
        const SizedBox(height: 4),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _contentCtrl,
          builder: (_, val, __) => _buildPreviewBox(val.text),
        ),
        // 인라인 이미지 목록 숨김
        if (false) ...[
          if (_inlineImgPaths.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('첨부 이미지',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF424242))),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(_inlineImgPaths.length, (i) {
                return Stack(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      _inlineImgUrls[i],
                      width: 80,
                      height: 80,
                      fit: BoxFit.cover,
                      loadingBuilder: (_, child, progress) => progress == null
                          ? child
                          : const SizedBox(
                              width: 80,
                              height: 80,
                              child: Center(
                                  child: CircularProgressIndicator(strokeWidth: 2))),
                      errorBuilder: (_, __, ___) => const SizedBox(
                          width: 80,
                          height: 80,
                          child: Icon(Icons.broken_image_rounded, color: Colors.grey)),
                    ),
                  ),
                  Positioned(
                    top: 2,
                    right: 2,
                    child: Semantics(
                      label: '이미지 삭제 버튼입니다.',
                      child: GestureDetector(
                        onTap: () => _removeImage(i),
                        child: Container(
                          decoration: const BoxDecoration(
                              color: Colors.red, shape: BoxShape.circle),
                          padding: const EdgeInsets.all(2),
                          child: const Icon(Icons.close_rounded,
                              size: 14, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ]);
              }),
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildPreviewBox(String text) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 60),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE0E0E0)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: text.trim().isEmpty
          ? const Text('내용을 입력하면 미리보기가 표시됩니다.',
              style: TextStyle(color: Color(0xFFBDBDBD), fontSize: 13))
          : RichText(
              text: TextSpan(
                style: const TextStyle(
                    color: Color(0xFF1A1A2E), fontSize: 14, height: 1.6),
                children: _parseHtmlSpans(text),
              ),
            ),
    );
  }

  // `<b>`, `<i>`, `<u>`, `<font color>` 태그를 파싱해 InlineSpan 목록으로 변환
  List<InlineSpan> _parseHtmlSpans(String html) {
    final spans = <InlineSpan>[];
    final tagRe = RegExp(r'<(/?)(\w+)([^>]*)>', caseSensitive: false);
    int boldDepth = 0, italicDepth = 0, underlineDepth = 0;
    final colorStack = <Color?>[];

    void addText(String text) {
      if (text.isEmpty) return;
      spans.add(TextSpan(
        text: text,
        style: TextStyle(
          fontWeight: boldDepth > 0 ? FontWeight.bold : FontWeight.normal,
          fontStyle: italicDepth > 0 ? FontStyle.italic : FontStyle.normal,
          decoration:
              underlineDepth > 0 ? TextDecoration.underline : TextDecoration.none,
          color: colorStack.isNotEmpty ? colorStack.last : null,
        ),
      ));
    }

    int pos = 0;
    for (final m in tagRe.allMatches(html)) {
      addText(html.substring(pos, m.start));
      pos = m.end;
      final closing = m.group(1) == '/';
      final tag = m.group(2)!.toLowerCase();
      final attrs = m.group(3) ?? '';
      if (!closing) {
        switch (tag) {
          case 'b':
            boldDepth++;
          case 'i':
            italicDepth++;
          case 'u':
            underlineDepth++;
          case 'font':
            final cm =
                RegExp(r'color="([^"]+)"', caseSensitive: false).firstMatch(attrs);
            if (cm != null) {
              final hex = cm.group(1)!.replaceAll('#', '');
              try {
                colorStack.add(Color(int.parse('FF$hex', radix: 16)));
              } catch (_) {
                colorStack.add(null);
              }
            } else {
              colorStack.add(null);
            }
        }
      } else {
        switch (tag) {
          case 'b':
            if (boldDepth > 0) boldDepth--;
          case 'i':
            if (italicDepth > 0) italicDepth--;
          case 'u':
            if (underlineDepth > 0) underlineDepth--;
          case 'font':
            if (colorStack.isNotEmpty) colorStack.removeLast();
        }
      }
    }
    addText(html.substring(pos));
    return spans;
  }

  Widget _buildLabel(String text, {bool required = false}) {
    return RichText(
      text: TextSpan(
        text: text,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF424242)),
        children: required
            ? const [TextSpan(text: ' *', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w700))]
            : [],
      ),
    );
  }

  InputDecoration _inputDeco(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFFBDBDBD), fontSize: 13),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _blue, width: 2)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.red)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }
}
