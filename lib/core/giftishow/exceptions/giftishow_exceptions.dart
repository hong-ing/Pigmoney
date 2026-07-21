/// 기프티쇼 API 예외 처리 클래스들

/// 기프티쇼 API 기본 예외 클래스
class GiftishowException implements Exception {
  final String message;
  final String? code;
  final dynamic originalError;
  final StackTrace? stackTrace;

  const GiftishowException(
    this.message, {
    this.code,
    this.originalError,
    this.stackTrace,
  });

  @override
  String toString() {
    if (code != null) {
      return 'GiftishowException($code): $message';
    }
    return 'GiftishowException: $message';
  }

  /// 사용자 친화적인 메시지
  String get userFriendlyMessage {
    switch (code) {
      case 'E0010':
        return '비즈머니 잔액이 부족합니다. 잔액을 충전해주세요.';
      case 'E0008':
        return '유효하지 않은 인증 키입니다. 설정을 확인해주세요.';
      case 'E0009':
        return '유효하지 않은 인증 토큰입니다. 설정을 확인해주세요.';
      case 'ERR0401':
        return '요청한 상품을 찾을 수 없습니다.';
      case 'ERR0215':
        return '이미 사용된 거래 ID입니다. 새로운 거래 ID를 사용해주세요.';
      case 'ERR0808':
        return '이미 취소된 쿠폰입니다.';
      case 'COUPON.0006':
        return '취소할 수 없는 쿠폰입니다.';
      case 'COUPON.0007':
        return '이미 교환된 상품으로 취소가 불가능합니다.';
      case 'COUPON.0008':
        return '이미 취소된 쿠폰입니다.';
      default:
        return message;
    }
  }

  /// 에러 타입 분류
  GiftishowErrorType get errorType {
    if (code == null) return GiftishowErrorType.unknown;

    if (code!.startsWith('E00')) {
      if (code == 'E0010') return GiftishowErrorType.insufficientBalance;
      if (code == 'E0008' || code == 'E0009') return GiftishowErrorType.authentication;
      return GiftishowErrorType.api;
    }

    if (code!.startsWith('ERR')) {
      if (code == 'ERR0401') return GiftishowErrorType.notFound;
      if (code == 'ERR0215') return GiftishowErrorType.duplicateTransaction;
      if (code == 'ERR0808') return GiftishowErrorType.alreadyCancelled;
      return GiftishowErrorType.business;
    }

    if (code!.startsWith('COUPON.')) {
      return GiftishowErrorType.coupon;
    }

    return GiftishowErrorType.unknown;
  }

  /// 재시도 가능 여부
  bool get isRetryable {
    switch (errorType) {
      case GiftishowErrorType.network:
      case GiftishowErrorType.timeout:
      case GiftishowErrorType.server:
        return true;
      case GiftishowErrorType.authentication:
      case GiftishowErrorType.insufficientBalance:
      case GiftishowErrorType.duplicateTransaction:
      case GiftishowErrorType.alreadyCancelled:
      case GiftishowErrorType.notFound:
        return false;
      default:
        return false;
    }
  }
}

/// 네트워크 관련 예외
class GiftishowNetworkException extends GiftishowException {
  const GiftishowNetworkException(
    super.message, {
    super.code,
    super.originalError,
    super.stackTrace,
  });

  @override
  String get userFriendlyMessage => '네트워크 연결을 확인해주세요.';

  @override
  GiftishowErrorType get errorType => GiftishowErrorType.network;
}

/// 인증 관련 예외
class GiftishowAuthException extends GiftishowException {
  const GiftishowAuthException(
    super.message, {
    super.code,
    super.originalError,
    super.stackTrace,
  });

  @override
  String get userFriendlyMessage => '인증 정보가 올바르지 않습니다. 설정을 확인해주세요.';

  @override
  GiftishowErrorType get errorType => GiftishowErrorType.authentication;
}

/// 비즈머니 부족 예외
class GiftishowInsufficientBalanceException extends GiftishowException {
  final int currentBalance;
  final int requiredAmount;

  const GiftishowInsufficientBalanceException(
    super.message, {
    required this.currentBalance,
    required this.requiredAmount,
    super.code,
    super.originalError,
    super.stackTrace,
  });

