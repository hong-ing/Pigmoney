import '../giftishow_api.dart';
import '../models/coupon_model.dart';

/// 쿠폰 관리 서비스
/// 
/// 기프티쇼 쿠폰 발송, 조회, 관리를 담당하는 서비스 클래스
class CouponService {
  final GiftishowApi _api;

  CouponService(this._api);

  /// 쿠폰 발송
  /// 
  /// [request]: 쿠폰 발송 요청 정보
  Future<CouponSendResponse> sendCoupon(CouponSendRequest request) async {
    // 요청 데이터 유효성 검증
    _validateSendRequest(request);

    return await _api.sendCoupon(request);
  }

  /// MMS 쿠폰 발송 (간편 메서드)
  /// 
  /// [goodsCode]: 상품 코드
  /// [phoneNo]: 수신 전화번호 (하이픈 제거)
  /// [callbackNo]: 발신 전화번호 (하이픈 제거)
  /// [userId]: 사용자 ID
  /// [trId]: 거래 ID (고유값, 25자 이하)
  /// [mmsTitle]: MMS 제목 (10자 이하)
  /// [mmsMsg]: MMS 메시지
  /// [orderNo]: 주문번호 (옵션)
  Future<CouponSendResponse> sendMmsCoupon({
    required String goodsCode,
    required String phoneNo,
    required String callbackNo,
    required String userId,
    required String trId,
    required String mmsTitle,
    required String mmsMsg,
    String? orderNo,
  }) async {
    final request = CouponSendRequest(
      goodsCode: goodsCode,
      phoneNo: phoneNo,
      callbackNo: callbackNo,
      userId: userId,
      trId: trId,
      mmsTitle: mmsTitle,
      mmsMsg: mmsMsg,
      orderNo: orderNo,
      gubun: CouponSendType.mms,
    );

    return await sendCoupon(request);
  }

  /// PIN 번호 쿠폰 발송 (간편 메서드)
  /// 
  /// [goodsCode]: 상품 코드
  /// [phoneNo]: 수신 전화번호 (하이픈 제거)
  /// [callbackNo]: 발신 전화번호 (하이픈 제거)
  /// [userId]: 사용자 ID
  /// [trId]: 거래 ID (고유값, 25자 이하)
  /// [mmsTitle]: MMS 제목 (10자 이하)
  /// [mmsMsg]: MMS 메시지
  /// [orderNo]: 주문번호 (옵션)
  Future<CouponSendResponse> sendPinCoupon({
    required String goodsCode,
    required String phoneNo,
    required String callbackNo,
    required String userId,
    required String trId,
    required String mmsTitle,
    required String mmsMsg,
    String? orderNo,
  }) async {
    final request = CouponSendRequest(
      goodsCode: goodsCode,
      phoneNo: phoneNo,
      callbackNo: callbackNo,
      userId: userId,
      trId: trId,
      mmsTitle: mmsTitle,
      mmsMsg: mmsMsg,
      orderNo: orderNo,
      gubun: CouponSendType.pin,
    );

    return await sendCoupon(request);
  }

  /// 바코드 이미지 쿠폰 발송 (간편 메서드)
  /// 
  /// [goodsCode]: 상품 코드
  /// [phoneNo]: 수신 전화번호 (하이픈 제거)
  /// [callbackNo]: 발신 전화번호 (하이픈 제거)
  /// [userId]: 사용자 ID
  /// [trId]: 거래 ID (고유값, 25자 이하)
  /// [mmsTitle]: MMS 제목 (10자 이하)
  /// [mmsMsg]: MMS 메시지
  /// [orderNo]: 주문번호 (옵션)
  Future<CouponSendResponse> sendBarcodeCoupon({
    required String goodsCode,
    required String phoneNo,
    required String callbackNo,
    required String userId,
    required String trId,
    required String mmsTitle,
    required String mmsMsg,
    String? orderNo,
  }) async {
    final request = CouponSendRequest(
      goodsCode: goodsCode,
      phoneNo: phoneNo,
      callbackNo: callbackNo,
      userId: userId,
      trId: trId,
      mmsTitle: mmsTitle,
      mmsMsg: mmsMsg,
      orderNo: orderNo,
      gubun: CouponSendType.barcode,
    );

    return await sendCoupon(request);
  }

  /// 쿠폰 상세 정보 조회
  /// 
  /// [trId]: 거래 ID
  Future<CouponDetailResponse> getCouponDetail(String trId) async {
    if (trId.isEmpty) {
      throw ArgumentError('trId cannot be empty');
    }

    return await _api.getCouponDetail(trId);
  }

  /// 쿠폰 취소
  /// 
  /// [trId]: 거래 ID
  /// [userId]: 사용자 ID
  Future<CouponCancelResponse> cancelCoupon(String trId, String userId) async {
    if (trId.isEmpty) {
      throw ArgumentError('trId cannot be empty');
    }
    if (userId.isEmpty) {
      throw ArgumentError('userId cannot be empty');
    }

    return await _api.cancelCoupon(trId, userId);
  }

