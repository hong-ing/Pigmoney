import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pigmoney/core/utils/log/logger.dart';
import 'package:pigmoney/core/utils/pref/pref_util.dart';
import 'package:pigmoney/core/utils/device_id_helper.dart';
import 'package:pigmoney/core/ads/admob_service.dart';
import 'package:pigmoney/core/ads/admob_service2.dart';
import 'package:pigmoney/core/ads/admob_service_work.dart';
import 'package:pigmoney/core/ads/admob_service_auto_earn.dart';
import 'package:pigmoney/core/ads/admob_service_attendance_check.dart';

import '../../core/firebase/firebase_remote_config_service.dart';
import '../../data/order/model/order.dart';
import '../../data/order/order_repository.dart';
import '../../data/user/model/user.dart';
import '../../data/user/user_repository.dart';
import '../../data/gift_order/model/gift_order.dart';
import '../../data/gift_order/repository/gift_order_repository.dart';
import 'order_provider.dart';
import 'sync_loading_provider.dart';
import 'giftishow_provider.dart';

// 사용자 저장소 프로바이더
final userRepositoryProvider = Provider<UserRepository>((ref) {
  return UserRepository();
});

// 현재 로그인한 사용자 정보를 가져오는 프로바이더
final userDataProvider = FutureProvider.autoDispose<User?>((ref) async {
  final repository = ref.watch(userRepositoryProvider);
  final currentUser = await repository.getCurrentUser();
  return currentUser;
});

// 닉네임으로 사용자 정보를 가져오는 프로바이더
final userByNicknameProvider = FutureProvider.family<User?, String>((ref, nickname) async {
  if (nickname.isEmpty) return null;
  final repository = ref.watch(userRepositoryProvider);
  return await repository.getUserByNickname(nickname);
});

// 일별 적립 데이터 프로바이더
final dailyEarningsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  // Firebase Auth 상태 직접 체크
  final currentUser = fb.FirebaseAuth.instance.currentUser;
  if (currentUser == null) {
    print('dailyEarningsProvider: 로그인되지 않음 - 빈 배열 반환');
    return [];
  }

  final repository = ref.watch(userRepositoryProvider);
  return await repository.getDailyEarnings(currentUser.uid);
});

// 월별 적립 데이터 프로바이더
final monthlyEarningsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  // Firebase Auth 상태 직접 체크
  final currentUser = fb.FirebaseAuth.instance.currentUser;
  if (currentUser == null) {
    print('monthlyEarningsProvider: 로그인되지 않음 - 빈 배열 반환');
    return [];
  }

  final repository = ref.watch(userRepositoryProvider);
  return await repository.getMonthlyEarnings(currentUser.uid);
});

// 일별 랭킹 데이터 프로바이더
final dailyRankingsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  // Firebase Auth 상태 직접 체크
  final currentUser = fb.FirebaseAuth.instance.currentUser;
  if (currentUser == null) {
    print('dailyRankingsProvider: 로그인되지 않음 - 빈 배열 반환');
    return [];
  }

  final repository = ref.watch(userRepositoryProvider);
  return await repository.getDailyRankings();
});

// 월별 랭킹 데이터 프로바이더
final monthlyRankingsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  // Firebase Auth 상태 직접 체크
  final currentUser = fb.FirebaseAuth.instance.currentUser;
  if (currentUser == null) {
    print('monthlyRankingsProvider: 로그인되지 않음 - 빈 배열 반환');
    return [];
  }

  final repository = ref.watch(userRepositoryProvider);
  return await repository.getMonthlyRankings();
});

// 기프티콘 주문 저장소 프로바이더
final giftOrderRepositoryProvider = Provider<GiftOrderRepository>((ref) {
  // UserRepository를 주입받아서 사용
  final userRepository = ref.watch(userRepositoryProvider);
  return GiftOrderRepository(userRepository: userRepository);
});


final isOldUserProvider = Provider<bool>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return false;
  final remoteConfig = FirebaseRemoteConfigService.current;
  if (remoteConfig == null) return false;
  return user.joinDate.isBefore(remoteConfig.oldUserCutoffDate);
});

// 현재 로그인한 사용자 상태 프로바이더
final currentUserProvider = StateNotifierProvider<CurrentUserNotifier, User?>((ref) {
  return CurrentUserNotifier(
    ref.watch(userRepositoryProvider),
    ref.watch(orderRepositoryProvider),
    ref.watch(giftOrderRepositoryProvider),
    ref,
  );
});

class CurrentUserNotifier extends StateNotifier<User?> {
  final UserRepository _repository;
  final OrderRepository _orderRepository;
  final GiftOrderRepository _giftOrderRepository;
  final Ref _ref;

