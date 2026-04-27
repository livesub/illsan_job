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
  static const String jobs             = 'jobs';

  // 구직 신청 컬렉션 (학생 → 교사 신청 내역)
  static const String jobApplications  = 'job_applications';

  // 계정 삭제 요청 컬렉션 (교사 → Cloud Function 트리거용)
  static const String deleteRequests   = 'delete_requests';

  // 비밀번호 초기화 요청 컬렉션 (교사 → Cloud Function 트리거용)
  static const String passwordResets   = 'password_resets';

  // 구직 공고 댓글/대댓글 컬렉션
  static const String jobComments      = 'job_comments';

  // 외출/조퇴 신청 컬렉션
  static const String outings          = 'outings';
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
  static const String fcmToken      = 'fcm_token';  // FCM 푸시 토큰 (앱 실행 시 갱신)
  // Cloud Functions에서 is_temp_password: true 시 자동 생성 (관리자 전달용)
  static const String tempPwPlain        = 'temp_pw_plain';
  static const String tempPwAt           = 'temp_pw_at';
  // 비밀번호 초기화 후 강제 변경 플래그 (초기화 시 true, 변경 완료 후 false)
  static const String needPasswordChange = 'need_password_change';
  // 가입 경로: 'email' | 'google' | 'kakao' 등 (미설정 시 email로 간주)
  static const String loginType     = 'login_type';
  // 당월 조퇴/결석 카운트 (매월 1일 자동 리셋 예정)
  static const String monthlyLateCount    = 'monthly_late_count';
  static const String monthlyAbsenceCount = 'monthly_absence_count';
  static const String lastResetDate       = 'last_reset_date';

  // ── loginType 값 상수 ────────────────────────────────────
  static const String loginTypeEmail  = 'email';   // 이메일 직접 가입
  static const String loginTypeGoogle = 'google';  // 구글 연동 가입
  static const String loginTypeKakao  = 'kakao';   // 카카오 연동 가입

  // ── role 상태값 상수 ─────────────────────────────────────
  // Firestore에 저장되는 문자열 값입니다. UserRole Enum과 반드시 일치해야 합니다.
  static const String roleSuperAdmin = 'SUPER_ADMIN'; // 최고 관리자
  static const String roleInstructor = 'INSTRUCTOR';  // 교사/강사
  static const String roleStudent    = 'STUDENT';     // 학생/수강생

  // ── status 상태값 상수 ───────────────────────────────────
  static const String statusPending   = 'pending';    // 승인 대기
  static const String statusActive = 'approved';     // 정상 활성
  static const String statusGraduated = 'graduated';  // 졸업/수료
  static const String statusDropped   = 'dropped';    // 중도탈락
  // 하위 호환 보존 (기존 데이터 마이그레이션 전까지 유지)
  static const String statusApproved  = 'approved';
  static const String statusRejected  = 'rejected';   // 거절
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
  static const String targetAll      = 'all';        // 전체(교사+학생) 공지
  static const String targetTeachers = 'teachers';   // 전체 교사 대상
  static const String targetStudents = 'students';   // 전체 학생 대상
  static const String targetCourse   = 'course';     // 특정 반 공지
  static const String targetCourseAll = 'course_all'; // 교사 담당 반 전체 공지
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
  static const String title            = 'title';
  static const String content          = 'content';
  static const String authorId         = 'author_id';
  static const String authorName       = 'author_name';
  static const String inlineImgs       = 'inline_imgs';
  static const String attachments      = 'attachments';
  static const String createdAt        = 'created_at';
  static const String isDeleted        = 'is_deleted';
  // 기간 — 교사가 입력한 자유 텍스트 (예: "채용 시 마감")
  static const String period           = 'period';
  // 조회수 — 상세 진입 시 FieldValue.increment(1)
  static const String viewCount        = 'view_count';
  // 등록 시각 Timestamp — 고도화 대비 hidden 필드
  static const String createdTimestamp = 'created_timestamp';
  // 노출 대상 반 — ['all'] 또는 강좌 ID 목록
  static const String targetCourses    = 'target_courses';

  static const String targetAll = 'all';
}