  @override
  String get userFriendlyMessage {
    final shortfall = requiredAmount - currentBalance;
    return '비즈머니가 ${_formatAmount(shortfall)}원 부족합니다. 현재 잔액: ${_formatAmount(currentBalance)}원';
  }

  @override
  GiftishowErrorType get errorType => GiftishowErrorType.insufficientBalance;

  String _formatAmount(int amount) {
    return amount.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
  }
}

/// 타임아웃 예외
class GiftishowTimeoutException extends GiftishowException {
  final Duration timeout;

  const GiftishowTimeoutException(
    super.message, {
    required this.timeout,
    super.code,
    super.originalError,
    super.stackTrace,
  });

  @override
  String get userFriendlyMessage => '요청 시간이 초과되었습니다. 잠시 후 다시 시도해주세요.';

  @override
  GiftishowErrorType get errorType => GiftishowErrorType.timeout;
}

/// 서버 에러 예외
class GiftishowServerException extends GiftishowException {
  final int? httpStatusCode;

  const GiftishowServerException(
    super.message, {
    this.httpStatusCode,
    super.code,
    super.originalError,
    super.stackTrace,
  });

  @override
  String get userFriendlyMessage => '서버에 일시적인 문제가 발생했습니다. 잠시 후 다시 시도해주세요.';

  @override
  GiftishowErrorType get errorType => GiftishowErrorType.server;
}

/// 유효성 검증 예외
class GiftishowValidationException extends GiftishowException {
  final Map<String, String> fieldErrors;

  const GiftishowValidationException(
    super.message, {
    this.fieldErrors = const {},
    super.code,
    super.originalError,
    super.stackTrace,
  });

  @override
  String get userFriendlyMessage {
    if (fieldErrors.isNotEmpty) {
      final errorMessages = fieldErrors.values.join('\n');
      return '입력 정보를 확인해주세요:\n$errorMessages';
    }
    return message;
  }

  @override
  GiftishowErrorType get errorType => GiftishowErrorType.validation;
}

/// 중복 거래 예외
class GiftishowDuplicateTransactionException extends GiftishowException {
  final String trId;

  const GiftishowDuplicateTransactionException(
    super.message, {
    required this.trId,
    super.code,
    super.originalError,
    super.stackTrace,
  });

  @override
  String get userFriendlyMessage => '이미 사용된 거래 ID입니다: $trId';

  @override
  GiftishowErrorType get errorType => GiftishowErrorType.duplicateTransaction;
}

/// 쿠폰 관련 예외
class GiftishowCouponException extends GiftishowException {
  final String? trId;
  final CouponErrorType couponErrorType;

  const GiftishowCouponException(
    super.message, {
    this.trId,
    required this.couponErrorType,
    super.code,
    super.originalError,
    super.stackTrace,
  });

  @override
  String get userFriendlyMessage {
    switch (couponErrorType) {
      case CouponErrorType.alreadyCancelled:
        return '이미 취소된 쿠폰입니다.';
      case CouponErrorType.alreadyUsed:
        return '이미 사용된 쿠폰입니다.';
      case CouponErrorType.expired:
        return '만료된 쿠폰입니다.';
      case CouponErrorType.notFound:
        return trId != null ? '쿠폰을 찾을 수 없습니다: $trId' : '쿠폰을 찾을 수 없습니다.';
      case CouponErrorType.sendFailed:
        return '쿠폰 발송에 실패했습니다.';
      case CouponErrorType.cannotCancel:
        return '취소할 수 없는 쿠폰입니다.';
      case CouponErrorType.invalidStatus:
        return '유효하지 않은 쿠폰 상태입니다.';
    }
  }

  @override
  GiftishowErrorType get errorType => GiftishowErrorType.coupon;
}

/// 에러 타입 열거형
enum GiftishowErrorType {
  /// 알 수 없는 에러
  unknown,
  /// 네트워크 에러
  network,
  /// 인증 에러
  authentication,
  /// 비즈머니 부족
  insufficientBalance,
  /// 타임아웃
  timeout,
  /// 서버 에러
  server,
  /// 유효성 검증 에러
  validation,
  /// API 에러
  api,
  /// 비즈니스 로직 에러
  business,
  /// 중복 거래
  duplicateTransaction,
  /// 이미 취소됨
  alreadyCancelled,
  /// 찾을 수 없음
  notFound,
  /// 쿠폰 관련 에러
  coupon,
}

