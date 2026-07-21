import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/giftishow/config/giftishow_config.dart';
import '../../core/giftishow/giftishow_client.dart';
import '../../core/giftishow/models/goods_model.dart';
import '../../core/giftishow/services/coupon_service.dart';
import '../../data/gift/model/gift_product.dart';
import '../../data/gift/repository/gift_repository.dart';
import '../../data/gift_order/repository/gift_order_repository.dart';
import 'user_provider.dart';

// 기프티쇼 클라이언트 프로바이더 (레거시 - 직접 호출용, 더 이상 사용하지 않음)
final giftishowClientProvider = Provider<GiftishowClient>((ref) {
  return GiftishowClient(
    authCode: GiftishowConfig.authCode,
    authToken: GiftishowConfig.authToken,
  );
});

// 쿠폰 서비스 프로바이더
final couponServiceProvider = Provider<CouponService>((ref) {
  final client = ref.watch(giftishowClientProvider);
  return CouponService(client.api);
});

// 기프트 설정 리포지토리 프로바이더
final giftRepositoryProvider = Provider<GiftRepository>((ref) {
  return GiftRepository();
});

// 기프트 상품 리스트 프로바이더
final giftProductsProvider = FutureProvider<List<GiftProduct>>((ref) async {
  final repository = ref.watch(giftRepositoryProvider);
  return await repository.getGiftProducts();
});

// 기프티쇼 상품 상태를 관리하는 StateNotifier
// IP 화이트리스트 적용으로 서버(Cloud Functions)를 통해 기프티쇼 API 호출
class GiftishowProductsNotifier extends StateNotifier<AsyncValue<List<Goods>>> {
  final GiftRepository giftRepository;
  final GiftOrderRepository giftOrderRepository;

  GiftishowProductsNotifier(this.giftRepository, this.giftOrderRepository) : super(const AsyncValue.loading()) {
    loadProducts();
  }

  Future<void> loadProducts() async {
    try {
      state = const AsyncValue.loading();

      // Firestore에서 기프트 상품 리스트 가져오기
      final giftProducts = await giftRepository.getGiftProducts();
      if (giftProducts.isEmpty) {
        state = const AsyncValue.data([]);
        return;
      }

      // 병렬로 모든 상품 조회 (속도 개선)
      final futures = giftProducts.map((giftProduct) async {
        try {
          final response = await giftOrderRepository.getGiftishowGoodsDetail(giftProduct.code);

          if (response['success'] == true && response['result'] != null) {
            final result = response['result'] as Map<String, dynamic>;
            final goodsDetailJson = result['goodsDetail'] as Map<String, dynamic>?;

            if (goodsDetailJson != null) {
              return Goods.fromJson(goodsDetailJson);
            }
          }
        } catch (e) {
          // 개별 상품 조회 실패해도 계속 진행
        }
        return null;
      }).toList();

      final results = await Future.wait(futures);
      final products = results.whereType<Goods>().toList();

      state = AsyncValue.data(products);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  // 특정 브랜드의 상품 검색
  Future<Goods?> findProductByBrand(String brandName) async {
    final goods = state.value ?? [];
    return goods.firstWhere(
      (g) => g.brandName.contains(brandName) || brandName.contains(g.brandName),
      orElse: () => throw Exception('$brandName 상품을 찾을 수 없습니다'),
    );
  }
}

// 기프티쇼 상품 프로바이더
final giftishowProductsProvider = StateNotifierProvider<GiftishowProductsNotifier, AsyncValue<List<Goods>>>((ref) {
  final giftRepository = ref.watch(giftRepositoryProvider);
  final giftOrderRepository = ref.watch(giftOrderRepositoryProvider);
  return GiftishowProductsNotifier(giftRepository, giftOrderRepository);
});

// 기프티쇼 상품 새로고침
final refreshGiftishowProductsProvider = Provider((ref) {
  return () => ref.read(giftishowProductsProvider.notifier).loadProducts();
});
