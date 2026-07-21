import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pigmoney/core/utils/log/logger.dart';

import '../user/model/user.dart';
import '../user/user_repository.dart';
import 'model/order.dart';

class OrderRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _collection = 'orders';
  final UserRepository _userRepository;

  // 생성자에서 UserRepository를 받도록 수정
  OrderRepository({UserRepository? userRepository}) : _userRepository = userRepository ?? UserRepository();

  // 주문 추가 (머니 차감 포함)
  Future<bool> addOrder(OrderHistory order) async {
    try {
      // Firestore 트랜잭션 시작
      bool result = await _firestore.runTransaction<bool>((transaction) async {
        // 1. 사용자 정보 가져오기
        final userDoc = await transaction.get(_firestore.doc('users/${order.uid}'));
        if (!userDoc.exists) {
          logger.e('사용자가 존재하지 않음: ${order.uid}');
          return false;
        }

        // 2. User 객체로 변환
        final user = User.fromFirestore(userDoc);

        // 3. 잔액 확인 (보너스머니는 이미 일반머니로 전환되었으므로 money만 체크)
        if (user.money < order.price) {
          logger.e('잔액 부족: 현재 ${user.money}, 필요 ${order.price}');
          return false;
        }

        // 4. 주문 컬렉션에 추가
        final orderRef = _firestore.collection(_collection).doc(order.orderNumber);
        transaction.set(orderRef, order.toJson());

        logger.d('hong user money ${user.money} order price ${order.price}');

        // 5. 주문 내역 추가
        final List<Map<String, dynamic>> updatedOrders = [...user.orderHistory.map((o) => o.toJson()), order.toJson()];

        // 사용자 문서 업데이트 (주문 내역만 업데이트)
        final userRef = _firestore.doc('users/${order.uid}');
        transaction.update(userRef, {
          'orderHistory': updatedOrders,
        });

        return true;
      });

      if (result) {
        // 트랜잭션 성공 후 UserRepository의 addEarning으로 머니 차감
        // 음수 값을 전달하여 차감 처리
        await _userRepository.purchaseProduct(amount: -order.price);
      }

      return result;
    } catch (e) {
      logger.e('주문 추가 오류: $e');
      return false;
    }
  }

  // 주문 삭제 (머니 환불 포함)
  Future<bool> deleteOrder(String orderNumber) async {
    try {
      // 1. 주문 정보 가져오기
      final orderDoc = await _firestore.collection(_collection).doc(orderNumber).get();
      if (!orderDoc.exists) {
        logger.e('주문이 존재하지 않음: $orderNumber');
        return false;
      }

      // 2. OrderHistory 객체로 변환
      final order = OrderHistory.fromJson(orderDoc.data()!);

      // 3. Firestore 트랜잭션 시작
      bool result = await _firestore.runTransaction<bool>((transaction) async {
        // 3.1 사용자 정보 가져오기
        final userDoc = await transaction.get(_firestore.doc('users/${order.uid}'));
        if (!userDoc.exists) {
          logger.e('사용자가 존재하지 않음: ${order.uid}');
          return false;
        }

        // 3.2 User 객체로 변환
        final user = User.fromFirestore(userDoc);

        // 3.3 주문 컬렉션에서 삭제
        final orderRef = _firestore.collection(_collection).doc(orderNumber);
        transaction.delete(orderRef);

        logger.d('hong user money ${user.money} order price ${order.price}');

        // 3.4 주문 내역에서 해당 주문 제거
        final List<Map<String, dynamic>> updatedOrders = user.orderHistory
            .where((o) => o.orderNumber != orderNumber)
            .map((o) => o.toJson())
            .toList();

        // 사용자 문서 업데이트 (주문 내역만 업데이트)
        final userRef = _firestore.doc('users/${order.uid}');
        transaction.update(userRef, {
          'orderHistory': updatedOrders,
        });

        return true;
      });

      if (result) {
        // 트랜잭션 성공 후 UserRepository의 addEarning으로 머니 환불
        // 양수 값을 전달하여 환불 처리
        await _userRepository.purchaseProduct(amount: order.price);
      }

      return result;
    } catch (e) {
      logger.e('주문 삭제 오류: $e');
      return false;
    }
  }

  // 주문 상태 업데이트
  Future<bool> updateOrderStatus(String orderNumber, String newStatus) async {
    try {
      await _firestore.collection(_collection).doc(orderNumber).update({
        'status': newStatus,
      });
      return true;
    } catch (e) {
      logger.e('주문 상태 업데이트 오류: $e');
      return false;
    }
  }

  // 닉네임으로 주문 목록 조회
  Future<List<OrderHistory>> getOrdersByNickname(String uid) async {
    try {
      final querySnapshot = await _firestore
          .collection(_collection)
          .where('uid', isEqualTo: uid)
          .orderBy('orderDate', descending: true)
          .get();

      return querySnapshot.docs.map((doc) => OrderHistory.fromJson(doc.data())).toList();
    } catch (e) {
      logger.e('닉네임으로 주문 조회 오류: $e');
      return [];
    }
  }

  // 모든 주문 목록 조회 (관리자용)
  Future<List<OrderHistory>> getAllOrders() async {
    try {
      final querySnapshot = await _firestore.collection(_collection).orderBy('orderDate', descending: true).get();

      return querySnapshot.docs.map((doc) => OrderHistory.fromJson(doc.data())).toList();
    } catch (e) {
      logger.e('모든 주문 조회 오류: $e');
      return [];
    }
  }
}