  CurrentUserNotifier(
    this._repository,
    this._orderRepository,
    this._giftOrderRepository,
    this._ref,
  ) : super(null) {
    // 생성자에서 사용자 정보 로드 시도 (자동 초기화)
    _initializeUser();
  }

  // 사용자 정보 초기화 (앱 시작 시 자동 호출됨)
  Future<void> _initializeUser() async {
    try {
      // Firebase Auth 상태를 먼저 확인
      final authUser = await fb.FirebaseAuth.instance.authStateChanges().first;
      if (authUser == null) {
        logger.d('Firebase Auth: 로그인되지 않음');
        state = null;
        return;
      }

      // 사용자 정보 로드 (캐시 사용 안함)
      final user = await _repository.getCurrentUser(forceRefresh: true);

      // ✅ 서버 데이터가 있으면 무조건 사용 (0이어도 정상일 수 있음)
      if (user != null) {
        state = user;
        logger.d('사용자 정보 자동 로드 (서버에서 강제): ${user.nickname}, 머니: ${user.money}');

        // 광고단위 분기 플래그 설정 (기존유저/신규유저)
        _applyOldUserToAds(user);

        // money가 0인 경우 경고만 출력
        if (user.money == 0) {
          logger.w('⚠️ 사용자 머니가 0입니다. 정상적인 상황일 수 있습니다.');
        }

        // deviceId 마이그레이션 - deviceId가 없으면 등록
        await _checkAndMigrateDeviceId(user);

        // 앱 버전 업데이트 (기존 유저 포함 - 매 실행 시)
        await _updateAppVersion(user);

        // 플랫폼(AOS/iOS) 백필 - 값 없을 때 1회만
        await _updatePlatform(user);
      } else {
        logger.d('사용자 정보를 가져올 수 없음');
        state = null;
      }
    } catch (e) {
      logger.e('사용자 정보 초기화 오류: $e');
      // ✅ 중요: 오류 시에도 기존 state 유지 (null로 설정하지 않음)
      if (state != null) {
        logger.w('네트워크 오류로 기존 사용자 데이터 유지');
      }
    }
  }

  /// 기존유저/신규유저에 따라 모든 광고 서비스의 광고단위를 분기 설정
  /// Why: 광고 단위 ID를 신규/기존 유저별로 분리 운영하기 위함
  /// How to apply: 사용자 로드 직후 매번 호출
  void _applyOldUserToAds(User user) {
    final remoteConfig = FirebaseRemoteConfigService.current;
    if (remoteConfig == null) return;

    // final isOldUser = user.joinDate.isBefore(remoteConfig.oldUserCutoffDate);
    admobService.setIsOldUser(false);
    admobService2.setIsOldUser(false);
    admobServiceWork.setIsOldUser(false);
    admobService3.setIsOldUser(false);
    admobService4.setIsOldUser(false);
  }

  // deviceId 마이그레이션 체크 및 실행
  Future<void> _checkAndMigrateDeviceId(User user) async {
    try {
      // 이미 deviceId가 등록되어 있으면 스킵
      if (user.deviceId.isNotEmpty) {
        logger.d('deviceId 이미 등록됨: ${user.deviceId}');
        return;
      }

      // 현재 기기의 deviceId 가져오기
      final currentDeviceId = await DeviceIdHelper.getDeviceId();
      if (!DeviceIdHelper.isValidDeviceId(currentDeviceId)) {
        logger.w('유효하지 않은 deviceId, 마이그레이션 스킵');
        return;
      }

      logger.d('deviceId 마이그레이션 필요 - 현재 기기: $currentDeviceId');

      // 서버에 deviceId 등록 요청
      final success = await _repository.migrateDeviceId(currentDeviceId);
      if (success) {
        // 로컬 상태 업데이트
        state = user.copyWith(deviceId: currentDeviceId);
        logger.d('deviceId 마이그레이션 완료');
      }
    } catch (e) {
      logger.e('deviceId 마이그레이션 체크 오류: $e');
      // 마이그레이션 실패해도 앱 동작에는 영향 없음
    }
  }

  // 앱 버전 업데이트 (기존 유저 포함 - 매 실행 시 자동)
  Future<void> _updateAppVersion(User user) async {
    try {
      final remoteConfig = FirebaseRemoteConfigService.current;
      if (remoteConfig == null) return;

      final currentVersion = remoteConfig.currentAppVersion;
      if (currentVersion.isEmpty) return;

      // 이미 동일한 버전이면 스킵
      if (user.appVersion == currentVersion) return;

      final success = await _repository.updateAppVersion(user.uid, currentVersion);
      if (success) {
        state = user.copyWith(appVersion: currentVersion);
        logger.d('앱 버전 업데이트 완료: $currentVersion');
      }
    } catch (e) {
      logger.e('앱 버전 업데이트 오류: $e');
    }
  }

