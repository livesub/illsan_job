# 인수인계 백업 — 2026-04-10

## 프로젝트
- 앱명: Job 알리미 (장애인 맞춤형 일자리/교육 정보 Flutter 앱)
- 스택: Flutter + Firebase (Auth, Firestore, Storage, Functions)
- Firebase 프로젝트 ID: illsan-job
- 역할 Enum: SUPER_ADMIN / INSTRUCTOR / STUDENT

## 금번 세션 완료 작업

### A. 공지사항 기능 (docs_rules/5. AI 관리자페이지 공지사항.docx 기준)

#### 1단계 — FCM 타겟 UI + 스마트에디터 색상

**`lib/core/utils/firestore_keys.dart`**
- `FsUser.fcmToken = 'fcm_token'` 추가
- `FsNotice` 타겟 상수 추가:
  - `targetTeachers = 'teachers'` (전체 교사)
  - `targetStudents = 'students'` (전체 학생)
  - `targetCourseAll = 'course_all'` (교사 담당 반 전체)

**`lib/features/manage/tabs/notice_tab.dart`** 주요 변경
- `_badgeLabel()` / `_badgeColor()` — 타겟별 배지 텍스트·색상
- `_applyFilterAndPage()` — 필터 로직: all계열(all/teachers/students), course계열(course/course_all) 그룹화
- `_buildTargetSelector()` 분기:
  - SUPER_ADMIN: 전체 / 전체 교사 / 전체 학생 (3선택 Row)
  - INSTRUCTOR: 담당 반 전체 / 특정 반 (2선택 Row)
- INSTRUCTOR 기본 타겟: `targetCourseAll` (담당 반 전체)
- `_buildSmartEditor()` — 색상 버튼 추가 (PopupMenuButton, 6색: 빨강/파랑/초록/주황/보라/검정)
- 색상 서식: `<font color="#HEX">선택텍스트</font>` HTML 태그 삽입

#### 2단계 — 첨부파일 업로드 (웹 호환, 3개/3MB)

**`lib/features/manage/tabs/notice_tab.dart`** 추가
- imports: `file_picker`
- 상태: `_existAttachPaths/Names`, `_newAttachFiles`, `_removedAttachPaths`
- 상수: `_maxAttach=3`, `_maxBytes=3MB`
- `_loadExistAttachments()` — 수정 모드 기존 첨부 로드
- `_pickAttachment()` — `pf.size` 사용 (dart:io File 금지, 웹 호환)
  - 초과 시 AlertDialog `"파일 용량은 3MB를 초과할 수 없습니다."`
- `_removeExistAttach()` / `_removeNewAttach()` — 개수별 제거
- `_save()` — 신규 파일 Storage 업로드 + 제거된 기존 파일 Hard Delete
- `_deleteNotice()` — inline이미지 + 첨부파일 동시 Hard Delete
- `_buildAttachSection()` / `_buildAttachTile()` — 첨부파일 UI
- 스토리지 경로: `uploads/notice/{년도}/{월}/attachments/`

#### 3단계 — Cloud Functions FCM 알림

**`functions/src/index.ts`**
- `onNoticeCreated` — `notices/{noticeId}` onCreate 트리거
- `_getTargetTokens()` — target별 FCM 토큰 수집:
  - `all`: INSTRUCTOR+STUDENT (approved)
  - `teachers`: INSTRUCTOR (approved)
  - `students`: STUDENT (approved)
  - `course`: course_id 일치 학생
  - `course_all`: 교사 담당 active 강좌 학생 (30개 배치 쿼리)
- `_sendFcm()` — `sendEachForMulticast` 500개 배치 발송
- `_formatCreatedAt()` — 서버 시간 yymmddHis 덮어쓰기
- ⚠️ FCM 토큰 저장(Flutter 측): `firebase_messaging` 패키지 미추가 → 별도 진행 필요

---

### B. 로그인 / 권한 라우팅 (docs_rules/6. AI 로그인(최고관리자).docx 기준)

#### 1단계 — LoginPage 신규

**`lib/features/login/login_page.dart`** (신규)
- 이메일 + 비밀번호 TextFormField
- 로딩: Stack + ModalBarrier + 중앙 CircularProgressIndicator
- 버튼 비활성: `_isLoading` 시 `onPressed: null`
- FirebaseAuthException code별 한글 에러 메시지

