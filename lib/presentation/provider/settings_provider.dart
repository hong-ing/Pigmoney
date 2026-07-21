import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/services/bgm_service.dart';

// 설정 상태를 관리하는 클래스
class SettingsState {
  final bool isBgmEnabled;
  final bool isSfxEnabled;
  final bool isVibrationEnabled;

  SettingsState({
    required this.isBgmEnabled,
    required this.isSfxEnabled,
    required this.isVibrationEnabled,
  });

  SettingsState copyWith({
    bool? isBgmEnabled,
    bool? isSfxEnabled,
    bool? isVibrationEnabled,
  }) {
    return SettingsState(
      isBgmEnabled: isBgmEnabled ?? this.isBgmEnabled,
      isSfxEnabled: isSfxEnabled ?? this.isSfxEnabled,
      isVibrationEnabled: isVibrationEnabled ?? this.isVibrationEnabled,
    );
  }
}

// 설정 상태를 관리하는 Notifier
class SettingsNotifier extends StateNotifier<SettingsState> {
  SettingsNotifier() : super(SettingsState(isBgmEnabled: true, isSfxEnabled: true, isVibrationEnabled: true)) {
    _loadSettings();
  }

  // SharedPreferences에서 설정 로드
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    // 기존 isSoundEnabled 키가 있으면 마이그레이션
    final legacySound = prefs.getBool('isSoundEnabled');
    final bgm = prefs.getBool('isBgmEnabled') ?? legacySound ?? true;
    final sfx = prefs.getBool('isSfxEnabled') ?? legacySound ?? true;

    state = SettingsState(
      isBgmEnabled: bgm,
      isSfxEnabled: sfx,
      isVibrationEnabled: prefs.getBool('isVibrationEnabled') ?? true,
    );

    // bgmService에 BGM 설정 캐시 반영 (광고 콜백의 resumeActive가 설정 존중하도록)
    bgmService.setBgmEnabled(bgm);
  }

  // 배경음악 설정 변경
  Future<void> toggleBgm(bool value) async {
    state = state.copyWith(isBgmEnabled: value);
    bgmService.setBgmEnabled(value); // 끄면 현재 게임 BGM 즉시 정지
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isBgmEnabled', value);
  }

  // 효과음 설정 변경
  Future<void> toggleSfx(bool value) async {
    state = state.copyWith(isSfxEnabled: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isSfxEnabled', value);
  }

  // 진동 설정 변경
  Future<void> toggleVibration(bool value) async {
    state = state.copyWith(isVibrationEnabled: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isVibrationEnabled', value);
  }
}

// Provider 생성
final settingsProvider = StateNotifierProvider<SettingsNotifier, SettingsState>((ref) {
  return SettingsNotifier();
});
