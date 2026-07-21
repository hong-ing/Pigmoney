import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/product/model/product.dart';
import '../../data/product/product_repository.dart';

// 상품 저장소 프로바이더
final productRepositoryProvider = Provider<ProductRepository>((ref) {
  return ProductRepository();
});

// 상품 목록 프로바이더 (Firebase)
final productsProvider = FutureProvider<List<Product>>((ref) async {
  final repository = ref.watch(productRepositoryProvider);
  return await repository.getProducts();
});

// 상품 스트림 프로바이더 (Firebase 실시간 업데이트)
final productsStreamProvider = StreamProvider<List<Product>>((ref) {
  final repository = ref.watch(productRepositoryProvider);
  return repository.getProductsStream();
});