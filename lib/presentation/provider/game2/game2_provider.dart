import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/bgm_service.dart';
import '../../../core/utils/korean_time_utils.dart';
import '../settings_provider.dart';
import '../user_provider.dart';
import 'game2_state.dart';

final game2Provider = StateNotifierProvider<Game2Notifier, Game2State>((ref) {
  return Game2Notifier(ref);
});

class Game2Notifier extends StateNotifier<Game2State> {
  final Ref ref;
  Timer? _summonTimer;
  Timer? _timerUpdateTimer;

  // BGM은 BgmService 싱글톤에서 관리 (화면 전환 시에도 재생 위치 유지)
  final AudioPlayer _brokenSoundPlayer = AudioPlayer();
  final AudioPlayer _collectSoundPlayer = AudioPlayer();

  // 터치 사운드 재사용 풀 (매 터치 NEW 플레이어 생성 금지 → iOS 세션 재구성/BGM 끊김 방지)
  final AudioPlayer _pigTouchPlayer = AudioPlayer();
  final List<AudioPlayer> _touchPool = List.generate(4, (_) => AudioPlayer());
  int _touchIdx = 0;
  bool _soundReady = false;

  // 🎯 크리티컬 시스템 스위치 (끄려면 false로만 변경)
  static const bool _game2CriticalEnabled = true;
  static const double _criticalChance = 0.05; // 5% 확률
  static const int _criticalDamage = 10; // 크리티컬 시 내구도 감소량

  final Random _random = Random();

  // 콜백 함수
  Function()? onPiggyBankBroken;

  // 🎯 크리티컬 발동 시 UI 연출 콜백 (강한 흔들림/큰 이펙트/CRITICAL 텍스트)
  Function()? onCritical;

  // ✅ 저금통 깨질 때 전면광고 준비 다이얼로그 콜백 (모든 단계)
  Function(String message, VoidCallback onComplete)? onShowBreakAdPreparationDialog;

  // ✅ 소환 완료 시 전면광고 노출 콜백 (5단계 이상, 플러스 선택 제거됨)
  VoidCallback? onShowSummonCompleteAd;

  Game2Notifier(this.ref) : super(const Game2State()) {
    _init();
  }

  Future<void> _init() async {
    await _loadGameState();
    await _checkDailyReset();
    await _configureSoundPlayers();

    // 소환 타이머 복원
    if (state.isSummoning && state.summonStartTime != null) {
      _restoreSummonTimer();
    }

    // 게임 상태 정상화 - 어떤 상태도 활성화되지 않은 경우 바로 저금통 소환
    if (!state.isPiggyBankActive && !state.isEmptyPiggyBank && !state.isSummoning && !state.hasReward && state.piggyBankCount > 0) {
      print('🔧 Game2: 비정상 상태 감지 - 바로 저금통 소환');
      print('🔧 현재 상태: round=${state.currentRound}, count=${state.piggyBankCount}');

      // 현재 라운드의 레벨로 바로 저금통 활성화 (소환 시간 없이)
      final currentLevel = min(state.currentRound, 10);
      final levelConfig = piggyBankLevels[currentLevel - 1];
      state = state.copyWith(
        isPiggyBankActive: true,
        isEmptyPiggyBank: false,
        currentLevel: currentLevel,
        currentDurability: levelConfig.durability,
        maxDurability: levelConfig.durability,
      );
    }

    state = state.copyWith(isLoading: false, isInitialized: true);
  }

