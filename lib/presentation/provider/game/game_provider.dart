import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pigmoney/presentation/game/model/coin.dart';
import 'package:pigmoney/presentation/provider/settings_provider.dart';
import 'package:pigmoney/presentation/provider/sync_loading_provider.dart';
import 'package:pigmoney/presentation/provider/user_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';

import '../../../../core/ads/admob_service.dart';
import '../../../core/services/bgm_service.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/utils/korean_time_utils.dart';
import '../../../core/utils/new_user_ad_utils.dart';
import '../../../core/utils/notification_service.dart';
import 'game_state.dart';

// game_provider.dart를 export로 사용할 수 있게 함
export 'game_provider.dart' show GameNotifier;

// ✅ 자동적립 리셋 정보를 담는 클래스
class AutoEarnResetInfo {
  final bool needsReset;
  final String reason;

  AutoEarnResetInfo({required this.needsReset, required this.reason});
}

// 전역 GameNotifier 참조 - admob_service에서 접근하기 위함
GameNotifier? globalGameNotifierRef;

class GameNotifier extends StateNotifier<GameState> {
  final Ref _ref;
  final Random _random = Random();
  Timer? _slotMachineTimer;
  Timer? _collectValueTimer;
  Timer? _cooldownTimer;

  // 🧪 테스트용 설정 - 실제 배포 시에는 false로 설정
  static const bool _isTestMode = false; // ← 테스트할 때는 true로 변경

  // 🧲 자석 버프 기능 스위치 (끄려면 false로만 변경, 버튼 표시 여부도 함께 제어됨)
  static const bool magnetBuffEnabled = true;
  static const int _magnetModeDurationSeconds = 30; // 자석 모드 지속 시간 (초)
  static const int _magnetCooldownSeconds = 600; // 발동 종료 후 쿨타임 (10분)
  static const String _magnetLastEndTimeKey = 'lastMagnetModeEndTime';
  static const String _magnetBuffOwnedKey = 'magnetBuffOwned';
  Timer? _magnetModeTimer;
  Timer? _magnetCooldownTimer;

  // 💣 폭탄 버프 기능 스위치 (끄려면 false로만 변경, 버튼 표시 여부도 함께 제어됨)
  static const bool bombBuffEnabled = true;
  static const int _bombGaugeMax = 100; // 게이지 최대값 (동전 100개 적립 시 발동 가능)
  static const String _bombGaugeKey = 'bombGaugeRemaining';
  // 폭탄으로 쓸어담은 동전 id (게이지 감소 제외용)
  final Set<String> _bombSweptCoinIds = {};

  // 🪙 바닥에 항상 유지되는 동전 개수
  static const int _maxFloorCoins = 10;

  // 🌅 로드 경로(_loadGameStateFromPrefs)에서 일일 리셋이 적용됐는지 표시.
  //    앱 재실행 리셋은 _checkServerResetOnceOnInit을 타지 않아(세션=서버) 폭탄 게이지가 남으므로,
  //    _initialize에서 이 플래그를 보고 폭탄 게이지를 마저 초기화한다.
  bool _dailyResetAppliedInLoad = false;

  // BGM은 BgmService 싱글톤에서 관리 (화면 전환 시에도 재생 위치 유지)
  final AudioPlayer _depositPlayer = AudioPlayer();
  final AudioCache _sfxCoinCache = AudioCache(prefix: 'audio/');
  List<AudioPlayer> _audioPlayerPool = [];
  int _currentPlayerIndex = 0;
  bool _isDepositPlaying = false;

  // 사운드 재생용 AudioPlayer 추가
  final AudioPlayer _refillSoundPlayer = AudioPlayer();
  final AudioPlayer _pigTouchSoundPlayer = AudioPlayer();
  bool _isRefillSoundPlaying = false;

  // 💣 폭발음 재생용 AudioPlayer
  final AudioPlayer _bombExplosionPlayer = AudioPlayer();
  // 🧲 자석 모드 반복 사운드용 AudioPlayer (활성화 동안 loop 재생)
  final AudioPlayer _magnetLoopPlayer = AudioPlayer();

  // 콜백 함수 정의
  Function(Coin)? onStartCoinAnimation;

  /// 🧲 자석으로 딸려가는 동전 전용 수집 애니메이션 콜백
  /// (magnetCoin: 딸려가는 동전, towardPosition: 먼저 터치한 동전의 위치)
  void Function(Coin magnetCoin, Offset towardPosition)? onStartMagnetCoinAnimation;
  Function(Coin)? onStartDropAnimation; // 낙하 애니메이션용
  Function(Coin)? onStartBombScatterAnimation; // 💣 폭탄 흩뿌림→수집 애니메이션용
  Function()? onBombFlash; // 💣 폭탄 발동 시 화면 플래시용

  // 리필 관련 콜백 함수 추가
  Function(int count, Future<bool> Function(int) callback)? onShowRefillConfirm;

  // 자동 적립 관련 이벤트 콜백
  Function(int level, String pigName)? onLevelUp;
  Function()? onNewDayStart;
  Function()? onAutoEarnCompleteMessage;

  // ✅ 광고 로딩 실패 시 스낵바 콜백 추가
  Function(String message)? onShowAdLoadingSnackBar;

  // ✅ 광고 로딩 다이얼로그 콜백 추가
  Function()? onShowAdLoadingDialog;
  Function()? onHideAdLoadingDialog;

  // ✅ tempMoney 가득 참 다이얼로그 콜백 추가
  Function()? onShowTempMoneyFullDialog;

  // ✅ tempMoney 수령 시 보상 선택 다이얼로그 콜백 (1배 vs 2배 광고)
  Function(int tempMoneyAmount, VoidCallback onCollectNormal, VoidCallback onCollectWithAd)? onShowTempMoneyRewardSelectionDialog;

  // ✅ 400개 동전 수집 시 전면광고 준비 다이얼로그 콜백 추가 (레거시)
  Function(String message, VoidCallback onComplete)? onShowCoinAdPreparationDialog;

  // ✅ 머니톡톡 리필 다이얼로그 콜백 (1-2회차: 3초, 3-10회차: 10초)
  Function({
    required int durationSeconds,
    required bool hasAd,
    int? adTriggerSeconds,
    VoidCallback? onAdTrigger,
    required VoidCallback onComplete,
    VoidCallback? onCancelled,
  })?
  onShowRefillLoadingDialog;

  // ✅ 리필 취소 팝업 콜백
  VoidCallback? onShowRefillCancelledDialog;

  // 광고 표시 상태 관리 메서드
  void setAdShowingState(bool isShowing) {
    state = state.copyWith(isShowingAd: isShowing);
  }

  // dispose 여부를 추적하는 변수 추가
  bool _isDisposed = false;
  bool _isNotifierDisposed = false;

  // 리필 관련 타이머 추가
  Timer? _coinsFillTimer;

  // 📦 luckyBagCount 서버 저장 보강 (초기화 버그 대응)
  // - 동전 소비로 값이 줄 때마다 디바운스로 서버에 반영해, 저장 누락 시에도 손실을 수 초로 제한
  // - _lastSyncedLuckyBagCount: 마지막으로 '서버에 반영된 것이 확인된' 값 (쓰기 중복 방지용)
  //   서버 권위 구조는 그대로 유지되며, 이 값은 저장 여부 판단에만 사용됨
  Timer? _bagSaveDebounceTimer;
  static const int _bagSaveDebounceMs = 4000; // 4초: 연타 구간을 한 번의 쓰기로 묶는 최소 주기
  int? _lastSyncedLuckyBagCount;
  bool _isSavingBag = false; // luckyBagCount 저장 진행 중 (중복 실행 방지)

  // 🎯 백그라운드 충전 문제 해결을 위한 시간 기반 계산
  DateTime? _fillStartTime;

  // 타이머 일시정지/재개 플래그
  bool _isPausedTimerForDialog = false;

  // 💾 스마트 저장 관련 변수들 추가
  Timer? _saveDebounceTimer;
  bool _isSaving = false;

  // 🔒 리필 작업 중 플래그 - 서버 동기화 충돌 방지
  bool _isRefilling = false;

  // 🚫 리필 광고 취소 플래그 - 백그라운드 전환 시 광고 차단용
  bool _refillAdCancelled = false;

  bool get isRefilling => _isRefilling; // 외부에서 리필 상태 확인용

  static const int _saveDebounceMs = 800; // 1초 디바운싱

  // ✅ 전면광고용 동전 수집 카운트 (400개마다 전면광고)
  int _coinCollectCountForAd = 0;
  static const int _coinAdThreshold = 200; // 전면광고 트리거 임계값
  // 리필 50회 시스템: 현재 회차 = 51 - 남은 횟수
  final int _maxRefillCount = 51;

  // 🎯 1사이클 = 15회. 리필 개수 / 확률밴드 / 광고 / 지갑 진행도가 모두 이 단위로 통일됨.
  static const int cycleSize = 15;

  // [1] 무한 리필 순환 (끄려면 false로만 변경)
  // 서버 시드(50)는 그대로 두고, 3사이클(31~45회차)을 무한 반복.
  // 45회차 리필 시 46이 아니라 31회차(rewardRefillCount=20)로 되돌림.
  // → 순환 구간은 항상 3사이클(금2%/은36%/동62%) · 20초당 +1 속도를 유지.
  // rewardRefillCount는 항상 6~50 범위(round 31~45 ↔ count 20~6)라 서버 상한(50)/리셋과 충돌 없음.
  static const bool _refillCycleEnabled = true;
  static const int _cycleBandStart = 31; // 순환 구간 시작 회차
  static const int _cycleBandEnd = 45; // 순환 구간 끝 회차 (다음은 31로 복귀)

  // 🎉 사이클 완주 시스템 스위치 (끄려면 false로만 변경)
  // 리필 회차 15/30/45 도달 시 완주 모달 → 보상 받고 종료 or 계속 진행
  // (순환으로 45에 재도달해도 cycleShown 키가 이미 true라 3사이클까지만 표시됨)
  static const bool cycleSystemEnabled = true;
  static const List<int> _cycleRounds = [15, 30, 45]; // 사이클 완주 회차
  static const int _cycleBonusAmount = 10000; // 완주 보상 머니

  /// 회차 → 사이클 내 순서(1~15). 1회차→1, 15회차→15, 16회차→1, 31회차→1 ...
  static int cyclePositionOf(int round) => ((round - 1) % cycleSize) + 1;

  /// [4] 전면광고 판정 — 사이클 내 순서 기준.
  /// 1·2번째는 광고 없음, 3번째부터 격회(퐁당퐁당)로 광고: 사이클 내 3,5,7,9,11,13,15번째.
  static bool isInterstitialRound(int round) {
    final int pos = cyclePositionOf(round);
    return pos >= 3 && pos.isOdd;
  }
  static const String _cycleShownKeyPrefix = 'cycleShown_'; // + round_gameDate
  // 표시 보류 중인 완주 회차(15/30/45) - 백그라운드 전환 등으로 모달을 놓쳐도 진입 시 복구
  static const String _cyclePendingKeyPrefix = 'cyclePendingRound_'; // + gameDate
  static const String _cycleBonusGivenKeyPrefix = 'cycleBonusGiven_'; // + gameDate
  static const String _moneyTalkFinishedDateKey = 'moneyTalkFinishedDate'; // 종료한 게임날짜

  /// 🎉 사이클 완주 모달 표시 콜백 (cycleIndex: 1~3, todayTotal: 오늘 모은 머니, null이면 표시 생략)
  Function(int cycleIndex, int? todayTotal)? onShowCycleCompleteDialog;

