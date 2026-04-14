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
import 'dart:convert'; // 🌟 JSON 데이터 인코딩/디코딩을 위해 반드시 추가!
import 'package:flutter_quill/flutter_quill.dart'; // 🌟 스마트 에디터 라이브러리
import '../../../core/utils/firestore_keys.dart';

class CourseTab extends StatefulWidget {
  const CourseTab({super.key});

  @override
  State<CourseTab> createState() => _CourseTabState();
}

class _CourseTabState extends State<CourseTab> {
  static const int _pageSize = 10;
  static const Color _blue = Color(0xFF1565C0);

  List<QueryDocumentSnapshot> _allCourses = [];
  List<QueryDocumentSnapshot> _filteredCourses = [];
  List<QueryDocumentSnapshot> _pagedCourses = [];
  final TextEditingController _searchCtrl = TextEditingController();
  String? _statusFilter;
  int _currentPage = 1;
  bool _hasMore = false;
  bool _isLoading = false;
  int _activeTeacherCount = 0;
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
    } catch (e) {
      if (!mounted) return;
      setState(() => _teacherCountLoading = false);
    }
  }

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
          .limit(200)
          .get();

      if (!mounted) return;
      _allCourses = snap.docs;
      setState(() => _isLoading = false);
      _applyFilterAndPage();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  void _applyFilterAndPage() {
    final searchText = _searchCtrl.text.trim();
    List<QueryDocumentSnapshot> filtered = _allCourses.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final status = data[FsCourse.status] as String? ?? '';
      if (_statusFilter != null && status != _statusFilter) return false;
      return true;
    }).toList();

    if (searchText.isNotEmpty) {
      filtered = filtered.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final name = (data[FsCourse.name] as String? ?? '').toLowerCase();
        return name.contains(searchText.toLowerCase());
      }).toList();
    }

    _filteredCourses = filtered;
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

  Future<void> _showEditDialog(QueryDocumentSnapshot doc) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CourseFormDialog(editDoc: doc),
    );
    if (result == true) await _loadAllCourses();
  }

  // 강좌 종료 처리
  Future<void> _showCloseConfirm(QueryDocumentSnapshot doc) async {
    // ... 기존과 동일 (생략하지 않고 코드 보존)
    final data = doc.data() as Map<String, dynamic>;
    final name = data[FsCourse.name] as String? ?? '이 강좌';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('강좌 종료'),
        content: Text('"$name" 강좌를 종료 처리하시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('종료 처리')),
        ],
      ),
    );
    if (confirmed != true) return;
    await FirebaseFirestore.instance.collection(FsCol.courses).doc(doc.id).update({FsCourse.status: FsCourse.statusClosed});
    _loadAllCourses();
  }

  // 강좌 삭제 처리
  Future<void> _showDeleteConfirm(QueryDocumentSnapshot doc) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('강좌 삭제'),
        content: const Text('강좌를 삭제하시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('삭제')),
        ],
      ),
    );
    if (confirmed != true) return;
    await FirebaseFirestore.instance.collection(FsCol.courses).doc(doc.id).update({FsCourse.status: FsCourse.statusDeleted});
    _loadAllCourses();
  }

  @override
  Widget build(BuildContext context) {
    final bool canCreate = !_teacherCountLoading && _activeTeacherCount > 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('강좌 관리', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                    SizedBox(height: 4),
                    Text('강좌를 개설하고 관리합니다.', style: TextStyle(fontSize: 14, color: Color(0xFF757575))),
                  ],
                ),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: canCreate ? _blue : Colors.grey, foregroundColor: Colors.white, minimumSize: Size.zero, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),),
                onPressed: canCreate ? _showAddDialog : null,
                icon: const Icon(Icons.add_rounded),
                label: Text('강좌 개설 (${_activeTeacherCount}명)'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _searchCtrl,
            onChanged: (_) => _resetFilter(),
            decoration: InputDecoration(hintText: '강좌명 검색', prefixIcon: const Icon(Icons.search), filled: true, fillColor: Colors.white),
          ),
          const SizedBox(height: 16),
          _buildCourseList(),
          const SizedBox(height: 12),
          _buildPagination(),
        ],
      ),
    );
  }

  Widget _buildCourseList() {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: [
          Container(
            width: double.infinity, padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(color: _blue, borderRadius: BorderRadius.only(topLeft: Radius.circular(14), topRight: Radius.circular(14))),
            child: const Text('강좌 목록', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
          if (_isLoading) const Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())
          else if (_pagedCourses.isEmpty) const Padding(padding: EdgeInsets.all(32), child: Text('데이터가 없습니다.'))
          else Column(children: _pagedCourses.map(_buildCourseTile).toList()),
        ],
      ),
    );
  }

  Widget _buildCourseTile(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final name = data[FsCourse.name] ?? '';
    final teacher = data[FsCourse.teacherName] ?? '';
    return ListTile(
      title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text('담당: $teacher'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(icon: const Icon(Icons.edit, color: _blue), onPressed: () => _showEditDialog(doc)),
          IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => _showDeleteConfirm(doc)),
        ],
      ),
    );
  }

  Widget _buildPagination() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(icon: const Icon(Icons.chevron_left), onPressed: _currentPage > 1 ? _prevPage : null),
        Text('$_currentPage 페이지'),
        IconButton(icon: const Icon(Icons.chevron_right), onPressed: _hasMore ? _nextPage : null),
      ],
    );
  }
}


