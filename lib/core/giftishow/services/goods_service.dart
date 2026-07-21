import '../giftishow_api.dart';
import '../models/goods_model.dart';

/// 상품 관리 서비스
/// 
/// 기프티쇼 상품 조회 및 관리를 담당하는 서비스 클래스
class GoodsService {
  final GiftishowApi _api;

  GoodsService(this._api);

  /// 상품 리스트 조회
  /// 
  /// [start]: 시작 페이지 (기본: 1)
  /// [size]: 페이지당 상품 수 (기본: 20, 최대: 100)
  /// [category]: 카테고리 필터링 (옵션)
  /// [brandCode]: 브랜드 코드 필터링 (옵션)
  Future<GoodsListResponse> getGoodsList({
    int start = 1,
    int size = 20,
    String? category,
    String? brandCode,
  }) async {
    // 파라미터 유효성 검증
    if (start < 1) throw ArgumentError('start must be greater than 0');
    if (size < 1 || size > 100) throw ArgumentError('size must be between 1 and 100');

    final response = await _api.getGoodsList(start: start, size: size);
    
    // 클라이언트 사이드 필터링 (API에서 직접 지원하지 않는 경우)
    if (category != null || brandCode != null) {
      final filteredGoods = response.goodsList.where((goods) {
        bool categoryMatch = category == null || 
            goods.goodsTypeDtlNm.contains(category) ||
            goods.brandName.contains(category);
        bool brandMatch = brandCode == null || goods.brandCode == brandCode;
        return categoryMatch && brandMatch;
      }).toList();

      return GoodsListResponse(
        code: response.code,
        message: response.message,
        listNum: filteredGoods.length,
        goodsList: filteredGoods,
      );
    }

    return response;
  }

  /// 상품 상세 정보 조회
  /// 
  /// [goodsCode]: 상품 코드
  Future<GoodsDetailResponse> getGoodsDetail(String goodsCode) async {
    if (goodsCode.isEmpty) {
      throw ArgumentError('goodsCode cannot be empty');
    }

    return await _api.getGoodsDetail(goodsCode);
  }

  /// 인기 상품 조회
  /// 
  /// [limit]: 조회할 상품 수 (기본: 10)
  Future<List<Goods>> getPopularGoods({int limit = 10}) async {
    final response = await getGoodsList(size: 50); // 더 많은 상품을 가져와서 필터링
    
    if (!response.isSuccess) {
      throw GiftishowException('Failed to fetch popular goods: ${response.message}');
    }

    // 인기도 순으로 정렬하고 제한
    final popularGoods = response.goodsList
        .where((goods) => goods.popular > 0)
        .toList();
    
    popularGoods.sort((a, b) => b.popular.compareTo(a.popular));
    
    return popularGoods.take(limit).toList();
  }

  /// 할인 상품 조회
  /// 
  /// [minDiscountRate]: 최소 할인율 (기본: 1)
  /// [limit]: 조회할 상품 수 (기본: 20)
  Future<List<Goods>> getDiscountGoods({
    int minDiscountRate = 1,
    int limit = 20,
  }) async {
    final response = await getGoodsList(size: 50);
    
    if (!response.isSuccess) {
      throw GiftishowException('Failed to fetch discount goods: ${response.message}');
    }

    // 할인율 조건에 맞는 상품 필터링 및 정렬
    final discountGoods = response.goodsList
        .where((goods) => goods.discountRate >= minDiscountRate && goods.isOnSale)
        .toList();
    
    discountGoods.sort((a, b) => b.discountRate.compareTo(a.discountRate));
    
    return discountGoods.take(limit).toList();
  }

  /// 브랜드별 상품 조회
  /// 
  /// [brandCode]: 브랜드 코드
  /// [limit]: 조회할 상품 수 (기본: 20)
  Future<List<Goods>> getGoodsByBrand(
    String brandCode, {
    int limit = 20,
  }) async {
    if (brandCode.isEmpty) {
      throw ArgumentError('brandCode cannot be empty');
    }

    return await getGoodsList(brandCode: brandCode, size: limit)
        .then((response) => response.goodsList);
  }

