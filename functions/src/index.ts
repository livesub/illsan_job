// Cloud Functions for illsan-job
//
// 트리거: users/{uid} 문서 업데이트
//   - is_deleted: false→true   → Firebase Auth 계정 비활성화
//   - is_deleted: true→false   → Firebase Auth 계정 재활성화
//   - is_temp_password false→true → 임시 비밀번호 생성 후 Auth 업데이트 + Firestore 저장

import { onDocumentUpdated, onDocumentCreated } from 'firebase-functions/v2/firestore';
import * as admin from 'firebase-admin';

admin.initializeApp();

export const onUserDocumentUpdated = onDocumentUpdated(
  'users/{uid}',
  async (event) => {
    const before = event.data?.before.data();
    const after  = event.data?.after.data();
    if (!before || !after) return;

    const uid = event.params.uid;
    const fsUpdates: Record<string, unknown> = {};

    // ── Auth 비활성화/재활성화 ─────────────────────────────
    // is_deleted 값이 변경된 경우에만 처리합니다.
    if (before['is_deleted'] !== after['is_deleted']) {
      const disabled = after['is_deleted'] === true;
      try {
        await admin.auth().updateUser(uid, { disabled });
        console.log(`Auth ${disabled ? '비활성화' : '재활성화'}: ${uid}`);
      } catch (e) {
        console.error(`Auth 상태 변경 실패: ${uid}`, e);
      }
    }

    // ── 임시 비밀번호 생성 및 적용 ──────────────────────────
    // ① need_password_change false→true: 고정 임시 비밀번호 'Temppw123!' 적용 (학생 초기화)
    // ② temp_pw_plain 변경: 제공된 값으로 Auth 업데이트 + is_temp_password 플래그 설정
    // ③ is_temp_password false→true이고 temp_pw_plain 없음: 자동 생성 후 Firestore 역기록
    const needPwChange = before['need_password_change'] !== true && after['need_password_change'] === true;
    const beforePlain  = ((before['temp_pw_plain'] as string) ?? '').trim();
    const afterPlain   = ((after['temp_pw_plain']  as string) ?? '').trim();
    const isTempActivated = before['is_temp_password'] !== true && after['is_temp_password'] === true;

    if (needPwChange) {
      const fixedTempPw = 'Temppw123!';
      try {
        await admin.auth().updateUser(uid, { password: fixedTempPw });
        fsUpdates['temp_pw_plain'] = fixedTempPw;
        fsUpdates['temp_pw_at']    = admin.firestore.FieldValue.serverTimestamp();
        console.log(`임시 비밀번호(고정) 적용: ${uid}`);
      } catch (e) {
        console.error(`임시 비밀번호 적용 실패: ${uid}`, e);
      }
    } else if (afterPlain.length > 0 && beforePlain !== afterPlain) {
      try {
        await admin.auth().updateUser(uid, { password: afterPlain });
        fsUpdates['is_temp_password'] = true;
        fsUpdates['temp_pw_at']       = admin.firestore.FieldValue.serverTimestamp();
        console.log(`임시 비밀번호 적용: ${uid}`);
      } catch (e) {
        console.error(`임시 비밀번호 적용 실패: ${uid}`, e);
      }
    } else if (isTempActivated) {
      const tempPw = generateTempPassword();
      try {
        await admin.auth().updateUser(uid, { password: tempPw });
        fsUpdates['temp_pw_plain'] = tempPw;
        fsUpdates['temp_pw_at']    = admin.firestore.FieldValue.serverTimestamp();
        console.log(`임시 비밀번호 자동 생성: ${uid}`);
      } catch (e) {
        console.error(`임시 비밀번호 자동 생성 실패: ${uid}`, e);
      }
    }

    // ── Firestore 역기록 ──────────────────────────────────
    if (Object.keys(fsUpdates).length > 0) {
      await event.data!.after.ref.update(fsUpdates);
    }
  }
);

