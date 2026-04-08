# 교사 대시보드 구현 (docs_rules/3. AI 관리자페이지 회원관리(교사).docx)

## 1단계 — 기반 + 교사 홈 대시보드 전체 (현재)
- [ ] firestore_keys.dart: loginType, FsJobApp, FsCol.jobApplications/deleteRequests 추가
- [ ] functions/src/index.ts: onStudentDeleteRequested 트리거 함수 추가
- [ ] instructor_home_tab.dart 신규 생성 (담당 강좌 카드 + 승인 팝업 + 구직신청 관리)
- [ ] admin_dashboard_page.dart: INSTRUCTOR 홈 탭 → InstructorHomeTab 교체 + 프로필 아바타

## 2단계 — 교사 마이페이지 (다음)
- [ ] instructor_my_page.dart 신규 생성 (프로필 수정, 이메일 read-only)
- [ ] admin_dashboard_page.dart: 아바타 클릭 → 마이페이지 라우팅 연결