// ─────────────────────────────────────────────────────────
// job_applications/{id} 문서 필드 상수
//
// 문서 구조:
//   job_id          : String    — 구직 공고 ID (jobs/{id} 참조)
//   job_title       : String    — 공고 제목 (비정규화)
//   author_id       : String    — 공고 등록 교사 uid
//   applicant_id    : String    — 신청 학생 uid
//   applicant_name  : String    — 학생 이름 (비정규화)
//   applicant_email : String    — 학생 이메일 (비정규화)
//   course_id       : String    — 학생 소속 강좌 ID (비정규화)
//   course_name     : String    — 학생 소속 강좌명 (비정규화)
//   status          : String    — 'pending' | 'approved' | 'cancelled'
//   applied_at      : Timestamp — 신청 시각
// ─────────────────────────────────────────────────────────
class FsJobApp {
  FsJobApp._();

  static const String jobId          = 'job_id';
  static const String jobTitle       = 'job_title';
  static const String authorId       = 'author_id';
  static const String applicantId    = 'applicant_id';
  static const String applicantName  = 'applicant_name';
  static const String applicantEmail = 'applicant_email';
  static const String courseId       = 'course_id';
  static const String courseName     = 'course_name';
  static const String status         = 'status';
  static const String appliedAt      = 'applied_at';

  static const String statusPending   = 'pending';
  static const String statusApproved  = 'approved';
  static const String statusCancelled = 'cancelled';
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
// ─────────────────────────────────────────────────────────
// job_comments/{id} 문서 필드 상수
//
// 문서 구조:
//   job_id      : String  — 소속 공고 ID
//   content     : String  — 댓글 본문 (삭제 시 텍스트 교체)
//   author_id   : String  — 작성자 uid
//   author_name : String  — 작성자 이름 (비정규화)
//   parent_id   : String? — 대댓글 시 부모 댓글 ID (null = 최상위)
//   is_deleted  : bool    — Soft Delete 여부 (true = 삭제 처리됨)
//   created_at  : String  — yymmddHis 포맷
// ─────────────────────────────────────────────────────────
class FsJobComment {
  FsJobComment._();

  static const String jobId       = 'job_id';
  static const String content     = 'content';
  static const String authorId    = 'author_id';
  static const String authorName  = 'author_name';
  static const String authorEmail = 'author_email'; // 닉네임 마스킹용
  static const String authorRole  = 'author_role';  // 'STUDENT' | 'INSTRUCTOR' | 'SUPER_ADMIN'
  static const String parentId    = 'parent_id';
  static const String isDeleted   = 'is_deleted';
  static const String createdAt   = 'created_at';

  // Soft Delete 통합 문구
  static const String deletedText   = '삭제 요청된 글입니다';
  // 하위 호환 보존
  static const String deletedByRule = '규정에 의해 삭제된 댓글입니다';
  static const String deletedBySelf = '삭제된 글입니다';
}

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

// ─────────────────────────────────────────────────────────
// outings/{id} 문서 필드 상수
//
// 문서 구조:
//   uid        : String    — 신청 학생 uid
//   user_name  : String    — 학생 이름 (비정규화)
//   job_type   : String    — 직종
//   reason     : String    — 사유
//   start_time : Timestamp — 외출 시작 일시
//   end_time   : Timestamp — 외출 종료 일시
//   contact    : String    — 연락처(휴대폰)
//   status     : String    — 'pending' | 'approved' | 'rejected'
//   created_at : Timestamp — 신청 시각 (serverTimestamp)
// ─────────────────────────────────────────────────────────
class FsOuting {
  FsOuting._();

  static const String uid       = 'uid';
  static const String userName  = 'user_name';
  static const String courseId  = 'course_id';  // 학생 소속 강좌 ID (비정규화)
  static const String jobType   = 'job_type';
  static const String reason    = 'reason';
  static const String startTime = 'start_time';
  static const String endTime   = 'end_time';
  static const String contact   = 'contact';
  static const String status    = 'status';
  static const String createdAt = 'created_at';

  static const String statusPending  = 'pending';
  static const String statusApproved = 'approved';
  static const String statusRejected = 'rejected';
}