// ── 학생 비밀번호 초기화: Auth 삭제 → 재생성 → Firestore 문서 이전 ──
// password_resets/{reqId} 생성 시 트리거
// payload: { student_uid, email, temp_password }
export const onPasswordResetRequested = onDocumentCreated(
  'password_resets/{reqId}',
  async (event) => {
    const data       = event.data?.data();
    const studentUid = (data?.['student_uid']   as string | undefined) ?? '';
    const email      = (data?.['email']         as string | undefined) ?? '';
    const tempPw     = (data?.['temp_password'] as string | undefined) ?? '';
    if (!studentUid || !email || !tempPw) return;

    const db        = admin.firestore();
    const oldDocRef = db.collection('users').doc(studentUid);
    const oldDoc    = await oldDocRef.get();
    if (!oldDoc.exists) {
      await event.data!.ref.update({ status: 'error', error: 'user_not_found' });
      return;
    }
    const oldData = oldDoc.data()!;

    // 기존 Auth 삭제 (없으면 무시)
    try { await admin.auth().deleteUser(studentUid); } catch (_) {}

    // 새 Auth 계정 생성
    let newUid: string;
    try {
      const newUser = await admin.auth().createUser({ email, password: tempPw });
      newUid = newUser.uid;
    } catch (e) {
      await event.data!.ref.update({ status: 'error', error: String(e) });
      return;
    }

    // 새 users/{newUid} 문서 생성 (기존 데이터 + 초기화 필드)
    await db.collection('users').doc(newUid).set({
      ...oldData,
      need_password_change: true,
      temp_pw_plain: tempPw,
      temp_pw_at: admin.firestore.FieldValue.serverTimestamp(),
    });

    // 기존 users/{oldUid} 문서 삭제
    await oldDocRef.delete();

    // 완료 표시
    await event.data!.ref.update({ status: 'done' });
  }
);

// ── 학생 계정 완전 삭제 (교사 거절 처리) ─────────────────
// delete_requests/{uid} 문서 생성 시 트리거됩니다.
// Auth 계정 삭제 → users/{uid} 문서 삭제 → 요청 문서 삭제
export const onStudentDeleteRequested = onDocumentCreated(
  'delete_requests/{uid}',
  async (event) => {
    const uid = event.params.uid;
    try {
      await admin.auth().deleteUser(uid);
      console.log(`Auth 삭제: ${uid}`);
    } catch (e) {
      // Auth 계정이 없는 경우 무시
      console.log(`Auth 삭제 건너뜀: ${uid}`, e);
    }
    try {
      await admin.firestore().collection('users').doc(uid).delete();
      console.log(`Firestore 사용자 삭제: ${uid}`);
    } catch (e) {
      console.error(`Firestore 사용자 삭제 실패: ${uid}`, e);
    }
    // 요청 문서 자체 삭제
    await event.data!.ref.delete();
  }
);

// ── 공지사항 등록 시 FCM 푸시 알림 발송 ─────────────────────
// notices/{noticeId} 문서 생성 트리거
// 1. target 값에 따라 대상 FCM 토큰 조회
// 2. 500개 배치로 sendEachForMulticast 발송
// 3. created_at 서버 시간으로 덮어쓰기 (yymmddHis 포맷)
export const onNoticeCreated = onDocumentCreated(
  'notices/{noticeId}',
  async (event) => {
    const data = event.data?.data();
    if (!data) return;

    const target   = data['target']    as string | undefined;
    const authorId = data['author_id'] as string | undefined;
    const courseId = data['course_id'] as string | undefined;
    const title    = (data['title']    as string | undefined) ?? '새 공지사항';
    const rawBody  = (data['content']  as string | undefined) ?? '';
    // HTML 태그 제거 후 최대 100자 미리보기
    const body = rawBody.replace(/<[^>]+>/g, '').substring(0, 100);

    // 서버 시간 created_at 덮어쓰기 (yymmddHis)
    await event.data!.ref.update({ created_at: _formatCreatedAt(new Date()) });

    if (!target || !authorId) return;

    const tokens = await _getTargetTokens(target, authorId, courseId);
    if (tokens.length === 0) {
      console.log('FCM 발송 대상 토큰 없음');
      return;
    }

    await _sendFcm(tokens, title, body);
  }
);