  // 사운드 플레이어 설정
  Future<void> _configureSoundPlayers() async {
    try {
      // BGM은 BgmService에서 관리하므로 여기서 설정하지 않음.
      // iOS: 앱 전체 단일 AVAudioSession → 전역 컨텍스트(playback+mixWithOthers) 상속.
      //   런타임 per-player setAudioContext는 전역 setCategory를 재실행해 재생 중 BGM을
      //   뭉개므로 iOS에서는 호출하지 않는다.
      // Android: 플레이어별 audioFocus:none 필요 → 반드시 설정(회귀 방지).
      if (!Platform.isIOS) {
        final ctx = AudioContext(
          android: const AudioContextAndroid(
            contentType: AndroidContentType.sonification,
            usageType: AndroidUsageType.game,
            audioFocus: AndroidAudioFocus.none,
          ),
        );
        await _brokenSoundPlayer.setAudioContext(ctx);
        await _collectSoundPlayer.setAudioContext(ctx);
        await _pigTouchPlayer.setAudioContext(ctx);
        for (final p in _touchPool) {
          await p.setAudioContext(ctx);
        }
      }

      // 효과음 플레이어 사전 설정 (release 대신 stop → 재사용, 완료 시 teardown 축소)
      for (final p in _touchPool) {
        await p.setReleaseMode(ReleaseMode.stop);
        await p.setVolume(0.15);
      }
      await _pigTouchPlayer.setReleaseMode(ReleaseMode.stop);
      await _pigTouchPlayer.setVolume(0.5);

      _soundReady = true;
    } catch (e) {}
  }

  // BGM 재생
  void playBackgroundMusic() async {
    try {
      final settings = ref.read(settingsProvider);
      if (!settings.isBgmEnabled) {
        print('🔇 Game2 BGM: 배경음악 설정이 꺼져있음');
        return;
      }

      print('🎵 Game2 BGM 재생 시작');
      // BgmService 사용 - 일시정지 상태면 이어서 재생, 아니면 처음부터
      await bgmService.play(GameType.game2, fromStart: false);

      state = state.copyWith(isBgmPlaying: true);
      print('🎵 Game2 BGM 재생 성공');
    } catch (e) {
      print('❌ Game2 BGM 재생 실패: $e');
    }
  }

  // BGM 정지 (화면 나갈 때는 pause로 위치 유지)
  void stopBackgroundMusic() async {
    try {
      await bgmService.pause(GameType.game2);
      state = state.copyWith(isBgmPlaying: false);
    } catch (e) {}
  }

  // BGM 일시정지
  void pauseBackgroundMusic() async {
    try {
      await bgmService.pause(GameType.game2);
    } catch (e) {}
  }

  // BGM 재개
  void resumeBackgroundMusic() async {
    try {
      final settings = ref.read(settingsProvider);
      if (settings.isBgmEnabled) {
        await bgmService.resume(GameType.game2);
      }
    } catch (e) {}
  }

  // 터치 사운드 재생 (재사용 풀 사용 - NEW 플레이어/ setAudioContext 없음 → iOS BGM 세션 보호)
  void playTouchSound({bool critical = false}) {
    try {
      if (!ref.read(settingsProvider).isSfxEnabled || !_soundReady) return;

      // 풀에서 다음 플레이어 선택 (라운드로빈). 컨텍스트는 설정 시 1회만.
      final player = _touchPool[_touchIdx];
      _touchIdx = (_touchIdx + 1) % _touchPool.length;

      player.stop(); // 재생 중이면 처음으로 리셋 (setCategory/setActive 미유발)
      // 크리티컬은 더 크게 (일반 0.15 → 크리티컬 0.5). setVolume은 세션 재구성 없음.
      player.setVolume(critical ? 0.5 : 0.15);
      player.play(AssetSource('audio/game2_touch.mp3'));
    } catch (e) {
      print('❌ 터치 사운드 재생 실패: $e');
    }
  }

  // 깨짐 사운드 재생
  void playBrokenSound() async {
    try {
      final settings = ref.read(settingsProvider);
      if (!settings.isSfxEnabled) {
        print('🔇 Game2: 깨짐 사운드 - 설정 꺼짐');
        return;
      }

      print('💥 Game2: 깨짐 사운드 재생');
      await _brokenSoundPlayer.play(AssetSource('audio/game2_break.mp3'));
      await _brokenSoundPlayer.setVolume(0.5);
    } catch (e) {
      print('❌ Game2: 깨짐 사운드 재생 실패: $e');
    }
  }

