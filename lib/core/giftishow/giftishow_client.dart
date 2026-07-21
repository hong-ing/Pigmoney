import 'package:http/http.dart' as http;

import 'giftishow_api.dart';
import 'services/goods_service.dart';
import 'services/brand_service.dart';
import 'services/coupon_service.dart';
import 'services/bizmoney_service.dart';
import 'exceptions/giftishow_exceptions.dart';
import 'utils/retry_helper.dart';

/// 기프티쇼 클라이언트 (통합 인터페이스)
/// 
/// 기프티쇼 비즈 API의 모든 기능을 제공하는 통합 클라이언트입니다.
/// 
/// 사용 예제:
/// ```dart
/// final client = GiftishowClient(
///   authCode: 'your_auth_code_here',
///   authToken: 'your_auth_token_here',
/// );
/// 
/// // 상품 조회
/// final goods = await client.goods.getGoodsList();
/// 
/// // 쿠폰 발송
/// final response = await client.coupon.sendMmsCoupon(
///   goodsCode: 'G00000280811',
///   phoneNo: '01012345678',
///   callbackNo: '15880108',
///   userId: 'user123',
///   trId: 'coupon_20241201_1234',
///   mmsTitle: '쿠폰 발송',
///   mmsMsg: '안녕하세요! 쿠폰을 보내드립니다.',
/// );
/// ```
class GiftishowClient {
  late final GiftishowApi _api;
  late final GoodsService _goodsService;
  late final BrandService _brandService;
  late final CouponService _couponService;
  late final BizMoneyService _bizMoneyService;
  
  final CircuitBreaker? _circuitBreaker;
  final RetryPolicy? _defaultRetryPolicy;

  /// GiftishowClient 생성자
  /// 
  /// [authCode]: 기프티쇼 비즈에서 발급받은 인증 키
  /// [authToken]: 기프티쇼 비즈에서 발급받은 토큰 키
  /// [httpClient]: HTTP 클라이언트 (옵션, 테스트용)
  /// [enableCircuitBreaker]: 서킷 브레이커 활성화 여부
  /// [enableRetry]: 자동 재시도 활성화 여부
  GiftishowClient({
    required String authCode,
    required String authToken,
    http.Client? httpClient,
    bool enableCircuitBreaker = true,
    bool enableRetry = true,
  }) : _circuitBreaker = enableCircuitBreaker ? CircuitBreaker() : null,
       _defaultRetryPolicy = enableRetry ? RetryPolicy.network : null {
    
    _api = GiftishowApi(
      authCode: authCode,
      authToken: authToken,
      client: httpClient,
    );
    
    _goodsService = GoodsService(_api);
    _brandService = BrandService(_api);
    _couponService = CouponService(_api);
    _bizMoneyService = BizMoneyService(_api);
  }

  /// 상품 관리 서비스
  GoodsService get goods => _goodsService;

  /// 브랜드 관리 서비스
  BrandService get brand => _brandService;

  /// 쿠폰 관리 서비스
  CouponService get coupon => _couponService;

  /// 비즈머니 관리 서비스
  BizMoneyService get bizMoney => _bizMoneyService;

  /// 원본 API 클라이언트 (고급 사용자용)
  GiftishowApi get api => _api;

  /// 재시도와 서킷 브레이커를 적용한 작업 실행
  Future<T> executeWithResilience<T>(
    Future<T> Function() operation, {
    RetryPolicy? retryPolicy,
  }) async {
    final policy = retryPolicy ?? _defaultRetryPolicy;
    
    Future<T> wrappedOperation() async {
      if (_circuitBreaker != null) {
        return await _circuitBreaker!.execute(operation);
      } else {
        return await operation();
      }
    }

    if (policy != null) {
      return await policy.execute(wrappedOperation);
    } else {
      return await wrappedOperation();
    }
  }

  /// 클라이언트 상태 확인
  Future<GiftishowClientHealth> checkHealth() async {
    final startTime = DateTime.now();
    
    try {
      // 간단한 API 호출로 연결 상태 확인
      await executeWithResilience(() => _bizMoneyService.getBizMoney('health_check'));
      
      final responseTime = DateTime.now().difference(startTime);
      
      return GiftishowClientHealth(
        isHealthy: true,
        responseTime: responseTime,
        circuitBreakerState: _circuitBreaker?.state,
        lastError: null,
      );
    } catch (e) {
      final responseTime = DateTime.now().difference(startTime);
      
      return GiftishowClientHealth(
        isHealthy: false,
        responseTime: responseTime,
        circuitBreakerState: _circuitBreaker?.state,
        lastError: e is Exception ? e : Exception(e.toString()),
      );
    }
  }

