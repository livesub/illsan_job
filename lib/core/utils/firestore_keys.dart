// Firestore 컬렉션명, 필드명, 상태값을 상수로 관리하는 파일입니다.
// 문자열 오타로 인한 버그를 방지하기 위해 하드코딩 대신 이 상수를 사용합니다.
//
// 사용 예시:
//   FirebaseFirestore.instance.collection(FsCol.users)
//   doc.data()[FsUser.role] == FsUser.roleInstructor

// ─────────────────────────────────────────────────────────
// 컬렉션 이름 상수
// ─────────────────────────────────────────────────────────
class FsCol {
  FsCol._();

  // 전체 회원 컬렉션 (SUPER_ADMIN, INSTRUCTOR, STUDENT 모두 포함)
  static const String users   = 'users';

  // 강좌(반) 컬렉션
  static const String courses = 'courses';

  // 공지사항 컬렉션
  static const String notices = 'notices';

  // 구직 게시물 컬렉션
  static const String jobs    = 'jobs';
}

// ─────────────────────────────────────────────────────────
// users/{uid} 문서 필드 상수
//
// 문서 구조:
//   uid           : String    — 문서 ID = Firebase Auth UID
//   name          : String    — 사용자 실명
//   email         : String    — 로그인에 사용하는 이메일
//   phone         : String?   — 전화번호 (교사/관리자만)
//   role          : String    — 'SUPER_ADMIN' | 'INSTRUCTOR' | 'STUDENT'
//   status        : String    — 'pending' | 'approved' | 'rejected'
//   is_deleted    : bool      — 교사 소프트 삭제 여부 (true = 비활성, 로그인 차단)
//   course_id     : String?   — 학생이 소속된 강좌 문서 ID (STUDENT 전용)
//   bio           : String?   — 자기소개 / 쓰고 싶은 말 (교사 선택)
//   photo_url     : String?   — 프로필 사진 Storage URL (교사 선택)
//   is_temp_password : bool   — true 이면 최초 로그인 시 비밀번호 변경 강제
//   created_at    : Timestamp — 계정 최초 생성 시각
// ─────────────────────────────────────────────────────────
class FsUser {
  FsUser._();

  // ── 필드명 상수 ──────────────────────────────────────────
  static const String name          = 'name';
  static const String email         = 'email';
  static const String phone         = 'phone';
  static const String role          = 'role';
  static const String status        = 'status';
  static const String isDeleted     = 'is_deleted';
  static const String courseId      = 'course_id';
  static const String bio           = 'bio';
  static const String photoUrl      = 'photo_url';
  static const String isTempPw      = 'is_temp_password';
  static const String createdAt     = 'created_at';

  // ── role 상태값 상수 ─────────────────────────────────────
  // Firestore에 저장되는 문자열 값입니다. UserRole Enum과 반드시 일치해야 합니다.
  static const String roleSuperAdmin = 'SUPER_ADMIN'; // 최고 관리자
  static const String roleInstructor = 'INSTRUCTOR';  // 교사/강사
  static const String roleStudent    = 'STUDENT';     // 학생/수강생

  // ── status 상태값 상수 ───────────────────────────────────
  // 계정 승인 상태를 나타냅니다.
  static const String statusPending  = 'pending';   // 승인 대기 중
  static const String statusApproved = 'approved';  // 승인 완료
  static const String statusRejected = 'rejected';  // 승인 거절
}

// ─────────────────────────────────────────────────────────
// courses/{id} 문서 필드 상수
//
// 문서 구조:
//   id            : String       — 문서 ID (Firestore 자동 생성)
//   name          : String       — 강좌명
//   status        : String       — 'active' | 'closed' | 'deleted'
//   teacher_id    : String       — 담당 교사 uid (users/{uid} 참조)
//   teacher_name  : String       — 담당 교사 이름 (조인 비용 절약용 캐시)
//   content       : String       — 강좌 내용 HTML (스마트 에디터 출력값)
//   inline_imgs   : List<String> — 본문 내 인라인 이미지 Storage 경로 목록
//   attachments   : List<String> — 별도 첨부 파일 Storage 경로 목록
//   created_at    : String       — 등록 시각 yymmddHis 포맷 (예: 260401090500)
//   end_date      : Timestamp    — 강좌 종료 예정일 (자동 종료 스케줄러 기준)
// ─────────────────────────────────────────────────────────
class FsCourse {
  FsCourse._();

  // ── 필드명 상수 ──────────────────────────────────────────
  static const String name         = 'name';
  static const String status       = 'status';
  static const String teacherId    = 'teacher_id';
  static const String teacherName  = 'teacher_name';
  static const String content      = 'content';
  static const String inlineImgs   = 'inline_imgs';
  static const String attachments  = 'attachments';
  static const String createdAt    = 'created_at';
  static const String endDate      = 'end_date';

  // ── status 상태값 상수 ───────────────────────────────────
  static const String statusActive  = 'active';   // 진행 중 — 정상 운영 상태
  static const String statusClosed  = 'closed';   // 종료 — 수동/자동 종료됨
  static const String statusDeleted = 'deleted';  // 삭제 — 완전 폐기 (리스트 제외)
}

