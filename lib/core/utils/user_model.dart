import 'package:cloud_firestore/cloud_firestore.dart';
import '../enums/user_role.dart';
import 'firestore_keys.dart';

// Firestore users/{uid} 문서를 타입 안전하게 다루는 모델
class UserModel {
  final String   uid;
  final String   name;
  final String   email;
  final String   phone;
  final UserRole role;
  final String   status;
  final bool     isDeleted;
  final String   courseId;
  final String   bio;
  final String   photoUrl;
  final bool     isTempPw;
  final String   loginType;
  final DateTime? createdAt;

  const UserModel({
    required this.uid,
    required this.name,
    required this.email,
    required this.phone,
    required this.role,
    required this.status,
    required this.isDeleted,
    required this.courseId,
    required this.bio,
    required this.photoUrl,
    required this.isTempPw,
    required this.loginType,
    this.createdAt,
  });

  // Firestore 문서 → UserModel
  factory UserModel.fromMap(String uid, Map<String, dynamic> map) {
    final roleStr = (map[FsUser.role] as String?) ?? FsUser.roleStudent;
    final ts      = map[FsUser.createdAt];
    return UserModel(
      uid:        uid,
      name:       (map[FsUser.name]     as String?) ?? '',
      email:      (map[FsUser.email]    as String?) ?? '',
      phone:      (map[FsUser.phone]    as String?) ?? '',
      role:       roleStr.toUserRole(),
      status:     (map[FsUser.status]   as String?) ?? FsUser.statusPending,
      isDeleted:  (map[FsUser.isDeleted] as bool?)  ?? false,
      courseId:   (map[FsUser.courseId] as String?) ?? '',
      bio:        (map[FsUser.bio]      as String?) ?? '',
      photoUrl:   (map[FsUser.photoUrl] as String?) ?? '',
      isTempPw:   (map[FsUser.isTempPw] as bool?)  ?? false,
      loginType:  (map[FsUser.loginType] as String?) ?? FsUser.loginTypeEmail,
      createdAt:  ts is Timestamp ? ts.toDate() : null,
    );
  }

  // Firestore 저장용 Map (uid 제외 — 문서 ID로 관리)
  Map<String, dynamic> toMap() => {
    FsUser.name:      name,
    FsUser.email:     email,
    FsUser.phone:     phone,
    FsUser.role:      role.code,
    FsUser.status:    status,
    FsUser.isDeleted: isDeleted,
    FsUser.courseId:  courseId,
    FsUser.bio:       bio,
    FsUser.photoUrl:  photoUrl,
    FsUser.isTempPw:  isTempPw,
    FsUser.loginType: loginType,
  };

  bool get isApproved  => status == FsUser.statusApproved;
  bool get isSuperAdmin => role == UserRole.SUPER_ADMIN;
  bool get isInstructor => role == UserRole.INSTRUCTOR;
  bool get isStudent    => role == UserRole.STUDENT;
}