  // 수집 사운드 재생
  void playCollectSound() async {
    try {
      final settings = ref.read(settingsProvider);
      if (!settings.isSfxEnabled) return;

      await _collectSoundPlayer.play(AssetSource('audio/pig_deposit_sound.mp3'));
      await _collectSoundPlayer.setVolume(0.5);
    } catch (e) {}
  }

  // 돼지 터치 사운드 재생 (레벨 선택) - 재사용 플레이어(누수/ setAudioContext 없음)
  void playPigTouchSound() async {
    try {
      if (!ref.read(settingsProvider).isSfxEnabled) return;

      await _pigTouchPlayer.stop();
      await _pigTouchPlayer.play(AssetSource('audio/pig_touch.mp3'));
    } catch (e) {}
  }

  // 첫 라운드 저금통 활성화
  void _activateFirstRoundPiggyBank() {
    final levelConfig = piggyBankLevels[0]; // Level 1
    state = state.copyWith(
      isPiggyBankActive: true,
      isEmptyPiggyBank: false,
      currentLevel: 1,
      currentDurability: levelConfig.durability,
      maxDurability: levelConfig.durability,
    );
  }

  // ✅ 현재 라운드에 맞는 저금통 즉시 활성화 (소환 시간 없이)
  void _activatePiggyBankForCurrentRound() {
    final currentLevel = min(state.currentRound, 10);
    final levelConfig = piggyBankLevels[currentLevel - 1];
    print('🐷 저금통 즉시 활성화 - 라운드: ${state.currentRound}, 레벨: $currentLevel');
    state = state.copyWith(
      isPiggyBankActive: true,
      isEmptyPiggyBank: false,
      currentLevel: currentLevel,
      currentDurability: levelConfig.durability,
      maxDurability: levelConfig.durability,
    );
  }

  // 저금통 터치 (내구도 감소)
  void touchPiggyBank() {
    if (!state.isPiggyBankActive || state.currentDurability <= 0) return;

    // 🎯 크리티컬 판정 (5% 확률)
    final bool isCritical = _game2CriticalEnabled && _random.nextDouble() < _criticalChance;

    // 터치 사운드 재생 (크리티컬은 더 크게)
    playTouchSound(critical: isCritical);

    // 진동 - 일반: medium(강함), 크리티컬: heavy(더 강함)
    if (isCritical) {
      HapticFeedback.heavyImpact();
    } else {
      HapticFeedback.mediumImpact();
    }

    // 내구도 감소 (크리티컬 -10, 일반 -1). 0 밑으로는 내려가지 않게 clamp.
    final int damage = isCritical ? _criticalDamage : 1;
    final int newDurability = (state.currentDurability - damage).clamp(0, state.maxDurability);
    state = state.copyWith(
      currentDurability: newDurability,
      isShaking: true,
    );

    // 🎯 크리티컬 연출 콜백 (강한 흔들림/큰 이펙트/CRITICAL 텍스트)
    if (isCritical) {
      onCritical?.call();
    }

    // 쉐이킹 효과 제거
    Future.delayed(const Duration(milliseconds: 100), () {
      state = state.copyWith(isShaking: false);
    });

    // 내구도가 0이면 깨짐 처리
    if (newDurability <= 0) {
      _breakPiggyBank();
    }

    _saveGameState();
  }

