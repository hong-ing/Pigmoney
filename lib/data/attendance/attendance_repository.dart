import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pigmoney/core/utils/log/logger.dart';
import 'package:pigmoney/data/attendance/model/attendance_model.dart';

// ────────────────────────────────Repository Contract────────────────────────────────

abstract class AttendanceRepository {
  Future<void> updateAttendanceData({
    required String userId,
    required AttendanceData data,
  });

  Future<AttendanceData?> getAttendanceData({
    required String userId,
  });
}

class FirebaseAttendanceRepository implements AttendanceRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  Future<void> updateAttendanceData({
    required String userId,
    required AttendanceData data,
  }) async {
    try {
      logger.d('출석체크: updateAttendanceData 호출 - userId: $userId');

      // 데이터 검증
      if (data.slots.length != 3) {
        logger.e('출석체크: 잘못된 슬롯 개수 - ${data.slots.length}개 (3개여야 함)');
        throw Exception('출석체크 슬롯은 정확히 3개여야 합니다');
      }

      // 중복 ID 체크
      final ids = data.slots.map((s) => s.id).toSet();
      if (ids.length != data.slots.length) {
        logger.e('출석체크: 중복된 슬롯 ID 발견');
        throw Exception('중복된 슬롯 ID가 있습니다');
      }

      await _firestore.collection('users').doc(userId).update({
        'attendanceData': data.toJson(),
      });
      logger.d('출석체크: updateAttendanceData 완료');
    } catch (e) {
      logger.e('출석체크 데이터 업데이트 오류: $e');
      logger.e('출석체크 오류 스택트레이스: ${StackTrace.current}');
      rethrow;
    }
  }

  @override
  Future<AttendanceData?> getAttendanceData({
    required String userId,
  }) async {
    try {
      logger.d('출석체크: getAttendanceData 호출 - userId: $userId');
      final userDoc = await _firestore.collection('users').doc(userId).get();

      if (!userDoc.exists || userDoc.data()?['attendanceData'] == null) {
        logger.d('출석체크: getAttendanceData - 데이터 없음');
        return null;
      }

      logger.d('출석체크: getAttendanceData - 데이터 파싱 중');

      try {
        final data = AttendanceData.fromJson(userDoc.data()!['attendanceData']);

        // 데이터 검증
        if (data.slots.length != 3) {
          logger.w('출석체크: 슬롯 개수 오류 (${data.slots.length}개) - 새로 생성');
          return null; // null 반환하여 새로 생성하도록 함
        }

        logger.d('출석체크: getAttendanceData 완료 - ${data.slots.length}개 슬롯');
        return data;
      } catch (parseError) {
        logger.e('출석체크 데이터 파싱 오류: $parseError');
        // 파싱 오류 시 null 반환하여 새로 생성하도록 함
        return null;
      }
    } catch (e) {
      logger.e('출석체크 데이터 가져오기 오류: $e');
      logger.e('출석체크 오류 스택트레이스: ${StackTrace.current}');
      return null;
    }
  }
}
