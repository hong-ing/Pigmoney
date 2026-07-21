import '../giftishow_api.dart';
import '../models/brand_model.dart';

/// 브랜드 관리 서비스
/// 
/// 기프티쇼 브랜드 조회 및 관리를 담당하는 서비스 클래스
class BrandService {
  final GiftishowApi _api;

  BrandService(this._api);

  /// 브랜드 리스트 조회
  Future<BrandListResponse> getBrandList() async {
    return await _api.getBrandList();
  }

  /// 브랜드 상세 정보 조회
  /// 
  /// [brandCode]: 브랜드 코드
  Future<BrandDetailResponse> getBrandDetail(String brandCode) async {
    if (brandCode.isEmpty) {
      throw ArgumentError('brandCode cannot be empty');
    }

    return await _api.getBrandDetail(brandCode);
  }

  /// 카테고리별 브랜드 조회
  /// 
  /// [categoryName]: 카테고리명 (예: "편의점/마트", "커피", "치킨" 등)
  Future<List<Brand>> getBrandsByCategory(String categoryName) async {
    final response = await getBrandList();
    
    if (!response.isSuccess) {
      throw GiftishowException('Failed to fetch brands: ${response.message}');
    }

    return response.brandList
        .where((brand) => brand.category1Name.contains(categoryName))
        .toList();
  }

  /// 인기 브랜드 조회 (정렬 순서 기준)
  /// 
  /// [limit]: 조회할 브랜드 수 (기본: 10)
  Future<List<Brand>> getPopularBrands({int limit = 10}) async {
    final response = await getBrandList();
    
    if (!response.isSuccess) {
      throw GiftishowException('Failed to fetch popular brands: ${response.message}');
    }

    // 정렬 순서가 낮은 것부터 (인기 순)
    final sortedBrands = response.brandList.toList();
    sortedBrands.sort((a, b) => a.sort.compareTo(b.sort));

    return sortedBrands.take(limit).toList();
  }

  /// 브랜드 검색
  /// 
  /// [keyword]: 검색 키워드
  Future<List<Brand>> searchBrands(String keyword) async {
    if (keyword.isEmpty) {
      throw ArgumentError('keyword cannot be empty');
    }

    final response = await getBrandList();
    
    if (!response.isSuccess) {
      throw GiftishowException('Failed to search brands: ${response.message}');
    }

    final lowerKeyword = keyword.toLowerCase();
    
    return response.brandList
        .where((brand) =>
            brand.brandName.toLowerCase().contains(lowerKeyword) ||
            brand.category1Name.toLowerCase().contains(lowerKeyword) ||
            brand.category2Name.toLowerCase().contains(lowerKeyword))
        .toList();
  }

  /// 카테고리별 브랜드 그룹화
  Future<Map<String, List<Brand>>> getBrandsGroupedByCategory() async {
    final response = await getBrandList();
    
    if (!response.isSuccess) {
      throw GiftishowException('Failed to fetch brands: ${response.message}');
    }

    return response.brandsByCategory;
  }

  /// 브랜드 존재 여부 확인
  /// 
  /// [brandCode]: 브랜드 코드
  Future<bool> isBrandExists(String brandCode) async {
    try {
      final response = await getBrandDetail(brandCode);
      return response.isSuccess && response.brandDetail != null;
    } catch (e) {
      return false;
    }
  }

  /// 특정 브랜드의 카테고리 정보 조회
  /// 
  /// [brandCode]: 브랜드 코드
  Future<String?> getBrandCategory(String brandCode) async {
    final response = await getBrandDetail(brandCode);
    
    if (!response.isSuccess || response.brandDetail == null) {
      return null;
    }

    return response.brandDetail!.categoryInfo;
  }

  /// 브랜드명으로 브랜드 코드 찾기
  /// 
  /// [brandName]: 브랜드명
  Future<String?> findBrandCodeByName(String brandName) async {
    final response = await getBrandList();
    
    if (!response.isSuccess) {
      return null;
    }

    final brand = response.brandList
        .where((brand) => brand.brandName.toLowerCase() == brandName.toLowerCase())
        .firstOrNull;

    return brand?.brandCode;
  }

  /// 카테고리 목록 조회
  Future<List<String>> getCategories() async {
    final response = await getBrandList();
    
    if (!response.isSuccess) {
      throw GiftishowException('Failed to fetch categories: ${response.message}');
    }

    final categories = response.brandList
        .map((brand) => brand.category1Name)
        .where((category) => category.isNotEmpty)
        .toSet()
        .toList();

    categories.sort();
    return categories;
  }

  /// 브랜드 통계 정보
  Future<Map<String, dynamic>> getBrandStatistics() async {
    final response = await getBrandList();
    
    if (!response.isSuccess) {
      throw GiftishowException('Failed to fetch brand statistics: ${response.message}');
    }

    final categoryGroups = response.brandsByCategory;
    
    return {
      'totalBrands': response.brandList.length,
      'totalCategories': categoryGroups.keys.length,
      'brandsPerCategory': categoryGroups.map(
        (category, brands) => MapEntry(category, brands.length),
      ),
      'topCategory': categoryGroups.entries
          .reduce((a, b) => a.value.length > b.value.length ? a : b)
          .key,
    };
  }
}

/// List의 firstOrNull 확장 (null safety를 위한)
extension ListExtension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}