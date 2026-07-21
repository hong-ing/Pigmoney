import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import '../utils/log/logger.dart';

/// 게임 타입 enum
enum GameType {
  game1, // 머니톡톡
  game2, // 머니팡팡
}

/// BGM 서비스 - 싱글톤으로 화면 전환 시에도 재생 위치 유지
class BgmService {
  static final BgmService _instance = BgmService._internal();
  static BgmService get instance => _instance;

  factory BgmService() => _instance;
  BgmService._internal();

  // 각 게임별 AudioPlayer 인스턴스
  final Map<GameType, AudioPlayer> _players = {};

  // 각 게임별 현재 재생 상태
  final Map<GameType, bool> _isPlaying = {};

  // 현재 활성(마지막으로 play된) 게임. 광고/라이프사이클 콜백이 "현재 게임"만 제어하도록.
  GameType? _activeGame;
  GameType? get activeGame => _activeGame;

  // BGM 설정 캐시 (settings_provider가 갱신). resumeActive에서 동기 체크용.
  bool _bgmEnabled = true;
  void setBgmEnabled(bool value) {
    _bgmEnabled = value;
    // 끄면 현재 활성 게임 BGM 즉시 정지
    if (!value) {
      final g = _activeGame;
      if (g != null) pause(g);
    }
  }

  // 각 게임별 BGM 파일 경로
  final Map<GameType, String> _bgmPaths = {
    GameType.game1: 'audio/background_music.mp3',
    GameType.game2: 'audio/game2_bgm.mp3',
  };

  /// AudioPlayer 초기화 (한 번만 호출)
  Future<void> initialize(GameType gameType) async {
    if (_players.containsKey(gameType)) {
      logger.d('BGM Service: ${gameType.name} 이미 초기화됨');
      return;
    }

    try {
      final player = AudioPlayer();

      // iOS는 앱 전체 단일 AVAudioSession → main.dart의 전역 컨텍스트(playback+mixWithOthers)를
      // 그대로 상속. per-player setAudioContext는 전역 setCategory를 재실행해 재생 중 BGM을
      // 뭉갤 수 있으므로 iOS에서는 호출하지 않는다. Android만 per-player 컨텍스트 설정.
      if (!Platform.isIOS) {
        await player.setAudioContext(
          AudioContext(
            android: const AudioContextAndroid(
              isSpeakerphoneOn: false,
              audioMode: AndroidAudioMode.normal,
              stayAwake: false,
              contentType: AndroidContentType.music,
              usageType: AndroidUsageType.game,
              audioFocus: AndroidAudioFocus.gainTransientMayDuck,
            ),
          ),
        );
      }

      _players[gameType] = player;
      _isPlaying[gameType] = false;

      logger.d('BGM Service: ${gameType.name} 초기화 완료');
    } catch (e) {
      logger.e('BGM Service: ${gameType.name} 초기화 실패 - $e');
    }
  }

  /// BGM 재생 시작 (처음부터 또는 이어서)
  Future<void> play(GameType gameType, {bool fromStart = false}) async {
    print('🎵 BgmService.play() 시작 - gameType: ${gameType.name}, fromStart: $fromStart');

    // ★ 상호배제: 다른 게임 BGM은 완전 정지(pause 아님) → 두 BGM 동시 재생/겹침 방지.
    // iOS mixWithOthers라 두 player가 동시에 playing이면 실제로 겹쳐 들리므로 필수.
    for (final other in GameType.values) {
      if (other != gameType && _players.containsKey(other)) {
        await stop(other);
      }
    }
    _activeGame = gameType;

    await initialize(gameType);

    final player = _players[gameType];
    if (player == null) {
      print('🎵 BgmService.play() - player가 null입니다!');
      return;
    }

    try {
      final bgmPath = _bgmPaths[gameType];
      if (bgmPath == null) {
        print('🎵 BgmService.play() - bgmPath가 null입니다!');
        return;
      }

      print('🎵 BgmService.play() - player.state: ${player.state}, bgmPath: $bgmPath');

      // 이미 재생 중이면 무시
      if (player.state == PlayerState.playing) {
        print('🎵 BgmService.play() - 이미 재생 중');
        return;
      }

      // 일시정지 상태이고 fromStart가 false면 resume
      if (player.state == PlayerState.paused && !fromStart) {
        print('🎵 BgmService.play() - resume 실행');
        await player.resume();
        _isPlaying[gameType] = true;
        print('🎵 BgmService.play() - resume 완료');
        return;
      }

      // 처음부터 재생
      print('🎵 BgmService.play() - 처음부터 재생 시작');
      await player.play(AssetSource(bgmPath));
      await player.setReleaseMode(ReleaseMode.loop);
      _isPlaying[gameType] = true;
      print('🎵 BgmService.play() - 처음부터 재생 완료');
    } catch (e) {
      print('🎵 BgmService.play() - 재생 실패: $e');
    }
  }