  // 플랫폼(AOS/iOS) 백필 - 값이 없는 유저만 1회 기록 후 재호출 안함
  // Why: 유저별 OS 구분값 수집. 이미 값 있으면 트래픽 안 씀(서버 update 스킵)
  // How to apply: 사용자 로드 직후 _initializeUser에서 1회 호출
  Future<void> _updatePlatform(User user) async {
    try {
      // 이미 값이 있으면 스킵 (트래픽 절약)
      if (user.platform.isNotEmpty) return;

      final platform = Platform.isIOS ? 'iOS' : 'AOS';
      final success = await _repository.updatePlatform(user.uid, platform);
      if (success) {
        // deviceId/appVersion 등 직전 세션 갱신 보존 위해 최신 state 기준 copyWith
        state = (state ?? user).copyWith(platform: platform);
        logger.d('플랫폼 정보 백필 완료: $platform');
      }
    } catch (e) {
      logger.e('플랫폼 정보 백필 오류: $e');
    }
  }

  // 현재 로그인한 사용자 정보 가져오기 (명시적 호출 시)
  Future<void> fetchCurrentUser({bool forceRefresh = false}) async {
    final syncLoading = _ref.read(syncLoadingProvider.notifier);

    try {
      syncLoading.startLoading(message: '사용자 정보를 가져오는 중');

      final user = await _repository.getCurrentUser(forceRefresh: forceRefresh);

      // ✅ 서버 데이터를 신뢰하되, null인 경우만 처리
      if (user != null) {
        state = user;
        logger.d('사용자 정보 명시적 로드: ${user.nickname}, 머니: ${user.money}');

        // 광고단위 분기 플래그 설정 (기존유저/신규유저)
        _applyOldUserToAds(user);

        // money가 0인 경우 경고만 출력
        if (user.money == 0) {
          logger.w('⚠️ 사용자 머니가 0입니다. 정상적인 상황일 수 있습니다.');
        }
      } else {
        logger.e('사용자 정보를 가져올 수 없음');
        // 기존 state 유지
      }

      syncLoading.stopLoading();
    } catch (e) {
      logger.e('사용자 정보 가져오기 오류: $e');
      syncLoading.stopLoading();
      // ✅ 오류 시 기존 state 유지
    }
  }

  // 닉네임으로 사용자 정보 가져오기
  Future<User?> getUserByNickname(String nickname) async {
    try {
      return await _repository.getUserByNickname(nickname);
    } catch (e) {
      logger.e('닉네임으로 사용자 정보 가져오기 오류: $e');
      return null;
    }
  }

  // 사용자 데이터 전체 갱신 (데이터 동기화 필요시)
  Future<void> refreshUserData() async {
    if (state == null) {
      await fetchCurrentUser();
      return;
    }

    try {
      // 서버에서 강제로 최신 데이터 가져오기
      final updatedUser = await _repository.getUserByNickname(state!.nickname);
      if (updatedUser != null) {
        state = updatedUser;
        logger.d('사용자 데이터 갱신 완료: ${updatedUser.nickname}');
      }
    } catch (e) {
      logger.e('사용자 데이터 갱신 오류: $e');
    }
  }

  // 주문 내역 추가 - OrderRepository에 위임
  Future<bool> addOrderHistory(OrderHistory order) async {
    if (state == null) return false;

    try {
      // OrderRepository에 주문 추가 위임 (머니 차감 로직 포함)
      final success = await _orderRepository.addOrder(order);

      if (success) {
        // DB에서 실제 값을 가져오도록 변경
        await refreshUserData();

        // 디버그 로그 추가
        logger.d('🐷 PigMoney [DEBUG] 사용자 데이터 갱신 완료: ${state!.nickname}');
      }

      return success;
    } catch (e) {
      logger.e('주문 내역 추가 오류: $e');
      return false;
    }
  }

  // 주문번호로 최신 주문 정보 조회
  Future<OrderHistory?> getOrderByOrderNumber(String orderNumber) async {
    try {
      return await _repository.getOrderByOrderNumber(orderNumber);
    } catch (e) {
      logger.e('주문 정보 조회 오류: $e');
      return null;
    }
  }