// target 값별 대상 users에서 fcm_token 수집
async function _getTargetTokens(
  target: string,
  authorId: string,
  courseId?: string
): Promise<string[]> {
  const db = admin.firestore();

  // course_all: 교사 담당 활성 강좌의 학생 전체
  if (target === 'course_all') {
    const courseSnap = await db.collection('courses')
      .where('teacher_id', '==', authorId)
      .where('status', '==', 'active')
      .get();
    const courseIds = courseSnap.docs.map(d => d.id);
    if (courseIds.length === 0) return [];

    const tokens: string[] = [];
    // Firestore 'in' 쿼리 최대 30개 제한 → 배치 처리
    for (let i = 0; i < courseIds.length; i += 30) {
      const chunk = courseIds.slice(i, i + 30);
      const snap  = await db.collection('users')
        .where('course_id', 'in', chunk)
        .where('status', '==', 'approved')
        .get();
      snap.docs.forEach(d => {
        const t = d.data()['fcm_token'] as string | undefined;
        if (t) tokens.push(t);
      });
    }
    return tokens;
  }

  let query: admin.firestore.Query = db.collection('users')
    .where('status', '==', 'approved');

  switch (target) {
    case 'all':
      query = query.where('role', 'in', ['INSTRUCTOR', 'STUDENT']);
      break;
    case 'teachers':
      query = query.where('role', '==', 'INSTRUCTOR');
      break;
    case 'students':
      query = query.where('role', '==', 'STUDENT');
      break;
    case 'course':
      if (!courseId) return [];
      query = query.where('course_id', '==', courseId);
      break;
    default:
      return [];
  }

  const snap = await query.get();
  return snap.docs
    .map(d => d.data()['fcm_token'] as string | undefined)
    .filter((t): t is string => !!t);
}

// 500개 배치로 FCM 발송
async function _sendFcm(tokens: string[], title: string, body: string): Promise<void> {
  const BATCH = 500;
  for (let i = 0; i < tokens.length; i += BATCH) {
    const batch = tokens.slice(i, i + BATCH);
    try {
      const result = await admin.messaging().sendEachForMulticast({
        tokens: batch,
        notification: { title, body },
      });
      console.log(`FCM 발송 완료: 성공 ${result.successCount} / 실패 ${result.failureCount}`);
    } catch (e) {
      console.error('FCM 발송 오류:', e);
    }
  }
}

// yymmddHis 포맷: 260403113500
function _formatCreatedAt(date: Date): string {
  const yy = String(date.getFullYear()).slice(2);
  const mm = String(date.getMonth() + 1).padStart(2, '0');
  const dd = String(date.getDate()).padStart(2, '0');
  const hh = String(date.getHours()).padStart(2, '0');
  const ii = String(date.getMinutes()).padStart(2, '0');
  const ss = String(date.getSeconds()).padStart(2, '0');
  return `${yy}${mm}${dd}${hh}${ii}${ss}`;
}

// 8자 임시 비밀번호 생성: 대문자 1 + 특수문자 1 + 숫자 1 + 나머지 5자 혼합
function generateTempPassword(): string {
  const upper   = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  const lower   = 'abcdefghijklmnopqrstuvwxyz';
  const digits  = '0123456789';
  const special = '!@#$%^&*';
  const all     = upper + lower + digits + special;

  const chars = [
    upper  [Math.floor(Math.random() * upper.length)],
    special[Math.floor(Math.random() * special.length)],
    digits [Math.floor(Math.random() * digits.length)],
    ...Array.from({ length: 5 }, () => all[Math.floor(Math.random() * all.length)]),
  ];
  return chars.sort(() => Math.random() - 0.5).join('');
}
