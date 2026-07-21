import 'package:cloud_firestore/cloud_firestore.dart';

/// 기프티콘 주문 정보 모델
class GiftOrderHistory {
  final String orderId;
  final String userId;
  final String goodsCode;
  final String goodsName;
  final String brandCode;
  final String brandName;
  final String goodsImgUrl;
  final int price;
  final DateTime orderDate;
  final String status; // '구매완료', '사용완료', '만료'
  final String? barcodeNumber;
  final String? barcodeImageUrl;
  final DateTime? expiryDate;
  final Map<String, dynamic>? goodsDetail; // 상품 상세 정보 저장
  final String? trId; // 기프티쇼 거래 ID
  final String? phoneNumber; // 구매 시 입력한 휴대폰 번호

  GiftOrderHistory({
    required this.orderId,
    required this.userId,
    required this.goodsCode,
    required this.goodsName,
    required this.brandCode,
    required this.brandName,
    required this.goodsImgUrl,
    required this.price,
    required this.orderDate,
    required this.status,
    this.barcodeNumber,
    this.barcodeImageUrl,
    this.expiryDate,
    this.goodsDetail,
    this.trId,
    this.phoneNumber,
  });

  /// Firestore에서 데이터를 가져올 때 사용
  factory GiftOrderHistory.fromFirestore(
    Map<String, dynamic> data,
    String orderId,
  ) {
    return GiftOrderHistory(
      orderId: orderId,
      userId: data['userId'] ?? '',
      goodsCode: data['goodsCode'] ?? '',
      goodsName: data['goodsName'] ?? '',
      brandCode: data['brandCode'] ?? '',
      brandName: data['brandName'] ?? '',
      goodsImgUrl: data['goodsImgUrl'] ?? '',
      price: data['price'] ?? 0,
      orderDate: (data['orderDate'] as Timestamp).toDate(),
      status: data['status'] ?? '구매완료',
      barcodeNumber: data['barcodeNumber'],
      barcodeImageUrl: data['barcodeImageUrl'],
      expiryDate: data['expiryDate'] != null ? (data['expiryDate'] as Timestamp).toDate() : null,
      goodsDetail: data['goodsDetail'] as Map<String, dynamic>?,
      trId: data['trId'],
      phoneNumber: data['phoneNumber'],
    );
  }

  /// Firestore에 저장할 때 사용
  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'goodsCode': goodsCode,
      'goodsName': goodsName,
      'brandCode': brandCode,
      'brandName': brandName,
      'goodsImgUrl': goodsImgUrl,
      'price': price,
      'orderDate': Timestamp.fromDate(orderDate),
      'status': status,
      'barcodeNumber': barcodeNumber,
      'barcodeImageUrl': barcodeImageUrl,
      'expiryDate': expiryDate != null ? Timestamp.fromDate(expiryDate!) : null,
      'goodsDetail': goodsDetail,
      'trId': trId,
      'phoneNumber': phoneNumber,
    };
  }

  /// 상태 업데이트를 위한 copyWith 메서드
  GiftOrderHistory copyWith({
    String? orderId,
    String? userId,
    String? goodsCode,
    String? goodsName,
    String? brandCode,
    String? brandName,
    String? goodsImgUrl,
    int? price,
    DateTime? orderDate,
    String? status,
    String? barcodeNumber,
    String? barcodeImageUrl,
    DateTime? expiryDate,
    Map<String, dynamic>? goodsDetail,
    String? trId,
    String? phoneNumber,
  }) {
    return GiftOrderHistory(
      orderId: orderId ?? this.orderId,
      userId: userId ?? this.userId,
      goodsCode: goodsCode ?? this.goodsCode,
      goodsName: goodsName ?? this.goodsName,
      brandCode: brandCode ?? this.brandCode,
      brandName: brandName ?? this.brandName,
      goodsImgUrl: goodsImgUrl ?? this.goodsImgUrl,
      price: price ?? this.price,
      orderDate: orderDate ?? this.orderDate,
      status: status ?? this.status,
      barcodeNumber: barcodeNumber ?? this.barcodeNumber,
      barcodeImageUrl: barcodeImageUrl ?? this.barcodeImageUrl,
      expiryDate: expiryDate ?? this.expiryDate,
      goodsDetail: goodsDetail ?? this.goodsDetail,
      trId: trId ?? this.trId,
      phoneNumber: phoneNumber ?? this.phoneNumber,
    );
  }

  /// 유효기간이 지났는지 확인
  bool get isExpired {
    if (expiryDate == null) return false;
    return DateTime.now().isAfter(expiryDate!);
  }

  /// 사용 가능한지 확인
  bool get isUsable {
    return status == '구매완료' && !isExpired;
  }

  /// JSON 변환을 위한 fromJson 메서드
  factory GiftOrderHistory.fromJson(Map<String, dynamic> json) {
    return GiftOrderHistory(
      orderId: json['orderId'] ?? '',
      userId: json['userId'] ?? '',
      goodsCode: json['goodsCode'] ?? '',
      goodsName: json['goodsName'] ?? '',
      brandCode: json['brandCode'] ?? '',
      brandName: json['brandName'] ?? '',
      goodsImgUrl: json['goodsImgUrl'] ?? '',
      price: json['price'] ?? 0,
      orderDate: json['orderDate'] is Timestamp ? (json['orderDate'] as Timestamp).toDate() : DateTime.parse(json['orderDate'] as String),
      status: json['status'] ?? '구매완료',
      barcodeNumber: json['barcodeNumber'],
      barcodeImageUrl: json['barcodeImageUrl'],
      expiryDate: json['expiryDate'] != null
          ? (json['expiryDate'] is Timestamp ? (json['expiryDate'] as Timestamp).toDate() : DateTime.parse(json['expiryDate'] as String))
          : null,
      goodsDetail: json['goodsDetail'] as Map<String, dynamic>?,
      trId: json['trId'],
      phoneNumber: json['phoneNumber'],
    );
  }

  /// JSON 변환을 위한 toJson 메서드
  Map<String, dynamic> toJson() {
    return {
      'orderId': orderId,
      'userId': userId,
      'goodsCode': goodsCode,
      'goodsName': goodsName,
      'brandCode': brandCode,
      'brandName': brandName,
      'goodsImgUrl': goodsImgUrl,
      'price': price,
      'orderDate': Timestamp.fromDate(orderDate),
      'status': status,
      'barcodeNumber': barcodeNumber,
      'barcodeImageUrl': barcodeImageUrl,
      'expiryDate': expiryDate != null ? Timestamp.fromDate(expiryDate!) : null,
      'goodsDetail': goodsDetail,
      'trId': trId,
      'phoneNumber': phoneNumber,
    };
  }
}
