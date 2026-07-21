/// 쿠폰 관련 모델 클래스

/// 쿠폰 발송 요청 모델
class CouponSendRequest {
  final String goodsCode;
  final String? orderNo;
  final String mmsMsg;
  final String mmsTitle;
  final String callbackNo;
  final String phoneNo;
  final String trId;
  final String? templateId;
  final String? bannerId;
  final String userId;
  final CouponSendType gubun;

  const CouponSendRequest({
    required this.goodsCode,
    this.orderNo,
    required this.mmsMsg,
    required this.mmsTitle,
    required this.callbackNo,
    required this.phoneNo,
    required this.trId,
    this.templateId,
    this.bannerId,
    required this.userId,
    required this.gubun,
  });

  /// 파라미터 맵으로 변환
  Map<String, String> toParams() {
    final params = <String, String>{
      'goods_code': goodsCode,
      'mms_msg': mmsMsg,
      'mms_title': mmsTitle,
      'callback_no': callbackNo,
      'phone_no': phoneNo,
      'tr_id': trId,
      'user_id': userId,
      'gubun': gubun.value,
    };
    
    if (orderNo != null) params['order_no'] = orderNo!;
    if (templateId != null) params['template_id'] = templateId!;
    if (bannerId != null) params['banner_id'] = bannerId!;
    
    return params;
  }

  /// TR_ID 유효성 검증
  bool get isValidTrId {
    return trId.isNotEmpty && trId.length <= 25;
  }

  /// MMS 제목 유효성 검증
  bool get isValidMmsTitle {
    return mmsTitle.isNotEmpty && mmsTitle.length <= 10;
  }

  /// 전화번호 유효성 검증 (하이픈 제거된 상태)
  bool get isValidPhoneNo {
    final phoneRegex = RegExp(r'^01[0-9]{8,9}$');
    return phoneRegex.hasMatch(phoneNo);
  }

  /// 발신번호 유효성 검증 (하이픈 제거된 상태)
  bool get isValidCallbackNo {
    final callbackRegex = RegExp(r'^[0-9]{8,11}$');
    return callbackRegex.hasMatch(callbackNo);
  }
}

/// 쿠폰 발송 타입
enum CouponSendType {
  /// PIN 번호 수신
  pin('Y'),
  /// MMS 발송
  mms('N'),
  /// 바코드 이미지 수신
  barcode('I');

  const CouponSendType(this.value);
  final String value;

  String get displayName {
    switch (this) {
      case CouponSendType.pin:
        return 'PIN 번호 수신';
      case CouponSendType.mms:
        return 'MMS 발송';
      case CouponSendType.barcode:
        return '바코드 이미지 수신';
    }
  }
}

/// 쿠폰 발송 응답 모델
class CouponSendResponse {
  final String code;
  final String? message;
  final CouponSendResult? result;

  const CouponSendResponse({
    required this.code,
    this.message,
    this.result,
  });

  factory CouponSendResponse.fromJson(Map<String, dynamic> json) {
    final result = json['result'] as Map<String, dynamic>?;
    final nestedResult = result?['result'] as Map<String, dynamic>?;
    
    return CouponSendResponse(
      code: json['code'] as String? ?? '',
      message: json['message'] as String?,
      result: nestedResult != null ? CouponSendResult.fromJson(nestedResult) : null,
    );
  }

  /// 성공 여부
  bool get isSuccess => code == '0000';
}

/// 쿠폰 발송 결과 모델
class CouponSendResult {
  final String orderNo;
  final String? pinNo;
  final String? couponImgUrl;

  const CouponSendResult({
    required this.orderNo,
    this.pinNo,
    this.couponImgUrl,
  });

  factory CouponSendResult.fromJson(Map<String, dynamic> json) {
    return CouponSendResult(
      orderNo: json['orderNo'] as String? ?? '',
      pinNo: json['pinNo'] as String?,
      couponImgUrl: json['couponImgUrl'] as String?,
    );
  }

