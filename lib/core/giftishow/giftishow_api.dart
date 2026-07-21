import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';

import 'models/brand_model.dart';
import 'models/coupon_model.dart';
import 'models/goods_model.dart';

/// 기프티쇼 비즈 API 클라이언트
/// 
/// 기프티쇼 비즈 API를 사용하여 모바일 쿠폰을 발송하고 관리할 수 있는 Flutter 패키지입니다.
/// B2B 전용 API로 포인트 교환, 이벤트 경품 등의 용도로 사용됩니다.
class GiftishowApi {
  static const String _baseUrl = 'https://bizapi.giftishow.com/bizApi';
  
  final String _authCode;
  final String _authToken;
  final http.Client _client;
  
  /// GiftishowApi 생성자
  /// 
  /// [authCode]: 기프티쇼 비즈에서 발급받은 인증 키
  /// [authToken]: 기프티쇼 비즈에서 발급받은 토큰 키
  GiftishowApi({
    required String authCode,
    required String authToken,
    http.Client? client,
  }) : _authCode = authCode,
        _authToken = authToken,
        _client = client ?? http.Client();

  /// HTTP 요청을 위한 공통 파라미터
  Map<String, String> get _commonParams => {
    'custom_auth_code': _authCode,
    'custom_auth_token': _authToken,
    'dev_yn': 'N', // 운영환경만 지원
  };

  /// HTTP POST 요청 수행
  Future<Map<String, dynamic>> _post(
    String endpoint,
    Map<String, String> params,
  ) async {
    final url = Uri.parse('$_baseUrl$endpoint');
    
    try {
      final response = await _client.post(
        url,
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: params,
      );

      if (response.statusCode != 200) {
        throw GiftishowException('HTTP Error: ${response.statusCode}');
      }

      final jsonData = json.decode(response.body) as Map<String, dynamic>;
      
      // API 에러 코드 체크
      final code = jsonData['code'] as String?;
      if (code != '0000') {
        final message = jsonData['message'] as String? ?? 'Unknown error';
        throw GiftishowException('API Error: $code - $message');
      }

      return jsonData;
    } catch (e) {
      if (e is GiftishowException) rethrow;
      throw GiftishowException('Network error: $e');
    }
  }

  /// 상품 리스트 조회
  /// 
  /// [start]: 시작 페이지 (기본: 1)
  /// [size]: 페이지당 상품 수 (기본: 20)
  Future<GoodsListResponse> getGoodsList({
    int start = 1,
    int size = 20,
  }) async {
    final params = {
      ..._commonParams,
      'api_code': '0101',
      'start': start.toString(),
      'size': size.toString(),
    };

    final response = await _post('/goods', params);
    return GoodsListResponse.fromJson(response);
  }

  /// 상품 상세 정보 조회
  /// 
  /// [goodsCode]: 상품 코드
  Future<GoodsDetailResponse> getGoodsDetail(String goodsCode) async {
    final params = {
      ..._commonParams,
      'api_code': '0111',
    };

    final response = await _post('/goods/$goodsCode', params);
    return GoodsDetailResponse.fromJson(response);
  }

  /// 브랜드 리스트 조회
  Future<BrandListResponse> getBrandList() async {
    final params = {
      ..._commonParams,
      'api_code': '0102',
    };

    final response = await _post('/brands', params);
    return BrandListResponse.fromJson(response);
  }

  /// 브랜드 상세 정보 조회
  /// 
  /// [brandCode]: 브랜드 코드
  Future<BrandDetailResponse> getBrandDetail(String brandCode) async {
    final params = {
      ..._commonParams,
      'api_code': '0112',
    };

    final response = await _post('/brands/$brandCode', params);
    return BrandDetailResponse.fromJson(response);
  }

  /// 쿠폰 발송
  /// 
  /// [request]: 쿠폰 발송 요청 정보
  Future<CouponSendResponse> sendCoupon(CouponSendRequest request) async {
    final params = {
      ..._commonParams,
      'api_code': '0204',
      ...request.toParams(),
    };

    final response = await _post('/send', params);
    return CouponSendResponse.fromJson(response);
  }

  /// 쿠폰 상세 정보 조회
  /// 
  /// [trId]: 거래 ID
  Future<CouponDetailResponse> getCouponDetail(String trId) async {
    final params = {
      ..._commonParams,
      'api_code': '0201',
      'tr_id': trId,
    };

    final response = await _post('/coupons', params);
    return CouponDetailResponse.fromJson(response);
  }

  /// 쿠폰 취소
  /// 
  /// [trId]: 거래 ID
  /// [userId]: 사용자 ID
  Future<CouponCancelResponse> cancelCoupon(String trId, String userId) async {
    final params = {
      ..._commonParams,
      'api_code': '0202',
      'tr_id': trId,
      'user_id': userId,
    };

    final response = await _post('/cancel', params);
    return CouponCancelResponse.fromJson(response);
  }

  /// 쿠폰 재전송
  /// 
  /// [trId]: 거래 ID
  /// [userId]: 사용자 ID
  /// [smsFlag]: SMS 발송 여부 (Y: SMS, N: MMS)
  Future<CouponResendResponse> resendCoupon(
    String trId,
    String userId, {
    String smsFlag = 'N',
  }) async {
    final params = {
      ..._commonParams,
      'api_code': '0203',
      'tr_id': trId,
      'user_id': userId,
      'sms_flag': smsFlag,
    };

    final response = await _post('/resend', params);
    return CouponResendResponse.fromJson(response);
  }

  /// 비즈머니 잔액 조회
  /// 
  /// [userId]: 사용자 ID
  Future<BizMoneyResponse> getBizMoney(String userId) async {
    final params = {
      ..._commonParams,
      'api_code': '0301',
      'user_id': userId,
    };

    final response = await _post('/bizmoney', params);
    return BizMoneyResponse.fromJson(response);
  }

  /// 발송실패 쿠폰 취소
  /// 
  /// [trId]: 거래 ID
  /// [userId]: 사용자 ID
  Future<SendFailCancelResponse> cancelSendFail(String trId, String userId) async {
    final params = {
      ..._commonParams,
      'api_code': '0205',
      'tr_id': trId,
      'user_id': userId,
    };

    final response = await _post('/sendFail/cancel', params);
    return SendFailCancelResponse.fromJson(response);
  }

  /// 클라이언트 종료
  void dispose() {
    _client.close();
  }
}

/// 기프티쇼 API 예외 클래스
class GiftishowException implements Exception {
  final String message;
  
  const GiftishowException(this.message);
  
  @override
  String toString() => 'GiftishowException: $message';
}