**`lib/features/login/login_intro_page.dart`**
- 로그인 버튼 → `Navigator.push(LoginPage)` 연결

#### 2단계 — 인증 + Firestore Role 확인 + 즉시 라우팅

**`lib/features/login/login_page.dart`** `_login()` 업데이트
- `signInWithEmailAndPassword` → `users/{uid}` Firestore 조회
- 문서 없으면 signOut + "등록되지 않은 계정" 에러
- `pushAndRemoveUntil(AdminDashboardPage(role, name), (_)=>false)` — 즉시 강제 이동

**`lib/features/manage/admin_dashboard_page.dart`**
- 로그아웃 구현: `signOut()` + `pushAndRemoveUntil(LoginIntroPage)`
- import 추가: `login_intro_page.dart`

#### 3단계 — RouteGuard (라우팅 가드)

**`lib/core/utils/route_guard.dart`** (신규)
- `RouteGuard` — StreamBuilder(authStateChanges) 최상위 가드
- `_RoleRouter` — StatefulWidget, Future 캐싱으로 중복 Firestore 조회 방지
  - 미로그인 → LoginIntroPage
  - Firestore 문서 없음 → signOut → LoginIntroPage
  - STUDENT → SnackBar "권한이 없습니다" + signOut → LoginIntroPage
  - INSTRUCTOR / SUPER_ADMIN → AdminDashboardPage(role, name)

**`lib/main.dart`**
- 기존 StreamBuilder + FutureBuilder 제거
- `home: const RouteGuard()` 단순화

---

## 주요 파일 구조 (현재)
```
lib/
  core/
    enums/user_role.dart
    utils/
      firestore_keys.dart   — FsCol, FsUser(fcmToken추가), FsCourse, FsNotice(타겟5종), FsJob, StoragePath
      route_guard.dart      ← 신규 (라우팅 가드)
    theme/app_theme.dart
  features/
    login/
      login_intro_page.dart
      login_page.dart       ← 신규 (이메일/비밀번호 로그인)
    instructor/
      instructor_profile_page.dart
    manage/
      admin_dashboard_page.dart  — 로그아웃 구현
      tabs/
        home_tab.dart
        instructor_home_tab.dart
        member_tab.dart
        course_tab.dart
        teacher_tab.dart
        notice_tab.dart          — 공지사항 전면 개편
        job_tab.dart
  firebase_options.dart
  main.dart                      — RouteGuard 단일 home
functions/
  src/index.ts                   — onNoticeCreated FCM 트리거 추가
```

## Firestore 컬렉션 스키마 (전체)
- **users**: uid, name, email, phone, role, status, is_deleted, course_id, bio, photo_url, is_temp_password, login_type, created_at, temp_pw_plain, temp_pw_at, **fcm_token**
- **courses**: name, status, teacher_id, teacher_name, content, inline_imgs, attachments, created_at, end_date
- **notices**: title, content, author_id, author_name, target(all/teachers/students/course/course_all), course_id, inline_imgs, attachments, created_at, is_deleted
- **jobs**: title, content, author_id, author_name, inline_imgs, attachments, created_at, is_deleted, period, target_courses, created_timestamp
- **job_applications**: job_id, job_title, author_id, applicant_id, applicant_name, applicant_email, course_id, course_name, status, applied_at
- **delete_requests**: → Cloud Function 트리거

## Storage 경로
- 공지/강좌/구직 인라인: `uploads/{board}/{년도}/{월}/inline/`
- 공지/강좌/구직 첨부: `uploads/{board}/{년도}/{월}/attachments/`
- 교사 프로필 사진: `uploads/profile/{uid}/photo.jpg`

## 미완료 항목
- FCM 토큰 저장 (Flutter): `firebase_messaging` 패키지 pubspec.yaml 추가 후 진행 필요
  - `FsUser.fcmToken('fcm_token')` 필드에 앱 실행 시 토큰 갱신 로직 작성 예정

## Cloud Functions (전체)
| 함수 | 트리거 | 동작 |
|------|--------|------|
| `onUserDocumentUpdated` | users/{uid} 업데이트 | is_deleted → Auth 활성/비활성, is_temp_password → 임시PW 생성 |
| `onStudentDeleteRequested` | delete_requests/{uid} 생성 | Auth + Firestore 물리 삭제 |
| `onNoticeCreated` | notices/{noticeId} 생성 | target별 FCM 토큰 수집 → 푸시 알림 발송 |