  /// PIN 번호 발송 여부
  bool get hasPinNo => pinNo != null && pinNo!.isNotEmpty;

  /// 쿠폰 이미지 URL 존재 여부
  bool get hasCouponImage => couponImgUrl != null && couponImgUrl!.isNotEmpty;
}

/// 쿠폰 정보 모델
class CouponInfo {
  final String goodsCd;
  final String pinStatusCd;
  final String goodsNm;
  final String sellPriceAmt;
  final String remainAmt;
  final String senderTelNo;
  final String cnsmPriceAmt;
  final String? sendRstCd;
  final String pinStatusNm;
  final String mmsBrandThumImg;
  final String brandNm;
  final String? sendRstMsg;
  final String correcDtm;
  final String recverTelNo;
  final String validPrdEndDt;
  final String sendBasicCd;
  final String sendStatusCd;

  const CouponInfo({
    required this.goodsCd,
    required this.pinStatusCd,
    required this.goodsNm,
    required this.sellPriceAmt,
    required this.remainAmt,
    required this.senderTelNo,
    required this.cnsmPriceAmt,
    this.sendRstCd,
    required this.pinStatusNm,
    required this.mmsBrandThumImg,
    required this.brandNm,
    this.sendRstMsg,
    required this.correcDtm,
    required this.recverTelNo,
    required this.validPrdEndDt,
    required this.sendBasicCd,
    required this.sendStatusCd,
  });

  factory CouponInfo.fromJson(Map<String, dynamic> json) {
    return CouponInfo(
      goodsCd: json['goodsCd'] as String? ?? '',
      pinStatusCd: json['pinStatusCd'] as String? ?? '',
      goodsNm: json['goodsNm'] as String? ?? '',
      sellPriceAmt: json['sellPriceAmt'] as String? ?? '',
      remainAmt: json['remainAmt'] as String? ?? '',
      senderTelNo: json['senderTelNo'] as String? ?? '',
      cnsmPriceAmt: json['cnsmPriceAmt'] as String? ?? '',
      sendRstCd: json['sendRstCd'] as String?,
      pinStatusNm: json['pinStatusNm'] as String? ?? '',
      mmsBrandThumImg: json['mmsBrandThumImg'] as String? ?? '',
      brandNm: json['brandNm'] as String? ?? '',
      sendRstMsg: json['sendRstMsg'] as String?,
      correcDtm: json['correcDtm'] as String? ?? '',
      recverTelNo: json['recverTelNo'] as String? ?? '',
      validPrdEndDt: json['validPrdEndDt'] as String? ?? '',
      sendBasicCd: json['sendBasicCd'] as String? ?? '',
      sendStatusCd: json['sendStatusCd'] as String? ?? '',
    );
  }

  /// 쿠폰 상태 (핀 상태 기준)
  CouponStatus get status {
    switch (pinStatusCd) {
      case '01': return CouponStatus.issued;
      case '02': return CouponStatus.used;
      case '03': return CouponStatus.returned;
      case '04': return CouponStatus.disposed;
      case '05': return CouponStatus.refunded;
      case '06': return CouponStatus.reissued;
      case '07': return CouponStatus.cancelled;
      case '08': return CouponStatus.expired;
      default: return CouponStatus.unknown;
    }
  }

  /// 유효기간 만료 여부
  bool get isExpired {
    try {
      final endDate = DateTime.parse(validPrdEndDt.replaceAll('T', ' ').substring(0, 19));
      return DateTime.now().isAfter(endDate);
    } catch (e) {
      return false;
    }
  }

  /// 사용 가능 여부
  bool get isUsable => status == CouponStatus.issued && !isExpired;

  /// 가격 정보 (포맷팅된)
  String get formattedPrice {
    try {
      final price = int.parse(sellPriceAmt);
      return '${price.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}원';
    } catch (e) {
      return '${sellPriceAmt}원';
    }
  }
}

