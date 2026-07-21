import 'dart:async';
import 'dart:math';

import '../exceptions/giftishow_exceptions.dart';

/// 재시도 헬퍼 클래스
/// 
/// API 호출 실패 시 자동 재시도 로직을 제공합니다.
class RetryHelper {
  static const int _defaultMaxRetries = 3;
  static const Duration _defaultInitialDelay = Duration(seconds: 1);
  static const double _defaultBackoffMultiplier = 2.0;
  static const Duration _defaultMaxDelay = Duration(seconds: 30);

  /// 지수 백오프와 함께 재시도 실행
  /// 
  /// [operation]: 실행할 작업
  /// [maxRetries]: 최대 재시도 횟수
  /// [initialDelay]: 초기 지연 시간
  /// [backoffMultiplier]: 백오프 배수
  /// [maxDelay]: 최대 지연 시간
  /// [shouldRetry]: 재시도 여부를 결정하는 함수
  static Future<T> executeWithRetry<T>(
    Future<T> Function() operation, {
    int maxRetries = _defaultMaxRetries,
    Duration initialDelay = _defaultInitialDelay,
    double backoffMultiplier = _defaultBackoffMultiplier,
    Duration maxDelay = _defaultMaxDelay,
    bool Function(Exception)? shouldRetry,
  }) async {
    int attempt = 0;
    Duration currentDelay = initialDelay;

    while (true) {
      try {
        return await operation();
      } catch (e) {
        attempt++;

        // 재시도 가능한 예외인지 확인
        final exception = e is Exception ? e : Exception(e.toString());
        final canRetry = shouldRetry?.call(exception) ?? _defaultShouldRetry(exception);

        if (!canRetry || attempt >= maxRetries) {
          rethrow;
        }

        // 지연 후 재시도
        await Future.delayed(currentDelay);
        
        // 다음 지연 시간 계산 (지수 백오프)
        currentDelay = Duration(
          milliseconds: min(
            (currentDelay.inMilliseconds * backoffMultiplier).round(),
            maxDelay.inMilliseconds,
          ),
        );
      }
    }
  }

  /// 기본 재시도 여부 판단 로직
  static bool _defaultShouldRetry(Exception exception) {
    if (exception is GiftishowException) {
      return exception.isRetryable;
    }

    // 네트워크 관련 에러들은 재시도 가능
    final message = exception.toString().toLowerCase();
    return message.contains('timeout') ||
           message.contains('connection') ||
           message.contains('network') ||
           message.contains('socket');
  }

  /// 간단한 재시도 (고정 지연 시간)
  static Future<T> executeWithFixedDelay<T>(
    Future<T> Function() operation, {
    int maxRetries = _defaultMaxRetries,
    Duration delay = _defaultInitialDelay,
    bool Function(Exception)? shouldRetry,
  }) async {
    return executeWithRetry(
      operation,
      maxRetries: maxRetries,
      initialDelay: delay,
      backoffMultiplier: 1.0, // 고정 지연
      shouldRetry: shouldRetry,
    );
  }

  /// 즉시 재시도 (지연 없음)
  static Future<T> executeWithImmediateRetry<T>(
    Future<T> Function() operation, {
    int maxRetries = _defaultMaxRetries,
    bool Function(Exception)? shouldRetry,
  }) async {
    return executeWithRetry(
      operation,
      maxRetries: maxRetries,
      initialDelay: Duration.zero,
      backoffMultiplier: 1.0,
      shouldRetry: shouldRetry,
    );
  }

  /// 무작위 지터가 포함된 재시도
  static Future<T> executeWithJitter<T>(
    Future<T> Function() operation, {
    int maxRetries = _defaultMaxRetries,
    Duration baseDelay = _defaultInitialDelay,
    Duration maxJitter = const Duration(milliseconds: 500),
    bool Function(Exception)? shouldRetry,
  }) async {
    int attempt = 0;
    final random = Random();

    while (true) {
      try {
        return await operation();
      } catch (e) {
        attempt++;

        final exception = e is Exception ? e : Exception(e.toString());
        final canRetry = shouldRetry?.call(exception) ?? _defaultShouldRetry(exception);

        if (!canRetry || attempt >= maxRetries) {
          rethrow;
        }

        // 베이스 지연 + 무작위 지터
        final jitterMs = random.nextInt(maxJitter.inMilliseconds + 1);
        final totalDelay = baseDelay + Duration(milliseconds: jitterMs);
        
        await Future.delayed(totalDelay);
      }
    }
  }
}

