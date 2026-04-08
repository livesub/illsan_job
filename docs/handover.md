# 인수인계 백업 — 2026-04-08

## 프로젝트
- 앱명: Job 알리미 (장애인 맞춤형 일자리/교육 정보 Flutter 앱)
- 스택: Flutter + Firebase (Auth, Firestore, Storage, Functions)
- Firebase 프로젝트 ID: illsan-job
- 역할 Enum: SUPER_ADMIN / INSTRUCTOR / STUDENT

## 완료된 10단계 (문서: docs_rules/2. AI 관리자페이지 강좌 개설및 강사 회원 가입(최고 관리자).docx)

| 단계 | 내용 | 파일 |
|------|------|------|
| 1 | Firebase Auth + 로그인 페이지 | lib/features/login/login_intro_page.dart |
| 2 | 관리자 대시보드 사이드바 구조 | lib/features/manage/admin_dashboard_page.dart |
| 3 | 회원 관리 탭 (학생/교사 목록, 승인/거절) | lib/features/manage/tabs/member_tab.dart |
| 4 | 강좌 관리 탭 (목록/검색/필터/페이징) | lib/features/manage/tabs/course_tab.dart |
| 5 | 강좌 개설/수정/삭제 다이얼로그 | lib/features/manage/tabs/course_tab.dart |
| 6 | 교사 관리 탭 (목록/등록/수정/삭제방어/인수인계) | lib/features/manage/tabs/teacher_tab.dart |
| 7 | 스마트 에디터 (B/I/U 서식 + 인라인 이미지 업로드) | course_tab, notice_tab, job_tab |
| 8 | Cloud Functions (Auth 비활성화 + 임시비밀번호 생성) | functions/src/index.ts |
| 9 | 공지사항 탭 Firestore 연동 | lib/features/manage/tabs/notice_tab.dart |
| 10 | 구직 등록 탭 Firestore 연동 | lib/features/manage/tabs/job_tab.dart |

## 주요 파일 구조
```
lib/
  core/
    enums/user_role.dart          — UserRole enum (SUPER_ADMIN, INSTRUCTOR, STUDENT)
    utils/firestore_keys.dart     — FsCol, FsUser, FsCourse, FsNotice, FsJob, StoragePath 상수
    theme/app_theme.dart
  features/
    login/login_intro_page.dart
    manage/
      admin_dashboard_page.dart   — 사이드바 + 콘텐츠 라우팅 (userRole, userName 주입)
      tabs/
        home_tab.dart
        member_tab.dart
        course_tab.dart           — 7단계 스마트 에디터 포함
        teacher_tab.dart          — 6단계: Secondary App 교사등록, 인수인계, 8단계 임시비밀번호 표시
        notice_tab.dart           — 9단계: 전체 재작성 완료
        job_tab.dart              — 10단계: 전체 재작성 완료
  firebase_options.dart
functions/
  src/index.ts                    — onUserDocumentUpdated (Auth 비활성화 + 임시비밀번호)
  package.json                    — firebase-functions v6, firebase-admin v12, Node 20
  tsconfig.json
firebase.json                     — functions 소스 등록 완료
```

## Firestore 컬렉션 스키마 요약
- **users**: uid, name, email, phone, role, status, is_deleted, course_id, bio, photo_url, is_temp_password, created_at, temp_pw_plain, temp_pw_at
- **courses**: name, status(active/closed/deleted), teacher_id, teacher_name, content, inline_imgs, attachments, created_at, end_date
- **notices**: title, content, author_id, author_name, target(all/course), course_id, inline_imgs, attachments, created_at, is_deleted
- **jobs**: title, content, author_id, author_name, inline_imgs, attachments, created_at, is_deleted

## 6단계에서 수정된 주요 버그
1. `teacher_tab.dart` `_save()` — `createUserWithEmailAndPassword` 호출 시 관리자 세션이 교사 계정으로 교체되는 버그 → Secondary Firebase App 방식으로 수정
2. `_TeacherEditDialog` — 수정 다이얼로그에 이메일 read-only 표시 누락 → 추가
3. `_buildPhotoField()` — 사진 선택/변경 버튼 Semantics 누락 → 추가

## 8단계 Cloud Functions 배포 방법
```bash
cd functions
npm install
npm run build
firebase deploy --only functions
```
트리거: `users/{uid}` 문서 업데이트 시
- `is_deleted` false→true: Firebase Auth 계정 비활성화
- `is_deleted` true→false: Firebase Auth 계정 재활성화
- `is_temp_password` false→true: 임시 비밀번호 생성 → Auth 업데이트 + Firestore `temp_pw_plain` 저장

## notice_tab / job_tab 권한 규칙
- SUPER_ADMIN: 전체 등록/수정/삭제
- INSTRUCTOR: 본인 작성(`author_id == uid`)만 수정/삭제
- notice_tab INSTRUCTOR: 반별 공지만 작성 가능 (전체 공지 선택 불가)

## Storage 경로 규칙 (StoragePath 클래스)
- 강좌 인라인 이미지: `uploads/course/yyyy/mm/inline/`
- 공지 인라인 이미지: `uploads/notice/yyyy/mm/inline/`
- 구직 인라인 이미지: `uploads/job/yyyy/mm/inline/`
- 교사 프로필 사진: `uploads/profile/{uid}/photo.jpg`
- 삭제 시 반드시 Storage Hard Delete 필수 (CLAUDE.md 규칙)

## 다음 작업 없음 (10단계 전부 완료)