  // ✅ 머니팡팡 랜덤 문구 리스트
  static const List<String> _breakAdMessages = [
    '두구두구… 대박의 기운이 느껴져요! 🎰',
    '와! 꽤 묵직한데요? 내용물을 확인 중입니다! ✨',
    '와르르! 쏟아진 동전들을 예쁘게 모으고 있어요! 💰',
    '잠시만요! 흩어진 머니들을 하나씩 세어보고 있어요! 🧮',
    '두근두근… 깨진 저금통 안에 얼마가 들어있을까요? 🔍',
    '오늘 운세 최고! 저금통 속에 보물이 가득해 보여요 🌈',
    '와, 이 소리 들리세요? 짤랑거리는 소리가 엄청나요! 🎵',
    '대박 예감! 쏟아지는 코인을 기대하세요! 🔥',
    '와! 숨겨진 보너스 동전까지 탈탈 털어 모으는 중이에요! 🧺',
    '와! 동전 탑이 완성됐어요. 무너지기 전에 얼른 수거할게요! 🗼',
    '운수 좋은 날! 코인 요정이 당신의 저금통을 가득 채웠나 봐요 🧚',
    '찰랑찰랑~ 쏟아지는 동전 소리에 기분까지 좋아지네요! 😊',
    '금빛 행운이 쏟아져요! 하나도 빠짐없이 금고에 담아낼게요! 🏦',
    '지금 이 기분! 쏟아지는 동전 소리만큼 짜릿한 건 없죠? ⚡',
    '저금통 속 머니 확인 완료! 이제 당신의 지갑으로 배달 갑니다! 🚚',
  ];

  // 저금통 깨짐 처리
  void _breakPiggyBank() {
    playBrokenSound();

    // 보상 계산 (플러스 선택 제거됨 - 레벨 기본 보상 범위 사용)
    final levelConfig = piggyBankLevels[state.currentLevel - 1];
    final random = Random();
    final reward = levelConfig.minReward + random.nextInt(levelConfig.maxReward - levelConfig.minReward + 1);

    // 플래시 효과 시작
    state = state.copyWith(
      isPiggyBankActive: false,
      showFlashEffect: true,
    );

    // 플래시 효과 제거 (시간 증가: 500ms -> 800ms)
    Future.delayed(const Duration(milliseconds: 800), () {
      state = state.copyWith(showFlashEffect: false);
    });

    onPiggyBankBroken?.call();

    // ✅ 모든 단계: 전면광고 준비 다이얼로그 표시 후 보상 표시
    if (state.currentLevel >= 1) {
      final randomMessage = _breakAdMessages[random.nextInt(_breakAdMessages.length)];
      print('🎯 머니팡팡 전면광고 준비 - 레벨: ${state.currentLevel}, 메시지: $randomMessage');

      // 다이얼로그 완료 후 보상 상태로 전환
      onShowBreakAdPreparationDialog?.call(randomMessage, () {
        _setRewardState(reward);
      });
    } else {
      // 1단계: 바로 보상 표시
      _setRewardState(reward);
    }

    _saveGameState();
  }

  // ✅ 보상 상태 설정 (전면광고 후 호출)
  void _setRewardState(int reward) {
    state = state.copyWith(
      hasReward: true,
      rewardAmount: reward,
    );
    _saveGameState();
  }

  // ✅ 보상 수집 (동전탑 터치 시 호출)
  // 모든 단계: 바로 수령 후 다음 단계 소환 (5단계는 소환 완료 후 돼지 선택 팝업 표시)
  Future<void> collectReward() async {
    if (!state.hasReward || state.isCollectingReward) return;

    // 모든 단계 바로 수령
    await _collectRewardNormal();
  }

  // ✅ 일반 보상 수령 (1배)
  Future<void> _collectRewardNormal() async {
    if (!state.hasReward) return;

    state = state.copyWith(isCollectingReward: true);
    playCollectSound();

    try {
      final userRepo = ref.read(userRepositoryProvider);
      final currentUser = ref.read(currentUserProvider);
      if (currentUser != null) {
        await userRepo.addEarning(amount: state.rewardAmount);
        await ref.read(currentUserProvider.notifier).fetchCurrentUser(forceRefresh: true);
      }
    } catch (e) {
      print('보상 수령 오류: $e');
    }

    await _proceedToNextRound();
  }

  // ✅ 광고 표시 상태 설정 (외부에서 호출 가능)
  void setIsShowingAd(bool value) {
    state = state.copyWith(isShowingAd: value);
  }

