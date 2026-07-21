import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pigmoney/data/attendance/attendance_manager.dart';
import 'package:pigmoney/data/attendance/attendance_repository.dart';

import 'user_provider.dart';

// 출석체크 저장소 프로바이더
final attendanceRepositoryProvider = Provider<AttendanceRepository>((ref) {
  return FirebaseAttendanceRepository();
});

// 출석체크 매니저 프로바이더 - 초기화 완료까지 대기
final attendanceManagerProvider = FutureProvider.autoDispose<AttendanceManager?>((ref) async {
  // Firebase Auth 상태 직접 체크
  final currentUser = fb.FirebaseAuth.instance.currentUser;
  if (currentUser == null) {
    print('attendanceManagerProvider: 로그인되지 않음 - null 반환');
    return null;
  }

  final repository = ref.watch(attendanceRepositoryProvider);
  final userRepository = ref.watch(userRepositoryProvider);

  // now 주입 → 테스트 용이
  final manager = AttendanceManager(
    repository: repository,
    userId: currentUser.uid,
    now: () => DateTime.now(),
    userRepository: userRepository,
  );

  // ✅ 초기화 완료까지 대기
  await manager.initialise();

  // dispose 시 정리
  ref.onDispose(() {
    print('AttendanceManager dispose 시작');
    manager.dispose();
    print('AttendanceManager dispose 완료');
  });

  return manager;
});
