# 프로젝트 핵심 규칙

## 1. 개발/구조 (Flutter+Firebase 전용, 외부 백엔드 금지)
- 언어/주석: 한글 필수. UI 주석 금지. DB/권한/상태 등 핵심 로직만 1줄 개조식.
- 권한/접근성: Enum 필수(문자열 비교 금지), 위젯 Semantics 필수.
- 폴더: lib/core, features 유지 (임의 생성 금지).
- 코드 작성 (Lint 및 품질 보장):
  - Warning 0개 유지 (`flutter analyze` 통과 필수)
  - 위젯 `const`, 불변 변수 `final` 필수
  - 비동기(`await`) 후 `if(!mounted) return;` 필수
  - `unused`, `dead_code` 임의 삭제 절대 금지 (나중 사용을 위해 보존)
  - 미요청 기능/필드/unused 코드 생성 금지
  - 기존 함수 재사용 / null safety 준수
  - UI 중첩 1 depth 최소화 / 사용 import만 포함
  - pubspec.yaml 수정 금지
  - 주석 기본 금지 (필수 로직만 예외)

## 2. [핵심] 토큰 절약/동작 통제
- 수다/설명 절대 금지 (코드 생성 불가 시에만 1줄 원인 출력).
- 출력 순서: **[변경 요약]** 1줄 고정 반드시 출력 → `// 파일명 (경로 불명확 시만 전체 경로)` → 결과 코드
- **[출력 토큰 방어]** 파일 전체 코드 출력 금지. diff 금지. 오직 **수정된 '함수 단위' 우선**, 불가 시 '클래스 단위'로 출력
- 수정된 함수 외 코드 포함 출력 금지 (연관 코드 확장 금지)
- 리팩토링 금지: 요청된 범위 외 구조 변경 금지
- 명령어 제어: `flutter run` 등 자동 실행 금지 (해결책 제안만).
- 루프 방지: 동일 에러 2회 실패 시 재시도 금지 → 1줄 질문
- 요구사항 불명확 시 추측 구현 금지 → 1줄 질문
- 파일 탐색: 파일명 기준 1개만 선택 (내용 무작위 열람 금지)
- 동일 요청 반복 시 이전 응답 재사용, 재생성 금지
- 규칙 파일(CLAUDE.md, docs/rules) 수정 금지
- 백업 ("요약 백업 해줘" 입력): 현재 상태/변수 `docs/handover.md`에 **Overwrite(덮어쓰기)**. 누적 금지. 완료 후 딱 1줄 `[백업 완료] /clear 후 docs/handover.md 읽기` 출력.
- TODO (3단계 이상 작업): 시작 전 `docs/todo.md`에 전체 단계 1회 **Overwrite**. (작업 중 `[x]` 체크 등 파일 업데이트 절대 금지).

## 3. 상세 규칙 위치 (필요시 참조)
- core: docs/rules/core.md
- UI: docs/rules/ui.md
- 접근성: docs/rules/accessibility.md
- 백엔드: docs/rules/backend.md