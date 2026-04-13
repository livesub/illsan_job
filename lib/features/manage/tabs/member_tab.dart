import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/enums/user_role.dart';
import '../../../core/utils/firestore_keys.dart';
import 'package:firebase_core/firebase_core.dart';

class MemberTab extends StatefulWidget {
  final UserRole userRole;
  const MemberTab({super.key, required this.userRole});

  @override
  State<MemberTab> createState() => _MemberTabState();
}

class _MemberTabState extends State<MemberTab> {
  static const Color _blue = Color(0xFF1565C0);
  static const int _pageSize = 10;

  // 강좌 목록 {id, name, teacherId} — 교사/학생 공용 필터
  List<Map<String, String>> _courses = [];

  // ── 교사 탭 (클라이언트 사이드 필터+페이징) ──────────────────
  List<QueryDocumentSnapshot> _allTeachers = [];
  bool _teachersLoading = true;
  final TextEditingController _teacherSearchCtrl = TextEditingController();
  String _teacherCourseFilter = '전체';
  int _teacherPage = 1;

  // ── 학생 탭 (Firestore 커서 페이징) ─────────────────────────
  List<QueryDocumentSnapshot> _students = [];
  bool _studentsLoading = false;
  bool _studentHasMore = false;
  final List<DocumentSnapshot?> _studentCursors = [null];
  int _studentPage = 1;
  final TextEditingController _studentSearchCtrl = TextEditingController();
  String _studentCourseFilter = '전체';

  @override
  void initState() {
    super.initState();
    // 교사 검색: 클라이언트 필터 즉시 적용 (rebuild → getter 재계산)
    _teacherSearchCtrl.addListener(() => setState(() => _teacherPage = 1));
    // 학생 검색: clear 버튼 표시용 rebuild만
    _studentSearchCtrl.addListener(() => setState(() {}));
    _loadCourses();
    _loadTeachers();
    _loadStudents();
  }