  /// 쿠폰 재전송
  /// 
  /// [trId]: 거래 ID
  /// [userId]: 사용자 ID
  /// [sendAsSms]: SMS로 재전송 여부 (기본: false, MMS로 전송)
  Future<CouponResendResponse> resendCoupon(
    String trId,
    String userId, {
    bool sendAsSms = false,
  }) async {
    if (trId.isEmpty) {
      throw ArgumentError('trId cannot be empty');
    }
    if (userId.isEmpty) {
      throw ArgumentError('userId cannot be empty');
    }

    return await _api.resendCoupon(
      trId,
      userId,
      smsFlag: sendAsSms ? 'Y' : 'N',
    );
  }

  /// 발송실패 쿠폰 취소
  /// 
  /// [trId]: 거래 ID
  /// [userId]: 사용자 ID
  Future<SendFailCancelResponse> cancelSendFailCoupon(
    String trId,
    String userId,
  ) async {
    if (trId.isEmpty) {
      throw ArgumentError('trId cannot be empty');
    }
    if (userId.isEmpty) {
      throw ArgumentError('userId cannot be empty');
    }

    return await _api.cancelSendFail(trId, userId);
  }

  /// 쿠폰 발송 가능 여부 확인
  /// 
  /// [goodsCode]: 상품 코드
  /// [userId]: 사용자 ID
  /// [requiredAmount]: 필요한 금액 (옵션)
  Future<bool> canSendCoupon(
    String goodsCode,
    String userId, {
    int? requiredAmount,
  }) async {
    try {
      // 비즈머니 잔액 확인
      final bizMoneyResponse = await _api.getBizMoney(userId);
      if (!bizMoneyResponse.isSuccess) {
        return false;
      }

      // 필요한 금액이 지정된 경우 잔액 확인
      if (requiredAmount != null) {
        if (bizMoneyResponse.balanceAmount < requiredAmount) {
          return false;
        }
      }

      // 상품 상태 확인은 GoodsService를 통해 수행하는 것을 권장
      // 여기서는 기본적인 확인만 수행
      return true;
    } catch (e) {
      return false;
    }
  }

  /// 쿠폰 상태 확인
  /// 
  /// [trId]: 거래 ID
  Future<CouponStatus?> getCouponStatus(String trId) async {
    try {
      final response = await getCouponDetail(trId);
      if (!response.isSuccess || response.couponInfoList.isEmpty) {
        return null;
      }

      return response.couponInfoList.first.status;
    } catch (e) {
      return null;
    }
  }

  /// 사용자별 쿠폰 히스토리 조회 (다중 TR_ID 처리)
  /// 
  /// [trIds]: 거래 ID 목록
  Future<List<CouponInfo>> getCouponHistory(List<String> trIds) async {
    if (trIds.isEmpty) {
      return [];
    }

    final List<CouponInfo> allCoupons = [];

    // 각 TR_ID별로 순차적으로 조회
    for (final trId in trIds) {
      try {
        final response = await getCouponDetail(trId);
        if (response.isSuccess) {
          allCoupons.addAll(response.couponInfoList);
        }
      } catch (e) {
        // 개별 조회 실패는 무시하고 계속 진행
        continue;
      }
    }

    // 날짜순으로 정렬 (최신순)
    allCoupons.sort((a, b) => b.correcDtm.compareTo(a.correcDtm));

    return allCoupons;
  }

  /// TR_ID 생성 헬퍼
  /// 
  /// [prefix]: TR_ID 접두사 (기본: 'coupon')
  String generateTrId({String prefix = 'coupon'}) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = (timestamp % 10000).toString().padLeft(4, '0');
    
    final trId = '${prefix}_${DateTime.now().yyyyMMdd}_$random';
    
    // 25자 제한 확인
    if (trId.length > 25) {
      throw ArgumentError('Generated TR_ID exceeds 25 characters: $trId');
    }
    
    return trId;
  }

  /// 전화번호 포맷팅 (하이픈 제거)
  /// 
  /// [phoneNo]: 전화번호
  String formatPhoneNumber(String phoneNo) {
    return phoneNo.replaceAll(RegExp(r'[^0-9]'), '');
  }

  /// 쿠폰 발송 요청 유효성 검증
  void _validateSendRequest(CouponSendRequest request) {
    if (!request.isValidTrId) {
      throw ArgumentError('Invalid TR_ID: must be non-empty and max 25 characters');
    }

    if (!request.isValidMmsTitle) {
      throw ArgumentError('Invalid MMS title: must be non-empty and max 10 characters');
    }

    if (!request.isValidPhoneNo) {
      throw ArgumentError('Invalid phone number format: ${request.phoneNo}');
    }

    if (!request.isValidCallbackNo) {
      throw ArgumentError('Invalid callback number format: ${request.callbackNo}');
    }

    if (request.goodsCode.isEmpty) {
      throw ArgumentError('goodsCode cannot be empty');
    }

    if (request.userId.isEmpty) {
      throw ArgumentError('userId cannot be empty');
    }

    if (request.mmsMsg.isEmpty) {
      throw ArgumentError('mmsMsg cannot be empty');
    }
  }
}

/// DateTime 확장 (yyyyMMdd 포맷)
extension DateTimeExtension on DateTime {
  String get yyyyMMdd {
    return '${year.toString().padLeft(4, '0')}${month.toString().padLeft(2, '0')}${day.toString().padLeft(2, '0')}';
  }
}