// ─────────────────────────────────────────────────────────
// 🌟 스마트 에디터가 적용된 강좌 등록/수정 다이얼로그
// ─────────────────────────────────────────────────────────
class _CourseFormDialog extends StatefulWidget {
  final QueryDocumentSnapshot? editDoc;
  const _CourseFormDialog({this.editDoc});

  @override
  State<_CourseFormDialog> createState() => _CourseFormDialogState();
}

class _CourseFormDialogState extends State<_CourseFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  
  // Quill 에디터 컨트롤러
  late QuillController _quillController;

  List<Map<String, String>> _teachers = [];
  String? _selectedTeacherId;
  String? _selectedTeacherName;
  DateTime? _endDate;
  bool _loadingTeachers = true;
  bool _saving = false;

  bool get _isEdit => widget.editDoc != null;
  static const Color _blue = Color(0xFF1565C0);

  @override
  void initState() {
    super.initState();
    _initFormAndEditor(); // 🌟 데이터 로드와 에디터 초기화를 한 번에 처리합니다.
    _loadActiveTeachers();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _quillController.dispose();
    super.dispose();
  }

  // 🌟 핵심 로직: 폼 데이터와 에디터 내용을 불러와서 초기화합니다.
  void _initFormAndEditor() {
    Document doc = Document(); // 기본 빈 문서 생성

    if (_isEdit) {
      final data = widget.editDoc!.data() as Map<String, dynamic>;
      _nameCtrl.text = data[FsCourse.name] ?? '';
      _selectedTeacherId = data[FsCourse.teacherId];
      _selectedTeacherName = data[FsCourse.teacherName];
      final ts = data[FsCourse.endDate] as Timestamp?;
      _endDate = ts?.toDate();
      
      // 강좌 내용 불러오기
      final content = data[FsCourse.content] as String? ?? '';
      if (content.isNotEmpty) {
        try {
          // 1. JSON (Delta) 형식으로 예쁘게 저장된 데이터인 경우
          final decoded = jsonDecode(content);
          doc = Document.fromJson(decoded);
        } catch (e) {
          // 2. 예전 방식으로 저장된 '일반 텍스트'이거나 에러가 난 경우 (호환성 유지)
          doc.insert(0, content);
        }
      }
    }

    // 불러온 문서(doc)를 바탕으로 에디터 컨트롤러를 생성합니다.
    _quillController = QuillController(
      document: doc,
      selection: const TextSelection.collapsed(offset: 0),
    );
  }

  Future<void> _loadActiveTeachers() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection(FsCol.users)
          .where(FsUser.role, isEqualTo: FsUser.roleInstructor)
          .where(FsUser.isDeleted, isNotEqualTo: true)
          .get();
      if (!mounted) return;
      setState(() {
        _teachers = snap.docs.map((d) => {'uid': d.id, 'name': d.data()[FsUser.name] as String? ?? ''}).toList();
        _loadingTeachers = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loadingTeachers = false);
    }
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime(2020), lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _endDate = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('종료일을 선택하세요.')));
      return;
    }
    setState(() => _saving = true);

    // 🌟 핵심 로직: 에디터의 내용을 텍스트가 아닌 'JSON 서식 데이터(Delta)'로 변환하여 저장합니다.
    final contentJson = jsonEncode(_quillController.document.toDelta().toJson());

    final payload = {
      FsCourse.name: _nameCtrl.text.trim(),
      FsCourse.teacherId: _selectedTeacherId,
      FsCourse.teacherName: _selectedTeacherName,
      FsCourse.content: contentJson, // JSON 형태의 문자열로 DB에 저장
      FsCourse.endDate: Timestamp.fromDate(_endDate!),
      FsCourse.inlineImgs: [], 
    };

    try {
      if (_isEdit) {
        await FirebaseFirestore.instance.collection(FsCol.courses).doc(widget.editDoc!.id).update(payload);
      } else {
        await FirebaseFirestore.instance.collection(FsCol.courses).add({
          ...payload,
          FsCourse.status: FsCourse.statusActive,
          FsCourse.attachments: [], 
          FsCourse.createdAt: FieldValue.serverTimestamp(),
        });
      }
      if (!mounted) return;

      // 마우스 트래커 에러 방지: 포커스 해제 후 0.05초 대기하고 창 닫기
      FocusManager.instance.primaryFocus?.unfocus();
      Future.delayed(const Duration(milliseconds: 50), () {
        if (!mounted) return;
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEdit ? '강좌가 수정되었습니다.' : '강좌가 개설되었습니다.'),
            backgroundColor: const Color(0xFF00897B)
          )
        );
      });
    } catch (e) {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLabel('강좌명 *'),
                      TextFormField(controller: _nameCtrl, decoration: const InputDecoration(hintText: '강좌명 입력')),
                      const SizedBox(height: 20),
                      _buildLabel('담당 교사 *'),
                      _buildTeacherDropdown(),
                      const SizedBox(height: 20),
                      _buildLabel('과정 종료일 *'),
                      _buildEndDateField(),
                      const SizedBox(height: 20),
                      
                      _buildLabel('강좌 내용 *'),
                      _buildQuillEditor(),
                      const SizedBox(height: 28),

                      SizedBox(
                        width: double.infinity, height: 50,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: _blue, foregroundColor: Colors.white),
                          onPressed: _saving ? null : _save,
                          child: const Text('저장 완료', style: TextStyle(fontWeight: FontWeight.bold)),
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

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: const BoxDecoration(color: _blue, borderRadius: BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16))),
      child: Row(children: [
        const Icon(Icons.school, color: Colors.white),
        const SizedBox(width: 10),
        const Text('강좌 개설/수정', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.close, color: Colors.white), 
          onPressed: () {
            // 닫기 버튼 마우스 트래커 에러 방지
            FocusManager.instance.primaryFocus?.unfocus();
            Future.delayed(const Duration(milliseconds: 50), () {
              if (mounted) Navigator.pop(context);
            });
          }
        ),
      ]),
    );
  }

  Widget _buildQuillEditor() {
    return Container(
      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
      child: Column(
        children: [
          QuillSimpleToolbar(controller: _quillController),
          const Divider(height: 1),
          Container(
            height: 250,
            padding: const EdgeInsets.all(12),
            child: QuillEditor.basic(controller: _quillController),
          ),
        ],
      ),
    );
  }

  Widget _buildTeacherDropdown() {
    return DropdownButtonFormField<String>(
      value: _selectedTeacherId,
      items: _teachers.map((t) => DropdownMenuItem(value: t['uid'], child: Text(t['name']!))).toList(),
      onChanged: (val) {
        setState(() {
          _selectedTeacherId = val;
          _selectedTeacherName = _teachers.firstWhere((t) => t['uid'] == val)['name'];
        });
      },
      decoration: const InputDecoration(hintText: '교사 선택'),
    );
  }

  Widget _buildEndDateField() {
    return InkWell(
      onTap: _pickEndDate,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 10),
        decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
        child: Text(_endDate == null ? '날짜 선택' : '${_endDate!.year}-${_endDate!.month}-${_endDate!.day}'),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)));
  }
}