/// 재시도 정책 설정 클래스
class RetryPolicy {
  final int maxRetries;
  final Duration initialDelay;
  final double backoffMultiplier;
  final Duration maxDelay;
  final bool Function(Exception) shouldRetry;

  const RetryPolicy({
    this.maxRetries = 3,
    this.initialDelay = const Duration(seconds: 1),
    this.backoffMultiplier = 2.0,
    this.maxDelay = const Duration(seconds: 30),
    required this.shouldRetry,
  });

  /// 네트워크 에러에 대한 기본 정책
  static const RetryPolicy network = RetryPolicy(
    maxRetries: 3,
    initialDelay: Duration(seconds: 1),
    backoffMultiplier: 2.0,
    maxDelay: Duration(seconds: 10),
    shouldRetry: _isNetworkError,
  );

  /// 서버 에러에 대한 기본 정책
  static const RetryPolicy server = RetryPolicy(
    maxRetries: 2,
    initialDelay: Duration(seconds: 2),
    backoffMultiplier: 2.0,
    maxDelay: Duration(seconds: 30),
    shouldRetry: _isServerError,
  );

  /// 타임아웃에 대한 기본 정책
  static const RetryPolicy timeout = RetryPolicy(
    maxRetries: 2,
    initialDelay: Duration(seconds: 3),
    backoffMultiplier: 1.5,
    maxDelay: Duration(seconds: 15),
    shouldRetry: _isTimeoutError,
  );

  /// 정책에 따라 재시도 실행
  Future<T> execute<T>(Future<T> Function() operation) async {
    return RetryHelper.executeWithRetry(
      operation,
      maxRetries: maxRetries,
      initialDelay: initialDelay,
      backoffMultiplier: backoffMultiplier,
      maxDelay: maxDelay,
      shouldRetry: shouldRetry,
    );
  }

  static bool _isNetworkError(Exception exception) {
    if (exception is GiftishowNetworkException) return true;
    
    final message = exception.toString().toLowerCase();
    return message.contains('network') ||
           message.contains('connection') ||
           message.contains('socket');
  }

  static bool _isServerError(Exception exception) {
    if (exception is GiftishowServerException) return true;
    
    final message = exception.toString().toLowerCase();
    return message.contains('server') ||
           message.contains('internal') ||
           message.contains('5');
  }

  static bool _isTimeoutError(Exception exception) {
    if (exception is GiftishowTimeoutException) return true;
    
    final message = exception.toString().toLowerCase();
    return message.contains('timeout');
  }
}

/// 서킷 브레이커 패턴 구현
class CircuitBreaker {
  final int failureThreshold;
  final Duration timeout;
  final Duration resetTimeout;

  int _failureCount = 0;
  DateTime? _lastFailureTime;
  CircuitBreakerState _state = CircuitBreakerState.closed;

  CircuitBreaker({
    this.failureThreshold = 5,
    this.timeout = const Duration(seconds: 30),
    this.resetTimeout = const Duration(minutes: 1),
  });

  /// 작업 실행
  Future<T> execute<T>(Future<T> Function() operation) async {
    if (_state == CircuitBreakerState.open) {
      if (_shouldAttemptReset()) {
        _state = CircuitBreakerState.halfOpen;
      } else {
        throw GiftishowException('Circuit breaker is open');
      }
    }

    try {
      final result = await operation().timeout(timeout);
      _onSuccess();
      return result;
    } catch (e) {
      _onFailure();
      rethrow;
    }
  }

  void _onSuccess() {
    _failureCount = 0;
    _state = CircuitBreakerState.closed;
  }

  void _onFailure() {
    _failureCount++;
    _lastFailureTime = DateTime.now();

    if (_failureCount >= failureThreshold) {
      _state = CircuitBreakerState.open;
    }
  }

  bool _shouldAttemptReset() {
    return _lastFailureTime != null &&
           DateTime.now().difference(_lastFailureTime!) > resetTimeout;
  }

  /// 현재 상태
  CircuitBreakerState get state => _state;

  /// 실패 횟수
  int get failureCount => _failureCount;

  /// 상태 리셋
  void reset() {
    _failureCount = 0;
    _lastFailureTime = null;
    _state = CircuitBreakerState.closed;
  }
}

/// 서킷 브레이커 상태
enum CircuitBreakerState {
  /// 정상 상태
  closed,
  /// 차단 상태
  open,
  /// 반개방 상태
  halfOpen,
}