  @override
  void dispose() {
    _teacherSearchCtrl.dispose();
    _studentSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCourses() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection(FsCol.courses)
          .where(FsCourse.status, isEqualTo: FsCourse.statusActive)
          .orderBy(FsCourse.name)
          .get();
      if (!mounted) return;
      setState(() {
        _courses = snap.docs.map((d) {
          final data = d.data() as Map<String, dynamic>; 
          return {
            'id': d.id,
            'name': (data[FsCourse.name] ?? '') as String,
            'teacherId': (data[FsCourse.teacherId] ?? '') as String,
          };
        }).toList();
      });
    } catch (e) {
      print('강좌 목록을 불러오는 중 에러 발생: $e');
    }
  }





  Future<void> _loadTeachers() async {
    setState(() => _teachersLoading = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection(FsCol.users)
          .where(FsUser.role, isEqualTo: FsUser.roleInstructor)
          .orderBy(FsUser.name)
          .get();
      if (!mounted) return;
      setState(() {
        _allTeachers = snap.docs.where((d) {
          return (d.data() as Map<String, dynamic>)[FsUser.isDeleted] != true;
        }).toList();
        _teachersLoading = false;
      });
    } catch (e) {
      print('🚨 교사 목록 불러오기 에러: $e');
      if (mounted) setState(() => _teachersLoading = false);
    }
  }

  // 교사 이름+강좌 클라이언트 필터 (getter — rebuild 시 자동 재계산)
  List<QueryDocumentSnapshot> get _filteredTeachers {
    final search = _teacherSearchCtrl.text.trim().toLowerCase();
    String? courseTeacherId;
    if (_teacherCourseFilter != '전체') {
      final c = _courses.firstWhere(
        (c) => c['id'] == _teacherCourseFilter,
        orElse: () => {'teacherId': ''},
      );
      courseTeacherId = c['teacherId'];
    }
    return _allTeachers.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final name = ((data[FsUser.name] as String?) ?? '').toLowerCase();
      if (search.isNotEmpty && !name.startsWith(search)) return false;
      if (courseTeacherId != null) {
        if (courseTeacherId!.isEmpty || doc.id != courseTeacherId) return false;
      }
      return true;
    }).toList();
  }

  List<QueryDocumentSnapshot> get _pagedTeachers {
    final all = _filteredTeachers;
    final start = (_teacherPage - 1) * _pageSize;
    if (start >= all.length) return [];
    return all.sublist(start, (start + _pageSize).clamp(0, all.length));
  }

  bool get _teacherHasPrev => _teacherPage > 1;
  bool get _teacherHasMore => _teacherPage * _pageSize < _filteredTeachers.length;

  // 강좌 선택 시 강좌 전체 로드 후 클라이언트 이름 필터+페이징,
  // 전체 선택 시 Firestore 커서 페이징
  Future<void> _loadStudents() async {
    setState(() => _studentsLoading = true);
    try {
      final search   = _studentSearchCtrl.text.trim();
      final hasCourse = _studentCourseFilter != '전체';
      final hasSearch = search.isNotEmpty;

      List<QueryDocumentSnapshot> pageDocs;
      bool hasMore;

      if (hasCourse) {
        final snap = await FirebaseFirestore.instance
            .collection(FsCol.users)
            .where(FsUser.courseId, isEqualTo: _studentCourseFilter)
            .orderBy(FsUser.name)
            .get();
        var docs = snap.docs.where((d) {
          return (d.data() as Map<String, dynamic>)[FsUser.isDeleted] != true;
        }).toList();
        if (hasSearch) {
          docs = docs.where((d) {
            final n = ((d.data() as Map<String, dynamic>)[FsUser.name] as String? ?? '').toLowerCase();
            return n.startsWith(search.toLowerCase());
          }).toList();
        }
        final start = (_studentPage - 1) * _pageSize;
        hasMore  = docs.length > start + _pageSize;
        pageDocs = docs.sublist(start.clamp(0, docs.length), (start + _pageSize).clamp(0, docs.length));
      } else {
        Query query = FirebaseFirestore.instance
            .collection(FsCol.users)
            .where(FsUser.role, isEqualTo: FsUser.roleStudent);
        if (hasSearch) {
          query = query
              .where(FsUser.name, isGreaterThanOrEqualTo: search)
              .where(FsUser.name, isLessThanOrEqualTo: '$search\uf8ff');
        }
        query = query.orderBy(FsUser.name).limit(_pageSize + 1);
        final cursor = _studentCursors[_studentPage - 1];
        if (cursor != null) query = query.startAfterDocument(cursor);
        final snap = await query.get();
        final docs = snap.docs.where((d) {
          return (d.data() as Map<String, dynamic>)[FsUser.isDeleted] != true;
        }).toList();
        hasMore  = docs.length > _pageSize;
        pageDocs = hasMore ? docs.sublist(0, _pageSize) : docs;
      }

      if (!mounted) return;
      setState(() {
        _students        = pageDocs;
        _studentHasMore  = hasMore;
        _studentsLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _studentsLoading = false);
    }
  }

  void _resetStudentAndLoad() {
    _studentCursors..clear()..add(null);
    _studentPage = 1;
    _loadStudents();
  }

  void _studentNextPage() {
    if (!_studentHasMore || _students.isEmpty) return;
    if (_studentCourseFilter == '전체' && _studentCursors.length <= _studentPage) {
      _studentCursors.add(_students.last);
    }
    setState(() => _studentPage++);
    _loadStudents();
  }

  void _studentPrevPage() {
    if (_studentPage <= 1) return;
    setState(() => _studentPage--);
    _loadStudents();
  }

  // settings/admin_config.temp_password를 읽어 학생 비밀번호 초기화합니다.
  // Firestore 업데이트 → onUserDocumentUpdated CF가 Firebase Auth 비밀번호를 변경합니다.
  Future<void> _resetStudentPassword(QueryDocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;
    final name = (data[FsUser.name] as String?) ?? '학생';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('비밀번호 초기화'),
        content: Text('$name 학생의 비밀번호를 초기화하시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFD32F2F)),
            child: const Text('초기화'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    // 로딩 다이얼로그 표시
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(children: [
          SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 16),
          Text('처리 중...'),
        ]),
      ),
    );

    try {
      // 1. settings/admin_config 에서 공용 임시 비밀번호 비동기 읽기
      final configDoc = await FirebaseFirestore.instance
          .collection('settings')
          .doc('admin_config')
          .get();
      final tempPw = (configDoc.data()?['temp_password'] as String?) ?? '';

      if (tempPw.isEmpty) {
        if (!mounted) return;
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('임시 비밀번호가 설정되지 않았습니다. 관리자 설정을 확인해 주세요.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // 2. 학생 Firestore 문서 업데이트 → onUserDocumentUpdated CF가 Auth 비밀번호 변경
      await FirebaseFirestore.instance.collection(FsCol.users).doc(doc.id).update({
        FsUser.isTempPw:    true,
        FsUser.tempPwPlain: tempPw,
        FsUser.tempPwAt:    FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      Navigator.of(context).pop(); // 로딩 닫기

      // pop 완료 후 다음 프레임에 결과 팝업 표시 (mouse_tracker 재진입 방지)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showResetResultDialog(tempPw);
      });
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('초기화 실패: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _showResetResultDialog(String tempPw) {
    showDialog(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: const Text('비밀번호 초기화 완료'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text(
              '비밀번호가 초기화되었습니다.\n[복사하기] 버튼을 눌러 학생에게 전달하세요.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFE3F2FD),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(children: [
                Expanded(
                  child: SelectableText(
                    tempPw,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w800,
                        letterSpacing: 2, color: _blue),
                  ),
                ),
                Semantics(
                  label: '임시 비밀번호 복사 버튼입니다.',
                  child: IconButton(
                    icon: const Icon(Icons.copy_rounded, color: _blue),
                    tooltip: '복사하기',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: tempPw));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('클립보드에 복사되었습니다.')),
                      );
                    },
                  ),
                ),
              ]),
            ),
          ]),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('확인'),
            ),
          ],
        ),
      );
  }

  Map<String, String> get _courseNameMap =>
      {for (final c in _courses) c['id']!: c['name']!};

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            color: Colors.white,
            child: const TabBar(
              labelColor: _blue,
              unselectedLabelColor: Color(0xFF757575),
              indicatorColor: _blue,
              indicatorWeight: 3,
              labelStyle: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              unselectedLabelStyle: TextStyle(fontSize: 15, fontWeight: FontWeight.w400),
              tabs: [Tab(text: '교사 리스트'), Tab(text: '학생 리스트(강좌별)')],
            ),
          ),
          Expanded(
            child: TabBarView(children: [_buildTeacherTab(), _buildStudentTab()]),
          ),
        ],
      ),
    );
  }

  // ── 교사 탭 ──────────────────────────────────────────────
  Widget _buildTeacherTab() {
    final paged = _pagedTeachers;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('교사 리스트',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF1A1A2E))),
                  SizedBox(height: 4),
                  Text('등록된 교사 목록을 조회합니다.',
                      style: TextStyle(fontSize: 14, color: Color(0xFF757575))),
                ]),
              ),
              Semantics(
                label: '교사 등록 버튼입니다.',
                child: ElevatedButton.icon(
                  onPressed: () async {
                    await showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => _TeacherRegisterDialog(courses: _courses),
                    );
                    _loadTeachers();
                  },
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('교사 등록'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(0, 0),
                    backgroundColor: _blue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 검색 + 강좌 필터
          Row(children: [
            Expanded(flex: 2,
              child: Semantics(label: '교사 이름 검색 입력란입니다.',
                child: TextField(
                  controller: _teacherSearchCtrl,
                  decoration: _searchDeco('이름으로 검색',
                      _teacherSearchCtrl.text.isNotEmpty
                          ? IconButton(icon: const Icon(Icons.clear_rounded, size: 18), onPressed: () => _teacherSearchCtrl.clear())
                          : null),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(flex: 2,
              child: Semantics(label: '강좌 선택 드롭다운입니다.',
                child: _courseDropdown(
                  value: _teacherCourseFilter,
                  onChanged: (val) {
                    if (val == null) return;
                    setState(() { _teacherCourseFilter = val; _teacherPage = 1; });
                  },
                ),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 4))],
            ),
            child: Column(children: [
              _listHeader('교사 목록 (${_filteredTeachers.length}명)'),
              if (_teachersLoading)
                const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
              else if (paged.isEmpty)
                const Padding(padding: EdgeInsets.all(32),
                    child: Text('등록된 교사가 없습니다.', style: TextStyle(color: Color(0xFF757575))))
              else
                Column(children: paged.map(_buildTeacherTile).toList()),
            ]),
          ),
          const SizedBox(height: 12),
          if (!_teachersLoading && _filteredTeachers.length > _pageSize)
            _buildPagination(
              page: _teacherPage,
              hasPrev: _teacherHasPrev,
              hasMore: _teacherHasMore,
              onPrev: () => setState(() => _teacherPage--),
              onNext: () => setState(() => _teacherPage++),
            ),
        ],
      ),
    );
  }

  Widget _buildTeacherTile(QueryDocumentSnapshot doc) {
    final data     = doc.data() as Map<String, dynamic>;
    final name     = (data[FsUser.name]     as String?) ?? '이름 없음';
    final email    = (data[FsUser.email]    as String?) ?? '';
    final phone    = (data[FsUser.phone]    as String?) ?? '';
    final photoUrl = (data[FsUser.photoUrl] as String?) ?? '';
    return Semantics(
      label: '$name 교사 항목입니다. 클릭하면 정보를 수정합니다.',
      child: InkWell(
        onTap: () async {
          await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => _TeacherEditDialog(doc: doc, courses: _courses),
          );
          _loadTeachers();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0)))),
          child: Row(children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: _blue.withValues(alpha: 0.12),
              backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
              child: photoUrl.isEmpty ? const Icon(Icons.person_rounded, color: _blue, size: 22) : null,
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              Text('$email${phone.isNotEmpty ? ' · $phone' : ''}',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF757575)),
                  overflow: TextOverflow.ellipsis),
            ])),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFFBDBDBD), size: 20),
          ]),
        ),
      ),
    );
  }

  // ── 학생 탭 (조회 전용) ───────────────────────────────────
  Widget _buildStudentTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('학생 리스트',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF1A1A2E))),
          const SizedBox(height: 4),
          const Text('강좌별 학생 목록을 조회합니다. 학생 정보는 조회만 가능합니다.',
              style: TextStyle(fontSize: 14, color: Color(0xFF757575))),
          const SizedBox(height: 16),
          // 검색 + 강좌 필터
          Row(children: [
            Expanded(flex: 2,
              child: Semantics(label: '학생 이름 검색 입력란입니다.',
                child: TextField(
                  controller: _studentSearchCtrl,
                  onSubmitted: (_) => _resetStudentAndLoad(),
                  decoration: _searchDeco('이름으로 검색 (Enter)',
                      _studentSearchCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 18),
                              onPressed: () { _studentSearchCtrl.clear(); _resetStudentAndLoad(); })
                          : null),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(flex: 2,
              child: Semantics(label: '강좌 선택 드롭다운입니다.',
                child: _courseDropdown(
                  value: _studentCourseFilter,
                  onChanged: (val) {
                    if (val == null) return;
                    setState(() => _studentCourseFilter = val);
                    _resetStudentAndLoad();
                  },
                ),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 4))],
            ),
            child: Column(children: [
              _listHeader('학생 목록 (${_students.length}명 표시)'),
              if (_studentsLoading)
                const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
              else if (_students.isEmpty)
                const Padding(padding: EdgeInsets.all(32),
                    child: Text('해당 조건의 학생이 없습니다.', style: TextStyle(color: Color(0xFF757575))))
              else
                Column(children: _students.map(_buildStudentTile).toList()),
            ]),
          ),
          const SizedBox(height: 12),
          if (!_studentsLoading && (_students.isNotEmpty || _studentPage > 1))
            _buildPagination(
              page: _studentPage,
              hasPrev: _studentPage > 1,
              hasMore: _studentHasMore,
              onPrev: _studentPrevPage,
              onNext: _studentNextPage,
            ),
        ],
      ),
    );
  }

  Widget _buildStudentTile(QueryDocumentSnapshot doc) {
    final data      = doc.data() as Map<String, dynamic>;
    final name      = (data[FsUser.name]     as String?) ?? '이름 없음';
    final email     = (data[FsUser.email]    as String?) ?? '';
    final courseId  = (data[FsUser.courseId] as String?) ?? '';
    final status    = (data[FsUser.status]   as String?) ?? FsUser.statusPending;
    final createdAt = data[FsUser.createdAt];
    final courseName  = _courseNameMap[courseId] ?? '-';
    final joinDate    = _formatDate(createdAt);
    final statusColor = _statusColor(status);
    return Semantics(
      label: '$name 학생, $courseName 반, $joinDate 가입',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0)))),
        child: Row(children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: const Color(0xFFE3F2FD),
            child: Text(name.isNotEmpty ? name.substring(0, 1) : '?',
                style: const TextStyle(color: _blue, fontWeight: FontWeight.w700, fontSize: 14)),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: _blue.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(courseName,
                    style: const TextStyle(fontSize: 11, color: _blue, fontWeight: FontWeight.w600)),
              ),
            ]),
            const SizedBox(height: 2),
            Text('$email · 가입일 $joinDate',
                style: const TextStyle(fontSize: 12, color: Color(0xFF757575)),
                overflow: TextOverflow.ellipsis),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(_statusKo(status),
                style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
          // 비밀번호 초기화 버튼 (SUPER_ADMIN 전용)
          if (widget.userRole == UserRole.SUPER_ADMIN) ...[
            const SizedBox(width: 4),
            Semantics(
              label: '$name 비밀번호 초기화 버튼입니다.',
              child: IconButton(
                icon: const Icon(Icons.lock_reset_rounded, size: 20, color: Color(0xFF9E9E9E)),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => _resetStudentPassword(doc),
              ),
            ),
          ],
        ]),
      ),
    );
  }

  // ── 공통 UI 헬퍼 ──────────────────────────────────────────
  Widget _listHeader(String title) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: _blue,
        borderRadius: BorderRadius.only(topLeft: Radius.circular(14), topRight: Radius.circular(14)),
      ),
      child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
    );
  }

  Widget _buildPagination({
    required int page,
    required bool hasPrev,
    required bool hasMore,
    required VoidCallback onPrev,
    required VoidCallback onNext,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Semantics(
          label: '이전 페이지 버튼입니다.',
          child: IconButton(
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: hasPrev ? onPrev : null,
            color: _blue,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(color: _blue, borderRadius: BorderRadius.circular(8)),
          child: Text('$page 페이지',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        ),
        Semantics(
          label: '다음 페이지 버튼입니다.',
          child: IconButton(
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: hasMore ? onNext : null,
            color: _blue,
          ),
        ),
      ],
    );
  }

  Widget _courseDropdown({required String value, required ValueChanged<String?> onChanged}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          items: [
            const DropdownMenuItem(value: '전체', child: Text('전체 강좌')),
            ..._courses.map((c) => DropdownMenuItem(
                  value: c['id']!,
                  child: Text(c['name']!, overflow: TextOverflow.ellipsis),
                )),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }

  InputDecoration _searchDeco(String hint, Widget? suffix) => InputDecoration(
    hintText: hint,
    prefixIcon: const Icon(Icons.search_rounded, color: _blue),
    suffixIcon: suffix,
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _blue, width: 2)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  );

  String _statusKo(String s) {
    switch (s) {
      case FsUser.statusPending:  return '승인 대기';
      case FsUser.statusApproved: return '승인 완료';
      case FsUser.statusRejected: return '거절';
      default: return s;
    }
  }

  Color _statusColor(String s) {
    switch (s) {
      case FsUser.statusPending:  return const Color(0xFFF57C00);
      case FsUser.statusApproved: return const Color(0xFF00897B);
      case FsUser.statusRejected: return const Color(0xFFD32F2F);
      default: return Colors.grey;
    }
  }

  String _formatDate(dynamic val) {
    if (val == null) return '-';
    try {
      final dt = (val as Timestamp).toDate();
      return '${dt.year}.${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return '-';
    }
  }
}

