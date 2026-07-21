import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'dart:convert';

import '../../user/user_repository.dart';
import '../model/gift_order.dart';

/// 기프티콘 주문 저장소
class GiftOrderRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _collection = 'gift_orders';
  final UserRepository _userRepository;

  // Cloud Functions URL (환경에 맞게 수정)
  static const String _functionsBaseUrl = 'https://asia-northeast3-cashbank-a1c93.cloudfunctions.net';

  // 기프티쇼 API 엔드포인트
  static const String _sendCouponUrl = '$_functionsBaseUrl/sendGiftishowCoupon';
  static const String _getCouponDetailUrl = '$_functionsBaseUrl/getGiftishowCouponDetail';
  static const String _getGoodsDetailUrl = '$_functionsBaseUrl/getGiftishowGoodsDetail';

  // 생성자에서 UserRepository를 받도록 수정
  GiftOrderRepository({UserRepository? userRepository}) : _userRepository = userRepository ?? UserRepository();

  /// 기프티콘 구매 자격 검증 (서버 측 검증)
  ///
  /// 회원가입 후 3일 경과 여부를 서버 시간 기준으로 검증합니다.
  /// 클라이언트 시간 조작을 방지하기 위해 서버에서 검증합니다.
  ///
  /// Returns: Map<String, dynamic>
  /// - 'eligible': bool (구매 가능 여부)
  /// - 'daysSinceJoin': int (가입 후 경과 일수)
  /// - 'message': String (메시지)
  /// - 'error': String? (에러 코드)
  /// - 'joinDate': String? (가입일 ISO 8601)
  /// - 'eligibleDate': String? (구매 가능일 ISO 8601)
  Future<Map<String, dynamic>> verifyPurchaseEligibility(String uid) async {
    try {
      final url = '$_functionsBaseUrl/verifyGiftPurchaseEligibility';
      print('🌐 [Repository] 요청 URL: $url');
      print('🌐 [Repository] 요청 UID: $uid');

      final response = await http
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'uid': uid}),
          )
          .timeout(
            Duration(seconds: 10),
            onTimeout: () {
              print('❌ [Repository] 타임아웃 발생');
              throw Exception('서버 응답 시간 초과');
            },
          );

      print('🌐 [Repository] 응답 코드: ${response.statusCode}');
      print('🌐 [Repository] 응답 본문: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        print('✅ [Repository] 파싱 성공: $data');
        return data;
      } else if (response.statusCode == 404) {
        print('❌ [Repository] 404 - 사용자 없음');
        final responseBody = response.body;
        print('❌ [Repository] 응답 내용: $responseBody');

        // 서버에서 온 실제 응답 반환
        try {
          final data = jsonDecode(responseBody) as Map<String, dynamic>;
          return data;
        } catch (e) {
          return {
            'eligible': false,
            'error': 'USER_NOT_FOUND',
            'message': '사용자를 찾을 수 없습니다',
            'rawResponse': responseBody,
          };
        }
      } else if (response.statusCode == 400) {
        print('❌ [Repository] 400 - 잘못된 요청');
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return {
          'eligible': false,
          'error': data['error'] ?? 'BAD_REQUEST',
          'message': data['message'] ?? '잘못된 요청입니다',
        };
      } else {
        print('❌ [Repository] 기타 오류: ${response.statusCode}');
        throw Exception('서버 오류: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ [Repository] 예외 발생: $e');
      // 네트워크 오류나 서버 오류 시
      return {
        'eligible': false,
        'error': 'NETWORK_ERROR',
        'message': '서버와 통신할 수 없습니다. 네트워크 연결을 확인해주세요.',
        'details': e.toString(),
      };
    }
  }

  /// 기프티콘 주문 추가
  Future<String> createGiftOrder(GiftOrderHistory order) async {
    try {
      // 사용자 문서 가져오기
      final userDoc = await _firestore.collection('users').doc(order.userId).get();

      if (!userDoc.exists) {
        throw Exception('사용자를 찾을 수 없습니다');
      }

      // 사용자의 giftOrderHistory 배열에 추가
      final updatedGiftOrderHistory = List<Map<String, dynamic>>.from(
        userDoc.data()?['giftOrderHistory'] ?? [],
      );

      updatedGiftOrderHistory.add(order.toJson());

      // 사용자 문서 업데이트
      await _firestore.collection('users').doc(order.userId).update({
        'giftOrderHistory': updatedGiftOrderHistory,
      });

      return order.orderId;
    } catch (e) {
      throw Exception('기프티콘 주문 생성 실패: $e');
    }
  }

  /// 특정 사용자의 기프티콘 주문 내역 조회
  Future<List<GiftOrderHistory>> getUserGiftOrders(String userId) async {
    try {
      final userDoc = await _firestore.collection('users').doc(userId).get();

      if (!userDoc.exists) {
        return [];
      }

      final giftOrderHistory = userDoc.data()?['giftOrderHistory'] ?? [];

      return (giftOrderHistory as List).map((item) => GiftOrderHistory.fromJson(item as Map<String, dynamic>)).toList();
    } catch (e) {
      throw Exception('기프티콘 주문 내역 조회 실패: $e');
    }
  }

  /// 특정 사용자의 기프티콘 주문 내역 스트림
  Stream<List<GiftOrderHistory>> getUserGiftOrdersStream(String userId) {
    return _firestore.collection('users').doc(userId).snapshots().map((doc) {
      if (!doc.exists) return [];

      final giftOrderHistory = doc.data()?['giftOrderHistory'] ?? [];

      return (giftOrderHistory as List).map((item) => GiftOrderHistory.fromJson(item as Map<String, dynamic>)).toList();
    });
  }

  /// 특정 기프티콘 주문 조회 (userId 기반 - 권장)
  Future<GiftOrderHistory?> getGiftOrderByUserId(String userId, String orderId) async {
    try {
      final userDoc = await _firestore.collection('users').doc(userId).get();

      if (!userDoc.exists) {
        return null;
      }

      final giftOrderHistory = userDoc.data()?['giftOrderHistory'] ?? [];

      for (final orderData in giftOrderHistory) {
        if (orderData['orderId'] == orderId) {
          return GiftOrderHistory.fromJson(orderData as Map<String, dynamic>);
        }
      }

      return null;
    } catch (e) {
      throw Exception('기프티콘 주문 조회 실패: $e');
    }
  }

  /// 특정 기프티콘 주문 조회 (orderId만으로 조회 - 비권장, 메모리 사용 높음)
  @Deprecated('Use getGiftOrderByUserId instead to avoid OOM')
  Future<GiftOrderHistory?> getGiftOrder(String orderId) async {
    try {
      // 모든 사용자를 조회하여 해당 orderId를 가진 주문 찾기
      // 주의: 메모리 사용량이 높아 OOM 발생 가능
      final usersSnapshot = await _firestore.collection('users').get();

      for (final userDoc in usersSnapshot.docs) {
        final giftOrderHistory = userDoc.data()['giftOrderHistory'] ?? [];

        for (final orderData in giftOrderHistory) {
          if (orderData['orderId'] == orderId) {
            return GiftOrderHistory.fromJson(orderData as Map<String, dynamic>);
          }
        }
      }

      return null;
    } catch (e) {
      throw Exception('기프티콘 주문 조회 실패: $e');
    }
  }

  /// 기프티콘 주문 상태 업데이트
  Future<void> updateGiftOrderStatus(String userId, String orderId, String status) async {
    try {
      final userDoc = await _firestore.collection('users').doc(userId).get();

      if (!userDoc.exists) {
        throw Exception('사용자를 찾을 수 없습니다');
      }

      final giftOrderHistory = List<Map<String, dynamic>>.from(
        userDoc.data()?['giftOrderHistory'] ?? [],
      );

      // 해당 주문 찾아서 업데이트
      final orderIndex = giftOrderHistory.indexWhere((order) => order['orderId'] == orderId);
      if (orderIndex != -1) {
        giftOrderHistory[orderIndex]['status'] = status;

        await _firestore.collection('users').doc(userId).update({'giftOrderHistory': giftOrderHistory});
      }
    } catch (e) {
      throw Exception('기프티콘 주문 상태 업데이트 실패: $e');
    }
  }

  /// 바코드 정보 업데이트
  Future<void> updateBarcodeInfo(
    String userId,
    String orderId,
    String barcodeNumber,
    String barcodeImageUrl,
  ) async {
    try {
      final userDoc = await _firestore.collection('users').doc(userId).get();

      if (!userDoc.exists) {
        throw Exception('사용자를 찾을 수 없습니다');
      }

      final giftOrderHistory = List<Map<String, dynamic>>.from(
        userDoc.data()?['giftOrderHistory'] ?? [],
      );

      // 해당 주문 찾아서 업데이트
      final orderIndex = giftOrderHistory.indexWhere((order) => order['orderId'] == orderId);
      if (orderIndex != -1) {
        giftOrderHistory[orderIndex]['barcodeNumber'] = barcodeNumber;
        giftOrderHistory[orderIndex]['barcodeImageUrl'] = barcodeImageUrl;

        await _firestore.collection('users').doc(userId).update({'giftOrderHistory': giftOrderHistory});
      }
    } catch (e) {
      throw Exception('바코드 정보 업데이트 실패: $e');
    }
  }

  /// 기프티콘 구매 트랜잭션 (주문 생성 + 머니 차감)
  Future<String> purchaseGiftWithTransaction({
    required GiftOrderHistory order,
    required int price,
  }) async {
    try {
      final orderId = await _firestore.runTransaction<String>((transaction) async {
        // 1. 사용자 문서 가져오기
        final userRef = _firestore.collection('users').doc(order.userId);
        final userDoc = await transaction.get(userRef);

        if (!userDoc.exists) {
          throw Exception('사용자를 찾을 수 없습니다');
        }

        final userData = userDoc.data()!;
        final currentMoney = (userData['money'] ?? 0) as int;
        final nickname = userData['nickname'] ?? '';
        final ipAddress = userData['ipAddress'] ?? '';

        // 2. 잔액 확인
        if (currentMoney < price) {
          throw Exception('잔액이 부족합니다. 현재 잔액: $currentMoney M, 필요 금액: $price M');
        }

        // 3. 기프티콘 주문 컬렉션에 추가 (구매시간, 상품명, 닉네임, IP)
        final giftOrderRef = _firestore.collection(_collection).doc(order.orderId);
        final giftOrderData = {
          'orderId': order.orderId,
          'userId': order.userId,
          'nickname': nickname,
          'goodsName': order.goodsName,
          'orderDate': order.toJson()['orderDate'],
          'price': price,
          'status': order.status,
          'ipAddress': ipAddress,
          'phoneNumber': order.phoneNumber ?? '',
        };
        transaction.set(giftOrderRef, giftOrderData);

        // 4. 기프티콘 주문 내역 추가
        final giftOrderHistory = List<Map<String, dynamic>>.from(
          userData['giftOrderHistory'] ?? [],
        );
        giftOrderHistory.add(order.toJson());

        // 5. 트랜잭션으로 업데이트 (giftOrderHistory만 업데이트)
        transaction.update(userRef, {
          'giftOrderHistory': giftOrderHistory,
        });

        return order.orderId;
      });

      // 트랜잭션 성공 후 UserRepository의 addEarning으로 머니 차감
      // 음수 값을 전달하여 차감 처리
      await _userRepository.purchaseProduct(amount: -price);

      return orderId;
    } catch (e) {
      throw Exception('기프티콘 구매 트랜잭션 실패: $e');
    }
  }

  /// 만료된 기프티콘 상태 일괄 업데이트
  Future<void> updateExpiredGiftOrders() async {
    try {
      final now = DateTime.now();
      final usersSnapshot = await _firestore.collection('users').get();

      for (final userDoc in usersSnapshot.docs) {
        final giftOrderHistory = List<Map<String, dynamic>>.from(
          userDoc.data()['giftOrderHistory'] ?? [],
        );

        bool hasUpdates = false;

        for (int i = 0; i < giftOrderHistory.length; i++) {
          final order = giftOrderHistory[i];
          if (order['status'] == '구매완료' && order['expiryDate'] != null) {
            final expiryDate = (order['expiryDate'] as Timestamp).toDate();
            if (expiryDate.isBefore(now)) {
              giftOrderHistory[i]['status'] = '만료';
              hasUpdates = true;
            }
          }
        }

        if (hasUpdates) {
          await _firestore.collection('users').doc(userDoc.id).update({'giftOrderHistory': giftOrderHistory});
        }
      }
    } catch (e) {
      throw Exception('만료 기프티콘 업데이트 실패: $e');
    }
  }

  /// Cloud Functions를 통해 기프티쇼 MMS 쿠폰 발송
  ///
  /// [goodsCode]: 상품 코드
  /// [phoneNo]: 수신 전화번호 (하이픈 제거)
  /// [callbackNo]: 발신 전화번호 (하이픈 제거)
  /// [userId]: 사용자 ID (기프티쇼 계정)
  /// [trId]: 거래 ID (고유값, 25자 이하)
  /// [mmsTitle]: MMS 제목 (10자 이하)
  /// [mmsMsg]: MMS 메시지
  /// [uid]: Firebase 사용자 UID (검증용)
  /// [orderNo]: 주문번호 (옵션)
  /// [gubun]: 발송 타입 (N: MMS, Y: PIN, I: 바코드 이미지)
  Future<Map<String, dynamic>> sendGiftishowCoupon({
    required String goodsCode,
    required String phoneNo,
    required String callbackNo,
    required String userId,
    required String trId,
    required String mmsTitle,
    required String mmsMsg,
    String? uid,
    String? orderNo,
    String gubun = 'N',
  }) async {
    try {
      print('🎁 [Repository] 기프티쇼 쿠폰 발송 요청: trId=$trId');

      final response = await http
          .post(
            Uri.parse(_sendCouponUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'goodsCode': goodsCode,
              'phoneNo': phoneNo,
              'callbackNo': callbackNo,
              'userId': userId,
              'trId': trId,
              'mmsTitle': mmsTitle,
              'mmsMsg': mmsMsg,
              'uid': uid,
              'orderNo': orderNo,
              'gubun': gubun,
            }),
          )
          .timeout(
            Duration(seconds: 30),
            onTimeout: () {
              print('❌ [Repository] 기프티쇼 API 타임아웃');
              throw Exception('서버 응답 시간 초과');
            },
          );

      print('🎁 [Repository] 응답 코드: ${response.statusCode}');
      print('🎁 [Repository] 응답 본문: ${response.body}');

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 && data['success'] == true) {
        print('✅ [Repository] 기프티쇼 쿠폰 발송 성공');
        return data;
      } else {
        print('❌ [Repository] 기프티쇼 API 오류: ${data['message']}');
        return {
          'success': false,
          'code': data['code'] ?? 'UNKNOWN_ERROR',
          'message': data['message'] ?? '쿠폰 발송에 실패했습니다',
        };
      }
    } catch (e) {
      print('❌ [Repository] 기프티쇼 쿠폰 발송 예외: $e');
      return {
        'success': false,
        'code': 'NETWORK_ERROR',
        'message': '서버와 통신할 수 없습니다. 네트워크 연결을 확인해주세요.',
        'details': e.toString(),
      };
    }
  }

  /// Cloud Functions를 통해 기프티쇼 쿠폰 상세 정보 조회
  Future<Map<String, dynamic>> getGiftishowCouponDetail(String trId) async {
    try {
      final response = await http
          .post(
            Uri.parse(_getCouponDetailUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'trId': trId}),
          )
          .timeout(Duration(seconds: 15));

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data;
    } catch (e) {
      return {
        'success': false,
        'error': 'NETWORK_ERROR',
        'message': e.toString(),
      };
    }
  }

  /// Cloud Functions를 통해 기프티쇼 상품 상세 정보 조회
  Future<Map<String, dynamic>> getGiftishowGoodsDetail(String goodsCode) async {
    try {
      final response = await http
          .post(
            Uri.parse(_getGoodsDetailUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'goodsCode': goodsCode}),
          )
          .timeout(Duration(seconds: 15));

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data;
    } catch (e) {
      return {
        'success': false,
        'error': 'NETWORK_ERROR',
        'message': e.toString(),
      };
    }
  }

  /// UUID 생성기 (싱글톤)
  static const Uuid _uuid = Uuid();

  /// TR_ID 생성 헬퍼
  ///
  /// UUID v4를 사용하여 전 세계적으로 고유한 거래 ID를 생성합니다.
  /// 동시에 수천 명이 구매해도 충돌이 절대 발생하지 않습니다.
  ///
  /// 형식: pm_XXXXXXXXXX (25자 제한 충족)
  /// - pm_: 접두사 (3자)
  /// - UUID에서 하이픈 제거한 첫 22자
  String generateTrId({String prefix = 'pm'}) {
    // UUID v4 생성 (예: 550e8400-e29b-41d4-a716-446655440000)
    final uuid = _uuid.v4();

    // 하이픈 제거하고 첫 22자만 사용 (25자 제한: pm_ + 22자 = 25자)
    final uuidPart = uuid.replaceAll('-', '').substring(0, 22);

    return '${prefix}_$uuidPart';
  }
}
