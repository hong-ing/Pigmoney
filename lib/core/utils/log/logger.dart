import 'package:flutter/foundation.dart';

/// 로깅 유틸리티 클래스
/// 앱 전체에서 일관된 로깅을 제공합니다.
class Logger {
  // 로그 레벨
  static const int _verboseLevel = 0;
  static const int _debugLevel = 1;
  static const int _infoLevel = 2;
  static const int _warningLevel = 3;
  static const int _errorLevel = 4;

  // 현재 로그 레벨 - 릴리즈 모드에서는 정보 레벨 이상만 표시
  final int _currentLevel = kReleaseMode ? _infoLevel : _verboseLevel;

  // 태그
  final String _tag = '🐷 PigMoney';

  // 싱글톤 인스턴스
  static final Logger _instance = Logger._internal();
  factory Logger() => _instance;
  Logger._internal();

  /// 상세 로그
  void v(dynamic message) {
    if (_currentLevel <= _verboseLevel) {
      debugPrint('$_tag [VERBOSE] $message');
    }
  }

  /// 디버그 로그
  void d(dynamic message) {
    if (_currentLevel <= _debugLevel) {
      debugPrint('$_tag [DEBUG] $message');
    }
  }

  /// 정보 로그
  void i(dynamic message) {
    if (_currentLevel <= _infoLevel) {
      debugPrint('$_tag [INFO] $message');
    }
  }

  /// 경고 로그
  void w(dynamic message) {
    if (_currentLevel <= _warningLevel) {
      debugPrint('$_tag [WARN] $message');
    }
  }

  /// 에러 로그
  void e(dynamic message) {
    if (_currentLevel <= _errorLevel) {
      debugPrint('$_tag [ERROR] $message');
    }
  }
}

/// 앱 전체에서 사용할 로거 인스턴스
final logger = Logger();