/// 쿠폰 상태 열거형
enum CouponStatus {
  issued('발행'),
  used('교환(사용완료)'),
  returned('반품'),
  disposed('관리폐기'),
  refunded('환불'),
  reissued('재발행'),
  cancelled('구매취소(폐기)'),
  expired('기간만료'),
  unknown('알 수 없음');

  const CouponStatus(this.displayName);
  final String displayName;
}

/// 쿠폰 상세 응답 모델
class CouponDetailResponse {
  final String resCode;
  final String resMsg;
  final List<CouponInfo> couponInfoList;

  const CouponDetailResponse({
    required this.resCode,
    required this.resMsg,
    required this.couponInfoList,
  });

  factory CouponDetailResponse.fromJson(Map<String, dynamic> json) {
    final resultList = json['result'] as List<dynamic>? ?? [];
    final couponInfoList = <CouponInfo>[];
    
    for (final result in resultList) {
      final resultMap = result as Map<String, dynamic>;
      final couponList = resultMap['couponInfoList'] as List<dynamic>? ?? [];
      
      for (final coupon in couponList) {
        couponInfoList.add(CouponInfo.fromJson(coupon as Map<String, dynamic>));
      }
    }
    
    final firstResult = resultList.isNotEmpty ? resultList.first as Map<String, dynamic> : <String, dynamic>{};
    
    return CouponDetailResponse(
      resCode: firstResult['resCode'] as String? ?? json['code'] as String? ?? '',
      resMsg: firstResult['resMsg'] as String? ?? json['message'] as String? ?? '',
      couponInfoList: couponInfoList,
    );
  }

  /// 성공 여부
  bool get isSuccess => resCode == '0000';
}

/// 쿠폰 취소 응답 모델
class CouponCancelResponse {
  final String code;
  final String? message;

  const CouponCancelResponse({
    required this.code,
    this.message,
  });

  factory CouponCancelResponse.fromJson(Map<String, dynamic> json) {
    return CouponCancelResponse(
      code: json['code'] as String? ?? '',
      message: json['message'] as String?,
    );
  }

  /// 성공 여부
  bool get isSuccess => code == '0000';
}

/// 쿠폰 재전송 응답 모델
class CouponResendResponse {
  final String code;
  final String? message;

  const CouponResendResponse({
    required this.code,
    this.message,
  });

  factory CouponResendResponse.fromJson(Map<String, dynamic> json) {
    return CouponResendResponse(
      code: json['code'] as String? ?? '',
      message: json['message'] as String?,
    );
  }

  /// 성공 여부
  bool get isSuccess => code == '0000';
}

/// 비즈머니 응답 모델
class BizMoneyResponse {
  final String code;
  final String? message;
  final String balance;

  const BizMoneyResponse({
    required this.code,
    this.message,
    required this.balance,
  });

  factory BizMoneyResponse.fromJson(Map<String, dynamic> json) {
    return BizMoneyResponse(
      code: json['code'] as String? ?? '',
      message: json['message'] as String?,
      balance: json['balance'] as String? ?? '0',
    );
  }

  /// 성공 여부
  bool get isSuccess => code == '0000';

  /// 잔액 (정수형)
  int get balanceAmount {
    try {
      return int.parse(balance);
    } catch (e) {
      return 0;
    }
  }

  /// 포맷팅된 잔액
  String get formattedBalance {
    return '${balanceAmount.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}원';
  }
}

/// 발송실패 취소 응답 모델
class SendFailCancelResponse {
  final String code;
  final String? message;

  const SendFailCancelResponse({
    required this.code,
    this.message,
  });

  factory SendFailCancelResponse.fromJson(Map<String, dynamic> json) {
    return SendFailCancelResponse(
      code: json['code'] as String? ?? '',
      message: json['message'] as String?,
    );
  }

  /// 성공 여부
  bool get isSuccess => code == '0000';
}