  /// 가격대별 상품 조회
  /// 
  /// [minPrice]: 최소 가격
  /// [maxPrice]: 최대 가격
  /// [limit]: 조회할 상품 수 (기본: 20)
  Future<List<Goods>> getGoodsByPriceRange({
    int? minPrice,
    int? maxPrice,
    int limit = 20,
  }) async {
    final response = await getGoodsList(size: 50);
    
    if (!response.isSuccess) {
      throw GiftishowException('Failed to fetch goods by price range: ${response.message}');
    }

    // 가격 범위 필터링
    final filteredGoods = response.goodsList.where((goods) {
      final price = goods.discountPrice > 0 ? goods.discountPrice : goods.salePrice;
      bool minMatch = minPrice == null || price >= minPrice;
      bool maxMatch = maxPrice == null || price <= maxPrice;
      return minMatch && maxMatch && goods.isOnSale;
    }).toList();

    // 가격 순으로 정렬
    filteredGoods.sort((a, b) {
      final priceA = a.discountPrice > 0 ? a.discountPrice : a.salePrice;
      final priceB = b.discountPrice > 0 ? b.discountPrice : b.salePrice;
      return priceA.compareTo(priceB);
    });

    return filteredGoods.take(limit).toList();
  }

  /// 상품 검색
  /// 
  /// [keyword]: 검색 키워드
  /// [limit]: 조회할 상품 수 (기본: 20)
  Future<List<Goods>> searchGoods(
    String keyword, {
    int limit = 20,
  }) async {
    if (keyword.isEmpty) {
      throw ArgumentError('keyword cannot be empty');
    }

    final response = await getGoodsList(size: 50);
    
    if (!response.isSuccess) {
      throw GiftishowException('Failed to search goods: ${response.message}');
    }

    final lowerKeyword = keyword.toLowerCase();
    
    // 키워드로 검색 (상품명, 브랜드명, 검색키워드 필드에서 검색)
    final searchResults = response.goodsList.where((goods) {
      return goods.goodsName.toLowerCase().contains(lowerKeyword) ||
             goods.brandName.toLowerCase().contains(lowerKeyword) ||
             goods.srchKeyword.toLowerCase().contains(lowerKeyword);
    }).toList();

    // 관련도 순으로 정렬 (상품명에 키워드가 포함된 것을 우선)
    searchResults.sort((a, b) {
      bool aNameMatch = a.goodsName.toLowerCase().contains(lowerKeyword);
      bool bNameMatch = b.goodsName.toLowerCase().contains(lowerKeyword);
      
      if (aNameMatch && !bNameMatch) return -1;
      if (!aNameMatch && bNameMatch) return 1;
      
      // 둘 다 이름에 매치되거나 둘 다 안되면 인기도순
      return b.popular.compareTo(a.popular);
    });

    return searchResults.take(limit).toList();
  }

  /// 카테고리별 상품 조회
  /// 
  /// [category]: 카테고리명 (예: "편의점", "커피", "치킨" 등)
  /// [limit]: 조회할 상품 수 (기본: 20)
  Future<List<Goods>> getGoodsByCategory(
    String category, {
    int limit = 20,
  }) async {
    if (category.isEmpty) {
      throw ArgumentError('category cannot be empty');
    }

    return await getGoodsList(category: category, size: limit)
        .then((response) => response.goodsList);
  }

  /// 상품 판매 가능 여부 확인
  /// 
  /// [goodsCode]: 상품 코드
  Future<bool> isGoodsAvailable(String goodsCode) async {
    try {
      final response = await getGoodsDetail(goodsCode);
      return response.isSuccess && 
             response.goodsDetail != null && 
             response.goodsDetail!.isOnSale;
    } catch (e) {
      return false;
    }
  }

  /// 상품 가격 정보 조회
  /// 
  /// [goodsCode]: 상품 코드
  Future<Map<String, int>?> getGoodsPriceInfo(String goodsCode) async {
    final response = await getGoodsDetail(goodsCode);
    
    if (!response.isSuccess || response.goodsDetail == null) {
      return null;
    }

    final goods = response.goodsDetail!;
    return {
      'originalPrice': goods.salePrice,
      'discountPrice': goods.discountPrice,
      'realPrice': goods.realPrice,
      'discountRate': goods.discountRate,
    };
  }
}