  /// 서킷 브레이커 상태 리셋
  void resetCircuitBreaker() {
    _circuitBreaker?.reset();
  }

  /// 클라이언트 정리
  void dispose() {
    _api.dispose();
  }
}

/// 클라이언트 상태 정보
class GiftishowClientHealth {
  final bool isHealthy;
  final Duration responseTime;
  final CircuitBreakerState? circuitBreakerState;
  final Exception? lastError;

  const GiftishowClientHealth({
    required this.isHealthy,
    required this.responseTime,
    this.circuitBreakerState,
    this.lastError,
  });

  @override
  String toString() {
    return 'GiftishowClientHealth('
        'healthy: $isHealthy, '
        'responseTime: ${responseTime.inMilliseconds}ms, '
        'circuitBreaker: $circuitBreakerState'
        ')';
  }
}

/// 기프티쇼 클라이언트 빌더 (설정 옵션이 많을 때 사용)
class GiftishowClientBuilder {
  String? _authCode;
  String? _authToken;
  http.Client? _httpClient;
  bool _enableCircuitBreaker = true;
  bool _enableRetry = true;
  int _circuitBreakerFailureThreshold = 5;
  Duration _circuitBreakerTimeout = const Duration(seconds: 30);
  Duration _circuitBreakerResetTimeout = const Duration(minutes: 1);
  RetryPolicy? _defaultRetryPolicy;

  /// 인증 정보 설정
  GiftishowClientBuilder withAuth(String authCode, String authToken) {
    _authCode = authCode;
    _authToken = authToken;
    return this;
  }

  /// HTTP 클라이언트 설정
  GiftishowClientBuilder withHttpClient(http.Client client) {
    _httpClient = client;
    return this;
  }

  /// 서킷 브레이커 설정
  GiftishowClientBuilder withCircuitBreaker({
    bool enabled = true,
    int failureThreshold = 5,
    Duration timeout = const Duration(seconds: 30),
    Duration resetTimeout = const Duration(minutes: 1),
  }) {
    _enableCircuitBreaker = enabled;
    _circuitBreakerFailureThreshold = failureThreshold;
    _circuitBreakerTimeout = timeout;
    _circuitBreakerResetTimeout = resetTimeout;
    return this;
  }

  /// 재시도 정책 설정
  GiftishowClientBuilder withRetryPolicy(RetryPolicy? policy) {
    _enableRetry = policy != null;
    _defaultRetryPolicy = policy;
    return this;
  }

  /// 재시도 비활성화
  GiftishowClientBuilder withoutRetry() {
    _enableRetry = false;
    _defaultRetryPolicy = null;
    return this;
  }

  /// 클라이언트 빌드
  GiftishowClient build() {
    if (_authCode == null || _authToken == null) {
      throw ArgumentError('Auth code and token are required');
    }

    return GiftishowClient(
      authCode: _authCode!,
      authToken: _authToken!,
      httpClient: _httpClient,
      enableCircuitBreaker: _enableCircuitBreaker,
      enableRetry: _enableRetry,
    );
  }
}

/// 간편 팩토리 메서드들
extension GiftishowClientFactory on GiftishowClient {
  /// 개발/테스트용 클라이언트 생성
  static GiftishowClient development({
    required String authCode,
    required String authToken,
  }) {
    return GiftishowClientBuilder()
        .withAuth(authCode, authToken)
        .withCircuitBreaker(enabled: false) // 개발 시에는 서킷 브레이커 비활성화
        .withRetryPolicy(RetryPolicy.network) // 네트워크 에러만 재시도
        .build();
  }

  /// 프로덕션용 클라이언트 생성 (모든 보호 기능 활성화)
  static GiftishowClient production({
    required String authCode,
    required String authToken,
  }) {
    return GiftishowClientBuilder()
        .withAuth(authCode, authToken)
        .withCircuitBreaker(
          enabled: true,
          failureThreshold: 3, // 프로덕션에서는 더 낮은 임계값
          timeout: const Duration(seconds: 15),
          resetTimeout: const Duration(seconds: 30),
        )
        .withRetryPolicy(RetryPolicy.network)
        .build();
  }

  /// 테스트용 클라이언트 생성 (재시도 및 서킷 브레이커 비활성화)
  static GiftishowClient testing({
    required String authCode,
    required String authToken,
    http.Client? mockClient,
  }) {
    return GiftishowClientBuilder()
        .withAuth(authCode, authToken)
        .withHttpClient(mockClient ?? http.Client())
        .withCircuitBreaker(enabled: false)
        .withoutRetry()
        .build();
  }
}