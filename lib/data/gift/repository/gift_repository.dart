import 'package:cloud_firestore/cloud_firestore.dart';

import '../model/gift_product.dart';

class GiftRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _collection = 'gift';
  final String _documentId = '04CCqfu6AlMNDZ7wupTS';

  // 기프티콘 상품 리스트 가져오기
  Future<List<GiftProduct>> getGiftProducts() async {
    try {
      final doc = await _firestore.collection(_collection).doc(_documentId).get(const GetOptions(source: Source.server));

      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        if (data['products'] != null) {
          final products = (data['products'] as List).map((item) => GiftProduct.fromJson(item as Map<String, dynamic>)).toList();
          return products;
        }
      }

      return [];
    } catch (e) {
      print('기프티콘 상품 조회 오류: $e');
      return [];
    }
  }

  // 기프티콘 상품 리스트 실시간 스트림
  Stream<List<GiftProduct>> getGiftProductsStream() {
    return _firestore.collection(_collection).doc(_documentId).snapshots().map((doc) {
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        if (data['products'] != null) {
          return (data['products'] as List).map((item) => GiftProduct.fromJson(item as Map<String, dynamic>)).toList();
        }
      }
      return [];
    });
  }
}