/// 쿠폰 에러 타입
enum CouponErrorType {
  /// 이미 취소됨
  alreadyCancelled,
  /// 이미 사용됨
  alreadyUsed,
  /// 만료됨
  expired,
  /// 찾을 수 없음
  notFound,
  /// 발송 실패
  sendFailed,
  /// 취소 불가
  cannotCancel,
  /// 유효하지 않은 상태
  invalidStatus,
}

/// 에러 핸들러 유틸리티 클래스
class GiftishowErrorHandler {
  /// API 응답을 기반으로 적절한 예외 생성
  static GiftishowException createException(
    String code,
    String message, {
    dynamic originalError,
    StackTrace? stackTrace,
  }) {
    switch (code) {
      case 'E0008':
      case 'E0009':
        return GiftishowAuthException(
          message,
          code: code,
          originalError: originalError,
          stackTrace: stackTrace,
        );

      case 'E0010':
        return GiftishowInsufficientBalanceException(
          message,
          currentBalance: 0, // 실제 값은 별도 조회 필요
          requiredAmount: 0, // 실제 값은 별도 계산 필요
          code: code,
          originalError: originalError,
          stackTrace: stackTrace,
        );

      case 'ERR0215':
        return GiftishowDuplicateTransactionException(
          message,
          trId: '', // 실제 TR_ID는 컨텍스트에서 가져와야 함
          code: code,
          originalError: originalError,
          stackTrace: stackTrace,
        );

      case 'ERR0808':
      case 'COUPON.0008':
        return GiftishowCouponException(
          message,
          couponErrorType: CouponErrorType.alreadyCancelled,
          code: code,
          originalError: originalError,
          stackTrace: stackTrace,
        );

      case 'COUPON.0006':
      case 'COUPON.0007':
        return GiftishowCouponException(
          message,
          couponErrorType: CouponErrorType.cannotCancel,
          code: code,
          originalError: originalError,
          stackTrace: stackTrace,
        );

      default:
        return GiftishowException(
          message,
          code: code,
          originalError: originalError,
          stackTrace: stackTrace,
        );
    }
  }

  /// HTTP 상태 코드를 기반으로 예외 생성
  static GiftishowException createHttpException(
    int statusCode,
    String message, {
    dynamic originalError,
    StackTrace? stackTrace,
  }) {
    if (statusCode >= 500) {
      return GiftishowServerException(
        message,
        httpStatusCode: statusCode,
        originalError: originalError,
        stackTrace: stackTrace,
      );
    } else if (statusCode == 401 || statusCode == 403) {
      return GiftishowAuthException(
        message,
        originalError: originalError,
        stackTrace: stackTrace,
      );
    } else if (statusCode == 400) {
      return GiftishowValidationException(
        message,
        originalError: originalError,
        stackTrace: stackTrace,
      );
    } else if (statusCode == 404) {
      return GiftishowException(
        message,
        code: 'NOT_FOUND',
        originalError: originalError,
        stackTrace: stackTrace,
      );
    } else {
      return GiftishowException(
        message,
        originalError: originalError,
        stackTrace: stackTrace,
      );
    }
  }

  /// 네트워크 에러를 기반으로 예외 생성
  static GiftishowException createNetworkException(
    dynamic error, {
    StackTrace? stackTrace,
  }) {
    if (error.toString().contains('timeout')) {
      return GiftishowTimeoutException(
        'Request timeout',
        timeout: const Duration(seconds: 30),
        originalError: error,
        stackTrace: stackTrace,
      );
    }

    return GiftishowNetworkException(
      'Network error: ${error.toString()}',
      originalError: error,
      stackTrace: stackTrace,
    );
  }

  /// 유효성 검증 에러 생성
  static GiftishowValidationException createValidationException(
    Map<String, String> fieldErrors,
  ) {
    final message = 'Validation failed: ${fieldErrors.keys.join(', ')}';
    return GiftishowValidationException(
      message,
      fieldErrors: fieldErrors,
    );
  }
}