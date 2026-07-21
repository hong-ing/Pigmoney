import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tnk_flutter_rwd/tnk_flutter_rwd.dart';
import 'package:velocity_x/velocity_x.dart';

import '../../core/utils/log/logger.dart';
import '../provider/placement_ad_provider.dart';
import '../provider/user_provider.dart';

class ShoppingScreen extends ConsumerStatefulWidget {
  const ShoppingScreen({super.key});

  @override
  ConsumerState<ShoppingScreen> createState() => _ShoppingScreenState();
}

class _ShoppingScreenState extends ConsumerState<ShoppingScreen> {
  final _tnkFlutterRwdPlugin = TnkFlutterRwd();
  final NumberFormat _currencyFormat = NumberFormat.decimalPattern('ko_KR');

  @override
  void initState() {
    super.initState();
    _initializeTnk();
  }

  Future<void> _initializeTnk() async {
    try {
      final user = ref.read(currentUserProvider);
      if (user != null) {
        await _tnkFlutterRwdPlugin.setUserName(user.uid);
        await _tnkFlutterRwdPlugin.setCOPPA(false);
        _tnkFlutterRwdPlugin.setUseTermsPopup(false);
      }
    } catch (e) {
      logger.e('TNK 초기화 중 오류: $e');
    }
  }

  Future<void> _onAdItemClick(String appId) async {
    try {
      String? adDetail = await _tnkFlutterRwdPlugin.onItemClick(appId);

      if (adDetail != null) {
        Map<String, dynamic> jsonObject = jsonDecode(adDetail);
        String resCode = jsonObject["res_code"];

        if (resCode == "1") {
          logger.d('광고 상세 페이지 오픈 성공');
        } else {
          logger.e('광고 상세 페이지 오픈 실패: ${jsonObject["res_message"]}');
        }
      }
    } catch (e) {
      logger.e('광고 클릭 처리 중 오류: $e');
    }
  }

  Future<void> _showMoreAds() async {
    try {
      final adState = ref.read(placementAdProvider);

      // 오퍼월 표시
      await _tnkFlutterRwdPlugin.showAdList(adState.pubInfo.title);
      logger.d('오퍼월 표시');
    } catch (e) {
      logger.e('오퍼월 표시 중 오류: $e');
    }
  }

  Widget _buildAdItem(adItem) {
    return InkWell(
      onTap: () => _onAdItemClick(adItem.app_id.toString()),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // 상품 이미지
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                adItem.img_url,
                width: 130,
                height: 100,
                fit: BoxFit.fill,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    width: 110,
                    height: 100,
                    decoration: BoxDecoration(
                      color: Color(0xFF3A3A3A),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.image, color: Colors.grey[600], size: 30),
                  );
                },
              ),
            ),
            15.widthBox,

            // 상품 정보
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 상품명
                  adItem.app_nm.toString().text.size(14).letterSpacing(-0.2).heightRelaxed.medium.white.maxLines(2).make(),
                  8.heightBox,

                  // 가격 정보
                  if (adItem.org_prd_price > 0)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 원래 가격 (할인 전) - 취소선 표시
                        if (adItem.sale_dc_rate > 0 && adItem.org_prd_price != adItem.prd_price) ...{
                          Text(
                            '${_currencyFormat.format(adItem.org_prd_price)} 원',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[600],
                              decoration: TextDecoration.lineThrough,
                              height: 1.1,
                              decorationColor: Colors.grey[600],
                            ),
                          ),
                        } else ...{
                          4.heightBox,
                        },
                        // 현재 가격과 할인율
                        Row(
                          children: [
                            '${_currencyFormat.format(adItem.prd_price)} 원'.text.heightRelaxed.size(14).bold.white.make(),
                            if (adItem.sale_dc_rate > 0) ...[
                              6.widthBox,
                              Container(
                                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: '${adItem.sale_dc_rate}%'.text.size(10).scale(0.9).white.bold.make(),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),

                  // 포인트 정보
                  8.heightBox,
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      children: [
                        '${_currencyFormat.format(adItem.pnt_amt)} ${adItem.pnt_unit}'.text.size(13).black.bold.make(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final adState = ref.watch(placementAdProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // 헤더
            Container(
              padding: EdgeInsets.symmetric(horizontal: 30, vertical: 15),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  adState.pubInfo.title.text.letterSpacing(-0.2).size(17).bold.white.make(),
                  GestureDetector(
                    onTap: _showMoreAds,
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Color(0xFF3A3A3A),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: adState.pubInfo.more_lbl.text.size(13).color(Colors.white70).medium.make(),
                    ),
                  ),
                ],
              ),
            ),

            // 컨텐츠 영역
            _buildContent(adState).expand(),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(PlacementAdState adState) {
    // 로딩 중
    if (adState.isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              color: Color(0xFFFFD700),
              strokeWidth: 2,
            ),
            16.heightBox,
            Text('상품을 불러오는 중...', style: TextStyle(color: Colors.grey[400], fontSize: 14)),
          ],
        ),
      );
    }

    // 에러 발생
    if (adState.hasError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, color: Colors.grey[400], size: 48),
            16.heightBox,
            Text('상품을 불러올 수 없습니다', style: TextStyle(fontSize: 16, color: Colors.grey[400])),
            8.heightBox,
            TextButton(
              onPressed: () => ref.read(placementAdProvider.notifier).refreshAds(),
              style: TextButton.styleFrom(
                backgroundColor: Color(0xFF3A3A3A),
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
              child: Text('다시 시도', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    }

    // 광고 리스트가 비어있음
    if (adState.adList.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shopping_cart_outlined, color: Colors.grey[400], size: 48),
            16.heightBox,
            Text('표시할 상품이 없습니다', style: TextStyle(fontSize: 16, color: Colors.grey[400])),
            8.heightBox,
            TextButton(
              onPressed: () => ref.read(placementAdProvider.notifier).refreshAds(),
              style: TextButton.styleFrom(
                backgroundColor: Color(0xFF3A3A3A),
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
              child: Text('새로고침', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    }

    // 광고 리스트 표시
    return ListView.builder(
      padding: EdgeInsets.symmetric(horizontal: 16),
      itemCount: adState.adList.length,
      itemBuilder: (context, index) {
        return _buildAdItem(adState.adList[index]);
      },
    );
  }
}
