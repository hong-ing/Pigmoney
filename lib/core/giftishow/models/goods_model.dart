/// 상품 관련 모델 클래스

/// 상품 정보 모델
class Goods {
  final String goodsCode;
  final int goodsNo;
  final String goodsName;
  final String brandCode;
  final String brandName;
  final String content;
  final String contentAddDesc;
  final int discountRate;
  final String goodsTypeNm;
  final String goodsImgS;
  final String goodsImgB;
  final String goodsDescImgWeb;
  final String brandIconImg;
  final String mmsGoodsImg;
  final int discountPrice;
  final int realPrice;
  final int salePrice;
  final String srchKeyword;
  final String validPrdTypeCd;
  final int limitDay;
  final String validPrdDay;
  final String endDate;
  final String goodsComId;
  final String goodsComName;
  final String affiliateId;
  final String affiliate;
  final String exhGenderCd;
  final String exhAgeCd;
  final String mmsReserveFlag;
  final int popular;
  final String goodsStateCd;
  final String mmsBarcdCreateYn;
  final String rmCntFlag;
  final String saleDateFlagCd;
  final String goodsTypeDtlNm;
  final int category1Seq;
  final String saleDateFlag;
  final String rmIdBuyCntFlagCd;

  const Goods({
    required this.goodsCode,
    required this.goodsNo,
    required this.goodsName,
    required this.brandCode,
    required this.brandName,
    required this.content,
    required this.contentAddDesc,
    required this.discountRate,
    required this.goodsTypeNm,
    required this.goodsImgS,
    required this.goodsImgB,
    required this.goodsDescImgWeb,
    required this.brandIconImg,
    required this.mmsGoodsImg,
    required this.discountPrice,
    required this.realPrice,
    required this.salePrice,
    required this.srchKeyword,
    required this.validPrdTypeCd,
    required this.limitDay,
    required this.validPrdDay,
    required this.endDate,
    required this.goodsComId,
    required this.goodsComName,
    required this.affiliateId,
    required this.affiliate,
    required this.exhGenderCd,
    required this.exhAgeCd,
    required this.mmsReserveFlag,
    required this.popular,
    required this.goodsStateCd,
    required this.mmsBarcdCreateYn,
    required this.rmCntFlag,
    required this.saleDateFlagCd,
    required this.goodsTypeDtlNm,
    required this.category1Seq,
    required this.saleDateFlag,
    required this.rmIdBuyCntFlagCd,
  });

  factory Goods.fromJson(Map<String, dynamic> json) {
    return Goods(
      goodsCode: json['goodsCode'] as String? ?? '',
      goodsNo: _toInt(json['goodsNo']),
      goodsName: json['goodsName'] as String? ?? '',
      brandCode: json['brandCode'] as String? ?? '',
      brandName: json['brandName'] as String? ?? '',
      content: json['content'] as String? ?? '',
      contentAddDesc: json['contentAddDesc'] as String? ?? '',
      discountRate: _toInt(json['discountRate']),
      goodsTypeNm: json['goodsTypeNm'] as String? ?? '',
      goodsImgS: json['goodsImgS'] as String? ?? '',
      goodsImgB: json['goodsImgB'] as String? ?? '',
      goodsDescImgWeb: json['goodsDescImgWeb'] as String? ?? '',
      brandIconImg: json['brandIconImg'] as String? ?? '',
      mmsGoodsImg: json['mmsGoodsImg'] as String? ?? '',
      discountPrice: _toInt(json['discountPrice']),
      realPrice: _toInt(json['realPrice']),
      salePrice: _toInt(json['salePrice']),
      srchKeyword: json['srchKeyword'] as String? ?? '',
      validPrdTypeCd: json['validPrdTypeCd'] as String? ?? '',
      limitDay: _toInt(json['limitDay']),
      validPrdDay: json['validPrdDay'] as String? ?? '',
      endDate: json['endDate'] as String? ?? '',
      goodsComId: json['goodsComId'] as String? ?? '',
      goodsComName: json['goodsComName'] as String? ?? '',
      affiliateId: json['affiliateId'] as String? ?? '',
      affiliate: json['affiliate'] as String? ?? '',
      exhGenderCd: json['exhGenderCd'] as String? ?? '',
      exhAgeCd: json['exhAgeCd'] as String? ?? '',
      mmsReserveFlag: json['mmsReserveFlag'] as String? ?? '',
      popular: _toInt(json['popular']),
      goodsStateCd: json['goodsStateCd'] as String? ?? '',
      mmsBarcdCreateYn: json['mmsBarcdCreateYn'] as String? ?? '',
      rmCntFlag: json['rmCntFlag'] as String? ?? '',
      saleDateFlagCd: json['saleDateFlagCd'] as String? ?? '',
      goodsTypeDtlNm: json['goodsTypeDtlNm'] as String? ?? '',
      category1Seq: _toInt(json['category1Seq']),
      saleDateFlag: json['saleDateFlag'] as String? ?? '',
      rmIdBuyCntFlagCd: json['rmIdBuyCntFlagCd'] as String? ?? '',
    );
  }
  
