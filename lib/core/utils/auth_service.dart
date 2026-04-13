import 'package:cloud_firestore/cloud_firestore.dart';
import '../enums/user_role.dart';
import 'firestore_keys.dart';
import 'user_model.dart';

// 앱 전역에서 현재 로그인한 사용자 정보와 권한을 즉시 조회하는 싱글톤 서비스.
// 로그인 직후 loadUser()를 호출해 캐시하고, 로그아웃 시 clear()로 초기화합니다.
//
// 사용 예시:
//   await AuthService.instance.loadUser(uid);   // 로그인 직후
//   AuthService.instance.canManageMembers();    // 권한 체크
//   AuthService.instance.currentUser?.name;     // 사용자 정보 접근
//   AuthService.instance.clear();               // 로그아웃 시
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  UserModel? _user;

  // 현재 로그인한 UserModel. 미로그인 상태이면 null.
  UserModel? get currentUser => _user;

  // 현재 역할. 미로그인이면 STUDENT 반환 (최소 권한 원칙).
  UserRole get currentRole => _user?.role ?? UserRole.STUDENT;

  String get currentUid   => _user?.uid  ?? '';
  bool   get isSignedIn   => _user != null;
  bool   get isSuperAdmin => _user?.role == UserRole.SUPER_ADMIN;
  bool   get isInstructor => _user?.role == UserRole.INSTRUCTOR;

  // Firestore에서 사용자 문서를 읽어 내부 캐시에 저장합니다.
  // RouteGuard 또는 로그인 완료 시점에 반드시 호출해야 합니다.
  Future<UserModel?> loadUser(String uid) async {
    final doc = await FirebaseFirestore.instance
        .collection(FsCol.users)
        .doc(uid)
        .get();
    final data = doc.data();
    if (data == null) { _user = null; return null; }
    _user = UserModel.fromMap(uid, data);
    return _user;
  }

  // 이미 로드된 UserModel을 외부에서 직접 주입할 때 사용합니다.
  void setUser(UserModel user) => _user = user;

  // 로그아웃 시 캐시를 비웁니다.
  void clear() => _user = null;

  // ── 권한 체크 메서드 ─────────────────────────────────────
  // 각 기능별 접근 가능 여부를 반환합니다.

  // 회원(교사·학생) 목록 관리 — SUPER_ADMIN 전용
  bool canManageMembers() => _user?.role == UserRole.SUPER_ADMIN;

  // 강좌 개설·수정·삭제 — SUPER_ADMIN 전용
  bool canManageCourses() => _user?.role == UserRole.SUPER_ADMIN;

  // 공지사항 등록·수정 — SUPER_ADMIN, INSTRUCTOR
  bool canPostNotice() =>
      _user?.role == UserRole.SUPER_ADMIN ||
      _user?.role == UserRole.INSTRUCTOR;

  // 구직 공고 등록·관리 — SUPER_ADMIN, INSTRUCTOR
  bool canManageJobs() =>
      _user?.role == UserRole.SUPER_ADMIN ||
      _user?.role == UserRole.INSTRUCTOR;

  // 콘텐츠 수정: SUPER_ADMIN이거나 본인 작성 글인 경우 허용
  bool canEditContent(String authorId) =>
      _user?.role == UserRole.SUPER_ADMIN || _user?.uid == authorId;

  // 관리자 대시보드 진입 — SUPER_ADMIN, INSTRUCTOR (STUDENT 차단)
  bool hasAdminAccess() =>
      _user?.role == UserRole.SUPER_ADMIN ||
      _user?.role == UserRole.INSTRUCTOR;
}
