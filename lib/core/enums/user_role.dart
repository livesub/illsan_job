// 앱 전체에서 사용하는 사용자 역할(권한) Enum 파일입니다.
// 역할 비교는 반드시 이 Enum을 사용해야 합니다. (한글 문자열 직접 비교 금지!)
//
// 사용 예시:
//   ✅ if (role == UserRole.INSTRUCTOR) { ... }
//   ❌ if (role == '교사') { ... }  ← 절대 금지

// 사용자 역할을 나타내는 열거형(Enum)입니다.
// CLAUDE.md 규칙: 역할 코드는 반드시 영문 대문자(UPPER_SNAKE_CASE)로 관리합니다.
// ignore_for_file: constant_identifier_names
enum UserRole {
  // 최고 관리자 — 모든 기능에 접근 가능
  SUPER_ADMIN,

  // 교사/강사 — 반 관리, 공지사항 등록, 구직 공고 관리 가능
  INSTRUCTOR,

  // 학생/수강생 — 구직 공고 조회, 지원 등 기본 기능만 가능
  STUDENT,
}

// Firestore에 저장된 문자열을 UserRole Enum으로 변환하는 확장 함수입니다.
// 예: 'SUPER_ADMIN' → UserRole.SUPER_ADMIN
extension UserRoleExtension on String {
  // 문자열을 UserRole로 변환합니다. 알 수 없는 값이면 STUDENT를 기본값으로 반환합니다.
  UserRole toUserRole() {
    switch (this) {
      case 'SUPER_ADMIN':
        return UserRole.SUPER_ADMIN;
      case 'INSTRUCTOR':
        return UserRole.INSTRUCTOR;
      case 'STUDENT':
      default:
        return UserRole.STUDENT;
    }
  }
}

// UserRole Enum을 Firestore에 저장할 문자열로 변환하는 확장 함수입니다.
// 예: UserRole.INSTRUCTOR → 'INSTRUCTOR'
extension UserRoleToString on UserRole {
  String get code => name; // Enum의 이름(name)을 그대로 문자열로 반환
}
