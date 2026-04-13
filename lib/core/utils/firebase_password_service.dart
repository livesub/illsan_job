import 'package:cloud_firestore/cloud_firestore.dart';
import 'firestore_keys.dart';

// settings/admin_config 컬렉션에서 공용 임시 비밀번호를 읽어
// 학생 비밀번호를 초기화하는 서비스.
// Cloud Function(onUserDocumentUpdated)이 temp_pw_plain 감지 후 Firebase Auth 비밀번호를 변경합니다.
class FirebasePasswordService {
  FirebasePasswordService._();

  // settings/admin_config.temp_password 값을 반환합니다.
  static Future<String> fetchTempPassword() async {
    final doc = await FirebaseFirestore.instance
        .collection('settings')
        .doc('admin_config')
        .get();
    return (doc.data()?['temp_password'] as String?) ?? '';
  }

  // 학생 비밀번호를 임시 비밀번호로 초기화합니다.
  // 반환값: 설정된 임시 비밀번호 (UI 표시용)
  static Future<String> resetStudentPassword(String studentUid) async {
    final tempPw = await fetchTempPassword();
    if (tempPw.isEmpty) {
      throw Exception('임시 비밀번호가 설정되지 않았습니다. 관리자 설정을 확인해 주세요.');
    }
    await FirebaseFirestore.instance
        .collection(FsCol.users)
        .doc(studentUid)
        .update({
      FsUser.isTempPw:    true,
      FsUser.tempPwPlain: tempPw,
      FsUser.tempPwAt:    FieldValue.serverTimestamp(),
    });
    return tempPw;
  }
}