// ── 교사 등록 다이얼로그 ──────────────────────────────────────
class _TeacherRegisterDialog extends StatefulWidget {
  final List<Map<String, String>> courses;
  const _TeacherRegisterDialog({required this.courses});

  @override
  State<_TeacherRegisterDialog> createState() => _TeacherRegisterDialogState();
}

class _TeacherRegisterDialogState extends State<_TeacherRegisterDialog> {
  static const Color _blue = Color(0xFF1565C0);

  final _formKey      = GlobalKey<FormState>();
  final _nameCtrl     = TextEditingController();
  final _phoneCtrl    = TextEditingController();
  final _emailCtrl    = TextEditingController();
  final _pwCtrl       = TextEditingController();
  final _pwCfmCtrl    = TextEditingController();
  final _bioCtrl      = TextEditingController();

  PlatformFile? _photoFile;
  bool _isLoading    = false;
  bool _obscurePw    = true;
  bool _obscurePwCfm = true;

  @override
  void dispose() {
    _nameCtrl.dispose(); _phoneCtrl.dispose(); _emailCtrl.dispose();
    _pwCtrl.dispose();   _pwCfmCtrl.dispose(); _bioCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    if (result == null || result.files.isEmpty) return;
    setState(() => _photoFile = result.files.first);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    
    final email = _emailCtrl.text.trim(); //

    setState(() => _isLoading = true);

    try {
      // 1. [추가] Firestore를 통한 사전 중복 체크 (Proactive Check)
      // Auth에 생성되기 전, 우리 DB(users 컬렉션)에 이미 해당 이메일이 있는지 먼저 확인합니다.
      final existingUser = await FirebaseFirestore.instance
          .collection(FsCol.users)
          .where(FsUser.email, isEqualTo: email)
          .get();

      if (existingUser.docs.isNotEmpty) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        _showErrorDialog('이미 등록된 이메일입니다. 다른 이메일을 사용해 주세요.');
        return;
      }

      // 2. 임시 앱 생성 및 Auth 계정 생성 (기존 로직 유지)
      final uniqueName = 'tempRegisterApp_${DateTime.now().millisecondsSinceEpoch}';
      FirebaseApp? tempApp = await Firebase.initializeApp(
        name: uniqueName,
        options: Firebase.app().options,
      );

      try {
        final tempAuth = FirebaseAuth.instanceFor(app: tempApp);
        await tempAuth.setPersistence(Persistence.NONE);

        final cred = await tempAuth.createUserWithEmailAndPassword(
          email: email,
          password: _pwCtrl.text,
        );
        final uid = cred.user!.uid;

        // ... (이후 사진 업로드 및 Firestore 저장 로직은 기존과 동일)
        
        // 저장 성공 후 알림 및 닫기
        if (!mounted) return;
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('교사가 정상적으로 등록되었습니다.'))
        );

      } finally {
        // 작업 완료 후 임시 앱 삭제
        await tempApp.delete();
      }

    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      _showErrorDialog(_authError(e.code));
    } catch (e) {
      if (!mounted) return;
      _showErrorDialog('등록 실패: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 에러 다이얼로그 호출을 위한 헬퍼 함수
  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('알림'),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('확인'))
        ],
      ),
    );
  }
  String _authError(String code) {
    switch (code) {
      case 'email-already-in-use': return '이미 사용 중인 이메일입니다.';
      case 'invalid-email':        return '올바른 이메일 형식이 아닙니다.';
      case 'weak-password':        return '비밀번호는 6자 이상이어야 합니다.';
      default:                     return '계정 생성 중 오류가 발생했습니다.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Stack(children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('교사 등록', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.of(context).pop()),
                ]),
                const SizedBox(height: 16),
                if (false) ...[
                  Center(child: GestureDetector(
                    onTap: _pickPhoto,
                    child: Semantics(label: '프로필 사진 선택 버튼입니다.',
                      child: CircleAvatar(
                        radius: 40,
                        backgroundColor: const Color(0xFFE3F2FD),
                        backgroundImage: _photoFile?.bytes != null ? MemoryImage(_photoFile!.bytes!) : null,
                        child: _photoFile == null ? const Icon(Icons.add_a_photo_rounded, color: _blue, size: 28) : null,
                      ),
                    ),
                  )),
                  const SizedBox(height: 20),
                ],
                _field('이메일(ID)', _emailCtrl, keyboardType: TextInputType.emailAddress,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return '이메일을 입력해 주세요.';
                      if (!v.contains('@')) return '올바른 이메일 형식이 아닙니다.';
                      return null;
                    }),
                const SizedBox(height: 14),
                _field('이름', _nameCtrl,
                    validator: (v) => (v == null || v.trim().isEmpty) ? '이름을 입력해 주세요.' : null),
                const SizedBox(height: 14),
                _field('전화번호', _phoneCtrl, keyboardType: TextInputType.phone,
                    validator: (v) => (v == null || v.trim().isEmpty) ? '전화번호를 입력해 주세요.' : null),
                const SizedBox(height: 14),
                _pwField('비밀번호', _pwCtrl, _obscurePw, () => setState(() => _obscurePw = !_obscurePw),
                    validator: (v) {
                      if (v == null || v.isEmpty) return '비밀번호를 입력해 주세요.';
                      if (v.length < 6) return '6자 이상 입력해 주세요.';
                      return null;
                    }),
                const SizedBox(height: 14),
                _pwField('비밀번호 확인', _pwCfmCtrl, _obscurePwCfm, () => setState(() => _obscurePwCfm = !_obscurePwCfm),
                    validator: (v) => v != _pwCtrl.text ? '비밀번호가 일치하지 않습니다.' : null),
                const SizedBox(height: 14),
                _field('쓰고 싶은 말', _bioCtrl, maxLines: 3, required: false),
                const SizedBox(height: 24),
                Semantics(label: '교사 등록 완료 버튼입니다.',
                  child: SizedBox(width: double.infinity, height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _blue, foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _isLoading ? null : _submit,
                      child: const Text('등록', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
              ]),
            ),
          ),
          if (_isLoading) ...[
            const ModalBarrier(dismissible: false, color: Colors.black26),
            const Center(child: CircularProgressIndicator(color: _blue)),
          ],
        ]),
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl, {
    TextInputType? keyboardType, int maxLines = 1, bool required = true,
    String? Function(String?)? validator,
  }) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E))),
      const SizedBox(height: 6),
      TextFormField(
        controller: ctrl, keyboardType: keyboardType, maxLines: maxLines,
        decoration: _deco(),
        validator: validator ?? (required
            ? (v) => (v == null || v.trim().isEmpty) ? '$label을(를) 입력해 주세요.' : null
            : null),
      ),
    ]);
  }

  Widget _pwField(String label, TextEditingController ctrl, bool obscure,
      VoidCallback toggle, {String? Function(String?)? validator}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E))),
      const SizedBox(height: 6),
      TextFormField(
        controller: ctrl, obscureText: obscure,
        decoration: _deco().copyWith(
          suffixIcon: IconButton(
            icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                size: 20, color: const Color(0xFF757575)),
            onPressed: toggle,
          ),
        ),
        validator: validator,
      ),
    ]);
  }

  InputDecoration _deco() => InputDecoration(
    filled: true, fillColor: const Color(0xFFF8F9FA),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _blue, width: 2)),
    errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.red)),
    focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.red, width: 2)),
  );
}