/// 재시도 결과 통계
class RetryStatistics {
  final int totalAttempts;
  final int successfulAttempts;
  final int failedAttempts;
  final Duration totalExecutionTime;
  final List<Duration> attemptDurations;
  final List<Exception> exceptions;

  const RetryStatistics({
    required this.totalAttempts,
    required this.successfulAttempts,
    required this.failedAttempts,
    required this.totalExecutionTime,
    required this.attemptDurations,
    required this.exceptions,
  });

  /// 성공률
  double get successRate => 
      totalAttempts > 0 ? successfulAttempts / totalAttempts : 0.0;

  /// 평균 실행 시간
  Duration get averageExecutionTime {
    if (attemptDurations.isEmpty) return Duration.zero;
    
    final totalMs = attemptDurations
        .map((d) => d.inMilliseconds)
        .reduce((a, b) => a + b);
    
    return Duration(milliseconds: totalMs ~/ attemptDurations.length);
  }

  /// 가장 많이 발생한 예외 타입
  String? get mostCommonExceptionType {
    if (exceptions.isEmpty) return null;
    
    final typeCount = <String, int>{};
    for (final exception in exceptions) {
      final type = exception.runtimeType.toString();
      typeCount[type] = (typeCount[type] ?? 0) + 1;
    }
    
    return typeCount.entries
        .reduce((a, b) => a.value > b.value ? a : b)
        .key;
  }

  @override
  String toString() {
    return 'RetryStatistics('
        'attempts: $totalAttempts, '
        'success: $successfulAttempts, '
        'failed: $failedAttempts, '
        'successRate: ${(successRate * 100).toStringAsFixed(1)}%, '
        'avgTime: ${averageExecutionTime.inMilliseconds}ms'
        ')';
  }
}

/// 통계를 수집하는 재시도 실행기
class RetryExecutor {
  final List<Duration> _attemptDurations = [];
  final List<Exception> _exceptions = [];
  int _totalAttempts = 0;
  int _successfulAttempts = 0;

  /// 통계와 함께 재시도 실행
  Future<T> executeWithStats<T>(
    Future<T> Function() operation, {
    int maxRetries = 3,
    Duration initialDelay = const Duration(seconds: 1),
    double backoffMultiplier = 2.0,
    Duration maxDelay = const Duration(seconds: 30),
    bool Function(Exception)? shouldRetry,
  }) async {
    final startTime = DateTime.now();
    _attemptDurations.clear();
    _exceptions.clear();
    _totalAttempts = 0;
    _successfulAttempts = 0;

    try {
      final result = await RetryHelper.executeWithRetry(
        () => _wrapOperation(operation),
        maxRetries: maxRetries,
        initialDelay: initialDelay,
        backoffMultiplier: backoffMultiplier,
        maxDelay: maxDelay,
        shouldRetry: (e) {
          _exceptions.add(e);
          return shouldRetry?.call(e) ?? RetryHelper._defaultShouldRetry(e);
        },
      );
      
      _successfulAttempts = 1;
      return result;
    } catch (e) {
      if (e is Exception) {
        _exceptions.add(e);
      }
      rethrow;
    } finally {
      final endTime = DateTime.now();
      // 통계는 getStatistics()로 조회 가능
    }
  }

  Future<T> _wrapOperation<T>(Future<T> Function() operation) async {
    final attemptStart = DateTime.now();
    _totalAttempts++;
    
    try {
      final result = await operation();
      final attemptEnd = DateTime.now();
      _attemptDurations.add(attemptEnd.difference(attemptStart));
      return result;
    } catch (e) {
      final attemptEnd = DateTime.now();
      _attemptDurations.add(attemptEnd.difference(attemptStart));
      rethrow;
    }
  }

  /// 통계 조회
  RetryStatistics getStatistics() {
    final totalExecutionTime = _attemptDurations.isNotEmpty
        ? _attemptDurations.reduce((a, b) => a + b)
        : Duration.zero;

    return RetryStatistics(
      totalAttempts: _totalAttempts,
      successfulAttempts: _successfulAttempts,
      failedAttempts: _totalAttempts - _successfulAttempts,
      totalExecutionTime: totalExecutionTime,
      attemptDurations: List.unmodifiable(_attemptDurations),
      exceptions: List.unmodifiable(_exceptions),
    );
  }

  /// 통계 리셋
  void reset() {
    _attemptDurations.clear();
    _exceptions.clear();
    _totalAttempts = 0;
    _successfulAttempts = 0;
  }
}