// ─────────────────────────────────────────────────────────
// notices/{id} 문서 필드 상수
//
// 문서 구조:
//   id            : String       — 문서 ID (Firestore 자동 생성)
//   title         : String       — 공지 제목
//   content       : String       — 공지 내용 HTML (스마트 에디터)
//   author_id     : String       — 작성자 uid
//   author_name   : String       — 작성자 이름 (캐시)
//   target        : String       — 'all' | 'course' (전체 공지 / 강좌별 공지)
//   course_id     : String?      — target='course' 일 때 대상 강좌 ID
//   inline_imgs   : List<String> — 본문 이미지 Storage 경로 목록
//   attachments   : List<String> — 첨부 파일 Storage 경로 목록
//   created_at    : String       — yymmddHis 포맷
//   is_deleted    : bool         — 소프트 삭제 여부
// ─────────────────────────────────────────────────────────
class FsNotice {
  FsNotice._();

  // ── 필드명 상수 ──────────────────────────────────────────
  static const String title       = 'title';
  static const String content     = 'content';
  static const String authorId    = 'author_id';
  static const String authorName  = 'author_name';
  static const String target      = 'target';
  static const String courseId    = 'course_id';
  static const String inlineImgs  = 'inline_imgs';
  static const String attachments = 'attachments';
  static const String createdAt   = 'created_at';
  static const String isDeleted   = 'is_deleted';

  // ── target 상태값 상수 ───────────────────────────────────
  static const String targetAll    = 'all';    // 전체 공지
  static const String targetCourse = 'course'; // 특정 강좌 공지
}

// ─────────────────────────────────────────────────────────
// jobs/{id} 문서 필드 상수
//
// 문서 구조:
//   id            : String       — 문서 ID (Firestore 자동 생성)
//   title         : String       — 구직 공고 제목
//   content       : String       — 공고 내용 HTML (스마트 에디터)
//   author_id     : String       — 등록자 uid
//   author_name   : String       — 등록자 이름 (캐시)
//   inline_imgs   : List<String> — 본문 이미지 Storage 경로 목록
//   attachments   : List<String> — 첨부 파일 Storage 경로 목록
//   created_at    : String       — yymmddHis 포맷
//   is_deleted    : bool         — 소프트 삭제 여부
// ─────────────────────────────────────────────────────────
class FsJob {
  FsJob._();

  // ── 필드명 상수 ──────────────────────────────────────────
  static const String title       = 'title';
  static const String content     = 'content';
  static const String authorId    = 'author_id';
  static const String authorName  = 'author_name';
  static const String inlineImgs  = 'inline_imgs';
  static const String attachments = 'attachments';
  static const String createdAt   = 'created_at';
  static const String isDeleted   = 'is_deleted';
}

// ─────────────────────────────────────────────────────────
// Firebase Storage 업로드 경로 상수
//
// 디렉토리 구조:
//   uploads/{게시판종류}/{년도}/{월}/inline/       ← 본문 인라인 이미지
//   uploads/{게시판종류}/{년도}/{월}/attachments/  ← 별도 첨부 파일
//
// 게시판 종류(boardType) 값:
//   StoragePath.boardCourse  = 'course'
//   StoragePath.boardNotice  = 'notice'
//   StoragePath.boardJob     = 'job'
//   StoragePath.profilePhoto = 'profile'  ← 교사 프로필 사진
//
// 경로 생성 함수:
//   StoragePath.inlinePath('course', 2026, 4)
//   → 'uploads/course/2026/04/inline/'
// ─────────────────────────────────────────────────────────
class StoragePath {
  StoragePath._();

  // ── 게시판 종류 상수 ─────────────────────────────────────
  static const String boardCourse  = 'course';  // 강좌 게시판
  static const String boardNotice  = 'notice';  // 공지사항 게시판
  static const String boardJob     = 'job';     // 구직 게시판
  static const String boardProfile = 'profile'; // 교사 프로필 사진

  // ── 경로 생성 헬퍼 함수 ──────────────────────────────────

  // 본문 인라인 이미지 업로드 경로를 반환합니다.
  // 예: inlinePath('course', 2026, 4) → 'uploads/course/2026/04/inline/'
  static String inlinePath(String boardType, int year, int month) {
    final String mm = month.toString().padLeft(2, '0');
    return 'uploads/$boardType/$year/$mm/inline/';
  }

  // 첨부 파일 업로드 경로를 반환합니다.
  // 예: attachmentPath('course', 2026, 4) → 'uploads/course/2026/04/attachments/'
  static String attachmentPath(String boardType, int year, int month) {
    final String mm = month.toString().padLeft(2, '0');
    return 'uploads/$boardType/$year/$mm/attachments/';
  }

  // 교사 프로필 사진 경로를 반환합니다.
  // 예: profilePhotoPath('uid_abc123') → 'uploads/profile/uid_abc123/photo.jpg'
  static String profilePhotoPath(String uid) {
    return 'uploads/$boardProfile/$uid/photo.jpg';
  }

  // 현재 시각을 yymmddHis 포맷 문자열로 반환합니다.
  // 예: 2026년 4월 1일 09:05:00 → '260401090500'
  // 이 값이 Firestore created_at 필드에 저장됩니다.
  static String nowCreatedAt() {
    final now = DateTime.now();
    final yy = now.year.toString().substring(2);       // 연도 끝 2자리
    final mm = now.month.toString().padLeft(2, '0');   // 월
    final dd = now.day.toString().padLeft(2, '0');     // 일
    final hh = now.hour.toString().padLeft(2, '0');    // 시
    final ii = now.minute.toString().padLeft(2, '0');  // 분
    final ss = now.second.toString().padLeft(2, '0');  // 초
    return '$yy$mm$dd$hh$ii$ss';
  }
}