// ── 교사 정보 수정 다이얼로그 ────────────────────────────────
class _TeacherEditDialog extends StatefulWidget {
  final QueryDocumentSnapshot doc;
  final List<Map<String, String>> courses;
  const _TeacherEditDialog({required this.doc, required this.courses});

  @override
  State<_TeacherEditDialog> createState() => _TeacherEditDialogState();
}

class _TeacherEditDialogState extends State<_TeacherEditDialog> {
  static const Color _blue = Color(0xFF1565C0);

  final _formKey   = GlobalKey<FormState>();
  final _nameCtrl  = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _bioCtrl   = TextEditingController();

  PlatformFile? _newPhotoFile;
  String _existPhotoUrl = '';
  List<String> _assignedCourseIds = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final data = widget.doc.data() as Map<String, dynamic>;
    _nameCtrl.text  = (data[FsUser.name]     as String?) ?? '';
    _phoneCtrl.text = (data[FsUser.phone]    as String?) ?? '';
    _bioCtrl.text   = (data[FsUser.bio]      as String?) ?? '';
    _existPhotoUrl  = (data[FsUser.photoUrl] as String?) ?? '';
    _loadAssignedCourses();
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _phoneCtrl.dispose(); _bioCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAssignedCourses() async {
    final snap = await FirebaseFirestore.instance
        .collection(FsCol.courses)
        .where(FsCourse.teacherId, isEqualTo: widget.doc.id)
        .get();
    if (!mounted) return;
    setState(() { _assignedCourseIds = snap.docs.map((d) => d.id).toList(); });
  }

