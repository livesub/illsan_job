import 'package:cloud_firestore/cloud_firestore.dart';
import 'firestore_keys.dart';

class OutingModel {
  final String   id;
  final String   uid;
  final String   userName;
  final String   courseId;
  final String   jobType;
  final String   reason;
  final DateTime startTime;
  final DateTime endTime;
  final String   contact;
  final String   status;
  final DateTime? createdAt;

  const OutingModel({
    required this.id,
    required this.uid,
    required this.userName,
    required this.courseId,
    required this.jobType,
    required this.reason,
    required this.startTime,
    required this.endTime,
    required this.contact,
    required this.status,
    this.createdAt,
  });

  factory OutingModel.fromDoc(DocumentSnapshot doc) {
    final m = doc.data() as Map<String, dynamic>;
    final now = DateTime.now();
    return OutingModel(
      id:        doc.id,
      uid:       (m[FsOuting.uid]       as String?)    ?? '',
      userName:  (m[FsOuting.userName]  as String?)    ?? '',
      courseId:  (m[FsOuting.courseId]  as String?)    ?? '',
      jobType:   (m[FsOuting.jobType]   as String?)    ?? '',
      reason:    (m[FsOuting.reason]    as String?)    ?? '',
      startTime: (m[FsOuting.startTime] as Timestamp?)?.toDate() ?? now,
      endTime:   (m[FsOuting.endTime]   as Timestamp?)?.toDate() ?? now,
      contact:   (m[FsOuting.contact]   as String?)    ?? '',
      status:    (m[FsOuting.status]    as String?)    ?? FsOuting.statusPending,
      createdAt: (m[FsOuting.createdAt] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
    FsOuting.uid:       uid,
    FsOuting.userName:  userName,
    FsOuting.courseId:  courseId,
    FsOuting.jobType:   jobType,
    FsOuting.reason:    reason,
    FsOuting.startTime: Timestamp.fromDate(startTime),
    FsOuting.endTime:   Timestamp.fromDate(endTime),
    FsOuting.contact:   contact,
    FsOuting.status:    status,
    FsOuting.createdAt: FieldValue.serverTimestamp(),
  };
}
