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

    // ── 임시 비밀번호 생성 ────────────────────────────────
    // is_temp_password: false→true 변경 시에만 생성합니다.
    // (신규 등록 시 이미 true인 경우는 제외 — onDocumentUpdated 이므로 변경분만 처리)
    if (before['is_temp_password'] !== true && after['is_temp_password'] === true) {
      const tempPw = generateTempPassword();
      try {
        await admin.auth().updateUser(uid, { password: tempPw });
        // 관리자가 교사에게 전달할 수 있도록 Firestore에 저장합니다.
        fsUpdates['temp_pw_plain'] = tempPw;
        fsUpdates['temp_pw_at']    = admin.firestore.FieldValue.serverTimestamp();
        console.log(`임시 비밀번호 생성: ${uid}`);
      } catch (e) {
        console.error(`임시 비밀번호 생성 실패: ${uid}`, e);
      }
    }

    // ── Firestore 역기록 ──────────────────────────────────
    if (Object.keys(fsUpdates).length > 0) {
      await event.data!.after.ref.update(fsUpdates);
    }
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