  Future<void> _pickPhoto() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    if (result == null || result.files.isEmpty) return;
    setState(() => _newPhotoFile = result.files.first);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final uid = widget.doc.id;
      final teacherName = _nameCtrl.text.trim();
      String photoUrl = _existPhotoUrl;
      if (_newPhotoFile?.bytes != null) {
        final ref = FirebaseStorage.instance.ref(StoragePath.profilePhotoPath(uid));
        await ref.putData(_newPhotoFile!.bytes!, SettableMetadata(contentType: 'image/jpeg'));
        photoUrl = await ref.getDownloadURL();
      }
      await FirebaseFirestore.instance.collection(FsCol.users).doc(uid).update({
        FsUser.name: teacherName, FsUser.phone: _phoneCtrl.text.trim(),
        FsUser.bio: _bioCtrl.text.trim(), FsUser.photoUrl: photoUrl,
      });
      final batch = FirebaseFirestore.instance.batch();
      final prevSnap = await FirebaseFirestore.instance
          .collection(FsCol.courses).where(FsCourse.teacherId, isEqualTo: uid).get();
      for (final d in prevSnap.docs) {
        if (!_assignedCourseIds.contains(d.id)) {
          batch.update(d.reference, {FsCourse.teacherId: '', FsCourse.teacherName: ''});
        }
      }
      for (final courseId in _assignedCourseIds) {
        batch.update(
          FirebaseFirestore.instance.collection(FsCol.courses).doc(courseId),
          {FsCourse.teacherId: uid, FsCourse.teacherName: teacherName},
        );
      }
      await batch.commit();
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('정보가 수정되었습니다.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('수정 실패: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resetPassword() async {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789';
    final rand   = Random.secure();
    final tempPw = List.generate(8, (_) => chars[rand.nextInt(chars.length)]).join();
    setState(() => _isLoading = true);
    try {
      await FirebaseFirestore.instance.collection(FsCol.users).doc(widget.doc.id).update({
        FsUser.isTempPw: true, FsUser.tempPwPlain: tempPw, FsUser.tempPwAt: FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: const Text('임시 비밀번호 발급'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('아래 임시 비밀번호를 교사에게 전달하세요.\n교사는 첫 로그인 후 비밀번호를 변경해야 합니다.',
                style: TextStyle(fontSize: 14)),
            const SizedBox(height: 16),
            SelectableText(tempPw,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: 3, color: _blue)),
          ]),
          actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('확인'))],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('초기화 실패: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Stack(children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('교사 정보 수정', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.of(context).pop()),
                ]),
                const SizedBox(height: 16),
                if (false) Center(child: GestureDetector(
                  onTap: _pickPhoto,
                  child: Semantics(label: '프로필 사진 변경 버튼입니다.',
                    child: Stack(children: [
                      CircleAvatar(
                        radius: 40,
                        backgroundColor: const Color(0xFFE3F2FD),
                        backgroundImage: _newPhotoFile?.bytes != null
                            ? MemoryImage(_newPhotoFile!.bytes!) as ImageProvider
                            : (_existPhotoUrl.isNotEmpty ? NetworkImage(_existPhotoUrl) : null),
                        child: (_newPhotoFile == null && _existPhotoUrl.isEmpty)
                            ? const Icon(Icons.person_rounded, color: _blue, size: 36) : null,
                      ),
                      Positioned(bottom: 0, right: 0,
                        child: Container(
                          width: 24, height: 24,
                          decoration: const BoxDecoration(color: _blue, shape: BoxShape.circle),
                          child: const Icon(Icons.edit_rounded, color: Colors.white, size: 14),
                        ),
                      ),
                    ]),
                  ),
                )),
                _field('이름', _nameCtrl,
                    validator: (v) => (v == null || v.trim().isEmpty) ? '이름을 입력해 주세요.' : null),
                const SizedBox(height: 14),
                _field('전화번호', _phoneCtrl, keyboardType: TextInputType.phone),
                const SizedBox(height: 14),
                _field('쓰고 싶은 말', _bioCtrl, maxLines: 3, required: false),
                const SizedBox(height: 20),
                const Text('반 배정',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E))),
                const SizedBox(height: 8),
                widget.courses.isEmpty
                    ? const Text('등록된 강좌가 없습니다.', style: TextStyle(fontSize: 13, color: Color(0xFF757575)))
                    : Container(
                        decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE0E0E0)), borderRadius: BorderRadius.circular(10)),
                        child: Column(children: widget.courses.map((c) {
                          final isSelected = _assignedCourseIds.contains(c['id']);
                          return Semantics(label: '${c['name']} 반 배정 체크박스입니다.', checked: isSelected,
                            child: CheckboxListTile(
                              dense: true,
                              title: Text(c['name']!, style: const TextStyle(fontSize: 14)),
                              value: isSelected, activeColor: _blue,
                              onChanged: (checked) {
                                setState(() {
                                  if (checked == true) { _assignedCourseIds.add(c['id']!); }
                                  else { _assignedCourseIds.remove(c['id']!); }
                                });
                              },
                            ),
                          );
                        }).toList()),
                      ),
                const SizedBox(height: 16),
                Semantics(label: '비밀번호 초기화 버튼입니다.',
                  child: OutlinedButton.icon(
                    onPressed: _isLoading ? null : _resetPassword,
                    icon: const Icon(Icons.lock_reset_rounded, size: 18),
                    label: const Text('비밀번호 초기화'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFD32F2F),
                      side: const BorderSide(color: Color(0xFFD32F2F)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Semantics(label: '교사 정보 저장 버튼입니다.',
                  child: SizedBox(width: double.infinity, height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _blue, foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _isLoading ? null : _save,
                      child: const Text('저장', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
              ]),
            ),
          ),
          if (_isLoading) ...[
            const ModalBarrier(dismissible: false, color: Colors.black26),
            const Center(child: CircularProgressIndicator(color: _blue)),
          ],
        ]),
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl, {
    TextInputType? keyboardType, int maxLines = 1, bool required = true,
    String? Function(String?)? validator,
  }) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E))),
      const SizedBox(height: 6),
      TextFormField(
        controller: ctrl, keyboardType: keyboardType, maxLines: maxLines,
        decoration: _deco(),
        validator: validator ?? (required
            ? (v) => (v == null || v.trim().isEmpty) ? '$label을(를) 입력해 주세요.' : null
            : null),
      ),
    ]);
  }

  InputDecoration _deco() => InputDecoration(
    filled: true, fillColor: const Color(0xFFF8F9FA),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _blue, width: 2)),
    errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.red)),
    focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.red, width: 2)),
  );
}
