import 'package:cloud_firestore/cloud_firestore.dart';

class OrderHistory {
  final String uid;
  final String nickname;
  final String orderNumber;
  final DateTime orderDate;
  final String recipientName;
  final String address;
  final String phoneNumber;
  final String status;
  final String productId;
  final String productName;
  final int price;

  OrderHistory({
    required this.uid,
    required this.nickname,
    required this.orderNumber,
    required this.orderDate,
    required this.recipientName,
    required this.address,
    required this.phoneNumber,
    required this.status,
    required this.productId,
    required this.productName,
    required this.price,
  });

  factory OrderHistory.fromJson(Map<String, dynamic> json) {
    return OrderHistory(
      uid: json['uid'] as String,
      nickname: json['nickname'] ?? '',
      orderNumber: json['orderNumber'] ?? '',
      orderDate: (json['orderDate'] as Timestamp).toDate(),
      recipientName: json['recipientName'] ?? '',
      address: json['address'] ?? '',
      phoneNumber: json['phoneNumber'] ?? '',
      status: json['status'] ?? '주문완료',
      productId: json['productId'] ?? '',
      productName: json['productName'] ?? '',
      price: json['price'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      'nickname': nickname,
      'orderNumber': orderNumber,
      'orderDate': Timestamp.fromDate(orderDate),
      'recipientName': recipientName,
      'address': address,
      'phoneNumber': phoneNumber,
      'status': status,
      'productId': productId,
      'productName': productName,
      'price': price,
    };
  }

  static String generateOrderNumber(String phoneNumber) {
    final now = DateTime.now();
    final dateFormat = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final timeFormat = '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';

    // 전화번호 뒷 4자리 추출 (없으면 랜덤 숫자)
    final lastFourDigits = phoneNumber.length >= 4
        ? phoneNumber.substring(phoneNumber.length - 4)
        : '0000';

    return '${dateFormat}_$timeFormat-$lastFourDigits';
  }
}