  /// BGM 일시정지 (위치 유지)
  Future<void> pause(GameType gameType) async {
    final player = _players[gameType];
    if (player == null) return;

    try {
      if (player.state == PlayerState.playing) {
        await player.pause();
        logger.d('BGM Service: ${gameType.name} 일시정지');
      }
    } catch (e) {
      logger.e('BGM Service: ${gameType.name} 일시정지 실패 - $e');
    }
  }

  /// BGM 재개 (일시정지된 위치에서)
  Future<void> resume(GameType gameType) async {
    final player = _players[gameType];
    if (player == null) return;

    try {
      if (player.state == PlayerState.paused) {
        await player.resume();
        logger.d('BGM Service: ${gameType.name} 재개');
      } else if (player.state == PlayerState.stopped || player.state == PlayerState.completed) {
        // 정지 상태면 처음부터 재생
        await play(gameType, fromStart: true);
      }
    } catch (e) {
      logger.e('BGM Service: ${gameType.name} 재개 실패 - $e');
    }
  }

  /// 현재 활성 게임 BGM 일시정지 (광고/라이프사이클 콜백용 - 게임 종류 무관)
  Future<void> pauseActive() async {
    final g = _activeGame;
    if (g != null) await pause(g);
  }

  /// 현재 활성 게임 BGM 재개 (광고/라이프사이클 콜백용 - 게임 종류 무관)
  /// BGM 설정이 꺼져 있으면 no-op (설정 존중).
  Future<void> resumeActive() async {
    if (!_bgmEnabled) return;
    final g = _activeGame;
    if (g != null) await resume(g);
  }

  /// BGM 완전 정지 (위치 초기화)
  Future<void> stop(GameType gameType) async {
    final player = _players[gameType];
    if (player == null) return;

    try {
      await player.stop();
      _isPlaying[gameType] = false;
      logger.d('BGM Service: ${gameType.name} 정지');
    } catch (e) {
      logger.e('BGM Service: ${gameType.name} 정지 실패 - $e');
    }
  }

  /// 재생 중인지 확인
  bool isPlaying(GameType gameType) {
    final player = _players[gameType];
    if (player == null) return false;
    return player.state == PlayerState.playing;
  }

  /// 일시정지 상태인지 확인
  bool isPaused(GameType gameType) {
    final player = _players[gameType];
    if (player == null) return false;
    return player.state == PlayerState.paused;
  }

  /// 현재 재생 위치 가져오기
  Future<Duration?> getCurrentPosition(GameType gameType) async {
    final player = _players[gameType];
    if (player == null) return null;

    try {
      return await player.getCurrentPosition();
    } catch (e) {
      return null;
    }
  }

  /// 특정 위치로 이동
  Future<void> seek(GameType gameType, Duration position) async {
    final player = _players[gameType];
    if (player == null) return;

    try {
      await player.seek(position);
      logger.d('BGM Service: ${gameType.name} 위치 이동 - ${position.inSeconds}초');
    } catch (e) {
      logger.e('BGM Service: ${gameType.name} 위치 이동 실패 - $e');
    }
  }

  /// 리소스 해제 (앱 종료 시에만 호출)
  Future<void> dispose(GameType gameType) async {
    final player = _players[gameType];
    if (player == null) return;

    try {
      if (player.state != PlayerState.disposed) {
        await player.stop();
        await player.dispose();
      }
      _players.remove(gameType);
      _isPlaying.remove(gameType);
      logger.d('BGM Service: ${gameType.name} 리소스 해제');
    } catch (e) {
      logger.e('BGM Service: ${gameType.name} 리소스 해제 실패 - $e');
    }
  }

  /// 모든 BGM 리소스 해제
  Future<void> disposeAll() async {
    for (final gameType in GameType.values) {
      await dispose(gameType);
    }
  }
}

/// 전역 인스턴스
final bgmService = BgmService.instance;
