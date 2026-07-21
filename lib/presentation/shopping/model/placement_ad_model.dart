// ignore_for_file: non_constant_identifier_names

class TnkPlacementAdItem {
  int app_id = 0;
  String app_nm = "";
  String img_url = "";
  int pnt_amt = 0;
  int org_amt = 0;
  String pnt_unit = "";
  int prd_price = 0;
  int org_prd_price = 0;
  int sale_dc_rate = 0;
  bool multi_yn = false;
  int cmpn_type = 0;
  String cmpn_type_name = "";
  String like_yn = "";

  TnkPlacementAdItem({
    this.app_id = 0,
    this.app_nm = "",
    this.img_url = "",
    this.pnt_amt = 0,
    this.org_amt = 0,
    this.pnt_unit = "",
    this.prd_price = 0,
    this.org_prd_price = 0,
    this.sale_dc_rate = 0,
    this.multi_yn = false,
    this.cmpn_type = 0,
    this.cmpn_type_name = "",
    this.like_yn = "",
  });

  factory TnkPlacementAdItem.fromJson(Map<String, dynamic> json) {
    return TnkPlacementAdItem(
      app_id: json['app_id'] ?? 0,
      app_nm: json['app_nm'] ?? "",
      img_url: json['img_url'] ?? "",
      pnt_amt: json['pnt_amt'] ?? 0,
      org_amt: json['org_amt'] ?? 0,
      pnt_unit: json['pnt_unit'] ?? "",
      prd_price: json['prd_price'] ?? 0,
      org_prd_price: json['org_prd_price'] ?? 0,
      sale_dc_rate: json['sale_dc_rate'] ?? 0,
      multi_yn: json['multi_yn'] ?? false,
      cmpn_type: json['cmpn_type'] ?? 0,
      cmpn_type_name: json['cmpn_type_name'] ?? "",
      like_yn: json['like_yn'] ?? "",
    );
  }
}

class PlacementPubInfo {
  int ad_type = 2;
  String title = "쇼핑하고 돌려받기";
  String more_lbl = "더 보기 >";
  String cust_data = "";
  String ctype_surl = "";
  String pnt_unit = "M";
  String plcmt_id = "placement_cps";

  PlacementPubInfo({
    this.ad_type = 2,
    this.title = "쇼핑 후 적립🐷탭에서 머니 수령하세요",
    this.more_lbl = "더 보기 >",
    this.cust_data = "",
    this.ctype_surl = "",
    this.pnt_unit = "M",
    this.plcmt_id = "placement_cps",
  });

  factory PlacementPubInfo.fromJson(Map<String, dynamic> json) {
    return PlacementPubInfo(
      ad_type: json['ad_type'] ?? 2,
      title: json['title'] ?? "쇼핑 후 적립🐷탭에서 머니 수령하세요",
      more_lbl: json['more_lbl'] ?? "더 보기 >",
      cust_data: json['cust_data'] ?? "",
      ctype_surl: json['ctype_surl'] ?? "",
      pnt_unit: json['pnt_unit'] ?? "M",
      plcmt_id: json['plcmt_id'] ?? "placement_cps",
    );
  }
}

List<TnkPlacementAdItem> parseJsonToTnkPlacementAdItem(List<dynamic> adList) {
  return adList.map((item) => TnkPlacementAdItem.fromJson(item)).toList();
}