  // 주문 취소 기능 - OrderRepository에 위임
  Future<bool> cancelOrder(String orderNumber) async {
    if (state == null) return false;

    try {
      // OrderRepository에 주문 취소 위임 (머니 환불 로직 포함)
      final success = await _orderRepository.deleteOrder(orderNumber);

      if (success) {
        // DB에서 실제 값을 가져오도록 변경
        await refreshUserData();

        // 디버그 로그 추가
        logger.d('🐷 PigMoney [DEBUG] 사용자 데이터 갱신 완료: ${state!.nickname}');
      }

      return success;
    } catch (e) {
      logger.e('주문 취소 오류: $e');
      return false;
    }
  }

  // 주문 내역 전체 조회
  List<OrderHistory> getOrderHistory() {
    return state?.orderHistory ?? [];
  }

  // 기프티콘 주문 내역 조회 (사용 여부 자동 검증 포함)
  Stream<List<GiftOrderHistory>> getGiftOrderHistory() {
    if (state == null) return Stream.value([]);

    return _giftOrderRepository.getUserGiftOrdersStream(state!.uid).asyncMap((orders) async {
      // 주문완료 상태이고 trId가 있는 기프티콘들만 검증
      final ordersToVerify = orders.where((order) => order.status == '구매완료' && order.trId != null && order.trId!.isNotEmpty).toList();

      if (ordersToVerify.isEmpty) {
        return orders;
      }

      // 병렬로 쿠폰 상태 검증
      final verificationTasks = ordersToVerify.map((order) async {
        try {
          final couponService = _ref.read(couponServiceProvider);
          final couponStatus = await couponService.getCouponStatus(order.trId!);

          // 사용 완료 상태인지 확인
          if (couponStatus != null && couponStatus.displayName == '교환(사용완료)') {
            // 서버에 사용 완료 상태 업데이트
            await _giftOrderRepository.updateGiftOrderStatus(state!.uid, order.orderId, '사용완료');
            return order.copyWith(status: '사용완료');
          }
          return order;
        } catch (e) {
          // API 에러 시 기존 주문 그대로 반환
          logger.e('쿠폰 상태 검증 실패 (${order.orderId}): $e');
          return order;
        }
      });

      // 모든 검증 작업 완료 대기
      final verifiedOrders = await Future.wait(verificationTasks);

      // 검증되지 않은 주문들과 검증된 주문들 합치기
      final result = <GiftOrderHistory>[];
      final verifiedOrderIds = verifiedOrders.map((o) => o.orderId).toSet();

      for (final order in orders) {
        if (verifiedOrderIds.contains(order.orderId)) {
          final verifiedOrder = verifiedOrders.firstWhere((o) => o.orderId == order.orderId);
          result.add(verifiedOrder);
        } else {
          result.add(order);
        }
      }

      return result;
    });
  }

  // 기프티콘 주문 추가
  Future<String?> addGiftOrder(GiftOrderHistory order) async {
    try {
      return await _giftOrderRepository.createGiftOrder(order);
    } catch (e) {
      logger.e('기프티콘 주문 추가 오류: $e');
      return null;
    }
  }

  // 사용자 데이터 초기화 (로그아웃 시 사용) - 간소화된 버전
  Future<void> clearUserData() async {
    try {
      logger.d('사용자 데이터 초기화 시작');

      // 1. UserRepository의 캐시 정리 (Firebase 관련
      await _repository.clearCachedUserData();

      // 2. SharedPreferences 클리어
      await PrefUtil.clear();

      // 3. 현재 사용자 상태를 null로 설정
      state = null;

      logger.d('사용자 상태가 초기화되었습니다 (로그아웃)');
    } catch (e) {
      logger.e('사용자 데이터 초기화 중 오류: $e');
      // 오류가 발생해도 최소한 상태는 초기화
      state = null;
    }
  }

  // 회원 탈퇴 - 모든 사용자 데이터 삭제 (개선된 버전)
  Future<bool> deleteAccount(String password) async {
    if (state == null) return false;

    try {
      logger.d('회원 탈퇴 시작: ${state!.nickname}');

      // UserRepository의 deleteAccount 메서드 호출
      final success = await _repository.deleteAccount(password);

      if (success) {
        await PrefUtil.clear();
        state = null;

        logger.d('회원 탈퇴 성공 및 모든 상태 초기화 완료');
      } else {
        logger.e('회원 탈퇴 실패');
      }

      return success;
    } catch (e) {
      logger.e('회원 탈퇴 프로바이더 오류: $e');
      // 오류가 발생해도 최소한 로컬 상태는 초기화
      if (state != null) {
        await PrefUtil.clear();
        state = null;
      }
      return false;
    }
  }
}
