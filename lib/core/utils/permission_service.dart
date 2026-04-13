import '../enums/user_role.dart';

// 역할 기반 접근 제어(RBAC) 유틸리티
// 모든 권한 검사는 이 클래스의 static 메서드를 통해 수행합니다.
// 사용 예시: PermissionService.canManageMembers(role)
class PermissionService {
  PermissionService._();

  // 관리자 대시보드 진입 가능 여부 (STUDENT 차단)
  static bool hasAdminAccess(UserRole role) =>
      role == UserRole.SUPER_ADMIN || role == UserRole.INSTRUCTOR;

  // 회원(교사·학생) 목록 관리 — SUPER_ADMIN 전용
  static bool canManageMembers(UserRole role) =>
      role == UserRole.SUPER_ADMIN;

  // 강좌 개설·수정·삭제 — SUPER_ADMIN 전용
  static bool canManageCourses(UserRole role) =>
      role == UserRole.SUPER_ADMIN;

  // 공지사항 등록·수정 — SUPER_ADMIN, INSTRUCTOR
  static bool canPostNotice(UserRole role) =>
      role == UserRole.SUPER_ADMIN || role == UserRole.INSTRUCTOR;

  // 구직 공고 등록·관리 — SUPER_ADMIN, INSTRUCTOR
  static bool canManageJobs(UserRole role) =>
      role == UserRole.SUPER_ADMIN || role == UserRole.INSTRUCTOR;

  // 본인 작성 콘텐츠 수정 권한 (작성자 uid 일치 여부 포함)
  // SUPER_ADMIN은 모든 콘텐츠 수정 가능
  static bool canEditContent(UserRole role, String authorId, String currentUid) =>
      role == UserRole.SUPER_ADMIN || authorId == currentUid;

  // 시스템 설정 접근 — SUPER_ADMIN 전용
  static bool canAccessSettings(UserRole role) =>
      role == UserRole.SUPER_ADMIN;
}