  /// 오늘 머니톡톡을 종료했는지 확인 (게임 날짜 기준 - 날이 바뀌면 자동 해제)
  static Future<bool> isMoneyTalkFinishedToday() async {
    if (!cycleSystemEnabled) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      final finishedDate = prefs.getString(_moneyTalkFinishedDateKey);
      if (finishedDate == null) return false;
      // 저장된 날짜가 '오늘 게임날짜'와 다르면 자동으로 해제된 것으로 간주
      return finishedDate == KoreanTimeUtils.getCurrentGameDateKey();
    } catch (e) {
      print('🎉 머니톡톡 종료 상태 확인 오류: $e');
      return false;
    }
  }

  // ✅ 전면광고 준비 중 플래그 (중복 호출 방지)
  bool _isPreparingCoinAd = false;

  GameNotifier(this._ref) : super(const GameState()) {
    globalGameNotifierRef = this; // 전역 참조 설정
    _initialize();
    _setupConnectivityListener();
    _loadMagnetBuffState(); // 🧲 자석 버프 보유/쿨타임 상태 복원
    _loadBombBuffState(); // 💣 폭탄 게이지 상태 복원
    _loadMoneyTalkFinishedState(); // 🎉 오늘 머니톡톡 종료 여부 복원
    _preloadBombExplosionSound(); // 💣 폭발음 미리 로드 (재생 지연 방지)
  }

  Coin _generateRandomCoin(Offset position) {
    // [2] 사이클(15회) 단위 가변 확률 (1000분율). 회차 = _maxRefillCount - rewardRefillCount
    // roll < goldMax → 금, roll < silverMax → 은, 그 이상 → 동
    final int round = _maxRefillCount - state.rewardRefillCount;
    final int cycleNo = ((round - 1) ~/ cycleSize) + 1; // 1사이클→1, 2사이클→2, 3사이클 이후→3
    final int goldMax; // 금 경계 (1000분율)
    final int silverMax; // 은 경계 (금 다음 구간까지 누적)
    if (cycleNo <= 1) {
      goldMax = 40; // 금 4%
      silverMax = 440; // 은 40% (40+400)  → 동 56%
    } else if (cycleNo == 2) {
      goldMax = 30; // 금 3%
      silverMax = 410; // 은 38% (30+380)  → 동 59%
    } else {
      // 3사이클(31~45) 및 순환 구간 전체: 금2%/은36%/동62%로 고정
      goldMax = 20; // 금 2%
      silverMax = 380; // 은 36% (20+360)  → 동 62%
    }

    final int typeRoll = _random.nextInt(1000);
    CoinType type;
    int value;

    if (typeRoll < goldMax) {
      type = CoinType.gold;
      value = 100 + _random.nextInt(900);
    } else if (typeRoll < silverMax) {
      type = CoinType.silver;
      value = 10 + _random.nextInt(90);
    } else {
      type = CoinType.bronze;
      value = 1 + _random.nextInt(9);
    }

    return Coin(id: UniqueKey().toString(), type: type, value: value, position: position, animation: null);
  }

  // 연결 상태 변경 감지 및 자동 서버 동기화
  void _setupConnectivityListener() {
    _ref.listen<ConnectivityStatus>(connectivityStatusProvider, (previous, next) {
      // 오프라인에서 온라인으로 전환되었을 때
      if (previous == ConnectivityStatus.offline && next == ConnectivityStatus.online) {
        print('🌐 인터넷 연결 복구 감지 - 서버 동기화 시작');
        _syncPendingDataToServer();
      }
    });
  }

  // 대기 중인 데이터 서버 동기화
  Future<void> _syncPendingDataToServer() async {
    // 리필 중이거나 저장 중이면 건너뛰기
    if (_isRefilling || _isSaving) {
      print('⏳ 다른 작업 중 - 나중에 동기화 재시도');
      return;
    }

    try {
      print('💾 대기 중인 로컬 데이터 서버 동기화 시작');

      // 로컬 데이터가 있으면 서버에 저장
      await _flushEarningsToServer();

      print('✅ 서버 동기화 완료');
    } catch (e) {
      print('⚠️ 서버 동기화 실패 (다음 연결 시 재시도): $e');
    }
  }

  Future<void> flushEarnings() => _saveImmediately();

  // ✅ 크리티컬 버그 수정: 게임 상태를 유지하면서 서버 데이터만 동기화
  Future<void> syncWithServerData() async {
    // 🔒 리필 작업 중이면 서버 동기화 건너뛰기
    if (_isRefilling) {
      print('🔒 리필 작업 중 - 서버 동기화 건너뛰기');
      return;
    }

    final syncLoading = _ref.read(syncLoadingProvider.notifier);

    try {
      print('🔄 게임 상태 유지하며 서버 데이터 동기화 시작');
      syncLoading.startLoading(message: '게임 데이터를 동기화하는 중...');

      // 📦 [중요] 서버 값을 가져오기 전에 미저장 소비분을 먼저 반영한다.
      // 그래야 아래에서 서버 값으로 덮어써도 세션 진행분이 유실되지 않는다.
      await flushPendingLuckyBagSave();

      // 1. 사용자 데이터 새로고침 (서버에서 최신 정보 가져오기)
      syncLoading.updateMessage('사용자 정보를 가져오는 중');
      await _ref.read(currentUserProvider.notifier).fetchCurrentUser(forceRefresh: true);
      final user = _ref.read(currentUserProvider);

      if (user == null) {
        print('❌ 사용자 데이터 없음 - 동기화 실패');
        syncLoading.stopLoading();
        return;
      }

      // 2. 서버 데이터로 필요한 부분만 업데이트 (게임 상태는 보존)
      final currentTotalCash = state.totalCash;
      final serverMoney = user.money;

      // 리셋 버전이 변경되었는지 체크
      // 🛡️ sessionResetVersion이 null이면 '아직 로드 전'이라는 뜻이므로 리셋으로 오판하지 않는다.
      //    (노티파이어 재생성 직후 동기화가 먼저 도는 경우 세션 진행분이 날아가는 것 방지)
      if (state.sessionResetVersion == null) {
        // 🛡️ [수정] 세션 버전을 선점하지 않는다.
        //    (선점하면 로드/_checkServerResetOnceOnInit의 실제 리셋 적용이 스킵되어
        //     진짜 일일 리셋을 놓칠 수 있음 → 리셋 판정/버전 갱신은 로드 경로에 위임)
        print('🛡️ 세션 리셋버전 미설정 - 동기화에서는 리셋 판정/버전 선점 보류 (로드 경로가 처리)');
      } else if (state.sessionResetVersion != user.resetVersion) {
        // 새로운 리셋이 발생한 경우 - 서버 데이터로 완전히 초기화
        print('🌅 새로운 리셋 감지 - 서버 데이터로 초기화');
        print('  현재 세션: ${state.sessionResetVersion} vs 서버: ${user.resetVersion}');

        // 🔧 구함수 시드(5) → 50 승격 (세션 중 정상 리셋일 때만)
        final refillCount = state.sessionResetVersion != null
            ? await _migrateLegacyRefillSeed(user.rewardRefillCount, resetVersion: user.resetVersion)
            : user.rewardRefillCount;

        state = state.copyWith(
          luckyBagCount: user.luckyBagCount,
          rewardRefillCount: refillCount,
          totalCash: user.money,
          displayCash: user.money,
          sessionResetVersion: user.resetVersion,
          // 리셋 시 코인 상태도 초기화 (1회차 즉시 충전이므로 maxCoins만큼)
          currentCoins: _calculateMaxCoins(refillCount),
          maxCoins: _calculateMaxCoins(refillCount),
          fillSpeed: _calculateFillSpeed(refillCount),
          isFillingCoins: false,
          didInitCoins: false,
        );

        // 🔔 리셋 시 기존 '가득 참' 알림 취소
        NotificationService().cancelCoinPurseFullNotification();

        // 🔥 중요: 리셋 감지 시 로컬 캐시도 즉시 업데이트
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('luckyBagCount', user.luckyBagCount);
        await prefs.setInt('rewardRefillCount', refillCount);
        await prefs.setString('localResetVersion', user.resetVersion);
        // 🔥 코인 상태도 prefs에 저장 (게임 화면 진입 시 올바른 값 로드를 위해)
        await prefs.setInt('currentCoins', _calculateMaxCoins(refillCount));
        await prefs.setInt('maxCoins', _calculateMaxCoins(refillCount));
        await prefs.setBool('isFillingCoins', false);
        await prefs.setBool('isRightRefillFull', false); // 홈 펄스 플래그 초기화
        await prefs.remove('fillStartTime');
        print('💾 로컬 캐시 리셋 완료: 상자=${user.luckyBagCount}, 리필=$refillCount, 코인=${_calculateMaxCoins(refillCount)}');

        // 버튼 상태 업데이트
        _updateRefillButtonStates();

        print('✅ 리셋 완료 - 머니: ${serverMoney}, 코인: ${user.luckyBagCount}, 리필: $refillCount');
      } else {
        // 필요시에만 업데이트 (애니메이션 상태는 건드리지 않음)
        if (currentTotalCash != serverMoney ||
            state.luckyBagCount != user.luckyBagCount ||
            state.rewardRefillCount != user.rewardRefillCount) {
          state = state.copyWith(
            luckyBagCount: user.luckyBagCount,
            rewardRefillCount: user.rewardRefillCount,
            totalCash: serverMoney,
            displayCash: serverMoney,
            sessionResetVersion: user.resetVersion,
          );

          // 리필 관련 상태도 서버 데이터에 맞게 조정
          final newMaxCoins = _calculateMaxCoins(user.rewardRefillCount);
          final newFillSpeed = _calculateFillSpeed(user.rewardRefillCount);

          state = state.copyWith(
            maxCoins: newMaxCoins,
            fillSpeed: newFillSpeed,
          );

          // 버튼 상태 업데이트
          _updateRefillButtonStates();

          print('✅ 서버 데이터 동기화 완료 - 머니: $serverMoney, 코인: ${user.luckyBagCount}, 리필: ${user.rewardRefillCount}');
        } else {
          print('✅ 서버 데이터 동기화 - 변경사항 없음');
        }
      }
    } catch (e) {
      print('❌ 서버 데이터 동기화 중 오류: $e');
      syncLoading.stopLoading();
    } finally {
      // 정상적으로 완료된 경우에도 로딩 상태 정리
      if (syncLoading.isLoading) {
        syncLoading.stopLoading();
      }
    }
  }

  /// 💾 서버 저장 함수 - luckyBagCount, rewardRefillCount만 동기화
  /// ✅ 머니(money) 변경은 _claimTempMoneyInternal에서 addEarning으로 직접 처리
  /// ✅ 이 함수에서 money diff를 계산하여 보내면 외부 수입/지출과 충돌하여 머니 증발 버그 발생
  Future<void> _flushEarningsToServer() async {
    if (state.hasLoadError) return; // 로드 실패 상태에서는 저장 방지
    if (_isSaving) return; // 이미 저장 중이면 스킵

    final userRepo = _ref.read(userRepositoryProvider);
    final user = _ref.read(currentUserProvider);

    if (user == null) return;

    // ✅ totalCash를 항상 서버 값으로 동기화 (외부 수입/지출 반영)
    if (state.totalCash != user.money) {
      print('💾 totalCash 동기화: ${state.totalCash} → ${user.money} (외부 변경 반영)');
      state = state.copyWith(
        totalCash: user.money,
        displayCash: user.money,
      );
    }

    final bagChanged = state.luckyBagCount != user.luckyBagCount;
    final refillChanged = state.rewardRefillCount != user.rewardRefillCount;

    if (!bagChanged && !refillChanged) return; // 보낼 것 없음

    _isSaving = true;
    try {
      // ✅ amount는 항상 0 - money 변경은 _claimTempMoneyInternal에서 처리
      await userRepo.addEarning(
        amount: 0, // 동기화 전용 - amount 0이라 적립 기록 미생성
        luckyBagCount: bagChanged ? state.luckyBagCount : null,
        rewardRefillCount: refillChanged ? state.rewardRefillCount : null,
        source: 'moneyTalk',
      );
      if (bagChanged) _lastSyncedLuckyBagCount = state.luckyBagCount; // 📦 서버 반영 기준값 갱신
      print('💾 서버 저장: bag=$bagChanged(${state.luckyBagCount}), refill=$refillChanged(${state.rewardRefillCount})');

      // 서버 저장이 완료되었으므로 즉시 새로고침
      // 리필 중이 아닐 때만 새로고침 (리필 중에는 데이터 동기화 방지)
      if (!_isRefilling) {
        await _ref.read(currentUserProvider.notifier).refreshUserData();
        print('💾 서버 저장 후 데이터 새로고침 완료');
      } else {
        print('💾 리필 중 - 데이터 새로고침 건너뛰기');
      }
    } catch (e) {
      print('💾 서버 저장 오류 - 타입: ${e.runtimeType}, 메시지: $e');

      // 구체적인 오류 정보 로깅
      if (e.toString().contains('network')) {
        print('💾 네트워크 오류로 판단됨 - 나중에 재시도 필요');
      } else if (e.toString().contains('permission')) {
        print('💾 권한 오류로 판단됨 - 사용자 재인증 필요할 수 있음');
      }

      // 에러를 다시 던져서 상위에서 처리할 수 있도록 함
      rethrow;
    } finally {
      _isSaving = false;
    }
  }

  /// 💾 즉시 저장 (주요 액션 시 호출)
  Future<void> _saveImmediately() async {
    if (state.hasLoadError) return; // 로드 실패 상태에서는 저장 방지
    print('💾 즉시 저장 시작 - 디바운스 타이머 취소');
    _saveDebounceTimer?.cancel();

    try {
      await _flushEarningsToServer();
      print('💾 즉시 저장 완료');
    } catch (e) {
      print('💾 즉시 저장 중 오류: $e');
      rethrow; // 상위 호출자가 에러를 처리할 수 있도록 재발생
    }
  }

  /// 💰 레벨별 최대 tempMoney 한도 반환
  int _getMaxTempMoneyByLevel(int level) {
    switch (level) {
      case 1:
        return 10000;
      case 2:
        return 15000;
      case 3:
        return 20000;
      case 4:
        return 25000;
      case 5:
      case 6:
        return 30000;
      default:
        return 10000;
    }
  }

  /// 🔊 사운드만 디바운싱 (로컬 머니 시스템용)
  void _playSoundWithDebounce() {
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = Timer(Duration(milliseconds: _saveDebounceMs), () {
      if (!_isDisposed && !_isNotifierDisposed) {
        _playCoinDepositSound();
      }
    });
  }

  /// 💰 tempMoney 수령 요청 - 보상 선택 다이얼로그 표시
  void requestTempMoneyClaim() {
    if (state.tempMoney <= 0) {
      print('💰 적립할 머니가 없습니다');
      return;
    }

    // 1배 vs 2배 선택 다이얼로그 표시
    onShowTempMoneyRewardSelectionDialog?.call(
      state.tempMoney,
      () => _claimTempMoneyInternal(1), // 1배 수령
      () => _claimTempMoneyWithAd(), // 2배 수령 (광고)
    );
  }

  /// 💰 광고 없이 1배로 tempMoney 수령
  Future<bool> claimTempMoney() async {
    return await _claimTempMoneyInternal(1);
  }

  /// 💰 광고 보고 2배로 tempMoney 수령
  Future<void> _claimTempMoneyWithAd() async {
    if (state.tempMoney <= 0) return;

    state = state.copyWith(isShowingAd: true);
    bool adSuccess = false;

    onShowAdLoadingDialog?.call();

    admobService.loadAndShowRewardedAdWithFallback(
      (reward) {
        adSuccess = true;
      },
      onAdDismissed: () async {
        onHideAdLoadingDialog?.call();
        state = state.copyWith(isShowingAd: false);

        if (adSuccess) {
          // 광고 성공 시 적립 (기존/신규유저 모두 2배 — 다이얼로그 표시와 일치)
          await _claimTempMoneyInternal(2);

          // 🧲 광고 시청 성공 시 자석 버프 지급 (10분 쿨다운)
          await _grantMagnetBuffIfEligible();
        }
      },
      onAdFailedToShow: (error) {
        onHideAdLoadingDialog?.call();
        state = state.copyWith(isShowingAd: false);
        onShowAdLoadingSnackBar?.call('광고 로딩에 실패했습니다. 다시 시도해주세요.');
      },
    );
  }

  /// 🧲 앱 시작 시 자석 버프 보유/발동/쿨타임 상태 복원
  /// - 발동 종료 시각(발동 시작+30초)이 아직 미래면: 남은 시간만큼 자석 모드 재개
  /// - 이미 지났으면: 그 시각 기준으로 남은 쿨타임 계산
  Future<void> _loadMagnetBuffState() async {
    if (!magnetBuffEnabled) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      if (_isDisposed || _isNotifierDisposed) return;

      // 보유 상태 복원 (최대 1개)
      final owned = prefs.getBool(_magnetBuffOwnedKey) ?? false;

      final lastEndMillis = prefs.getInt(_magnetLastEndTimeKey) ?? 0;
      final nowMillis = DateTime.now().millisecondsSinceEpoch;

      if (lastEndMillis > nowMillis) {
        // 🔁 자석 발동(30초) 도중에 나갔다 돌아온 경우: 남은 시간만큼 이어서 재개
        final remainingActive = ((lastEndMillis - nowMillis) / 1000).ceil().clamp(1, _magnetModeDurationSeconds);
        state = state.copyWith(
          magnetBuffCount: owned ? 1 : 0,
          isMagnetModeActive: true,
          magnetRemainingSeconds: remainingActive,
        );
        _startMagnetModeTimer();
        _startMagnetLoopSound(); // 지지직 사운드도 재개
        print('🧲 자석 모드 재개: 남은 시간 $remainingActive초');
        return;
      }

      // 종료 시각 기준으로 남은 쿨타임 계산
      final elapsedSeconds = (nowMillis - lastEndMillis) ~/ 1000;
      final cooldownRemaining = (_magnetCooldownSeconds - elapsedSeconds).clamp(0, _magnetCooldownSeconds);

      state = state.copyWith(
        magnetBuffCount: owned ? 1 : 0,
        magnetCooldownRemainingSeconds: cooldownRemaining,
      );

      if (cooldownRemaining > 0) {
        _startMagnetCooldownTimer();
      }
      print('🧲 자석 상태 복원: 보유=$owned, 쿨타임 남은 시간=$cooldownRemaining초');
    } catch (e) {
      print('🧲 자석 상태 복원 에러: $e');
    }
  }

  /// 🧲 자석 버프 보유 상태 저장
  Future<void> _saveMagnetBuffOwned(bool owned) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_magnetBuffOwnedKey, owned);
    } catch (e) {
      print('🧲 자석 보유 상태 저장 에러: $e');
    }
  }

  /// 🧲 자석 버프 지급 (리워드 광고 시청 성공 시 호출)
  /// - 이미 보유 중이면 지급하지 않음 (최대 1개, 누적 불가)
  /// - 쿨타임(마지막 발동 종료 후 10분) 진행 중에는 지급하지 않음
  /// - 쿨타임 판정은 상태값이 아니라 SharedPreferences의 종료 시각 기준 (화면 이탈/재진입으로
  ///   상태가 초기화되어도 우회 불가)
  Future<void> _grantMagnetBuffIfEligible() async {
    if (!magnetBuffEnabled) return;
    if (_isDisposed || _isNotifierDisposed) return;
    if (state.magnetBuffCount >= 1) {
      print('🧲 이미 자석 보유 중 - 지급 생략');
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final lastEndMillis = prefs.getInt(_magnetLastEndTimeKey) ?? 0;
      final elapsedSeconds = (DateTime.now().millisecondsSinceEpoch - lastEndMillis) ~/ 1000;
      if (elapsedSeconds < _magnetCooldownSeconds) {
        print('🧲 쿨타임 진행 중(${_magnetCooldownSeconds - elapsedSeconds}초 남음) - 지급 생략');
        return;
      }
      if (_isDisposed || _isNotifierDisposed) return;

      state = state.copyWith(magnetBuffCount: 1);
      await _saveMagnetBuffOwned(true);
      print('🧲 자석 버프 지급!');
    } catch (e) {
      print('🧲 자석 버프 지급 에러: $e');
    }
  }

  /// 🧲 지금 광고를 보면 자석이 실제로 지급되는 상태인지 (2배 수집 다이얼로그 아이콘 표시용)
  /// 발동 중에는 지급 판정(종료 시각이 미래 → 쿨타임 취급)과 일치하도록 표시하지 않음
  bool get willGrantMagnetOnAd =>
      magnetBuffEnabled &&
      state.magnetBuffCount == 0 &&
      state.magnetCooldownRemainingSeconds == 0 &&
      !state.isMagnetModeActive;

  /// 🧲 자석 버프 발동 - 30초간 자석 모드 활성화
  void activateMagnetBuff() {
    if (!magnetBuffEnabled) return;
    if (_isDisposed || _isNotifierDisposed) return;
    if (state.magnetBuffCount <= 0) return;
    if (state.isMagnetModeActive) return; // 이미 활성화 중이면 중복 발동 방지
    if (state.magnetCooldownRemainingSeconds > 0) return; // 쿨타임 중에는 발동 불가

    state = state.copyWith(
      magnetBuffCount: 0, // 보유분 소모 (최대 1개)
      isMagnetModeActive: true,
      magnetRemainingSeconds: _magnetModeDurationSeconds,
    );
    _saveMagnetBuffOwned(false);

    // 🔒 악용 방지: 발동하는 순간 '예상 종료 시각(지금+30초)'을 미리 저장해둠.
    // 화면 이탈·강제 종료 등 어떤 이유로 30초가 중단되어도 쿨타임이 반드시 시작되도록 보장.
    // 정상 종료 시에는 _deactivateMagnetMode()가 실제 종료 시각으로 덮어씀.
    SharedPreferences.getInstance().then(
      (prefs) => prefs.setInt(
        _magnetLastEndTimeKey,
        DateTime.now().millisecondsSinceEpoch + _magnetModeDurationSeconds * 1000,
      ),
    );

    _startMagnetModeTimer();

    // 🔊 자석 모드 동안 지지직 사운드 반복 재생
    _startMagnetLoopSound();
    print('🧲 자석 모드 발동! (${_magnetModeDurationSeconds}초)');
  }

  /// 🧲 자석 모드 1초 카운트다운 타이머 (발동/재개 공용)
  void _startMagnetModeTimer() {
    _magnetModeTimer?.cancel();
    _magnetModeTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_isDisposed || _isNotifierDisposed) {
        timer.cancel();
        return;
      }
      final remaining = state.magnetRemainingSeconds - 1;
      if (remaining <= 0) {
        _deactivateMagnetMode();
      } else {
        state = state.copyWith(magnetRemainingSeconds: remaining);
      }
    });
  }

  /// 🧲 자석 모드 해제 - 종료 시점부터 10분 쿨타임 시작 (종료 시각은 로컬 저장)
  void _deactivateMagnetMode() {
    _magnetModeTimer?.cancel();
    _magnetModeTimer = null;
    _stopMagnetLoopSound(); // 🔊 자석 사운드 반드시 중지
    if (_isDisposed || _isNotifierDisposed) return;

    state = state.copyWith(
      isMagnetModeActive: false,
      magnetRemainingSeconds: 0,
      magnetCooldownRemainingSeconds: _magnetCooldownSeconds,
    );

    // 발동 종료 시각 저장 (앱 재시작해도 쿨타임 유지)
    SharedPreferences.getInstance().then((prefs) => prefs.setInt(_magnetLastEndTimeKey, DateTime.now().millisecondsSinceEpoch));

    _startMagnetCooldownTimer();
    print('🧲 자석 모드 해제 - 쿨타임 ${_magnetCooldownSeconds}초 시작');
  }

  /// 🧲 자석 쿨타임 카운트다운 타이머
  void _startMagnetCooldownTimer() {
    _magnetCooldownTimer?.cancel();
    _magnetCooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_isDisposed || _isNotifierDisposed) {
        timer.cancel();
        return;
      }
      final remaining = state.magnetCooldownRemainingSeconds - 1;
      if (remaining <= 0) {
        timer.cancel();
        _magnetCooldownTimer = null;
        state = state.copyWith(magnetCooldownRemainingSeconds: 0);
        print('🧲 자석 쿨타임 종료');
      } else {
        state = state.copyWith(magnetCooldownRemainingSeconds: remaining);
      }
    });
  }

  /// 🎉 사이클 완주 체크
  ///
  /// [completedRound] = '방금 다 쓴 회차'. 리필 완료 직후 소비한 회차를 넘긴다.
  ///   - 15회차를 다 쓰고 16회차로 넘어가는 시점 → 1사이클 완주
  ///   - 30회차를 다 쓰고 31회차로 넘어가는 시점 → 2사이클 완주
  ///   - 45회차를 다 쓰고 31회차로 '순환'하는 시점 → 3사이클 완주
  ///
  /// 결과 회차(round)로 판정하지 않는 이유: 30 완주 후와 45 완주 후가 둘 다 31회차라
  /// 구분이 불가능하다. 그래서 소비한 회차를 기준으로 판정한다.
  ///
  /// [completedRound]가 null이면(게임 진입 시 재확인) prefs에 남아 있는
  /// '표시 보류 중인 완주 회차'를 사용한다.
  Future<void> _checkCycleComplete({int? completedRound}) async {
    if (!cycleSystemEnabled) return;
    if (_isDisposed || _isNotifierDisposed) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final gameDate = KoreanTimeUtils.getCurrentGameDateKey();
      final pendingKey = '$_cyclePendingKeyPrefix$gameDate';

      int? round = completedRound;
      if (round != null) {
        if (!_cycleRounds.contains(round)) return; // 완주 회차가 아니면 무시
        // 아직 표시 못 한 완주를 기록해 둔다 (백그라운드 전환 등으로 유실돼도 진입 시 복구)
        await prefs.setInt(pendingKey, round);
      } else {
        // 진입 시 재확인: 보류 중인 완주가 있으면 그걸 표시
        round = prefs.getInt(pendingKey);
        if (round == null || !_cycleRounds.contains(round)) return;
      }

      final shownKey = '$_cycleShownKeyPrefix${round}_$gameDate';

      // 이미 오늘 본 사이클이면 다시 표시하지 않음 (회차 순환으로 재도달해도 1회만)
      if (prefs.getBool(shownKey) ?? false) {
        print('🎉 ${round}회차 사이클 모달 - 오늘 이미 표시함');
        await prefs.remove(pendingKey); // 보류 해제
        return;
      }

      // 🛡️ 콜백이 연결되지 않았으면(화면 미준비) 표시 이력을 남기지 않고 중단
      //    → 보류 기록(pendingKey)이 남아 있어 다음 진입/리필 때 다시 시도됨
      if (onShowCycleCompleteDialog == null) {
        print('🎉 ${round}회차 사이클 모달 - 콜백 미연결로 보류');
        return;
      }

      // 오늘 모은 머니 조회 (실패 시 null → 모달에서 해당 줄 생략)
      int? todayTotal;
      try {
        // 머니톡톡 적립분만 조회 (bySource.moneyTalk)
        todayTotal = await _ref.read(userRepositoryProvider).getTodayTotalEarnings(source: 'moneyTalk');
      } catch (e) {
        print('🎉 오늘 적립 합계 조회 실패 (생략): $e');
      }

      if (_isDisposed || _isNotifierDisposed) return;

      final cycleIndex = _cycleRounds.indexOf(round) + 1; // 1, 2, 3
      print('🎉 ${cycleIndex}사이클 완주! (${round}회차 사용 완료, 오늘 적립=$todayTotal)');
      onShowCycleCompleteDialog!.call(cycleIndex, todayTotal);

      // ✅ 실제로 모달을 띄운 뒤에 '오늘 표시함'으로 마킹 (중복 표시 방지) + 보류 해제
      await prefs.setBool(shownKey, true);
      await prefs.remove(pendingKey);
    } catch (e) {
      print('🎉 사이클 완주 체크 오류: $e');
    }
  }

  /// 🎉 앱/게임 진입 시 오늘 종료 여부 복원 (게임 날짜 기준이라 날이 바뀌면 자동 false)
  Future<void> _loadMoneyTalkFinishedState() async {
    if (!cycleSystemEnabled) return;
    try {
      final finished = await isMoneyTalkFinishedToday();
      if (_isDisposed || _isNotifierDisposed) return;
      if (finished != state.isMoneyTalkFinished) {
        state = state.copyWith(isMoneyTalkFinished: finished);
      }
      if (finished) {
        // 종료 상태로 진입한 경우: 충전 타이머가 돌지 않도록 확실히 정지
        _coinsFillTimer?.cancel();
        _coinsFillTimer = null;
        state = state.copyWith(isFillingCoins: false, clearFillSpeedText: true);
        print('🎉 오늘 머니톡톡 종료 상태로 진입 - 동전 배출/리필 차단');
      }
    } catch (e) {
      print('🎉 머니톡톡 종료 상태 복원 오류: $e');
    }
  }

  /// 🎉 '오늘은 여기까지' - 완주 보상 지급 + 오늘 머니톡톡 종료 처리
  /// 반환: 보상이 실제로 지급되었는지 여부
  Future<bool> finishTodayMoneyTalk() async {
    if (!cycleSystemEnabled) return false;

    bool bonusGiven = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      final gameDate = KoreanTimeUtils.getCurrentGameDateKey();

      // 1) 완주 보상 지급 (하루 1회만 - 중복 방지)
      final bonusKey = '$_cycleBonusGivenKeyPrefix$gameDate';
      if (!(prefs.getBool(bonusKey) ?? false)) {
        await prefs.setBool(bonusKey, true); // 먼저 마킹 (중복 호출 차단)
        try {
          await _ref.read(userRepositoryProvider).addEarning(
                amount: _cycleBonusAmount,
                source: 'cycleBonus',
              );
          bonusGiven = true;
          print('🎉 완주 보상 지급: $_cycleBonusAmount M');
        } catch (e) {
          // 지급 실패 시 마킹 해제 (다음 시도 가능하도록)
          await prefs.setBool(bonusKey, false);
          print('🎉 완주 보상 지급 실패: $e');
        }
      } else {
        print('🎉 완주 보상 - 오늘 이미 지급됨');
      }

      // 2) 지갑 자동 충전(리필) 타이머 정지 - 오늘은 더 이상 충전 안 됨
      _coinsFillTimer?.cancel();
      _coinsFillTimer = null;
      _fillStartTime = null;
      if (!_isDisposed && !_isNotifierDisposed) {
        state = state.copyWith(isFillingCoins: false, clearFillSpeedText: true);
      }
      await prefs.remove('fillStartTime');
      await prefs.remove('fillStartCoins');
      await prefs.setBool('isFillingCoins', false);
      await prefs.setBool('isRightRefillFull', false); // 홈 펄스 플래그도 해제
      print('🎉 지갑 자동 충전 정지');

      // 3) 지갑 충전 완료 로컬 알림 취소 (예약된 알림 제거)
      await NotificationService().cancelCoinPurseFullNotification();
      print('🎉 지갑 가득참 알림 취소');

      // 4) 오늘 종료 상태 저장 (게임 날짜 기준 - 날이 바뀌면 자동 해제)
      await prefs.setString(_moneyTalkFinishedDateKey, gameDate);
      if (!_isDisposed && !_isNotifierDisposed) {
        // 화면(빈 바닥 / '내일 다시 만나요' / 지갑 0·비활성)에 즉시 반영
        state = state.copyWith(isMoneyTalkFinished: true);
      }
      print('🎉 오늘($gameDate) 머니톡톡 종료 처리 완료');

      // 5) 최종 로컬 저장
      await _saveGameStateToPrefs();
    } catch (e) {
      print('🎉 머니톡톡 종료 처리 오류: $e');
    }
    return bonusGiven;
  }

  /// 💣 앱 시작 시 폭탄 게이지 상태 복원
  Future<void> _loadBombBuffState() async {
    if (!bombBuffEnabled) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      if (_isDisposed || _isNotifierDisposed) return;

      final gauge = prefs.getInt(_bombGaugeKey) ?? _bombGaugeMax;
      state = state.copyWith(bombGaugeRemaining: gauge.clamp(0, _bombGaugeMax));
      print('💣 폭탄 게이지 복원: $gauge');
    } catch (e) {
      print('💣 폭탄 게이지 복원 에러: $e');
    }
  }

  /// 💣 폭탄 버프 발동 - 바닥 동전 전부 한 번에 수집, 게이지 100으로 리셋
  void activateBombBuff() {
    if (!bombBuffEnabled) return;
    if (_isDisposed || _isNotifierDisposed) return;
    if (state.bombGaugeRemaining > 0) return; // 게이지가 다 차지 않으면 발동 불가

    // 이미 수집 중이 아닌 바닥 동전 전부 대상
    final coinsToSweep = state.floorCoins
        .where((c) => !state.selectedCoinIds.contains(c.id) && c.animationState != CoinAnimationState.collecting)
        .toList();
    if (coinsToSweep.isEmpty) return; // 쓸어담을 동전이 없으면 게이지 소모하지 않음

    // 게이지 먼저 100으로 리셋 + 쓸어담는 동전은 게이지 감소에서 제외되도록 표시
    final updatedSelectedIds = Set<String>.from(state.selectedCoinIds);
    for (final coin in coinsToSweep) {
      _bombSweptCoinIds.add(coin.id);
      updatedSelectedIds.add(coin.id);
    }
    state = state.copyWith(
      bombGaugeRemaining: _bombGaugeMax,
      selectedCoinIds: updatedSelectedIds,
    );

    // 💥 발동 연출: 폭발음을 가장 먼저 (흩뿌림 시작과 동시에 터지도록), 이어서 화면 플래시
    _playBombExplosionSound();
    onBombFlash?.call();

    // 전부 저금통으로 발사 (흩뿌림 연출이 연결되어 있으면 사용, 없으면 기본 수집 애니메이션)
    // 적립은 기존 handleAnimationEnd 경로 재사용
    for (final coin in coinsToSweep) {
      if (onStartBombScatterAnimation != null) {
        onStartBombScatterAnimation!.call(coin);
      } else {
        onStartCoinAnimation?.call(coin);
      }
    }

    _saveGameStateToPrefs();
    print('💣 폭탄 발동! ${coinsToSweep.length}개 동전 수집, 게이지 리셋');
  }

  /// 💣 폭발음 미리 로드 - 발동 순간 지연 없이 바로 터지도록
  /// (play() 시점에 파일을 로드하면 첫 재생이 한 박자 늦음)
  void _preloadBombExplosionSound() async {
    if (!bombBuffEnabled) return;
    try {
      await _bombExplosionPlayer.setPlayerMode(PlayerMode.lowLatency); // 짧은 효과음용 저지연 모드
      await _bombExplosionPlayer.setReleaseMode(ReleaseMode.stop); // 재생 후에도 소스 유지 (재사용)
      await _bombExplosionPlayer.setSource(AssetSource('audio/bomb_explosion.mp3'));
    } catch (e) {
      print('💣 폭발음 프리로드 오류: $e');
    }
  }

  /// 💣 폭발음 재생 (프리로드된 소스를 즉시 재생)
  void _playBombExplosionSound() async {
    try {
      final settings = _ref.read(settingsProvider);
      if (!settings.isSfxEnabled) return;
      await _bombExplosionPlayer.stop(); // 처음부터 재생되도록 리셋
      await _bombExplosionPlayer.resume();
    } catch (e) {
      print('💣 폭발음 재생 오류: $e');
    }
  }

  /// 🧲 자석 모드 반복 사운드 시작 (지지직 소리 loop)
  void _startMagnetLoopSound() async {
    try {
      final settings = _ref.read(settingsProvider);
      if (!settings.isSfxEnabled) return;
      await _magnetLoopPlayer.setReleaseMode(ReleaseMode.loop);
      await _magnetLoopPlayer.play(AssetSource('audio/magnet.mp3'));
    } catch (e) {
      print('🧲 자석 사운드 재생 오류: $e');
    }
  }

  /// 🧲 자석 모드 반복 사운드 중지
  void _stopMagnetLoopSound() {
    try {
      if (_magnetLoopPlayer.state != PlayerState.disposed) {
        _magnetLoopPlayer.stop();
      }
    } catch (e) {
      print('🧲 자석 사운드 중지 오류: $e');
    }
  }

  /// 🧲 터치한 동전과 가장 가까운 바닥 동전 찾기 (자석 모드용)
  Coin? _findNearestFloorCoin(Coin tappedCoin) {
    Coin? nearest;
    double nearestDistance = double.infinity;

    for (final coin in state.floorCoins) {
      if (coin.id == tappedCoin.id) continue;
      if (state.selectedCoinIds.contains(coin.id)) continue; // 이미 수집 중인 동전 제외
      if (coin.animationState != CoinAnimationState.none) continue;

      final distance = (coin.position - tappedCoin.position).distance;
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearest = coin;
      }
    }
    return nearest;
  }

  /// 💰 로컬 tempMoney를 서버로 전송 (오퍼월 방식)
  /// luckyBagCount도 함께 서버에 동기화
  /// [multiplier] - 배수 (1배 또는 2배)
  Future<bool> _claimTempMoneyInternal(int multiplier) async {
    if (state.hasLoadError) return false; // 로드 실패 상태에서는 저장 방지
    if (state.tempMoney <= 0) {
      print('💰 적립할 머니가 없습니다');
      return false;
    }

    if (_isSaving) {
      print('💰 이미 저장 중입니다');
      return false;
    }

    _isSaving = true; // 🔒 중복 호출 방지

    try {
      final claimAmount = state.tempMoney;
      final currentLuckyBagCount = state.luckyBagCount;
      print('💰 적립 시작: tempMoney=$claimAmount M, luckyBagCount=$currentLuckyBagCount');

      // ✅ 적립 전 서버 머니 확인 (검증용)
      final userBefore = _ref.read(currentUserProvider);
      final moneyBefore = userBefore?.money ?? 0;
      print('💰 적립 전 서버 머니: $moneyBefore M');

      // 사운드 재생
      final settings = _ref.read(settingsProvider);
      if (settings.isSfxEnabled) {
        await _depositPlayer.play(AssetSource('audio/pig_deposit_sound.mp3'));
      }

      // ✅ 서버에 저장 (tempMoney × multiplier + luckyBagCount 함께)
      final userRepo = _ref.read(userRepositoryProvider);
      final actualAmount = claimAmount * multiplier; // 배수 적용
      print('💰 적립 금액: $claimAmount × $multiplier = $actualAmount M');
      await userRepo.addEarning(
        amount: actualAmount,
        luckyBagCount: currentLuckyBagCount, // luckyBagCount도 함께 저장
        source: 'moneyTalk',
      );

      // ✅ 사용자 데이터 새로고침 (서버에서 강제로)
      await _ref.read(currentUserProvider.notifier).fetchCurrentUser(forceRefresh: true);
      final userAfter = _ref.read(currentUserProvider);

      // ✅ 서버 적립 검증: 실제로 머니가 증가했는지 확인
      if (userAfter == null) {
        print('💰 적립 실패: 서버에서 사용자 정보를 가져올 수 없음');
        return false;
      }

      final moneyAfter = userAfter.money;
      final actualIncrease = moneyAfter - moneyBefore;
      print('💰 적립 후 서버 머니: $moneyAfter M (증가량: $actualIncrease M)');

      // 검증: 적립 금액이 실제로 반영되었는지 확인
      // (다른 적립이 동시에 발생할 수 있으므로 >= 로 검증)
      if (actualIncrease < actualAmount) {
        print('💰 적립 검증 실패: 예상 증가량=$actualAmount M, 실제 증가량=$actualIncrease M');
        print('💰 tempMoney를 유지하고 롤백합니다');
        return false;
      }

      // ✅ 검증 성공: tempMoney 초기화 및 totalCash 서버 값으로 동기화
      state = state.copyWith(
        tempMoney: 0,
        totalCash: userAfter.money,
        displayCash: userAfter.money,
      );

      // ✅ SharedPreferences 업데이트
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('tempMoney', 0);
      await prefs.setInt('luckyBagCount', currentLuckyBagCount);

      print('💰 적립 완료 (검증됨): $claimAmount × $multiplier = $actualAmount M → 서버 머니: ${userAfter.money} M');
      return true;
    } catch (e) {
      print('💰 적립 중 오류: $e');
      // 에러 발생 시 tempMoney 유지 (롤백)
      return false;
    } finally {
      _isSaving = false; // 🔓 플래그 해제
    }
  }

  /// 📦 동전 소비 시 서버 저장 예약 (디바운스)
  /// 매 소비마다 쓰면 Firestore 비용이 폭증하므로 마지막 변경 후 4초 뒤 한 번만 저장한다.
  void _scheduleLuckyBagServerSave() {
    if (_isDisposed || _isNotifierDisposed) return;
    _bagSaveDebounceTimer?.cancel();
    _bagSaveDebounceTimer = Timer(const Duration(milliseconds: _bagSaveDebounceMs), () {
      _flushLuckyBagToServer();
    });
  }

  /// 📦 예약된 저장을 즉시 실행 (이탈/리셋/동기화 직전에 호출)
  Future<void> flushPendingLuckyBagSave() async {
    _bagSaveDebounceTimer?.cancel();
    _bagSaveDebounceTimer = null;
    await _flushLuckyBagToServer();
  }

  /// 📦 luckyBagCount 서버 저장 (재시도 포함)
  /// - 다른 저장/리필이 진행 중이면 '조용히 스킵'하지 않고 잠시 대기 후 재시도 → 저장 유실 방지
  /// - 서버 반영 확인된 값(_lastSyncedLuckyBagCount)과 비교해 불필요한 쓰기만 생략
  ///   (캐시된 user 값 비교는 stale일 때 오판 위험이 있어 사용하지 않음)
  Future<void> _flushLuckyBagToServer({int attempt = 0}) async {
    if (_isDisposed || _isNotifierDisposed) return;
    if (state.hasLoadError) return; // 로드 실패 상태에서는 저장 방지 (서버 값 훼손 방지)
    if (_isSavingBag) return; // 이미 저장 중이면 그 저장이 최신 값을 반영함

    // 🛡️ [리셋 가드] 서버 resetVersion이 클라가 반영한 세션 버전보다 최신이면
    //    = 일일 리셋이 아직 로컬에 반영되지 않은 상태이므로, 낡은 로컬 상자값으로
    //    리셋된 서버값(200)을 덮어쓰지 않도록 저장을 보류한다. (리셋 반영 후 재개)
    final resetGuardUser = _ref.read(currentUserProvider);
    if (resetGuardUser != null &&
        state.sessionResetVersion != resetGuardUser.resetVersion) {
      print('📦 리셋 미반영 상태(세션=${state.sessionResetVersion}, 서버=${resetGuardUser.resetVersion}) - 상자 저장 보류(덮어쓰기 방지)');
      return;
    }

    final int target = state.luckyBagCount;

    // 서버에 이미 반영된 값과 동일하면 쓰기 생략
    if (_lastSyncedLuckyBagCount != null && _lastSyncedLuckyBagCount == target) {
      return;
    }

    // 다른 저장/리필 진행 중 → 스킵하지 않고 대기 후 재시도 (최대 5회 ≈ 2.5초)
    if (_isSaving || _isRefilling) {
      if (attempt >= 5) {
        print('📦 저장 경합 지속 - 디바운스로 재예약');
        _scheduleLuckyBagServerSave();
        return;
      }
      await Future.delayed(const Duration(milliseconds: 500));
      return _flushLuckyBagToServer(attempt: attempt + 1);
    }

    _isSavingBag = true;
    try {
      final userRepo = _ref.read(userRepositoryProvider);
      await userRepo.addEarning(
        amount: 0, // 머니는 변경 없음 (동기화 전용)
        luckyBagCount: target,
        source: 'moneyTalk',
      );

      _lastSyncedLuckyBagCount = target;

      // 로컬 캐시도 함께 갱신 (표시/복구 보조용, 권위는 서버 유지)
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('luckyBagCount', target);

      print('✅ luckyBagCount 서버 저장 완료: $target');
    } catch (e) {
      print('⚠️ luckyBagCount 서버 저장 실패(시도 ${attempt + 1}): $e');
      // 네트워크 오류 등 → 지수 백오프로 재시도 (최대 3회)
      if (attempt < 3) {
        _isSavingBag = false;
        await Future.delayed(Duration(milliseconds: 800 * (attempt + 1)));
        return _flushLuckyBagToServer(attempt: attempt + 1);
      }
      // 최종 실패: _lastSyncedLuckyBagCount를 갱신하지 않아 다음 기회에 다시 시도됨
      _scheduleLuckyBagServerSave();
    } finally {
      _isSavingBag = false;
    }
  }

  /// 🚪 게임 화면 이탈 시 luckyBagCount를 서버에 저장
  /// (뒤로가기, 홈버튼, 앱 종료 등) - 대기 중인 디바운스 저장까지 즉시 반영
  Future<void> saveLuckyBagCountOnExit() async {
    await flushPendingLuckyBagSave();
  }

  Future<void> _initialize() async {
    try {
      // mounted 체크 추가
      if (!mounted) {
        print('GameNotifier가 이미 dispose됨 - 초기화 중단');
        return;
      }

      // 오디오 설정
      await _configureAudio();

      // mounted 체크
      if (!mounted) return;

      // 로컬 저장소에서 데이터 로드 (앱 실행 시 이미 메인 화면에서 서버 동기화 완료)
      await _loadGameStateFromPrefs();

      // mounted 체크
      if (!mounted) return;

      // ✅ 게임 시작 시간 기록 (리셋 체크용) - 한 번도 설정되지 않았을 때만
      await _ensureGameStartTime();

      // mounted 체크
      if (!mounted) return;

      // ✅ 게임 화면 진입 시 한 번만 리셋 체크 (타이머 방식 대신)
      await _checkServerResetOnceOnInit();

      // mounted 체크
      if (!mounted) return;

      // 💣 앱 재실행 경로에서 일일 리셋이 적용된 경우 폭탄 게이지도 초기화한다.
      //    (이 경로는 로드가 세션=서버로 맞춰버려 _checkServerResetOnceOnInit이 스킵되고,
      //     _loadBombBuffState는 전날 값을 복원하므로 여기서 확실히 덮어쓴다)
      if (_dailyResetAppliedInLoad) {
        _dailyResetAppliedInLoad = false;
        if (bombBuffEnabled && state.bombGaugeRemaining != _bombGaugeMax) {
          state = state.copyWith(bombGaugeRemaining: _bombGaugeMax);
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setInt(_bombGaugeKey, _bombGaugeMax);
          } catch (e) {
            print('💣 폭탄 게이지 리셋 저장 실패: $e');
          }
          print('💣 일일 리셋(앱 재실행 경로) - 폭탄 게이지 $_bombGaugeMax로 초기화');
        }
      }

      if (!mounted) return;

      // 설정에 따라 배경음악 재생
      final settings = _ref.read(settingsProvider);
      if (settings.isBgmEnabled) {
        playBackgroundMusic();
      }

      print('게임 초기화 완료 - 코인: ${state.luckyBagCount}개, 돈: ${state.totalCash}M');

      // mounted 체크 후 state 업데이트
      if (mounted) {
        state = state.copyWith(isLoading: false);
      }

      // 🎉 게임 진입 시 사이클 완주 모달 재확인 (표시 보류분 복구)
      //   리필 시점에 완주(15/30/45 소비)를 감지하면 prefs에 '보류' 기록을 남기므로,
      //   그때 모달을 못 띄웠어도(앱이 백그라운드로 감 / 콜백 미연결 등) 여기서 복구된다.
      //   보류가 없으면 아무 일도 하지 않는다.
      //   (콜백은 game_screen initState에서 이미 연결됨. 미연결이면 _checkCycleComplete가 다시 보류)
      await _checkCycleComplete();
    } catch (e) {
      print('게임 초기화 오류: $e');
      if (mounted) {
        state = state.copyWith(isLoading: false);
      }
    }
  }

  Future<void> _ensureGameStartTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // SharedPreferences에 gameStartTime이 없으면 새로 생성
      if (!prefs.containsKey('gameStartTime')) {
        final gameStartTime = DateTime.now();
        final koreanGameStartTime = KoreanTimeUtils.convertToKoreanTime(gameStartTime);
        await prefs.setString('gameStartTime', koreanGameStartTime.toIso8601String());

        // 상태에도 설정
        state = state.copyWith(gameStartTime: gameStartTime);
        print('🎮 앱 최초 실행 - 게임 시작 시간 기록: $gameStartTime');
      } else {
        // 이미 SharedPreferences에 있는 경우, 상태에 설정되지 않았으면 설정
        if (state.gameStartTime == null) {
          try {
            final koreanTime = DateTime.parse(prefs.getString('gameStartTime')!);
            final gameStartTime = koreanTime.toLocal();
            state = state.copyWith(gameStartTime: gameStartTime);
            print('🎮 기존 게임 시작 시간 복원: $gameStartTime');
          } catch (e) {
            print('🚨 게임 시작 시간 복원 실패: $e');
            // 복원 실패 시 새로 생성
            final gameStartTime = DateTime.now();
            final koreanGameStartTime = KoreanTimeUtils.convertToKoreanTime(gameStartTime);
            await prefs.setString('gameStartTime', koreanGameStartTime.toIso8601String());
            state = state.copyWith(gameStartTime: gameStartTime);
            print('🎮 게임 시작 시간 새로 생성: $gameStartTime');
          }
        }
      }
    } catch (e) {
      print('🚨 게임 시작 시간 보장 중 오류: $e');
    }
  }

  Future<void> _loadGameStateFromPrefs() async {
    try {
      print('데이터 로드 시작');
      final prefs = await SharedPreferences.getInstance();

      // 1. ✅ 항상 서버에서 최신 데이터 강제로 가져오기 (캐시 문제 해결)
      print('🔄 서버에서 최신 데이터 강제 새로고침...');
      await _ref.read(currentUserProvider.notifier).fetchCurrentUser(forceRefresh: true);
      final user = _ref.read(currentUserProvider);

      int savedLuckyBagCount = 0;
      int savedRewardRefillCount = 0;
      int savedCachedMoney = 0;
      String? serverResetVersion;

      if (user != null) {
        savedLuckyBagCount = user.luckyBagCount;
        _lastSyncedLuckyBagCount = user.luckyBagCount; // 📦 서버 반영 기준값 초기화
        savedRewardRefillCount = user.rewardRefillCount;
        savedCachedMoney = user.money;
        serverResetVersion = user.resetVersion;
        print('✅ 서버 데이터 로드 완료: 코인=$savedLuckyBagCount, 리필=$savedRewardRefillCount, 머니=$savedCachedMoney, 리셋버전=$serverResetVersion');
      } else {
        // 서버 연결 실패 시 게임 진입 불가
        print('🚨 서버 연결 실패 - 게임 진입 불가');
        state = state.copyWith(
          hasLoadError: true,
          isLoading: false,
        );
        return;
      }

      // 2. 서버에서 자동적립 레벨 가져오기 (서버 우선)
      int serverAutoEarnLevel = user?.autoEarnPigLevel ?? 1;
      int localAutoEarnLevel = prefs.getInt('currentAutoEarnLevel') ?? 1;

      // 서버 레벨이 0이면 처음 사용하는 것이므로 로컬 값 사용
      // 서버 레벨이 있으면 서버 값 우선
      int currentAutoEarnLevel = serverAutoEarnLevel > 0 ? serverAutoEarnLevel : localAutoEarnLevel;

      // 서버와 로컬이 다르면 로그 출력
      if (serverAutoEarnLevel > 0 && serverAutoEarnLevel != localAutoEarnLevel) {
        print('🔄 자동적립 레벨 서버 동기화: 로컬($localAutoEarnLevel) → 서버($serverAutoEarnLevel)');
      }
      int autoEarnMoney = prefs.getInt('autoEarnMoney') ?? 0;
      DateTime? autoEarnActiveStartTime;
      if (prefs.getString('autoEarnActiveStartTime') != null) {
        try {
          final koreanTime = DateTime.parse(prefs.getString('autoEarnActiveStartTime')!);
          autoEarnActiveStartTime = koreanTime.toLocal();
        } catch (e) {
          print('자동적립 시작 시간 파싱 오류: $e');
        }
      }
      int autoEarnActivatedDuration = prefs.getInt('autoEarnActivatedDuration') ?? 0;
      bool isAutoEarnActive = prefs.getBool('isAutoEarnActive') ?? false;
      bool isAutoEarnDoubleSpeed = prefs.getBool('isAutoEarnDoubleSpeed') ?? false;
      String? lastClaimedDate = prefs.getString('lastClaimedDate');

      // ✅ 로컬 tempMoney 로드
      int savedTempMoney = prefs.getInt('tempMoney') ?? 0;
      print('💰 로컬 tempMoney 로드: $savedTempMoney M');

      // ✅ 전면광고용 동전 수집 카운트 로드
      _coinCollectCountForAd = prefs.getInt('coinCollectCountForAd') ?? 0;
      print('🎯 전면광고용 동전 수집 카운트 로드: $_coinCollectCountForAd');

      // ✅ luckyBagCount는 항상 서버 값 사용 (게임 화면 이탈 시 서버에 저장됨)
      print('📦 서버 luckyBagCount 사용: $savedLuckyBagCount');

      // ✅ 추가: 게임 시작 시간 로드 (리셋 체크용)
      DateTime? gameStartTime;
      if (prefs.getString('gameStartTime') != null) {
        try {
          final koreanTime = DateTime.parse(prefs.getString('gameStartTime')!);
          gameStartTime = koreanTime.toLocal();
        } catch (e) {
          print('게임 시작 시간 파싱 오류: $e');
        }
      }

      int initialCurrentCoins = prefs.getInt('currentCoins') ?? 0;
      bool wasFillingCoins = prefs.getBool('isFillingCoins') ?? false;
      DateTime? fillStartTime;
      int fillStartCoins = 0;
      if (prefs.getString('fillStartTime') != null) {
        try {
          final fillStartTimeStr = prefs.getString('fillStartTime')!;
          fillStartTime = DateTime.parse(fillStartTimeStr);
          fillStartCoins = prefs.getInt('fillStartCoins') ?? 0;
          print('저장된 충전 시작 시간 복원: $fillStartTimeStr, 시작 코인: $fillStartCoins');
        } catch (e) {
          print('충전 시작 시간 파싱 오류: $e');
          fillStartTime = null;
        }
      }

      // ✅ 추가: 로컬에 저장된 이전 rewardRefillCount 로드
      int localRewardRefillCount = prefs.getInt('rewardRefillCount') ?? savedRewardRefillCount;

      // ✅ 서버 리셋 체크용 로컬 리셋버전 (승격 조건 판단에도 사용하므로 먼저 로드)
      String? localResetVersion = prefs.getString('localResetVersion');

      // 🔧 구함수 시드(5) → 50 승격 (서버 함수 미배포 상태 대비)
      //    허용: 정상 사용 이력(localResetVersion 있음 - 업데이트/일일리셋) 또는 오늘 가입한 신규 유저
      //    차단: 재설치(로컬 이력 없음 + 기존 가입자) - 소비 후 재설치로 리필 복구하는 악용 방지
      //    당일 중복 승격은 _migrateLegacyRefillSeed 내부 마킹으로 방지
      bool isJoinedToday = false;
      try {
        isJoinedToday = KoreanTimeUtils.isSameGameDay(
          KoreanTimeUtils.getNow(),
          KoreanTimeUtils.convertToKoreanTime(user.joinDate),
        );
      } catch (e) {
        print('🔧 가입일 확인 실패 (승격 조건에서 제외): $e');
      }
      if (localResetVersion != null || isJoinedToday) {
        final migrated = await _migrateLegacyRefillSeed(savedRewardRefillCount, resetVersion: serverResetVersion);
        if (migrated != savedRewardRefillCount) {
          savedRewardRefillCount = migrated;
          // 로컬 저장값도 구시드(5)면 함께 승격 (아래 '수동 변경 감지' 오탐 방지)
          if (localRewardRefillCount == 5) {
            localRewardRefillCount = migrated;
            await prefs.setInt('rewardRefillCount', migrated);
          }
        }
      } else if (serverResetVersion != null && serverResetVersion.isNotEmpty) {
        // 재설치/재로그인 첫 로드(로컬 이력 없음 + 기존 가입자): 승격 차단.
        // 이 로드가 localResetVersion을 새로 기록하므로, 마킹 없이는 같은 날
        // 화면 재진입 시 승격 게이트가 통과되어 버림 → 오늘 하루 전체를 봉인.
        await prefs.setString('refillSeedMigratedFor', serverResetVersion);
        print('🔧 재설치/재로그인 감지 - 오늘($serverResetVersion) 리필 시드 승격 봉인');
      }

      // ✅ [수정] 서버 리셋 여부를 먼저 판정 (리필 변경 처리보다 우선)
      // 진짜 일일 리셋에서는 refill도 항상 바뀌므로, 리셋을 리필변경보다 우선 처리해야
      // 리셋 분기(localResetVersion 갱신 + 상자값 반영)가 스킵되지 않는다.
      final bool isServerResetDetected = localResetVersion != serverResetVersion;
      bool resetAppliedInLoad = false;

      // ✅ 서버에서 rewardRefillCount를 수동으로 변경했는지 체크
      // 단, 서버 리셋인 경우는 아래 리셋 분기에서 통합 처리하므로 여기서는 제외
      bool isRefillCountChanged = localRewardRefillCount != savedRewardRefillCount;
      if (isRefillCountChanged && !isServerResetDetected) {
        print('🔧 서버 rewardRefillCount 변경 감지: 로컬($localRewardRefillCount) → 서버($savedRewardRefillCount)');

        // 서버의 새로운 회차 계산
        final newRound = _maxRefillCount - savedRewardRefillCount;
        final oldRound = _maxRefillCount - localRewardRefillCount;

        print('🔧 회차 변경: $oldRound회차 → $newRound회차');

        // 회차별 currentCoins 재설정
        if (newRound == 1) {
          // 1~2회차: 즉시 충전이므로 maxCoins로 설정
          initialCurrentCoins = _calculateMaxCoins(savedRewardRefillCount);
          print('🔧 즉시 충전 회차로 변경 - currentCoins를 maxCoins($initialCurrentCoins)로 설정');
        } else {
          // 7회차 이상: 점진적 충전이므로 0으로 설정
          initialCurrentCoins = 0;
          print('🔧 점진적 충전 회차로 변경 - currentCoins를 0으로 설정');
        }

        // 충전 상태 초기화
        wasFillingCoins = false;
        fillStartTime = null;
        _fillStartTime = null;

        print('🔧 서버 rewardRefillCount 변경 처리 완료');
      }

      // 3. ✅ [수정] 서버 리셋 반영 - refill 변경 여부와 무관하게 항상 적용
      if (isServerResetDetected) {
        resetAppliedInLoad = true;
        // 💣 이 경로(앱 재실행)로 리셋된 경우 _initialize에서 폭탄 게이지도 초기화하도록 표시
        _dailyResetAppliedInLoad = true;
        print('🌅 서버 리셋 감지: 로컬($localResetVersion) vs 서버($serverResetVersion)');
        print('🌅 서버 데이터로 완전 리셋: 상자=${savedLuckyBagCount}, 리필=${savedRewardRefillCount}');

        // 🔥 중요: 리셋 감지 시 로컬 캐시도 즉시 서버 값으로 업데이트
        await prefs.setInt('luckyBagCount', savedLuckyBagCount);
        await prefs.setInt('rewardRefillCount', savedRewardRefillCount);
        await prefs.setInt('cachedUserMoney', savedCachedMoney);
        await prefs.setBool('isRightRefillFull', false); // 홈 펄스 플래그 초기화
        // ✅ tempMoney는 리셋되지 않음 (사용자가 모아둔 로컬 머니 보존)
        print('💾 로컬 캐시 리셋 업데이트: 상자=${savedLuckyBagCount}, 리필=${savedRewardRefillCount}, tempMoney=${savedTempMoney} (유지)');

        // 현재 회차 계산
        final currentRound = _maxRefillCount - savedRewardRefillCount;

        // 회차별 currentCoins 설정
        if (currentRound == 1) {
          // 1~2회차: 즉시 충전이므로 maxCoins로 설정
          initialCurrentCoins = _calculateMaxCoins(savedRewardRefillCount);
          print('🌅 즉시 충전 회차($currentRound회차) - currentCoins를 maxCoins($initialCurrentCoins)로 설정');
        } else {
          // 7회차 이상: 점진적 충전이므로 0으로 설정
          initialCurrentCoins = 0;
          print('🌅 점진적 충전 회차($currentRound회차) - currentCoins를 0으로 설정');
        }

        wasFillingCoins = false;
        fillStartTime = null;
        _fillStartTime = null; // 타이머 시작 시간도 초기화

        // 로컬 리셋 버전 업데이트
        await prefs.setString('localResetVersion', serverResetVersion ?? '');
      }
      // ✅ luckyBagCount는 항상 서버 값 사용 (게임 화면 이탈 시 서버에 저장되므로)

      // 백그라운드 충전 계산 (서버 리셋과 무관하게 처리)
      if (!isServerResetDetected && wasFillingCoins && fillStartTime != null) {
        // 서버 리셋이 없을 때만 백그라운드 충전 계산
        final fillSpeedValue = _calculateFillSpeed(savedRewardRefillCount);
        final currentMaxCoins = _calculateMaxCoins(savedRewardRefillCount);

        if (fillSpeedValue > 0) {
          final now = DateTime.now();
          final elapsedSeconds = now.difference(fillStartTime).inSeconds;

          // 음수 방지 (시간 역전 방지)
          if (elapsedSeconds < 0) {
            print('⚠️ 경과 시간이 음수입니다. 충전 계산 건너뛰기');
            initialCurrentCoins = fillStartCoins; // 시작 코인 수로 초기화
          } else {
            // 🔥 시간 기반 정확한 계산: 시작 시간부터 현재까지의 총 코인 수
            int totalCoins = fillStartCoins + (elapsedSeconds / fillSpeedValue).floor();
            if (totalCoins > currentMaxCoins) {
              totalCoins = currentMaxCoins;
              wasFillingCoins = false; // 최대치 도달시 충전 완료
            }
            print(
              '🔥 백그라운드 복귀 후 시간기반 계산: 시작($fillStartCoins) + 경과(${(elapsedSeconds / fillSpeedValue).floor()}) = $totalCoins개 (경과시간: ${elapsedSeconds}초)',
            );
            print('충전 시작 시간: $fillStartTime, 현재 시간: $now');
            initialCurrentCoins = totalCoins;

            // 복원된 시작 시간을 현재 세션에 설정
            _fillStartTime = fillStartTime;
          }
        }
      }

      // 4. ✅ 자동적립 리셋 체크는 별도 함수에서 처리하므로 여기서는 제거
      print('🐷 자동적립 리셋 체크는 게임 화면 진입 시 별도로 처리됩니다.');

      // 5. 리필 관련 설정 계산
      final fillSpeedValue = _calculateFillSpeed(savedRewardRefillCount);
      final currentMaxCoins = _calculateMaxCoins(savedRewardRefillCount);
      // fillSpeedText 형식: 0.5초면 "0.5초당 +1", 1초 이상이면 "N초당 +1"
      final fillSpeedText = fillSpeedValue > 0 ? (fillSpeedValue < 1 ? "${fillSpeedValue}초당 +1" : "${fillSpeedValue.toInt()}초당 +1") : null;

      // ✅ 구버전(회차별 30-150개 시스템) prefs에서 복원된 코인이 새 maxCoins(50)를 넘으면 clamp
      if (initialCurrentCoins > currentMaxCoins) {
        print('⚠️ 구버전 코인 값 감지: $initialCurrentCoins → $currentMaxCoins로 조정');
        initialCurrentCoins = currentMaxCoins;
      }

      print("리필 설정 계산 - savedRewardRefillCount: $savedRewardRefillCount, currentMaxCoins: $currentMaxCoins, fillSpeed: $fillSpeedValue");

      bool savedDidInitCoins = prefs.getBool('didInitCoins') ?? false;

      // 6. 로컬 데이터에 바닥 코인 정보 가져오기
      List<String>? lastCoinsJson = prefs.getStringList('lastDroppedCoins');
      DateTime? savedRightRefillTime;
      if (prefs.getString('rightRefillNextAvailableTime') != null) {
        try {
          final koreanTime = DateTime.parse(prefs.getString('rightRefillNextAvailableTime')!);
          savedRightRefillTime = koreanTime.toLocal();
        } catch (e) {
          print('리필 쿨다운 시간 파싱 오류: $e');
        }
      }

      bool noCoinsInBag = savedLuckyBagCount <= 0;
      bool noCoinsOnFloor = (lastCoinsJson == null || lastCoinsJson.isEmpty);

      // 지갑이 비었고, 바닥에 코인이 없으며, 리필 횟수가 남아있을 때
      if (noCoinsInBag && noCoinsOnFloor && savedRewardRefillCount > 0) {
        int currentRound = _maxRefillCount - savedRewardRefillCount;
        print("초기화: 현재 ${currentRound}회차 (${savedRewardRefillCount}회 남음), 저장된 코인 $initialCurrentCoins개");
      }

      print("초기화 완료: rewardRefillCount=$savedRewardRefillCount, maxCoins=$currentMaxCoins, currentCoins=$initialCurrentCoins");

      // 7. 바닥 코인 복원
      List<Coin> restoredCoins = [];
      if (lastCoinsJson != null && lastCoinsJson.isNotEmpty) {
        try {
          final lastDroppedCoinsData = lastCoinsJson.map((s) => Map<String, dynamic>.from(jsonDecode(s))).toList();
          for (var coinData in lastDroppedCoinsData) {
            restoredCoins.add(
              Coin(
                id: coinData['id'],
                type: CoinType.values.byName(coinData['type']),
                value: coinData['value'],
                position: Offset(coinData['dx'], coinData['dy']),
              ),
            );
          }
          print('바닥 코인 ${restoredCoins.length}개 복원됨');
        } catch (e) {
          print('바닥 코인 복원 중 오류: $e');
        }
      }

      // 8. 상태 업데이트
      state = state.copyWith(
        luckyBagCount: savedLuckyBagCount,
        rewardRefillCount: savedRewardRefillCount,
        currentCoins: initialCurrentCoins,
        maxCoins: currentMaxCoins,
        fillSpeed: fillSpeedValue,
        fillSpeedText: fillSpeedText,
        isFillingCoins: wasFillingCoins,
        rightRefillNextAvailableTime: savedRightRefillTime,
        floorCoins: restoredCoins,
        totalCash: savedCachedMoney,
        displayCash: savedCachedMoney,
        // ✅ displayCash는 순수하게 서버 머니만 표시
        tempMoney: savedTempMoney,
        // ✅ 로컬 tempMoney 복원 (별도로 버튼에 표시)
        isLoading: false,
        currentAutoEarnLevel: currentAutoEarnLevel,
        autoEarnMoney: autoEarnMoney,
        autoEarnActiveStartTime: autoEarnActiveStartTime,
        autoEarnActivatedDuration: autoEarnActivatedDuration,
        isAutoEarnActive: isAutoEarnActive,
        isAutoEarnDoubleSpeed: isAutoEarnDoubleSpeed,
        lastClaimedDate: lastClaimedDate,
        didInitCoins: savedDidInitCoins,
        // 🛡️ [수정] 리셋을 실제로 적용했거나 이미 동기 상태일 때만 세션 버전 갱신.
        //    미적용인데 선점하면 _checkServerResetOnceOnInit이 안전 리셋(_performGameResetOnInit)을 스킵함.
        sessionResetVersion: (!isServerResetDetected || resetAppliedInLoad) ? serverResetVersion : state.sessionResetVersion,
        gameStartTime: gameStartTime, // ✅ 추가: 게임 시작 시간
      );

      // 10. 리필 상태 업데이트: 점진적 충전이 진행 중이면 타이머 시작
      if (savedRewardRefillCount > 0) {
        double fillSpeed = _calculateFillSpeed(savedRewardRefillCount);
        int currentRound = _maxRefillCount - savedRewardRefillCount;

        // 점진적 충전 단계인지 확인 (2회차 이상)
        if (fillSpeed > 0) {
          // 🔧 앱 재설치 또는 새로운 점진적 충전 시작 시나리오 처리
          // wasFillingCoins가 false여도 점진적 충전이 필요한 회차라면 자동으로 시작
          bool shouldStartFilling = false;

          if (wasFillingCoins && initialCurrentCoins < currentMaxCoins) {
            // 기존에 충전 중이었던 경우
            shouldStartFilling = true;
            print("기존 충전 복원: 현재=${initialCurrentCoins}, 최대=${currentMaxCoins}");
          } else if (!wasFillingCoins && initialCurrentCoins == 0 && currentRound >= 2) {
            // 앱 재설치 등으로 충전이 시작되지 않은 점진적 충전 회차
            shouldStartFilling = true;
            print("🔧 점진적 충전 자동 시작 필요: ${currentRound}회차, 현재=0, 최대=${currentMaxCoins}");
          }

          if (shouldStartFilling) {
            // fillSpeedText 형식: 0.5초면 "0.5초당 +1", 1초 이상이면 "N초당 +1"
            String fillSpeedTextStr = fillSpeed < 1 ? "${fillSpeed}초당 +1" : "${fillSpeed.toInt()}초당 +1";
            state = state.copyWith(
              isFillingCoins: true,
              fillSpeedText: fillSpeedTextStr,
              maxCoins: currentMaxCoins,
              fillSpeed: fillSpeed,
              currentCoins: initialCurrentCoins, // 현재 코인 수 확실히 설정
            );

            print("초기화 시 점진적 충전 타이머 시작: 속도=${fillSpeed}초당 1개, 현재=${initialCurrentCoins}, 최대=${currentMaxCoins}");

            // 복원된 fillStartTime이 있으면 사용, 없으면 새로 시작
            if (fillStartTime != null) {
              _fillStartTime = fillStartTime; // 복원된 시작 시간 사용
              print("백그라운드 복귀: 기존 충전 시작 시간 복원 $_fillStartTime");
            } else {
              _fillStartTime = DateTime.now(); // 새로운 충전 시작
              print("새로운 충전 시작: $_fillStartTime");
            }

            _startCoinFillingTimer(fillSpeed, currentMaxCoins, isNewCharge: fillStartTime == null); // 새로운 충전인지 여부 전달
          } else {
            // 타이머가 시작되지 않는 경우에도 maxCoins와 fillSpeed 상태를 올바르게 설정
            state = state.copyWith(
              maxCoins: currentMaxCoins,
              fillSpeed: fillSpeed,
            );
          }
        } else {
          // 즉시 충전 회차 (1회차)
          state = state.copyWith(
            maxCoins: currentMaxCoins,
            fillSpeed: fillSpeed,
          );
        }
      }

      // 11. 버튼 상태 업데이트
      _updateRefillButtonStates();

      // 12. 홈화면 애니메이션 플래그: 오른쪽 지갑이 이미 가득 찬 상태인지 체크
      if (initialCurrentCoins >= currentMaxCoins && currentMaxCoins > 0 && !wasFillingCoins) {
        SharedPreferences.getInstance().then((prefs) => prefs.setBool('isRightRefillFull', true));
      }

      print('게임 데이터 로드 완료: 코인=$savedLuckyBagCount, 리필=$savedRewardRefillCount, 머니=$savedCachedMoney');
    } catch (e) {
      print('❌ 게임 데이터 로드 오류: $e');
      // 오류 발생 시 기본값으로 덮어쓰지 않고 에러 상태만 설정
      state = state.copyWith(
        hasLoadError: true,
        isLoading: false,
      );
      print('❌ 데이터 로드 실패 - 에러 상태 설정 (기본값 저장 방지)');
    }
  }

  void setLayoutParams(Rect gameArea, Rect piggyBank, Rect rightUI, Rect pocketUI) {
    if (state.isInitialized) return;

    state = state.copyWith(
      isInitialized: true,
      gameArea: gameArea,
      piggyBankRect: piggyBank,
      rightUIRect: rightUI,
      pocketRect: pocketUI,
    );

    if (state.floorCoins.length < _maxFloorCoins && state.luckyBagCount > 0 && !state.didInitCoins) {
      final coinsToAdd = min(_maxFloorCoins - state.floorCoins.length, state.luckyBagCount);
      dropInitialCoins(coinsToAdd);
    }
  }

  Future<void> _saveGameStateToPrefs() async {
    if (_isNotifierDisposed) return;
    if (state.hasLoadError) return; // 로드 실패 상태에서는 저장 방지

    try {
      final prefs = await SharedPreferences.getInstance();

      // 마지막 저장 시간 기록 (이건 단순 로그용이므로 로컬 시간 유지)
      final now = DateTime.now();
      await prefs.setString('lastLocalSaveTime', now.toIso8601String());

      // ✅ 코인 충전 상태 저장 - 시간 기반 충전 시스템
      if (state.isFillingCoins && _fillStartTime != null) {
        await prefs.setString('fillStartTime', _fillStartTime!.toIso8601String());
        await prefs.setInt('fillStartCoins', 0); // 시작할 때 코인 수 (항상 0)
      } else {
        // 충전이 완료되었거나 충전 중이 아니면 저장된 시간 제거
        await prefs.remove('fillStartTime');
        await prefs.remove('fillStartCoins');
      }

      // 1. 핵심 게임 데이터 저장
      await prefs.setInt('luckyBagCount', state.luckyBagCount);
      await prefs.setInt('rewardRefillCount', state.rewardRefillCount);
      await prefs.setInt('currentCoins', state.currentCoins);
      await prefs.setInt('maxCoins', state.maxCoins);
      await prefs.setDouble('fillSpeed', state.fillSpeed);
      await prefs.setBool('isFillingCoins', state.isFillingCoins);
      await prefs.setBool('didInitCoins', state.didInitCoins);
      // ✅ 로컬 tempMoney 저장
      await prefs.setInt('tempMoney', state.tempMoney);
      // 💣 폭탄 게이지 저장
      await prefs.setInt(_bombGaugeKey, state.bombGaugeRemaining);
      if (state.fillSpeedText != null) {
        await prefs.setString('fillSpeedText', state.fillSpeedText!);
      } else {
        await prefs.remove('fillSpeedText');
      }

      // 2. 우측 리필 쿨다운 상태 저장
      if (state.rightRefillNextAvailableTime != null) {
        // ✅ 실제 쿨다운 시간을 한국시간으로 변환하여 저장
        final koreanTime = KoreanTimeUtils.convertToKoreanTime(state.rightRefillNextAvailableTime!);
        await prefs.setString('rightRefillNextAvailableTime', koreanTime.toIso8601String());
      }

      // 3. 자동적립 상태 저장
      await prefs.setInt('currentAutoEarnLevel', state.currentAutoEarnLevel);
      await prefs.setBool('isAutoEarnActive', state.isAutoEarnActive);
      await prefs.setInt('autoEarnActivatedDuration', state.autoEarnActivatedDuration);
      await prefs.setInt('autoEarnMoney', state.autoEarnMoney);
      await prefs.setBool('isAutoEarnDoubleSpeed', state.isAutoEarnDoubleSpeed);

      if (state.autoEarnActiveStartTime != null) {
        // ✅ 실제 시작 시간을 한국시간으로 변환하여 저장
        final koreanTime = KoreanTimeUtils.convertToKoreanTime(state.autoEarnActiveStartTime!);
        await prefs.setString('autoEarnActiveStartTime', koreanTime.toIso8601String());
      }

      // ✅ 추가: 게임 시작 시간 저장 (리셋 체크용)
      if (state.gameStartTime != null) {
        final koreanGameStartTime = KoreanTimeUtils.convertToKoreanTime(state.gameStartTime!);
        await prefs.setString('gameStartTime', koreanGameStartTime.toIso8601String());
      }

      // 4. 현재 머니 상태 저장
      await prefs.setInt('cachedUserMoney', state.totalCash);

      // 현재 세션의 리셋 버전 저장 (리셋 감지용)
      if (state.sessionResetVersion != null) {
        await prefs.setString('localResetVersion', state.sessionResetVersion!);
      }

      // 5. 바닥 코인 저장
      if (state.floorCoins.isNotEmpty) {
        List<String> currentFloorCoinsJson = state.floorCoins
            .map(
              (coin) => jsonEncode({
                'id': coin.id,
                'type': coin.type.name,
                'value': coin.value,
                'dx': coin.position.dx,
                'dy': coin.position.dy,
              }),
            )
            .toList();
        await prefs.setStringList('lastDroppedCoins', currentFloorCoinsJson);
      } else {
        await prefs.setStringList('lastDroppedCoins', []);
      }

      // ✅ 마지막 클레임 날짜 저장 (중복 제거됨)
      if (state.lastClaimedDate != null) {
        await prefs.setString('lastClaimedDate', state.lastClaimedDate!);
      }
    } catch (e) {
      print('로컬 저장 오류: $e');
    }
  }

  void dropInitialCoins(int count) {
    // 🎉 오늘 종료 상태여도 상자(luckyBagCount)에 남은 동전은 끝까지 사용 가능
    // (새 동전이 들어오는 '지갑 리필'만 차단됨)
    if (state.luckyBagCount <= 0 || !state.isInitialized) return;

    int coinsToDrop = min(count, state.luckyBagCount);
    List<Coin> newCoinsBatch = [];

    int attempts = 0;
    const int maxAttempts = 200; // 동전 10개 기준 (개수 증가에 맞춰 시도 횟수 확대)

    while (newCoinsBatch.length < coinsToDrop && attempts < maxAttempts) {
      attempts++;
      Offset pos = _getRandomSafePosition();

      if (_isPositionValid(pos, [...state.floorCoins, ...newCoinsBatch])) {
        final newCoin = _generateRandomCoin(pos)..animationState = CoinAnimationState.dropping;
        newCoinsBatch.add(newCoin);
      }
    }

    // 충분한 위치를 찾지 못했을 때 강제로 배치
    while (newCoinsBatch.length < coinsToDrop) {
      const double coinSize = 85.0;
      const double margin = 10.0;

      // 그리드 방식으로 균등하게 배치
      final int index = newCoinsBatch.length;
      final int cols = 3; // 3열로 배치
      final int row = index ~/ cols;
      final int col = index % cols;

      final double spacing = (state.gameArea.width - coinSize - 2 * margin) / (cols - 1);
      final double x = margin + coinSize / 2 + col * spacing;
      final double gridTop = state.pocketRect.bottom + 10.0;
      final double y = gridTop + row * (coinSize + 10);

      final pos = Offset(x, y);
      final newCoin = _generateRandomCoin(pos)..animationState = CoinAnimationState.dropping;
      newCoinsBatch.add(newCoin);
    }

    if (newCoinsBatch.isNotEmpty) {
      state = state.copyWith(
        floorCoins: [...state.floorCoins, ...newCoinsBatch],
        luckyBagCount: state.luckyBagCount - newCoinsBatch.length,
        didInitCoins: true,
      );
      _updateRefillButtonStates();
      _saveGameStateToPrefs();
      _scheduleLuckyBagServerSave(); // 📦 소비분 서버 반영 예약 (디바운스)

      for (final coin in newCoinsBatch) {
        onStartDropAnimation?.call(coin);
      }
    }
  }

  void handleDropAnimationEnd(Coin coin) {
    if (_isDisposed || _isNotifierDisposed) return;
    try {
      if (!state.floorCoins.any((c) => c.id == coin.id)) return;
      final updatedCoins = state.floorCoins.map((c) {
        if (c.id == coin.id) {
          c.animationState = CoinAnimationState.none;
          c.animation = null;
        }
        return c;
      }).toList();
      state = state.copyWith(
        floorCoins: updatedCoins,
        clearSelectedCoinIds: true,
      );
    } catch (e) {
      print('handleDropAnimationEnd 에러: $e');
    }
  }

  Offset _getRandomSafePosition() {
    if (!state.isInitialized) return Offset.zero;

    const double coinSize = 85.0;

    // 실제 위젯 위치 기반 동적 안전 영역 (기기/설정 무관)
    final double safeAreaLeft = 0;
    final double safeAreaRight = state.gameArea.width - coinSize;
    // 상단: 상자(pocketRect) 바로 아래 또는 gameArea.top 중 더 아래쪽 값 사용
    // (gameArea.top 을 높여서 동전이 너무 위로 올라가지 않도록 제어 가능)
    final double safeAreaTop = max(state.pocketRect.bottom - coinSize * 0.5, state.gameArea.top);
    // 하단: 돼지 상단에서 살짝 겹침
    final double safeAreaBottom = state.piggyBankRect != Rect.zero
        ? state.piggyBankRect.top + state.piggyBankRect.height * 0.2 - coinSize
        : state.gameArea.bottom - 250.0;

    if (safeAreaRight <= safeAreaLeft || safeAreaBottom <= safeAreaTop) {
      return state.gameArea.center;
    }

    double dx = safeAreaLeft + _random.nextDouble() * (safeAreaRight - safeAreaLeft);
    double dy = safeAreaTop + _random.nextDouble() * (safeAreaBottom - safeAreaTop);

    return Offset(dx, dy);
  }

  bool _isPositionValid(Offset pos, [List<Coin> existingCoins = const []]) {
    const double coinSize = 85.0;
    final Rect coinRect = Rect.fromCenter(center: pos, width: coinSize, height: coinSize);

    // ✅ 왼쪽 제한을 완화하여 화면 밖으로도 나갈 수 있도록 허용
    // 오른쪽은 여전히 엄격하게 제한
    if (pos.dx < -20 || pos.dx > state.gameArea.width - coinSize / 2) {
      return false;
    }

    // 우측 UI 요소와 겹치는지 체크 (상단 pocketRect는 safeAreaTop에서 이미 제어)
    if (state.rightUIRect.inflate(10).overlaps(coinRect)) {
      return false;
    }

    // 기존 코인들과 너무 가깝지 않은지 체크 (많이 겹쳐도 됨, 완전히 포개지는 것만 방지)
    const double minDistance = coinSize * 0.22; // 22% 거리 유지
    for (final existingCoin in existingCoins) {
      final distance = (pos - existingCoin.position).distance;
      if (distance < minDistance) {
        return false;
      }
    }

    return true;
  }

  void handleCoinTap(Coin tappedCoin) {
    if (_isNotifierDisposed) return;

    // ✅ 터치 처리 극도로 단순화 - 상태 체크 최소화
    // 이미 애니메이션 중인 코인도 다시 터치 가능 (중복 방지는 애니메이션 레벨에서 처리)

    // ✅ 즉시 애니메이션 시작 (selectedCoinIds 체크 제거)
    onStartCoinAnimation?.call(tappedCoin);

    // 🧲 자석 모드: 가장 가까운 바닥 동전 1개도 함께 수집
    //    (수집 대상 선정/적립 로직은 그대로. 연출만 '끌려가는' 전용 애니메이션 사용)
    Coin? magnetCoin;
    if (magnetBuffEnabled && state.isMagnetModeActive) {
      magnetCoin = _findNearestFloorCoin(tappedCoin);
      if (magnetCoin != null) {
        if (onStartMagnetCoinAnimation != null) {
          // 터치한 동전 쪽으로 빨려든 뒤 그 뒤를 따라 저금통으로
          onStartMagnetCoinAnimation!(magnetCoin, tappedCoin.position);
        } else {
          onStartCoinAnimation?.call(magnetCoin); // 콜백 미연결 시 기존 동작
        }
      }
    }

    // ✅ selectedCoinIds는 나중에 업데이트 (터치 즉시 반응 우선)
    final updatedSelectedIds = Set<String>.from(state.selectedCoinIds);
    updatedSelectedIds.add(tappedCoin.id);
    if (magnetCoin != null) updatedSelectedIds.add(magnetCoin.id);
    if (updatedSelectedIds.length != state.selectedCoinIds.length) {
      state = state.copyWith(selectedCoinIds: updatedSelectedIds);
    }
  }

  void startCollectingCoin(Coin coinWithAnimation) {
    if (_isDisposed) return;

    // ✅ 애니메이션 상태만 변경 (전체 floorCoins 업데이트 제거)
    coinWithAnimation.animationState = CoinAnimationState.collecting;

    // ✅ 즉시 사운드와 진동 효과 실행
    try {
      final settings = _ref.read(settingsProvider);
      if (settings.isSfxEnabled) _playCoinCollectSound();
      if (settings.isVibrationEnabled) {
        _applyStrongVibration();
      }
    } catch (e) {
      print('handleCoinTap effects error: $e');
    }
  }

  void handleAnimationEnd(Coin collectedCoin) {
    if (_isNotifierDisposed || _isDisposed) return;
    try {
      if (!state.floorCoins.any((c) => c.id == collectedCoin.id)) return;

      collectedCoin.dispose();

      // ✅ 로컬 tempMoney에 즉시 적립 (오퍼월 방식)
      final newTempMoney = state.tempMoney + collectedCoin.value;

      // ✅ displayCash는 서버 머니만 표시하므로 슬롯머신 효과 제거
      _showCoinCollectText('+${collectedCoin.value}');

      // 1. 수집된 코인을 리스트에서 제거합니다.
      final updatedCoins = state.floorCoins.where((c) => c.id != collectedCoin.id).toList();
      final updatedSelectedIds = Set<String>.from(state.selectedCoinIds)..remove(collectedCoin.id);

      // 💣 폭탄 게이지 감소 - 저금통에 들어간 동전마다 -1 (자석으로 딸려온 동전 포함)
      // 단, 폭탄으로 쓸어담은 동전은 제외 (발동 시 게이지가 100으로 리셋되므로)
      int newBombGauge = state.bombGaugeRemaining;
      if (bombBuffEnabled && !_bombSweptCoinIds.remove(collectedCoin.id)) {
        newBombGauge = max(0, newBombGauge - 1);
      }

      state = state.copyWith(
        tempMoney: newTempMoney, // ✅ 로컬 임시 머니 증가
        // totalCash는 변경하지 않음 (서버 동기화 시에만 변경)
        floorCoins: updatedCoins,
        selectedCoinIds: updatedSelectedIds,
        bombGaugeRemaining: newBombGauge,
      );

      // 2. 바닥에 코인이 _maxFloorCoins개 미만이고 주머니에 코인이 있으면 추가 드롭
      // 🎉 종료 상태여도 상자에 남은 동전은 계속 보충됨 (상자가 비면 자연스럽게 멈춤)
      if (updatedCoins.length < _maxFloorCoins && state.luckyBagCount > 0) {
        final coinsToAdd = min(_maxFloorCoins - updatedCoins.length, state.luckyBagCount);
        List<Coin> newCoinsToAdd = [];

        for (int i = 0; i < coinsToAdd; i++) {
          Offset pos = _getRandomSafePosition();
          int attempts = 0;
          while (!_isPositionValid(pos, [...updatedCoins, ...newCoinsToAdd]) && attempts < 50) {
            pos = _getRandomSafePosition();
            attempts++;
          }

          final newCoin = _generateRandomCoin(pos)..animationState = CoinAnimationState.dropping;
          newCoinsToAdd.add(newCoin);
        }

        if (newCoinsToAdd.isNotEmpty) {
          state = state.copyWith(
            floorCoins: [...updatedCoins, ...newCoinsToAdd],
            luckyBagCount: state.luckyBagCount - newCoinsToAdd.length,
          );
          _scheduleLuckyBagServerSave(); // 📦 소비분 서버 반영 예약 (디바운스)

          // 새 코인들의 드롭 애니메이션 시작
          for (final coin in newCoinsToAdd) {
            onStartDropAnimation?.call(coin);
          }
        }
      }

      // 3. 버튼 상태 업데이트 및 게임 상태 저장
      _updateRefillButtonStates();
      _saveGameStateToPrefs();

      // 🔊 사운드만 디바운싱 (서버 저장 제거)
      _playSoundWithDebounce();

      // 💰 레벨별 최대 tempMoney 한도 체크 (레벨1: 8000, 레벨2: 9000, 레벨3: 10000, 레벨4: 11000, 레벨5: 12000)
      final maxTempMoney = _getMaxTempMoneyByLevel(state.currentAutoEarnLevel);
      if (newTempMoney > maxTempMoney) {
        print('💰 tempMoney가 레벨${state.currentAutoEarnLevel} 한도($maxTempMoney) 초과: $newTempMoney - 저금통 가득 참 다이얼로그 표시');
        onShowTempMoneyFullDialog?.call();
      }

      // ✅ 전면광고용 동전 수집 카운트 증가 및 체크
      _incrementCoinCollectCountForAd();
    } catch (e) {
      print('handleAnimationEnd 에러: $e');
    }
  }

  // ✅ 전면광고용 동전 수집 카운트 증가 (자동 광고 비활성화 - right_refill 버튼으로 이동)
  void _incrementCoinCollectCountForAd() {
    _coinCollectCountForAd++;
    print('🎯 전면광고용 동전 수집: $_coinCollectCountForAd / $_coinAdThreshold');

    // SharedPreferences에 저장
    _saveCoinCollectCountForAd();

    // ✅ 200개 동전 자동 광고 비활성화 - right_refill 버튼 3회차 이상에서 광고 표시하도록 변경
    // if (_coinCollectCountForAd >= _coinAdThreshold && !_isPreparingCoinAd) {
    //   _triggerCoinAdPreparation();
    // }
  }

  // ✅ 전면광고용 동전 수집 카운트 저장
  Future<void> _saveCoinCollectCountForAd() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('coinCollectCountForAd', _coinCollectCountForAd);
    } catch (e) {
      print('전면광고용 동전 수집 카운트 저장 오류: $e');
    }
  }

  // ✅ 전면광고 준비 다이얼로그 트리거
  void _triggerCoinAdPreparation() {
    if (_isPreparingCoinAd) return;
    _isPreparingCoinAd = true;

    // 랜덤 메시지 선택
    final messages = [
      '눈과 손가락에 휴식을! 잠시 스트레칭 어떠신가요? 👀',
      '잠깐! 너무 열심히 달려오셨어요. 쉼표가 필요한 타이밍! ☕',
      '손가락도 숨을 쉬어야 해요! 잠시만 고른 후에 계속해볼까요? ✨',
      '에너지 충전 중... 더 강력한 터치를 위해 잠시만 기다려주세요! 🔋',
      '잠시 열기를 식히는 중입니다. 머니 파워가 차오르고 있어요! ⚡',
      '잠시만요! 쏟아진 머니들을 안전하게 금고로 옮기고 있습니다. 🔒',
      '집중력이 정말 대단하신데요? 이 기세면 부자 되는 건 시간문제! 💰',
      '와, 쉬지 않고 달려오셨네요! 당신의 열정에 박수를 보냅니다 👏',
      '꾸준함이 최고의 무기! 잠시 쉬었다가 다시 행운을 잡아봐요 🍀',
      '혹시 터치 천재 아니신가요? 잠시 기계 점검(?) 좀 하고 갈게요! 🤖',
      '동전들이 잠시 숨바꼭질을 하러 갔어요. 곧 다시 나타날 거예요! 🙈',
      '동전들도 당신의 손길에 감동했대요! 잠시만 숨 고르기 할게요 🎈',
    ];

    final randomMessage = messages[_random.nextInt(messages.length)];
    print('🎯 전면광고 준비 - 랜덤 메시지: $randomMessage');

    // 콜백 호출 (다이얼로그 표시 + 광고 표시 후 완료 콜백)
    onShowCoinAdPreparationDialog?.call(randomMessage, () {
      // 광고 표시 완료 후 카운트 리셋
      _resetCoinCollectCountForAd();
      _isPreparingCoinAd = false;
    });
  }

  // ✅ 전면광고용 동전 수집 카운트 리셋
  Future<void> _resetCoinCollectCountForAd() async {
    _coinCollectCountForAd = 0;
    print('🎯 전면광고용 동전 수집 카운트 리셋: 0');

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('coinCollectCountForAd', 0);
    } catch (e) {
      print('전면광고용 동전 수집 카운트 리셋 저장 오류: $e');
    }
  }

  void _updateRefillButtonStates() {
    // 현재 사용자가 사용하는 displayCoins 로직과 동일하게 계산
    // 1회차(즉시 충전)는 currentCoins가 0이어도 maxCoins만큼 표시
    final currentRound = _maxRefillCount - state.rewardRefillCount;
    final displayCoins = state.currentCoins == 0 && currentRound == 1 && state.rewardRefillCount > 0 ? state.maxCoins : state.currentCoins;

    // displayCoins가 0이 아니면 활성화 (수령 가능하거나 새 리필 시작 가능)
    bool canInteract = displayCoins != 0;
    // ✅ 리필 쿨다운 체크는 로컬시간 비교 유지 (내부 로직이므로)
    bool isCoolDownOver = state.rightRefillNextAvailableTime == null || DateTime.now().isAfter(state.rightRefillNextAvailableTime!);
    bool newRightRefillEnabled = canInteract && isCoolDownOver;

    // ✅ 디버깅 로그 추가
    print("🔧 리필 버튼 상태 업데이트:");
    print("  - luckyBagCount: ${state.luckyBagCount}");
    print("  - 바닥 코인: ${state.floorCoins.length}개");
    print("  - 남은 리필: ${state.rewardRefillCount}회");
    print("  - currentCoins: ${state.currentCoins} / maxCoins: ${state.maxCoins}");
    print("  - displayCoins: $displayCoins (0이 아님? $canInteract)");
    print("  - isFillingCoins: ${state.isFillingCoins}");
    print("  - 쿨다운 끝? $isCoolDownOver");
    print("  - 최종 버튼 활성화: $newRightRefillEnabled");

    if (state.isRightRefillEnabled != newRightRefillEnabled) {
      state = state.copyWith(
        isRightRefillEnabled: newRightRefillEnabled,
      );
    }
  }

  bool isAutoEarnComplete() {
    if (!state.isAutoEarnActive || state.autoEarnActiveStartTime == null) return false;
    // ✅ 자동적립 시간 계산은 로컬시간 비교 유지 (내부 로직이므로)
    final now = DateTime.now();
    final elapsedSeconds = now.difference(state.autoEarnActiveStartTime!).inSeconds;
    return elapsedSeconds >= state.autoEarnActivatedDuration;
  }

  /// 다이얼로그가 '취소'되었을 때 타이머를 재개하기 위한 함수
  void resumeFillTimer() {
    _isPausedTimerForDialog = false;
  }

  // 타이머 일시정지 메서드
  void pauseFillTimer() {
    _isPausedTimerForDialog = true;
  }

  Future<void> _configureAudio() async {
    // BGM은 BgmService 싱글톤에서 관리하므로 여기서 설정하지 않음.
    _audioPlayerPool = List.generate(5, (_) => AudioPlayer());

    // iOS: 앱 전체 단일 AVAudioSession → main.dart 전역 컨텍스트(playback+mixWithOthers) 상속.
    // per-player setAudioContext는 전역 setCategory를 재실행해 재생 중 BGM을 뭉개므로 iOS 생략.
    // Android는 플레이어별 audioFocus:none이 필요하므로 반드시 설정(회귀 방지).
    if (!Platform.isIOS) {
      final fxCtx = AudioContext(
        android: const AudioContextAndroid(
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.game,
          audioFocus: AndroidAudioFocus.none,
        ),
      );
      await _depositPlayer.setAudioContext(fxCtx);
      await _refillSoundPlayer.setAudioContext(fxCtx);
      await _pigTouchSoundPlayer.setAudioContext(fxCtx);
      for (final player in _audioPlayerPool) {
        await player.setAudioContext(fxCtx);
      }
    }
    try {
      await _sfxCoinCache.load('coin_collect_sound.mp3');
    } catch (e) {
      print("효과음 미리 로딩 실패: $e");
    }
  }

  // 🎵 머니톡톡 화면이 현재 '활성(포그라운드에 떠 있는)' 상태인지.
  //   BGM은 이 화면이 활성일 때만 재생/재개된다. 홈·다른 탭에서 노티파이어가 되살아나거나
  //   (main_screen이 resume마다 gameProvider.notifier를 읽어 autoDispose된 노티파이어를 재생성함)
  //   광고 종료 콜백이 와도 BGM이 켜지지 않도록 하는 단일 게이트.
  bool _isGameScreenActive = false;

  /// 머니톡톡 화면 진입/이탈 시 호출. 이탈(false) 시 BGM을 즉시 정지한다.
  void setGameScreenActive(bool active) {
    _isGameScreenActive = active;
    if (!active) {
      // 화면을 벗어나거나 종료될 때: 백그라운드/다른 화면에서 계속 나지 않도록 즉시 정지
      bgmService.pause(GameType.game1);
      _stopMagnetLoopSound();
    }
  }

  void playBackgroundMusic() async {
    final settings = _ref.read(settingsProvider);
    print('🎵 playBackgroundMusic 호출됨 - BGM 설정: ${settings.isBgmEnabled}, 화면활성: $_isGameScreenActive');
    if (!settings.isBgmEnabled) return;
    // 🎵 머니톡톡 화면이 활성일 때만 재생 (홈/다른 화면에서 재생 방지)
    if (!_isGameScreenActive) {
      print('🎵 playBackgroundMusic - 게임 화면 비활성 → 재생 안 함');
      return;
    }

    try {
      // BgmService 사용 - 일시정지 상태면 이어서 재생, 아니면 처음부터
      print('🎵 bgmService.play 호출 시작');
      await bgmService.play(GameType.game1, fromStart: false);
      print('🎵 bgmService.play 호출 완료');
    } catch (e) {
      print("BGM 재생 실패: $e");
    }
  }

  void stopBackgroundMusic() {
    // 화면 나갈 때는 pause만 (위치 유지)
    bgmService.pause(GameType.game1);
  }

  void pauseBackgroundMusic() {
    // 활성 게임 BGM만 정지. 모든 광고 서비스가 globalGameNotifierRef(=game1)를 통해
    // 이 메서드를 호출하므로, 활성 게임 기준으로 제어해야 game2에서 game1을 건드리지 않음.
    if (!_isDisposed) {
      bgmService.pauseActive();
      _stopMagnetLoopSound(); // 🧲 백그라운드/광고 중에는 지지직 사운드도 중지
    }
  }

  void resumeBackgroundMusic() {
    if (_isDisposed) return;
    // 🎵 머니톡톡 화면이 활성일 때만 재개.
    //   (광고 종료 콜백/생명주기 resume이 홈·다른 화면에서 와도 BGM이 켜지지 않도록)
    if (!_isGameScreenActive) {
      print('🎵 resumeBackgroundMusic - 게임 화면 비활성 → 재개 안 함');
      return;
    }
    // 활성 게임 BGM만 재개(isBgmEnabled는 bgmService가 캐시로 체크).
    bgmService.resumeActive();
    // 🧲 자석 모드가 아직 활성 상태면 지지직 사운드 재개
    if (state.isMagnetModeActive) {
      _startMagnetLoopSound();
    }
  }

  void _playCoinCollectSound() {
    try {
      final player = _audioPlayerPool[_currentPlayerIndex];
      _currentPlayerIndex = (_currentPlayerIndex + 1) % _audioPlayerPool.length;
      player.play(AssetSource('audio/coin_collect_sound.mp3'));
      player.setReleaseMode(ReleaseMode.release);
    } catch (e) {
      print('코인 수집 사운드 재생 실패: $e');
    }
  }

  void _playCoinDepositSound() async {
    if (_isDepositPlaying) return;
    _isDepositPlaying = true;
    try {
      final settings = _ref.read(settingsProvider);
      if (!settings.isSfxEnabled) {
        _isDepositPlaying = false;
        return;
      }
      await _depositPlayer.play(AssetSource('audio/coin_deposit_sound.mp3'));
      _depositPlayer.onPlayerComplete.first.then((_) {
        _isDepositPlaying = false;
      });
    } catch (e) {
      _isDepositPlaying = false;
    }
  }

  /// 🎉 사이클 완주 보상(10,000M) 획득 효과음
  /// 기존 출석 보상음(coin_attendance_sound)을 재사용해 '보상 획득' 느낌을 준다.
  /// (deposit 플레이어 재사용 - 완주 시점엔 동전 적립음이 울릴 일이 없어 충돌 없음)
  void playCycleBonusSound() async {
    try {
      final settings = _ref.read(settingsProvider);
      if (!settings.isSfxEnabled) return;
      await _depositPlayer.play(AssetSource('audio/coin_attendance_sound.mp3'));
    } catch (e) {
      print('🎉 완주 보상 효과음 재생 실패: $e');
    }
  }

  void playRefillSound() async {
    if (_isRefillSoundPlaying) return;
    _isRefillSoundPlaying = true;
    try {
      final settings = _ref.read(settingsProvider);
      if (!settings.isSfxEnabled) {
        _isRefillSoundPlaying = false;
        return;
      }
      await _refillSoundPlayer.play(AssetSource('audio/refill.mp3'));
      _refillSoundPlayer.onPlayerComplete.first.then((_) {
        _isRefillSoundPlaying = false;
      });
    } catch (e) {
      print('리필 사운드 재생 오류: $e');
      _isRefillSoundPlaying = false;
    }
  }

  void _safeDisposeAudioPlayers() {
    // BGM은 BgmService 싱글톤에서 관리하므로 여기서 dispose하지 않음
    // 화면 나갈 때 pause만 호출됨
    try {
      if (_depositPlayer.state != PlayerState.disposed) {
        _depositPlayer.stop();
        _depositPlayer.dispose();
      }
    } catch (e) {
      print('depositPlayer dispose 에러: $e');
    }
    try {
      if (_refillSoundPlayer.state != PlayerState.disposed) {
        _refillSoundPlayer.stop();
        _refillSoundPlayer.dispose();
      }
    } catch (e) {
      print('refillSoundPlayer dispose 에러: $e');
    }
    try {
      if (_pigTouchSoundPlayer.state != PlayerState.disposed) {
        _pigTouchSoundPlayer.stop();
        _pigTouchSoundPlayer.dispose();
      }
    } catch (e) {
      print('pigTouchSoundPlayer dispose 에러: $e');
    }
    try {
      if (_bombExplosionPlayer.state != PlayerState.disposed) {
        _bombExplosionPlayer.stop();
        _bombExplosionPlayer.dispose();
      }
    } catch (e) {
      print('bombExplosionPlayer dispose 에러: $e');
    }
    try {
      if (_magnetLoopPlayer.state != PlayerState.disposed) {
        _magnetLoopPlayer.stop();
        _magnetLoopPlayer.dispose();
      }
    } catch (e) {
      print('magnetLoopPlayer dispose 에러: $e');
    }
    for (var player in _audioPlayerPool) {
      try {
        if (player.state != PlayerState.disposed) {
          player.stop();
          player.dispose();
        }
      } catch (e) {
        print('audioPlayerPool dispose 에러: $e');
      }
    }
    _audioPlayerPool.clear();
  }

  @override
  void dispose() {
    print('💾 GameNotifier 종료 - 최종 데이터 저장 시작');

    // 📦 [최후 보루] 미저장 상자 동전이 남아 있으면 dispose 플래그를 세우기 전에 저장을 발사한다.
    // (정상 경로는 이탈/생명주기에서 await 저장이지만, 예외 경로 대비)
    try {
      final pendingBag = state.luckyBagCount;
      // 🛡️ [리셋 가드] 서버 리셋이 아직 로컬에 반영 안 된 상태면 저장하지 않는다
      //    (낡은 상자값으로 리셋된 서버값 200을 덮어쓰는 것 방지)
      final disposeUser = _ref.read(currentUserProvider);
      final bool resetPending = disposeUser != null && state.sessionResetVersion != disposeUser.resetVersion;
      if (!state.hasLoadError && !resetPending && _lastSyncedLuckyBagCount != pendingBag) {
        _bagSaveDebounceTimer?.cancel();
        _ref.read(userRepositoryProvider).addEarning(
              amount: 0,
              luckyBagCount: pendingBag,
              source: 'moneyTalk',
            );
        print('📦 dispose 시 미저장 상자 동전 서버 반영 시도: $pendingBag');
      } else if (resetPending) {
        print('📦 dispose 시 리셋 미반영 상태 - 상자 저장 보류(덮어쓰기 방지)');
      }
    } catch (e) {
      print('📦 dispose 시 상자 동전 저장 시도 실패: $e');
    }

    // 🧲 자석 발동 중 화면 이탈 시: 별도 기록 불필요.
    // 발동 시점에 저장한 종료 시각(시작+30초)이 그대로 유지되어, 재진입 시 남은 시간만큼
    // 자석이 재개되고(_loadMagnetBuffState) 쿨타임도 그 종료 시각 기준으로 돌아 악용 불가.

    // 1) 먼저 dispose 플래그 설정 (모든 비동기 작업 중단을 위해)
    _isNotifierDisposed = true;
    _isDisposed = true;

    // 🎵 화면 이탈/노티파이어 해제 시 BGM 확실히 정지 (뒤로가기·탭 전환 등 모든 이탈 경로 커버).
    //   이후 어떤 콜백이 와도 재생되지 않도록 화면 비활성 플래그도 내린다.
    _isGameScreenActive = false;
    try {
      bgmService.pause(GameType.game1);
    } catch (_) {}

    // 2) 전역 참조 안전하게 정리
    if (globalGameNotifierRef == this) {
      globalGameNotifierRef = null;
    }

    // 3) 💾 개선된 최종 저장 로직
    _saveDebounceTimer?.cancel(); // 대기 중인 저장 취소

    // 뒤로가기에서 이미 저장을 완료했으므로, dispose에서는 타이머 취소만 수행
    print('💾 디바운스 타이머 취소 완료 (저장은 뒤로가기에서 이미 완료됨)');

    // 4) 오디오 · 타이머 등 자원 해제
    _safeDisposeAudioPlayers();

    // 5) 모든 타이머 안전하게 취소
    _safeDisposeTimers();

    // 6) StateNotifier dispose 호출
    super.dispose();

    print('💾 GameNotifier 완전히 종료됨');
  }

  void _safeDisposeTimers() {
    try {
      _slotMachineTimer?.cancel();
      _slotMachineTimer = null;
    } catch (e) {
      print('슬롯머신 타이머 dispose 에러: $e');
    }

    try {
      _collectValueTimer?.cancel();
      _collectValueTimer = null;
    } catch (e) {
      print('수집값 타이머 dispose 에러: $e');
    }

    try {
      _cooldownTimer?.cancel();
      _cooldownTimer = null;
    } catch (e) {
      print('쿨다운 타이머 dispose 에러: $e');
    }

    try {
      _coinsFillTimer?.cancel();
      _coinsFillTimer = null;
    } catch (e) {
      print('코인 충전 타이머 dispose 에러: $e');
    }

    try {
      _saveDebounceTimer?.cancel();
      _saveDebounceTimer = null;
    } catch (e) {
      print('저장 디바운스 타이머 dispose 에러: $e');
    }

    try {
      _bagSaveDebounceTimer?.cancel();
      _bagSaveDebounceTimer = null;
    } catch (e) {
      print('상자 동전 저장 디바운스 타이머 dispose 에러: $e');
    }

    try {
      _magnetModeTimer?.cancel();
      _magnetModeTimer = null;
    } catch (e) {
      print('자석 모드 타이머 dispose 에러: $e');
    }

    try {
      _magnetCooldownTimer?.cancel();
      _magnetCooldownTimer = null;
    } catch (e) {
      print('자석 쿨타임 타이머 dispose 에러: $e');
    }
  }

  void _applyStrongVibration() async {
    bool? hasVibrator = await Vibration.hasVibrator();
    if (hasVibrator == true) {
      Vibration.vibrate(duration: 100, amplitude: 150);
    } else {
      HapticFeedback.heavyImpact();
      Future.delayed(const Duration(milliseconds: 100), () {
        HapticFeedback.heavyImpact();
      });
    }
  }

  /// ✅ 기존 함수 제거됨 - 새로운 통합 리셋 시스템으로 대체
  /// checkAutoEarnResetOnClaim()으로 대체됨

  void _showCoinCollectText(String text) {
    state = state.copyWith(collectValueText: text);
    _collectValueTimer?.cancel();
    _collectValueTimer = Timer(const Duration(milliseconds: 500), () {
      state = state.copyWith(clearCollectValueText: true);
    });
  }

  double _calculateFillSpeed(int refillCount) {
    // 현재 회차 = 51 - 남은 횟수 (50/50에서 시작하므로 첫 번째 리필이 1회차)
    // [3] 충전 속도(N초당 +1) 곡선 — 사이클 단위로 재설정
    //  · 1사이클(1~15): 1회차 0초, 2회차 0.2, 3회차 0.5, 4회차부터 (회차-3)초 → 15회차 12초
    //  · 2사이클(16~30): (회차-10)초 → 16회차 6초, 17회차 7초 ... 30회차 20초
    //    (개수 적은 사이클 초반 대기시간 완화 + 30회차에서 정확히 20초 도달 → 3사이클 진입 매끄럽게)
    //  · 3사이클 이후(31~) 및 순환 구간(31~45 반복): 20초 고정
    int currentRound = _maxRefillCount - refillCount;
    if (currentRound <= 1) return 0.0; // 즉시 리필
    if (currentRound == 2) return 0.2;
    if (currentRound == 3) return 0.5;
    if (currentRound <= 15) return (currentRound - 3).toDouble(); // 1사이클: 4회차 1초 ~ 15회차 12초
    if (currentRound <= 30) return (currentRound - 10).toDouble(); // 2사이클: 16회차 6초 ~ 30회차 20초
    return 20.0; // 3사이클 이후 & 순환 구간: 20초 고정
  }

  int _calculateMaxCoins(int refillCount) {
    // [1] 사이클 내 순서(1~15)에 따라 10, 15, 20 ... 80 (5씩 증가). 사이클마다 리셋.
    // 1회차=10, 15회차=80, 16회차=다시 10 ... 순환 구간(31~45)도 동일 패턴.
    final int round = _maxRefillCount - refillCount;
    final int pos = ((round - 1) % cycleSize) + 1; // 1~15
    return 10 + (pos - 1) * 5; // pos1→10, pos15→80
  }

  // 🎯 백그라운드 도즈 모드 대응 - 시간 기반 코인 충전 시스템
  void _startCoinFillingTimer(double fillSpeed, int maxCoins, {bool isNewCharge = false}) {
    _coinsFillTimer?.cancel(); // 기존 타이머가 있다면 취소

    // 안전장치: fillSpeed가 0이면 즉시 충전 방식이므로 타이머 불필요
    if (fillSpeed == 0.0) {
      print("❌ _startCoinFillingTimer: fillSpeed가 0이므로 타이머 시작하지 않음");
      return;
    }

    _isPausedTimerForDialog = false; // 타이머 일시정지 상태 초기화

    // 🕐 충전 시작 시간 기록 - 새로운 충전이거나 기존 시작 시간이 없는 경우에만 설정
    if (isNewCharge || _fillStartTime == null) {
      _fillStartTime = DateTime.now();
      print("✅ _startCoinFillingTimer 새로운 충전 시작: fillSpeed=$fillSpeed초당 1개, maxCoins=$maxCoins, 시작시간: $_fillStartTime");
    } else {
      print("✅ _startCoinFillingTimer 기존 충전 계속: fillSpeed=$fillSpeed초당 1개, maxCoins=$maxCoins, 기존시작시간: $_fillStartTime");
    }

    // 💾 충전 시작 시간 저장 (백그라운드 복귀 대응)
    _saveGameStateToPrefs();

    // 🔔 7회차부터: 충전 완료 예상 시각에 로컬알림 예약 (지갑 가득 참 안내)
    _scheduleCoinPurseFullNotificationIfNeeded(fillSpeed, maxCoins);

    // ⏱️ 틱 주기를 충전 간격에 맞춤: 0.2초당 +1이면 0.2초마다, 0.5초당 +1이면 0.5초마다 틱
    // (기존 고정 1초 틱은 0.2초 속도에서 '1초당 +5'로 뭉텅뭉텅 올라가 보이는 문제가 있었음)
    // 총 충전량/시간은 시간 기반 계산이라 동일, 화면 갱신 단위만 +1씩 잘게 쪼개짐
    final tickMs = (fillSpeed * 1000).clamp(100, 1000).toInt();
    _coinsFillTimer = Timer.periodic(Duration(milliseconds: tickMs), (timer) {
      if (_isNotifierDisposed || _isDisposed) {
        timer.cancel();
        return;
      }

      // 다이얼로그가 떠 있는 동안에는 타이머를 일시정지
      if (_isPausedTimerForDialog) {
        print("⏸️ 타이머 일시정지 중 (다이얼로그 표시됨)");
        return;
      }

      // 🔥 시간 기반 계산: 실제 경과 시간으로 코인 수 계산 (도즈 모드 대응)
      if (_fillStartTime != null) {
        final now = DateTime.now();
        // 밀리초 단위 계산: 정수 초 단위로 끊으면 1초 미만 속도(0.2초/0.5초)에서 +1씩 갱신이 안 됨
        final elapsedMs = now.difference(_fillStartTime!).inMilliseconds;
        final expectedCoins = (elapsedMs / (fillSpeed * 1000)).floor();

        // 최대치 제한
        final actualCoins = expectedCoins > maxCoins ? maxCoins : expectedCoins;

        if (actualCoins != state.currentCoins) {
          print("⚡ 시간기반 코인 업데이트: ${state.currentCoins} → $actualCoins (경과: ${(elapsedMs / 1000).toStringAsFixed(1)}초)");
          state = state.copyWith(currentCoins: actualCoins);
        }

        // 최대치에 도달하면 타이머 중지
        if (actualCoins >= maxCoins) {
          state = state.copyWith(isFillingCoins: false);
          timer.cancel();
          _fillStartTime = null; // 시작 시간 초기화
          print("🎉 코인 충전 완료: $maxCoins / $maxCoins (사용자 클릭 대기 중)");
          // 홈화면 애니메이션 플래그 설정 (오른쪽 지갑 가득 참)
          SharedPreferences.getInstance().then((prefs) => prefs.setBool('isRightRefillFull', true));
          _updateRefillButtonStates();
          _saveGameStateToPrefs();
        } else if (timer.tick % max(1, (5000 / tickMs).round()) == 0) {
          // 약 5초마다 중간 저장 (틱 주기가 잘게 쪼개져도 저장 빈도는 유지)
          _saveGameStateToPrefs();
        }
      } else {
        // 🔧 _fillStartTime이 null인 경우 즉시 설정
        print("⚠️ _fillStartTime이 null입니다. 새로 설정합니다.");
        _fillStartTime = DateTime.now();
        _saveGameStateToPrefs();
      }
    });
  }

  /// 🔧 마이그레이션: 구버전 Cloud Functions가 리셋/가입 시드로 5를 넣은 경우 50으로 승격
  /// (functions의 50 시드 배포 전까지 신규 클라이언트가 50회 시스템을 쓸 수 있도록 보정)
  ///
  /// 호출 조건은 호출부에서 보장할 것:
  /// - 정상 사용 이력(localResetVersion 있음) 또는 오늘 가입한 신규 유저만
  /// - 재설치(로컬 이력 없음 + 기존 가입자)는 호출 금지 (45회 소비 후 재설치 악용 방지)
  ///
  /// 같은 게임날짜에 두 번 승격되지 않도록 refillSeedMigratedFor로 마킹한다
  /// (신버전에서 45회 소비해 서버값이 다시 5가 된 날의 재승격 방지).
  Future<int> _migrateLegacyRefillSeed(int serverRefillCount, {String? resetVersion}) async {
    final prefs = await SharedPreferences.getInstance();
    final versionKey = resetVersion ?? '';

    if (serverRefillCount != 5) {
      // 서버값이 5 초과 = 오늘 이미 신규 시드(50) 또는 승격된 값 확인됨
      // → 이 날짜의 승격을 봉인 (50에서 45회 소비해 5가 된 날의 재승격 방지)
      if (serverRefillCount > 5 && versionKey.isNotEmpty) {
        await prefs.setString('refillSeedMigratedFor', versionKey);
      }
      return serverRefillCount;
    }

    if (versionKey.isNotEmpty && prefs.getString('refillSeedMigratedFor') == versionKey) {
      print('🔧 리필 시드 승격: 오늘($versionKey) 이미 승격/봉인됨 - 스킵');
      return serverRefillCount;
    }

    print('🔧 구버전 리필 시드(5) 감지 → 50으로 승격 시도');
    // 서버 반영이 확인된 경우에만 승격 (성공 여부를 bool로 보장받음)
    // 실패 시 승격하지 않고 5 유지 → 이후 동기화 강등/마킹 잠김 없이 다음 로드에서 재시도
    final success = await _ref.read(userRepositoryProvider).setRewardRefillCount(50);
    if (!success) {
      print('🔧 리필 시드 승격 서버 반영 실패 - 이번 로드에서는 승격 보류 (다음 로드에서 재시도)');
      return serverRefillCount;
    }

    // 서버 반영 성공 - 당일 재승격 방지 마킹
    if (versionKey.isNotEmpty) {
      await prefs.setString('refillSeedMigratedFor', versionKey);
    }
    print('🔧 리필 시드 승격 완료: 5 → 50');
    return 50;
  }

  /// 🔔 동전지갑 가득 참 로컬알림 예약 (7회차부터)
  /// 충전 시작 시간 기준으로 완료 예상 시각을 계산해 예약한다.
  void _scheduleCoinPurseFullNotificationIfNeeded(double fillSpeed, int maxCoins) {
    try {
      final currentRound = _maxRefillCount - state.rewardRefillCount;
      if (currentRound < 7 || fillSpeed <= 0 || _fillStartTime == null) {
        return;
      }

      final fullAt = _fillStartTime!.add(Duration(milliseconds: (fillSpeed * maxCoins * 1000).round()));
      final delay = fullAt.difference(DateTime.now());
      if (delay.inSeconds <= 0) {
        return; // 이미 가득 참 (백그라운드 복귀 등) - 알림 불필요
      }

      NotificationService().scheduleCoinPurseFullNotification(delay: delay);
      print('🔔 ${currentRound}회차 동전지갑 가득 참 알림 예약: ${delay.inSeconds}초 후');
    } catch (e) {
      print('🔔 동전지갑 알림 예약 중 오류 (무시): $e');
    }
  }

  // 전역 상태 정리를 위한 정적 메서드 추가
  static void clearGlobalState() {
    try {
      globalGameNotifierRef = null;
      print('게임 프로바이더 전역 상태 정리 완료');
    } catch (e) {
      print('게임 프로바이더 전역 상태 정리 중 오류: $e');
    }
  }

  /// 📅 게임 화면 진입 시 한 번만 서버 리셋 체크 (효율적인 방식)
  /// 🌅 백그라운드 → 포그라운드 복귀 / 머니톡톡 화면 재진입 시 일일 리셋 확인
  ///
  /// 앱을 종료하지 않고 새벽 5시를 넘긴 경우, 노티파이어가 살아있어 _initialize가 다시 돌지 않는다.
  /// 그래서 서버 값만 반영되고 바닥 동전·폭탄 게이지 등 게임 상태는 전날 것이 남는 문제가 있었다.
  ///
  /// 판정은 기존 로직(_checkServerResetOnceOnInit: 서버 resetVersion vs sessionResetVersion)을
  /// 그대로 재사용한다. 백그라운드 동안 서버 값이 바뀌었을 수 있으므로 판정 전에 유저 정보만 새로고침한다.
  /// 리셋이 아니면 _checkServerResetOnceOnInit이 아무 일도 하지 않으므로,
  /// 평상시 복귀에서 바닥 동전/상자가 초기화되는 일은 없다.
  Future<void> checkDailyResetOnResume() async {
    try {
      if (_isDisposed || _isNotifierDisposed) return;
      if (state.hasLoadError) return; // 로드 실패 상태에서는 건드리지 않음
      // 리필/저장 진행 중에는 상태를 흔들지 않는다 (기존 가드와 동일한 취지)
      if (_isRefilling || _isSaving) {
        print('🌅 복귀 리셋 체크 - 리필/저장 중이라 건너뜀');
        return;
      }

      // 최신 서버 resetVersion 확보 (백그라운드 동안 05시를 넘겼을 수 있음)
      await _ref.read(currentUserProvider.notifier).refreshUserData();
      if (_isDisposed || _isNotifierDisposed) return;

      // 기존 판정 + 적용 경로 재사용 (리셋이 아니면 no-op)
      await _checkServerResetOnceOnInit();
    } catch (e) {
      print('🌅 복귀 시 일일 리셋 체크 오류: $e');
    }
  }

  Future<void> _checkServerResetOnceOnInit() async {
    try {
      // 현재 사용자 정보에서 서버 리셋 버전 확인
      final user = _ref.read(currentUserProvider);
      if (user == null) return;

      final serverResetVersion = user.resetVersion;
      final currentSessionResetVersion = state.sessionResetVersion;

      // 서버 리셋 버전이 변경되었는지 체크
      if (serverResetVersion != currentSessionResetVersion) {
        print('🌅 게임 진입시 리셋 감지: 세션($currentSessionResetVersion) vs 서버($serverResetVersion) - 리셋 수행');

        // 사용자 데이터 새로고침 (최신 데이터 확보)
        await _ref.read(currentUserProvider.notifier).refreshUserData();
        final updatedUser = _ref.read(currentUserProvider);

        if (updatedUser != null) {
          // 게임 상태를 서버 데이터로 리셋
          await _performGameResetOnInit(updatedUser, serverResetVersion);
        }
      } else {
        print('📅 게임 진입시 리셋 체크: 리셋 불필요 (세션: $currentSessionResetVersion, 서버: $serverResetVersion)');
      }
    } catch (e) {
      print('📅 게임 진입시 리셋 체크 중 오류: $e');
    }
  }

  /// 📅 게임 화면 진입시에만 실행되는 리셋 (사용자 진행상황 보호)
  Future<void> _performGameResetOnInit(dynamic user, String? newResetVersion) async {
    print('🔄 게임 진입시 리셋 시작 - 사용자 플레이 전 안전한 리셋');

    _coinsFillTimer?.cancel();

    // 🔔 리셋 시 기존 '가득 참' 알림 취소 + 홈 펄스 플래그 초기화
    NotificationService().cancelCoinPurseFullNotification();
    SharedPreferences.getInstance().then((prefs) => prefs.setBool('isRightRefillFull', false));

    // 🔧 구함수 시드(5) → 50 승격 (세션 중 정상 리셋 경로)
    final refillCount = await _migrateLegacyRefillSeed(
      user.rewardRefillCount as int,
      resetVersion: newResetVersion,
    );

    // 서버에서 받은 최신 데이터로 상태 리셋
    state = state.copyWith(
      // 서버 데이터로 업데이트
      luckyBagCount: user.luckyBagCount,
      rewardRefillCount: refillCount,
      totalCash: user.money,
      displayCash: user.money,

      // 리셋되는 값들 (1회차 즉시 충전이므로 maxCoins만큼)
      currentCoins: _calculateMaxCoins(refillCount),
      maxCoins: _calculateMaxCoins(refillCount),
      fillSpeed: _calculateFillSpeed(refillCount),
      isFillingCoins: false,
      clearFillSpeedText: true,

      // 세션 리셋 버전 업데이트
      sessionResetVersion: newResetVersion,

      // 바닥 코인 초기화 플래그
      didInitCoins: false,
    );

    // 🌅 일일 리셋 시 함께 초기화되어야 하는 게임 상태들
    //   앱을 완전 종료 후 재실행하는 경로에서는 생성자(_loadBombBuffState 등)와
    //   setLayoutParams(바닥 동전 초기 배치)가 대신 처리해 준다. 그러나 백그라운드 복귀처럼
    //   노티파이어가 살아있는 경로에서는 그 경로를 타지 않으므로 여기서 직접 맞춰줘야 한다.

    // 💣 폭탄 게이지: 전날 잔량이 남지 않도록 최대치로 리셋
    if (bombBuffEnabled && state.bombGaugeRemaining != _bombGaugeMax) {
      state = state.copyWith(bombGaugeRemaining: _bombGaugeMax);
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(_bombGaugeKey, _bombGaugeMax);
      } catch (e) {
        print('💣 폭탄 게이지 리셋 저장 실패: $e');
      }
      print('💣 일일 리셋 - 폭탄 게이지 $_bombGaugeMax로 초기화');
    }

    // 🎉 '오늘 머니톡톡 종료' 해제 (게임 날짜가 바뀌었으므로 다시 플레이 가능)
    if (state.isMoneyTalkFinished) {
      state = state.copyWith(isMoneyTalkFinished: false);
      print('🎉 일일 리셋 - 오늘 종료 상태 해제');
    }

    // 로컬 저장소에 리셋된 상태 저장
    await _saveGameStateToPrefs();

    // 🪙 바닥 동전 재배치: 전날 동전을 걷어내고 초기 배치를 새로 뿌린다.
    //   최초 실행(아직 레이아웃 전)에는 isInitialized=false라 여기서 건너뛰고,
    //   뒤이어 호출되는 setLayoutParams가 didInitCoins=false를 보고 배치한다.
    if (state.isInitialized) {
      for (final coin in state.floorCoins) {
        coin.dispose(); // 진행 중이던 애니메이션 컨트롤러 정리
      }
      state = state.copyWith(floorCoins: [], didInitCoins: false);
      // 내부에서 상자 차감 + 로컬 저장 + 서버 반영 예약까지 처리
      dropInitialCoins(_maxFloorCoins);
      print('🪙 일일 리셋 - 바닥 동전 재배치 (상자=${state.luckyBagCount})');
    }

    // 버튼 상태 업데이트
    _updateRefillButtonStates();

    print('🔄 게임 진입시 리셋 완료 - 코인: ${state.luckyBagCount}개, 리필: ${state.rewardRefillCount}회, 자동적립: 레벨 1로 리셋');
  }

  /// 🔥 리필 시작 전 luckyBagCount를 서버에 즉시 동기화
  /// 로딩 다이얼로그 표시 중 앱 강제 종료 시에도 서버에 최신 값이 남도록 보장
  /// (_isRefilling 플래그를 설정하기 전에 호출되어야 함)
  Future<void> _syncLuckyBagCountBeforeRefill() async {
    if (state.hasLoadError) return;

    try {
      final user = _ref.read(currentUserProvider);
      if (user == null) {
        print('⚠️ 리필 사전 동기화 - user 없음, 건너뛰기');
        return;
      }

      // 서버 값과 다를 때만 동기화 (불필요한 요청 방지)
      if (state.luckyBagCount == user.luckyBagCount) {
        print('📦 리필 사전 동기화 - 서버 값과 동일(${state.luckyBagCount}), 건너뛰기');
        return;
      }

      print('🔥 리필 사전 동기화 시작: 로컬=${state.luckyBagCount}, 서버=${user.luckyBagCount}');

      _isSaving = true;
      try {
        final userRepo = _ref.read(userRepositoryProvider);
        await userRepo.addEarning(
          amount: 0, // 머니 변경 없음 (동기화 전용)
          luckyBagCount: state.luckyBagCount,
          source: 'moneyTalk',
        );

        // 로컬 캐시도 동기화
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('luckyBagCount', state.luckyBagCount);

        print('✅ 리필 사전 동기화 완료: ${state.luckyBagCount}');
      } finally {
        _isSaving = false;
      }
    } catch (e) {
      // 실패해도 리필은 계속 진행 (로컬 데이터 보호용 best-effort)
      print('⚠️ 리필 사전 동기화 실패 (계속 진행): $e');
    }
  }

  /// 옵션 A: 광고 없이 N개 동전 리필 (홀수 회차용 - 짧은 로딩)
  void handleRightRefillWithoutAd() async {
    final currentRound = _maxRefillCount - state.rewardRefillCount;
    final maxCoins = _calculateMaxCoins(state.rewardRefillCount);

    // 점진적 충전 회차인 경우 currentCoins 사용, 즉시 충전 회차인 경우 maxCoins 사용
    final coinsToRefill = (currentRound >= 2) ? state.currentCoins : maxCoins;

    print('옵션 A 선택 (디버그): ${currentRound}회차, maxCoins=$maxCoins, currentCoins=${state.currentCoins}, 최종 coinsToRefill=$coinsToRefill');

    // 🔥 크리티컬 버그 수정: 리필 로딩 중 강제 종료 대비 - 사전에 luckyBagCount 서버 동기화
    // (_isRefilling=true 설정 전에 동기화해야 함. 그렇지 않으면 inactive 콜백이 차단됨)
    await _syncLuckyBagCountBeforeRefill();

    // 🔒 리필 작업 시작 플래그 설정
    _isRefilling = true;
    print('🔒 리필 작업 시작 (1-2회차 광고 없음) - 서버 동기화 차단');

    // ✅ 충전 타이머 일시정지
    pauseFillTimer();

    // ✅ 리필 전 currentCoins를 0으로 먼저 설정 (깜빡임 방지)
    state = state.copyWith(currentCoins: 0);

    // ✅ 3초 로딩 다이얼로그 표시 후 리필 실행
    if (onShowRefillLoadingDialog != null) {
      onShowRefillLoadingDialog!(
        durationSeconds: 2,
        hasAd: false,
        onComplete: () {
          // ✅ 로딩 완료 후 충전 타이머 재개 및 리필 실행
          playRefillSound(); // 로딩 완료 시 소리 재생
          resumeFillTimer();
          _executeRefillWithAmount(coinsToRefill);
          _isRefilling = false;
        },
        onCancelled: () {
          // ✅ 취소 시 (백그라운드 전환) 타이머 재개하고 동전 복원
          print('⚠️ 1-2회차 리필 취소됨 - 동전 복원');
          resumeFillTimer();
          state = state.copyWith(currentCoins: coinsToRefill);
          _isRefilling = false;
          // 취소 팝업 표시
          onShowRefillCancelledDialog?.call();
        },
      );
    } else {
      // 콜백이 없으면 바로 실행 (fallback)
      resumeFillTimer();
      _executeRefillWithAmount(coinsToRefill);
      _isRefilling = false;
    }
  }

  /// ✅ right_refill 버튼 짝수 회차용: 7초 로딩 + 1초 시점 전면광고 호출
  void handleRightRefillWithInterstitialForRound(int round) async {
    // 점진적 충전 회차인 경우 currentCoins 사용
    final coinsToRefill = state.currentCoins;

    print('📦 right_refill 광고 리필 (${round}회차): currentCoins=${state.currentCoins}, coinsToRefill=$coinsToRefill');

    // 🔥 크리티컬 버그 수정: 리필 로딩 중 강제 종료 대비 - 사전에 luckyBagCount 서버 동기화
    // (_isRefilling=true 설정 전에 동기화해야 함. 그렇지 않으면 inactive 콜백이 차단됨)
    await _syncLuckyBagCountBeforeRefill();

    // 🔒 광고 표시 전 리필 플래그 설정
    _isRefilling = true;
    _refillAdCancelled = false; // 🚫 취소 플래그 초기화
    admobService.unblockAds(); // ✅ 광고 차단 해제 (새 리필 시작)
    print('🔒 리필 작업 시작 (${round}회차 전면광고) - 서버 동기화 차단');

    // ✅ 충전 타이머 일시정지
    pauseFillTimer();

    // ✅ 리필 전 currentCoins를 0으로 먼저 설정 (광고 후 이전 개수 깜빡임 방지)
    state = state.copyWith(currentCoins: 0);

    // ✅ 7초 로딩 다이얼로그 표시 (1초 시점에 광고 호출)
    if (onShowRefillLoadingDialog != null) {
      onShowRefillLoadingDialog!(
        durationSeconds: 7,
        hasAd: true,
        adTriggerSeconds: 1,
        onAdTrigger: () {
          // 🚫 취소된 경우 광고 호출하지 않음
          if (_refillAdCancelled) {
            print('🚫 ${round}회차 리필 취소됨 - 광고 호출 중단');
            return;
          }
          // ✅ 신규유저 전면광고 점진적 노출 체크
          final user = _ref.read(currentUserProvider);
          if (user != null && !NewUserAdUtils.shouldShowInterstitialAd(
            joinDate: user.joinDate,
            feature: AdFeature.moneyTalkTalk,
            currentRound: round,
          )) {
            print('📋 머니톡톡 ${round}회차 - 신규유저 전면광고 제한, 스킵');
            return;
          }
          // ✅ 2초 시점: 전면광고만 호출 (fallback 없음 - 리워드/보상형 전면 사용 안함)
          print('🎬 ${round}회차 리필 - 2초 시점 전면광고 호출 (fallback 없음)');
          setAdShowingState(true);
          admobService.loadAndShowInterstitialAd(
            onAdDismissed: () {
              // 🚫 취소된 경우 아무것도 하지 않음
              if (_refillAdCancelled) {
                print('🚫 ${round}회차 광고 닫힘 - 이미 취소됨, 무시');
                return;
              }
              print('🎯 ${round}회차 전면광고 닫힘');
              setAdShowingState(false);
              // 광고가 닫혀도 로딩 다이얼로그는 계속 진행 (10초까지)
            },
            onAdFailedToShow: (error) {
              // 🚫 취소된 경우 아무것도 하지 않음
              if (_refillAdCancelled) {
                print('🚫 ${round}회차 광고 실패 - 이미 취소됨, 무시');
                return;
              }
              print('🎯 ${round}회차 전면광고 표시 실패: $error - 로딩 계속 진행');
              setAdShowingState(false);
              // 실패해도 로딩 다이얼로그는 계속 진행 (10초까지)
            },
          );
        },
        onComplete: () {
          // ✅ 10초 로딩 완료 후 충전 타이머 재개 및 리필 실행
          print('✅ ${round}회차 리필 - 10초 로딩 완료, 리필 실행');
          playRefillSound(); // 로딩 완료 시 소리 재생
          resumeFillTimer();
          _executeRefillWithAmount(coinsToRefill);
          _isRefilling = false;
          _refillAdCancelled = false;
        },
        onCancelled: () {
          // ✅ 취소 시 (백그라운드 전환) 타이머 재개하고 동전 복원
          print('⚠️ ${round}회차 리필 취소됨 - 동전 복원 및 광고 차단');
          _refillAdCancelled = true; // 🚫 취소 플래그 설정 - 이후 광고 차단
          admobService.blockAds(); // 🚫 광고 표시 차단 (로드 완료된 광고도 차단)
          resumeFillTimer();
          state = state.copyWith(currentCoins: coinsToRefill);
          _isRefilling = false;
          setAdShowingState(false);
          // 취소 팝업 표시
          onShowRefillCancelledDialog?.call();
        },
      );
    } else {
      // 콜백이 없으면 기존 방식으로 fallback
      final String message = _getRefillMessageForRound(round);
      onShowCoinAdPreparationDialog?.call(message, () {
        resumeFillTimer();
        _executeRefillWithAmount(coinsToRefill);
        _isRefilling = false;
      });
    }
  }

  /// ✅ 회차별 고정 문구 반환 (3-10회차)
  String _getRefillMessageForRound(int round) {
    switch (round) {
      case 3:
        return '상자에 동전이 쌓이기 시작했어요! 🪙';
      case 4:
        return '차곡차곡 보관 중! 언제 꺼낼까요? 🤔';
      case 5:
        return '상자가 뚱뚱해지고 있어요! 🐷';
      case 6:
        return '절반 돌파! 상자가 든든하네요. 🛠️';
      case 7:
        return '벌써 상자가 꽤 묵직해졌어요! 📦';
      case 8:
        return '와! 상자가 터질 것 같아요. 💪';
      case 9:
        return '거의 다 찼어요! 한 번에 쏟아낼까요? 🔥';
      case 10:
        return '풀 리필 완료! 이제 동전 파티 시작! 🎉';
      default:
        return '동전을 모으는 중이에요! 💰';
    }
  }

  void _executeRefillWithAmount(int coinAmount) async {
    // 🎉 오늘 종료 상태면 리필 불가
    if (cycleSystemEnabled && state.isMoneyTalkFinished) {
      print('🎉 오늘 머니톡톡을 마쳐 리필할 수 없습니다');
      _isRefilling = false;
      return;
    }
    if (state.rewardRefillCount <= 0) {
      print('리필 횟수가 없어 리필할 수 없습니다.');
      _isRefilling = false; // 리필 불가능시 플래그 해제
      return;
    }

    // 홈화면 애니메이션 플래그 해제 (오른쪽 지갑 코인 소비)
    SharedPreferences.getInstance().then((prefs) => prefs.setBool('isRightRefillFull', false));

    // 🔔 지갑을 비웠으므로 기존 '가득 참' 알림 취소 (다음 충전 시작 시 재예약)
    NotificationService().cancelCoinPurseFullNotification();

    // 🔥 리필 전 리셋 상태 확인
    final user = _ref.read(currentUserProvider);
    if (user != null && state.sessionResetVersion != user.resetVersion) {
      print('⚠️ 리필 시작 전 리셋 감지 - 동기화 필요');
      await syncWithServerData();
      // 동기화 후 리필 가능 여부 재확인
      if (state.rewardRefillCount <= 0) {
        print('리셋 후 리필 횟수가 없어 리필할 수 없습니다.');
        _isRefilling = false;
        return;
      }
    }

    // 🔒 리필 작업 시작 - 플래그 설정 (이미 설정되어 있지 않은 경우만)
    if (!_isRefilling) {
      _isRefilling = true;
      print('🔒 리필 작업 시작 - 서버 동기화 차단');
    }

    final currentRefillCount = state.rewardRefillCount;
    // 🎉 이번 리필로 '다 쓰게 되는' 회차 (사이클 완주 판정 기준)
    final int consumedRound = _maxRefillCount - currentRefillCount;
    int remainingRefills = currentRefillCount - 1;
    // [핵심] 무한 리필 순환: 45회차 리필 시 46이 아니라 31회차로 되돌림.
    // → 3사이클(31~45)을 반복하며 금2%/20초/사이클 위치 기반 광고 유지. 서버 시드(50)는 미변경.
    // (rewardRefillCount는 6~50 범위를 벗어나지 않아 서버 상한/리셋과 충돌 없음)
    if (_refillCycleEnabled && (_maxRefillCount - remainingRefills) > _cycleBandEnd) {
      remainingRefills = _maxRefillCount - _cycleBandStart; // round 31 = 51 - 20
    }
    final fillSpeed = _calculateFillSpeed(currentRefillCount);

    print('리필 실행: ${coinAmount}개 동전, 남은 횟수: ${remainingRefills}');

    // 🔥 중요: 리필 전 현재 상태를 로컬에 먼저 저장
    await _saveGameStateToPrefs();
    print('💾 리필 전 로컬 상태 저장 완료');

    if (fillSpeed == 0) {
      // 즉시 리필 (1-2회차)
      state = state.copyWith(
        luckyBagCount: state.luckyBagCount + coinAmount,
        currentCoins: 0,
        rewardRefillCount: remainingRefills,
        maxCoins: _calculateMaxCoins(remainingRefills),
        fillSpeed: _calculateFillSpeed(remainingRefills),
        isFillingCoins: false,
        clearFillSpeedText: true,
      );

      // 로컬 저장 먼저 (네트워크 상태와 무관하게)
      await _saveGameStateToPrefs();
      print('💾 리필 후 로컬 상태 저장 완료');

      // 서버 저장 시도 (실패해도 로컬 데이터는 유지)
      try {
        await _saveImmediately();
      } catch (e) {
        print('⚠️ 서버 저장 실패 (로컬 데이터는 유지됨): $e');
        // 서버 저장 실패해도 계속 진행 (로컬 데이터는 이미 저장됨)
      }

      // 다음 리필이 점진적이면 자동으로 타이머 시작
      final nextFillSpeed = _calculateFillSpeed(remainingRefills);
      if (remainingRefills > 0 && nextFillSpeed > 0) {
        final nextMaxCoins = _calculateMaxCoins(remainingRefills);
        // fillSpeedText 형식: 0.5초면 "0.5초당 +1", 1초 이상이면 "N초당 +1"
        final nextFillSpeedText = nextFillSpeed < 1 ? '${nextFillSpeed}초당 +1' : '${nextFillSpeed.toInt()}초당 +1';
        print('즉시 리필 후 다음 점진적 충전 자동 시작: 속도=${nextFillSpeed}초당 1개, 최대=${nextMaxCoins}개');

        state = state.copyWith(
          isFillingCoins: true,
          fillSpeedText: nextFillSpeedText,
          currentCoins: 0,
          maxCoins: nextMaxCoins,
          fillSpeed: nextFillSpeed,
        );

        _startCoinFillingTimer(nextFillSpeed, nextMaxCoins, isNewCharge: true);
      }
    } else {
      state = state.copyWith(
        luckyBagCount: state.luckyBagCount + coinAmount,
        currentCoins: 0,
        rewardRefillCount: remainingRefills,
        maxCoins: _calculateMaxCoins(remainingRefills),
        fillSpeed: _calculateFillSpeed(remainingRefills),
        isFillingCoins: false,
        clearFillSpeedText: true,
      );

      // 로컬 저장 먼저 (네트워크 상태와 무관하게)
      await _saveGameStateToPrefs();
      print('💾 리필 후 로컬 상태 저장 완료');

      // 서버 저장 시도 (실패해도 로컬 데이터는 유지)
      try {
        await _saveImmediately();
      } catch (e) {
        print('⚠️ 서버 저장 실패 (로컬 데이터는 유지됨): $e');
        // 서버 저장 실패해도 계속 진행 (로컬 데이터는 이미 저장됨)
      }

      // 다음 리필이 점진적이면 자동으로 타이머 시작
      final nextFillSpeed = _calculateFillSpeed(remainingRefills);
      if (remainingRefills > 0 && nextFillSpeed > 0) {
        final nextMaxCoins = _calculateMaxCoins(remainingRefills);
        // fillSpeedText 형식: 0.5초면 "0.5초당 +1", 1초 이상이면 "N초당 +1"
        final nextFillSpeedText = nextFillSpeed < 1 ? '${nextFillSpeed}초당 +1' : '${nextFillSpeed.toInt()}초당 +1';
        print('점진적 리필 후 다음 점진적 충전 자동 시작: 속도=${nextFillSpeed}초당 1개, 최대=${nextMaxCoins}개');

        state = state.copyWith(
          isFillingCoins: true,
          fillSpeedText: nextFillSpeedText,
          currentCoins: 0,
          maxCoins: nextMaxCoins,
          fillSpeed: nextFillSpeed,
        );

        _startCoinFillingTimer(nextFillSpeed, nextMaxCoins, isNewCharge: true);
      }
    }

    _updateRefillButtonStates();

    // 최종 로컬 저장 (모든 상태 변경 후)
    await _saveGameStateToPrefs();
    print('💾 리필 완료 - 최종 로컬 상태 저장');

    // 🔓 리필 작업 완료 - 플래그 해제
    _isRefilling = false;
    print('🔓 리필 작업 완료 - 서버 동기화 허용');

    // 🎉 사이클 완주 체크 - '방금 다 쓴 회차'가 15/30/45면 모달
    //    (15회차를 소비해 16회차로 넘어간 시점 = 1사이클 완주)
    await _checkCycleComplete(completedRound: consumedRound);
  }
}

final gameProvider = StateNotifierProvider.autoDispose<GameNotifier, GameState>((ref) {
  final notifier = GameNotifier(ref);
  ref.onDispose(() {});
  return notifier;
});
