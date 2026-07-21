/// 브랜드 관련 모델 클래스

/// 브랜드 정보 모델
class Brand {
  final int brandSeq;
  final String brandCode;
  final String brandName;
  final String brandBannerImg;
  final String brandIconImg;
  final String mmsThumImg;
  final String content;
  final String category1Name;
  final int category1Seq;
  final String category2Name;
  final int category2Seq;
  final int sort;

  const Brand({
    required this.brandSeq,
    required this.brandCode,
    required this.brandName,
    required this.brandBannerImg,
    required this.brandIconImg,
    required this.mmsThumImg,
    required this.content,
    required this.category1Name,
    required this.category1Seq,
    required this.category2Name,
    required this.category2Seq,
    required this.sort,
  });

  factory Brand.fromJson(Map<String, dynamic> json) {
    return Brand(
      brandSeq: json['brandSeq'] as int? ?? 0,
      brandCode: json['brandCode'] as String? ?? '',
      brandName: json['brandName'] as String? ?? '',
      brandBannerImg: json['brandBannerImg'] as String? ?? '',
      brandIconImg: json['brandIconImg'] as String? ?? '',
      mmsThumImg: json['mmsThumImg'] as String? ?? '',
      content: json['content'] as String? ?? '',
      category1Name: json['category1Name'] as String? ?? '',
      category1Seq: json['category1Seq'] as int? ?? 0,
      category2Name: json['category2Name'] as String? ?? '',
      category2Seq: json['category2Seq'] as int? ?? 0,
      sort: json['sort'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'brandSeq': brandSeq,
      'brandCode': brandCode,
      'brandName': brandName,
      'brandBannerImg': brandBannerImg,
      'brandIconImg': brandIconImg,
      'mmsThumImg': mmsThumImg,
      'content': content,
      'category1Name': category1Name,
      'category1Seq': category1Seq,
      'category2Name': category2Name,
      'category2Seq': category2Seq,
      'sort': sort,
    };
  }

  /// 브랜드 아이콘 이미지 URL (썸네일용)
  String get thumbnailUrl => mmsThumImg.isNotEmpty ? mmsThumImg : brandIconImg;

  /// 브랜드 배너 이미지 URL (상단 배너용)
  String get bannerUrl => brandBannerImg;

  /// 카테고리 정보
  String get categoryInfo {
    if (category1Name.isNotEmpty && category2Name.isNotEmpty) {
      return '$category1Name > $category2Name';
    } else if (category1Name.isNotEmpty) {
      return category1Name;
    }
    return '';
  }
}

/// 브랜드 리스트 응답 모델
class BrandListResponse {
  final String code;
  final String? message;
  final int listNum;
  final List<Brand> brandList;

  const BrandListResponse({
    required this.code,
    this.message,
    required this.listNum,
    required this.brandList,
  });

  factory BrandListResponse.fromJson(Map<String, dynamic> json) {
    final result = json['result'] as Map<String, dynamic>? ?? {};
    final brandListJson = result['brandList'] as List<dynamic>? ?? [];
    
    return BrandListResponse(
      code: json['code'] as String? ?? '',
      message: json['message'] as String?,
      listNum: result['listNum'] as int? ?? 0,
      brandList: brandListJson.map((item) => Brand.fromJson(item as Map<String, dynamic>)).toList(),
    );
  }

  /// 성공 여부
  bool get isSuccess => code == '0000';

  /// 카테고리별 브랜드 그룹화
  Map<String, List<Brand>> get brandsByCategory {
    final Map<String, List<Brand>> grouped = {};
    
    for (final brand in brandList) {
      final category = brand.category1Name.isNotEmpty ? brand.category1Name : '기타';
      if (!grouped.containsKey(category)) {
        grouped[category] = [];
      }
      grouped[category]!.add(brand);
    }
    
    // 각 카테고리별로 정렬 순서로 정리
    grouped.forEach((key, value) {
      value.sort((a, b) => a.sort.compareTo(b.sort));
    });
    
    return grouped;
  }
}

/// 브랜드 상세 응답 모델
class BrandDetailResponse {
  final String code;
  final String? message;
  final Brand? brandDetail;

  const BrandDetailResponse({
    required this.code,
    this.message,
    this.brandDetail,
  });

  factory BrandDetailResponse.fromJson(Map<String, dynamic> json) {
    final result = json['result'] as Map<String, dynamic>? ?? {};
    final brandDetailJson = result['brandDetail'] as Map<String, dynamic>?;
    
    return BrandDetailResponse(
      code: json['code'] as String? ?? '',
      message: json['message'] as String?,
      brandDetail: brandDetailJson != null ? Brand.fromJson(brandDetailJson) : null,
    );
  }

  /// 성공 여부
  bool get isSuccess => code == '0000';
}