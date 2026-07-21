import 'package:cloud_firestore/cloud_firestore.dart';

import 'model/product.dart';

class ProductRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _collection = 'gold_product';
  final String _documentId = 'VScyNQdQhUojV7IAlxgt';

  // Firebase에서 상품 리스트 가져오기
  Future<List<Product>> getProducts() async {
    try {
      final doc = await _firestore.collection(_collection).doc(_documentId).get(const GetOptions(source: Source.server));

      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        if (data['product'] != null) {
          final products = (data['product'] as List).map((item) => Product.fromJson(item as Map<String, dynamic>)).toList();
          return products;
        }
      }

      return [];
    } catch (e) {
      print('상품 조회 오류: $e');
      return [];
    }
  }

  // 상품 리스트 실시간 스트림
  Stream<List<Product>> getProductsStream() {
    return _firestore.collection(_collection).doc(_documentId).snapshots().map((doc) {
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        if (data['product'] != null) {
          return (data['product'] as List).map((item) => Product.fromJson(item as Map<String, dynamic>)).toList();
        }
      }
      return [];
    });
  }
}