  /// 안전한 int 변환 헬퍼 함수
  static int _toInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) {
      final parsed = int.tryParse(value) ?? double.tryParse(value)?.toInt();
      return parsed ?? 0;
    }
    return 0;
  }

  Map<String, dynamic> toJson() {
    return {
      'goodsCode': goodsCode,
      'goodsNo': goodsNo,
      'goodsName': goodsName,
      'brandCode': brandCode,
      'brandName': brandName,
      'content': content,
      'contentAddDesc': contentAddDesc,
      'discountRate': discountRate,
      'goodsTypeNm': goodsTypeNm,
      'goodsImgS': goodsImgS,
      'goodsImgB': goodsImgB,
      'goodsDescImgWeb': goodsDescImgWeb,
      'brandIconImg': brandIconImg,
      'mmsGoodsImg': mmsGoodsImg,
      'discountPrice': discountPrice,
      'realPrice': realPrice,
      'salePrice': salePrice,
      'srchKeyword': srchKeyword,
      'validPrdTypeCd': validPrdTypeCd,
      'limitDay': limitDay,
      'validPrdDay': validPrdDay,
      'endDate': endDate,
      'goodsComId': goodsComId,
      'goodsComName': goodsComName,
      'affiliateId': affiliateId,
      'affiliate': affiliate,
      'exhGenderCd': exhGenderCd,
      'exhAgeCd': exhAgeCd,
      'mmsReserveFlag': mmsReserveFlag,
      'popular': popular,
      'goodsStateCd': goodsStateCd,
      'mmsBarcdCreateYn': mmsBarcdCreateYn,
      'rmCntFlag': rmCntFlag,
      'saleDateFlagCd': saleDateFlagCd,
      'goodsTypeDtlNm': goodsTypeDtlNm,
      'category1Seq': category1Seq,
      'saleDateFlag': saleDateFlag,
      'rmIdBuyCntFlagCd': rmIdBuyCntFlagCd,
    };
  }

  /// 상품이 판매중인지 확인
  bool get isOnSale => goodsStateCd == 'SALE';

  /// 할인된 가격 정보를 포함한 가격 정보
  String get priceInfo {
    if (discountRate > 0) {
      return '${discountPrice.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}원 (${discountRate}% 할인)';
    }
    return '${salePrice.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}원';
  }

  /// 유효기간 정보
  String get validityInfo {
    if (validPrdTypeCd == '01') {
      return '발급일로부터 ${limitDay}일';
    } else {
      return validPrdDay;
    }
  }
}

/// 상품 상세 정보 모델 (추가 정보 포함)
class GoodsDetail extends Goods {
  final String goodsTypeCd;
  final String categoryName1;
  final int vipPrice;
  final int goldPrice;
  final int platinumPrice;
  final int vipDiscountRate;
  final int goldDiscountRate;
  final int platinumDiscountRate;
  final int categorySeq1;

  const GoodsDetail({
    required super.goodsCode,
    required super.goodsNo,
    required super.goodsName,
    required super.brandCode,
    required super.brandName,
    required super.content,
    required super.contentAddDesc,
    required super.discountRate,
    required super.goodsTypeNm,
    required super.goodsImgS,
    required super.goodsImgB,
    required super.goodsDescImgWeb,
    required super.brandIconImg,
    required super.mmsGoodsImg,
    required super.discountPrice,
    required super.realPrice,
    required super.salePrice,
    required super.srchKeyword,
    required super.validPrdTypeCd,
    required super.limitDay,
    required super.validPrdDay,
    required super.endDate,
    required super.goodsComId,
    required super.goodsComName,
    required super.affiliateId,
    required super.affiliate,
    required super.exhGenderCd,
    required super.exhAgeCd,
    required super.mmsReserveFlag,
    required super.popular,
    required super.goodsStateCd,
    required super.mmsBarcdCreateYn,
    required super.rmCntFlag,
    required super.saleDateFlagCd,
    required super.goodsTypeDtlNm,
    required super.category1Seq,
    required super.saleDateFlag,
    required super.rmIdBuyCntFlagCd,
    required this.goodsTypeCd,
    required this.categoryName1,
    required this.vipPrice,
    required this.goldPrice,
    required this.platinumPrice,
    required this.vipDiscountRate,
    required this.goldDiscountRate,
    required this.platinumDiscountRate,
    required this.categorySeq1,
  });