  // ✅ 다음 라운드로 진행 (보상 수령 후)
  Future<void> _proceedToNextRound() async {
    final nextRound = state.currentRound + 1;

    if (nextRound > 10 || state.piggyBankCount <= 0) {
      // 하루 게임 완료 - 레벨 11 업데이트 (종료 상태)
      state = state.copyWith(
        hasReward: false,
        rewardAmount: 0,
        isCollectingReward: false,
        isPiggyBankActive: false,
        isEmptyPiggyBank: false,
        currentRound: 10,
        piggyBankCount: 0,
      );

      // 홈화면 애니메이션 플래그 해제
      SharedPreferences.getInstance().then((prefs) => prefs.setBool('isPigSummonComplete', false));

      // 서버에 레벨 11(완료) 업데이트
      final userRepository = ref.read(userRepositoryProvider);
      await userRepository.updatePigBankBreakLevel(11);
    } else {
      // ✅ 다음 라운드로 - 바로 다음 단계 저금통 자동 소환
      state = state.copyWith(
        hasReward: false,
        rewardAmount: 0,
        isCollectingReward: false,
        currentRound: nextRound,
      );

      // 서버에 현재 레벨 업데이트
      final userRepository = ref.read(userRepositoryProvider);
      await userRepository.updatePigBankBreakLevel(nextRound);

      // ✅ 자동으로 다음 단계 저금통 소환
      _autoStartNextLevel(nextRound);
    }

    _saveGameState();
  }

  // ✅ 자동으로 다음 단계 저금통 소환 (레벨 선택 없이)
  void _autoStartNextLevel(int nextRound) {
    if (state.piggyBankCount <= 0) return;

    final nextLevel = min(nextRound, 10);
    final levelConfig = piggyBankLevels[nextLevel - 1];

    print('🐷 자동 소환 시작 - 라운드: $nextRound, 레벨: $nextLevel');

    // piggyBankCount 감소
    final newPiggyBankCount = state.piggyBankCount - 1;

    // 즉시 소환인 경우 (레벨 1만 해당)
    if (levelConfig.summonTime == 0) {
      state = state.copyWith(
        isEmptyPiggyBank: false,
        isPiggyBankActive: true,
        currentLevel: nextLevel,
        currentDurability: levelConfig.durability,
        maxDurability: levelConfig.durability,
        piggyBankCount: newPiggyBankCount,
      );
    } else {
      // 타이머 소환
      state = state.copyWith(
        isEmptyPiggyBank: false,
        isSummoning: true,
        currentLevel: nextLevel,
        summonStartTime: DateTime.now(),
        summonDuration: levelConfig.summonTime,
        piggyBankCount: newPiggyBankCount,
      );

      // 홈화면 애니메이션 플래그 해제
      SharedPreferences.getInstance().then((prefs) => prefs.setBool('isPigSummonComplete', false));

      _startSummonTimer();
    }

    _saveGameState();
  }

  // ✅ 빈 저금통 터치 (레벨 선택 없이 자동 소환)
  void touchEmptyPiggyBank() {
    if (!state.isEmptyPiggyBank || state.isSummoning) return;
    if (state.piggyBankCount <= 0) return;

    playPigTouchSound();

    // 현재 라운드의 레벨로 자동 소환 시작
    _autoStartNextLevel(state.currentRound);
  }