  factory GoodsDetail.fromJson(Map<String, dynamic> json) {
    return GoodsDetail(
      goodsCode: json['goodsCode'] as String? ?? '',
      goodsNo: Goods._toInt(json['goodsNo']),
      goodsName: json['goodsName'] as String? ?? '',
      brandCode: json['brandCode'] as String? ?? '',
      brandName: json['brandName'] as String? ?? '',
      content: json['content'] as String? ?? '',
      contentAddDesc: json['contentAddDesc'] as String? ?? '',
      discountRate: Goods._toInt(json['discountRate']),
      goodsTypeNm: json['goodsTypeNm'] as String? ?? '',
      goodsImgS: json['goodsImgS'] as String? ?? '',
      goodsImgB: json['goodsImgB'] as String? ?? '',
      goodsDescImgWeb: json['goodsDescImgWeb'] as String? ?? '',
      brandIconImg: json['brandIconImg'] as String? ?? '',
      mmsGoodsImg: json['mmsGoodsImg'] as String? ?? '',
      discountPrice: Goods._toInt(json['discountPrice']),
      realPrice: Goods._toInt(json['realPrice']),
      salePrice: Goods._toInt(json['salePrice']),
      srchKeyword: json['srchKeyword'] as String? ?? '',
      validPrdTypeCd: json['validPrdTypeCd'] as String? ?? '',
      limitDay: Goods._toInt(json['limitDay']),
      validPrdDay: json['validPrdDay'] as String? ?? '',
      endDate: json['endDate'] as String? ?? '',
      goodsComId: json['goodsComId'] as String? ?? '',
      goodsComName: json['goodsComName'] as String? ?? '',
      affiliateId: json['affiliateId'] as String? ?? '',
      affiliate: json['affiliate'] as String? ?? '',
      exhGenderCd: json['exhGenderCd'] as String? ?? '',
      exhAgeCd: json['exhAgeCd'] as String? ?? '',
      mmsReserveFlag: json['mmsReserveFlag'] as String? ?? '',
      popular: Goods._toInt(json['popular']),
      goodsStateCd: json['goodsStateCd'] as String? ?? '',
      mmsBarcdCreateYn: json['mmsBarcdCreateYn'] as String? ?? '',
      rmCntFlag: json['rmCntFlag'] as String? ?? '',
      saleDateFlagCd: json['saleDateFlagCd'] as String? ?? '',
      goodsTypeDtlNm: json['goodsTypeDtlNm'] as String? ?? '',
      category1Seq: Goods._toInt(json['category1Seq']),
      saleDateFlag: json['saleDateFlag'] as String? ?? '',
      rmIdBuyCntFlagCd: json['rmIdBuyCntFlagCd'] as String? ?? '',
      goodsTypeCd: json['goodsTypeCd'] as String? ?? '',
      categoryName1: json['categoryName1'] as String? ?? '',
      vipPrice: Goods._toInt(json['vipPrice']),
      goldPrice: Goods._toInt(json['goldPrice']),
      platinumPrice: Goods._toInt(json['platinumPrice']),
      vipDiscountRate: Goods._toInt(json['vipDiscountRate']),
      goldDiscountRate: Goods._toInt(json['goldDiscountRate']),
      platinumDiscountRate: Goods._toInt(json['platinumDiscountRate']),
      categorySeq1: Goods._toInt(json['categorySeq1']),
    );
  }
}

/// 상품 리스트 응답 모델
class GoodsListResponse {
  final String code;
  final String? message;
  final int listNum;
  final List<Goods> goodsList;

  const GoodsListResponse({
    required this.code,
    this.message,
    required this.listNum,
    required this.goodsList,
  });

  factory GoodsListResponse.fromJson(Map<String, dynamic> json) {
    final result = json['result'] as Map<String, dynamic>? ?? {};
    final goodsListJson = result['goodsList'] as List<dynamic>? ?? [];
    
    return GoodsListResponse(
      code: json['code'] as String? ?? '',
      message: json['message'] as String?,
      listNum: Goods._toInt(result['listNum']),
      goodsList: goodsListJson.map((item) => Goods.fromJson(item as Map<String, dynamic>)).toList(),
    );
  }

  /// 성공 여부
  bool get isSuccess => code == '0000';
}

/// 상품 상세 응답 모델
class GoodsDetailResponse {
  final String code;
  final String? message;
  final GoodsDetail? goodsDetail;

  const GoodsDetailResponse({
    required this.code,
    this.message,
    this.goodsDetail,
  });

  factory GoodsDetailResponse.fromJson(Map<String, dynamic> json) {
    final result = json['result'] as Map<String, dynamic>? ?? {};
    final goodsDetailJson = result['goodsDetail'] as Map<String, dynamic>?;
    
    return GoodsDetailResponse(
      code: json['code'] as String? ?? '',
      message: json['message'] as String?,
      goodsDetail: goodsDetailJson != null ? GoodsDetail.fromJson(goodsDetailJson) : null,
    );
  }

  /// 성공 여부
  bool get isSuccess => code == '0000';
}