  // 소환 타이머 시작
  void _startSummonTimer() {
    _summonTimer?.cancel();
    _timerUpdateTimer?.cancel();

    // 매초 타이머 업데이트
    _timerUpdateTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateSummonTimer();
    });
  }

  // 소환 타이머 업데이트
  void _updateSummonTimer() {
    if (!state.isSummoning || state.summonStartTime == null) {
      _summonTimer?.cancel();
      _timerUpdateTimer?.cancel();
      return;
    }

    final now = DateTime.now();
    final elapsed = now.difference(state.summonStartTime!).inSeconds;
    final remaining = state.summonDuration - elapsed;

    if (remaining <= 0) {
      // 소환 완료
      _completeSummoning();
    } else {
      // 타이머 텍스트 업데이트
      final hours = remaining ~/ 3600;
      final minutes = (remaining % 3600) ~/ 60;
      final seconds = remaining % 60;
      final timerText = '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

      state = state.copyWith(summonTimerText: timerText);
    }
  }

  // 소환 완료
  void _completeSummoning() async {
    _summonTimer?.cancel();
    _timerUpdateTimer?.cancel();

    // 홈화면 애니메이션 플래그 설정 (상태 변경 전에 먼저 저장)
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isPigSummonComplete', true);

    final levelConfig = piggyBankLevels[state.currentLevel - 1];

    // ✅ 플러스 선택 제거: 모든 단계 바로 저금통 활성화
    state = state.copyWith(
      isSummoning: false,
      isPiggyBankActive: true,
      currentDurability: levelConfig.durability,
      maxDurability: levelConfig.durability,
      clearSummonStartTime: true,
      clearSummonTimerText: true,
    );

    // ✅ 5단계 이상: 소환 완료 시 전면광고 바로 노출 (기존 선택 팝업 대체)
    if (state.currentLevel >= 5) {
      print('🐷 ${state.currentLevel}단계 소환 완료 - 전면광고 노출');
      onShowSummonCompleteAd?.call();
    }

    _saveGameState();
  }

  // ✅ 현재 레벨의 최대 보상 (플러스 선택 제거됨)
  int get actualMaxReward => piggyBankLevels[state.currentLevel - 1].maxReward;

  // ✅ 현재 레벨의 돼지 이미지 (플러스 선택 제거됨)
  String get actualPigImage => piggyBankLevels[state.currentLevel - 1].pigImage;

  // 소환 타이머 복원
  void _restoreSummonTimer() {
    if (!state.isSummoning || state.summonStartTime == null) return;

    final now = DateTime.now();
    final elapsed = now.difference(state.summonStartTime!).inSeconds;
    final remaining = state.summonDuration - elapsed;

    if (remaining <= 0) {
      _completeSummoning();
    } else {
      _startSummonTimer();
    }
  }

  // 일일 리셋 체크 (내부용)
  Future<void> _checkDailyReset() async {
    final currentGameDateKey = KoreanTimeUtils.getCurrentGameDateKey();

    // lastPlayedDate가 null이거나 날짜가 다르면 리셋
    if (state.lastPlayedDate == null) {
      // 첫 실행
      state = state.copyWith(lastPlayedDate: currentGameDateKey);
      await _saveGameState();
    } else if (state.lastPlayedDate != currentGameDateKey) {
      // 게임 날짜가 변경됨 (5 AM KST 기준으로 날짜가 바뀜)
      print('🎮 Game2: 새로운 게임 날짜 감지 - 이전: ${state.lastPlayedDate}, 현재: $currentGameDateKey');
      await _resetDailyGame();
    }
  }

  // 게임 화면 진입 시 일일 리셋 체크 (public method)
  Future<void> checkDailyResetOnGameEntry() async {
    print('🎮 Game2: 게임 화면 진입 시 일일 리셋 체크 시작');

    final currentGameDateKey = KoreanTimeUtils.getCurrentGameDateKey();

    if (state.lastPlayedDate == null) {
      print('🎮 Game2: 첫 실행 - lastPlayedDate 설정: $currentGameDateKey');
      state = state.copyWith(lastPlayedDate: currentGameDateKey);
      await _saveGameState();
      // 첫 실행 시 바로 저금통 활성화
      if (!state.isPiggyBankActive && !state.isEmptyPiggyBank && !state.isSummoning && !state.hasReward && state.piggyBankCount > 0) {
        print('🎮 Game2: 첫 실행 - 바로 저금통 활성화');
        _activatePiggyBankForCurrentRound();
        await _saveGameState();
      }
      return;
    }

    // 게임 날짜 비교 (5 AM KST 기준)
    print('🎮 Game2 리셋 체크:');
    print('   마지막 플레이: ${state.lastPlayedDate}');
    print('   현재 게임 날짜: $currentGameDateKey');
    print('   리셋 필요: ${state.lastPlayedDate != currentGameDateKey}');

    if (state.lastPlayedDate != currentGameDateKey) {
      print('🌅 Game2: 새벽 5시 기준 새로운 날 - 게임 리셋 실행');
      await _resetDailyGame();
    } else {
      // 날짜가 같지만 상태가 비정상인 경우 바로 저금통 활성화
      if (!state.isPiggyBankActive && !state.isEmptyPiggyBank && !state.isSummoning && !state.hasReward && state.piggyBankCount > 0) {
        print('⚠️ Game2: 비정상 상태 감지 - 바로 저금통 활성화');
        _activatePiggyBankForCurrentRound();
        await _saveGameState();
      }
    }
  }

  // 일일 게임 리셋
  Future<void> _resetDailyGame() async {
    final todayString = KoreanTimeUtils.getCurrentGameDateKey();

    print('🔄 Game2: 일일 리셋 실행 - 새로운 날짜: $todayString');

    // 모든 상태 초기화
    state = const Game2State().copyWith(
      lastPlayedDate: todayString,
      currentRound: 1,
      piggyBankCount: 10,
      isLoading: false,
      isInitialized: true,
    );

    // 서버에 레벨 1로 리셋
    final userRepository = ref.read(userRepositoryProvider);
    await userRepository.updatePigBankBreakLevel(1);

    // 첫 라운드 저금통 활성화
    _activateFirstRoundPiggyBank();

    await _saveGameState();
  }

  // 게임 상태 저장
  Future<void> _saveGameState() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.setInt('game2_currentRound', state.currentRound);
      await prefs.setInt('game2_piggyBankCount', state.piggyBankCount);
      await prefs.setInt('game2_currentLevel', state.currentLevel);
      await prefs.setInt('game2_currentDurability', state.currentDurability);
      await prefs.setInt('game2_maxDurability', state.maxDurability);
      await prefs.setBool('game2_isPiggyBankActive', state.isPiggyBankActive);
      await prefs.setBool('game2_isEmptyPiggyBank', state.isEmptyPiggyBank);
      await prefs.setBool('game2_isSummoning', state.isSummoning);
      await prefs.setInt('game2_summonDuration', state.summonDuration);
      await prefs.setBool('game2_hasReward', state.hasReward);
      await prefs.setInt('game2_rewardAmount', state.rewardAmount);

      if (state.summonStartTime != null) {
        await prefs.setString('game2_summonStartTime', state.summonStartTime!.toIso8601String());
      } else {
        await prefs.remove('game2_summonStartTime');
      }

      if (state.lastPlayedDate != null) {
        await prefs.setString('game2_lastPlayedDate', state.lastPlayedDate!);
      }

      // 로컬에서만 piggyBankCount 관리
    } catch (e) {}
  }

  // 게임 상태 로드
  Future<void> _loadGameState() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 서버에서 저금통깨기 레벨 가져오기
      final user = ref.read(currentUserProvider);
      final serverPigBankBreakLevel = user?.pigBankBreakLevel ?? 0;
      final localCurrentRound = prefs.getInt('game2_currentRound') ?? 1;

      // 서버 레벨이 0이면 처음 사용하는 것이므로 로컬 값 사용
      // 서버 레벨이 11이면 완료 상태
      // 구버전(5회차 시스템)의 완료 상태 6 마이그레이션: 구앱은 완료 시 로컬 round=5를
      // 저장했으므로, 서버=6 + 로컬<=5 조합은 구버전 완료로 판단.
      // (신버전에서 6회차 진행 중이면 로컬 round도 6이므로 구분됨)
      // 그 외에는 서버 값 사용
      int currentRound;
      final isCompletedOnServer = serverPigBankBreakLevel == 11 ||
          (serverPigBankBreakLevel == 6 && localCurrentRound <= 5);
      if (serverPigBankBreakLevel == 0) {
        currentRound = localCurrentRound;
      } else if (isCompletedOnServer) {
        // 완료 상태 - 10라운드로 설정하고 piggyBankCount를 0으로
        currentRound = 10;
      } else {
        currentRound = serverPigBankBreakLevel;
      }

      // 서버와 로컬이 다르면 로그 출력
      if (serverPigBankBreakLevel > 0 && serverPigBankBreakLevel != localCurrentRound) {
        print('🔄 저금통깨기 레벨 서버 동기화: 로컬($localCurrentRound) → 서버($serverPigBankBreakLevel)');
      }

      // 서버가 완료 상태면 piggyBankCount를 0으로 설정
      final localPiggyBankCount = prefs.getInt('game2_piggyBankCount') ?? 10;
      final piggyBankCount = isCompletedOnServer ? 0 : localPiggyBankCount;
      final currentLevel = prefs.getInt('game2_currentLevel') ?? 1;
      final currentDurability = prefs.getInt('game2_currentDurability') ?? 100;
      final maxDurability = prefs.getInt('game2_maxDurability') ?? 100;
      final isPiggyBankActive = prefs.getBool('game2_isPiggyBankActive') ?? false;
      final isEmptyPiggyBank = prefs.getBool('game2_isEmptyPiggyBank') ?? false;
      final isSummoning = prefs.getBool('game2_isSummoning') ?? false;
      final summonDuration = prefs.getInt('game2_summonDuration') ?? 0;
      final hasReward = prefs.getBool('game2_hasReward') ?? false;
      final rewardAmount = prefs.getInt('game2_rewardAmount') ?? 0;
      final lastPlayedDate = prefs.getString('game2_lastPlayedDate');

      DateTime? summonStartTime;
      final summonStartTimeStr = prefs.getString('game2_summonStartTime');
      if (summonStartTimeStr != null) {
        summonStartTime = DateTime.parse(summonStartTimeStr);
      }

      state = state.copyWith(
        currentRound: currentRound,
        piggyBankCount: piggyBankCount,
        currentLevel: currentLevel,
        currentDurability: currentDurability,
        maxDurability: maxDurability,
        isPiggyBankActive: isPiggyBankActive,
        isEmptyPiggyBank: isEmptyPiggyBank,
        isSummoning: isSummoning,
        summonStartTime: summonStartTime,
        summonDuration: summonDuration,
        hasReward: hasReward,
        rewardAmount: rewardAmount,
        lastPlayedDate: lastPlayedDate,
      );
    } catch (e) {}
  }

  @override
  void dispose() {
    // 타이머 먼저 취소
    _summonTimer?.cancel();
    _timerUpdateTimer?.cancel();

    // BGM은 BgmService 싱글톤에서 관리하므로 여기서 dispose하지 않음
    // 화면 나갈 때 pause만 호출됨 (위치 유지)

    // 깨짐 사운드 플레이어 안전하게 정리
    try {
      if (_brokenSoundPlayer.state != PlayerState.disposed) {
        _brokenSoundPlayer.stop();
        Future.delayed(const Duration(milliseconds: 100), () {
          _brokenSoundPlayer.dispose();
        });
      }
    } catch (e) {
      print('깨짐 사운드 플레이어 dispose 에러: $e');
    }

    // 수집 사운드 플레이어 안전하게 정리
    try {
      if (_collectSoundPlayer.state != PlayerState.disposed) {
        _collectSoundPlayer.stop();
        Future.delayed(const Duration(milliseconds: 100), () {
          _collectSoundPlayer.dispose();
        });
      }
    } catch (e) {
      print('수집 사운드 플레이어 dispose 에러: $e');
    }

    // 터치 사운드 재사용 풀 + 돼지터치 플레이어 정리
    for (final player in [..._touchPool, _pigTouchPlayer]) {
      try {
        if (player.state != PlayerState.disposed) {
          player.stop();
          Future.delayed(const Duration(milliseconds: 50), () {
            player.dispose();
          });
        }
      } catch (e) {
        print('터치 사운드 플레이어 dispose 에러: $e');
      }
    }

    super.dispose();
  }
}
