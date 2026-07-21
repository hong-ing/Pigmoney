import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:velocity_x/velocity_x.dart';

import '../../../core/giftishow/models/goods_model.dart';
import '../../../data/gift/model/gift_product.dart';
import '../../provider/giftishow_provider.dart';
import '../../provider/user_provider.dart';
import 'giftishow_detail_screen.dart';

class GiftScreen extends ConsumerStatefulWidget {
  const GiftScreen({super.key});

  @override
  ConsumerState<GiftScreen> createState() => _GiftScreenState();
}

class _GiftScreenState extends ConsumerState<GiftScreen> {
  final NumberFormat _currencyFormat = NumberFormat.decimalPattern('ko_KR');

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);
    final formattedMoney = currentUser != null ? '${_currencyFormat.format(currentUser.money)} M' : '0 M';

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Color(0xffE8ECF2),
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            (currentUser?.nickname ?? '').text.size(18).medium.black.make(),
            GestureDetector(
              onTap: () => Navigator.pushNamed(context, '/money'),
              child: formattedMoney.text.size(18).medium.black.make(),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: _buildGiftProductList(),
      ),
    );
  }

  // '주문하기' 탭의 기프티콘 상품 목록 UI
  Widget _buildGiftProductList() {
    final giftishowProductsAsync = ref.watch(giftishowProductsProvider);

    return giftishowProductsAsync.when(
      data: (products) {
        if (products.isEmpty) {
          return VStack([
            Icon(Icons.card_giftcard, color: Colors.grey[400], size: 48),
            16.heightBox,
            '현재 이용 가능한 기프티콘이 없습니다'.text.size(16).color(Colors.grey[400]!).make(),
            24.heightBox,
            TextButton.icon(
              onPressed: () {
                ref.read(giftishowProductsProvider.notifier).loadProducts();
              },
              icon: Icon(Icons.refresh, color: Colors.orangeAccent),
              label: '다시 시도'.text.color(Colors.orangeAccent).make(),
            ),
          ], crossAlignment: CrossAxisAlignment.center).centered();
        }

        return ListView.builder(
          padding: EdgeInsets.symmetric(horizontal: 16.0),
          itemCount: products.length,
          itemBuilder: (context, index) => _buildGiftProductItem(products[index]),
        );
      },
      loading: () => CircularProgressIndicator(color: Colors.orangeAccent).centered(),
      error: (error, stack) => VStack([
        Icon(Icons.error_outline, color: Colors.grey[400], size: 48),
        16.heightBox,
        '기프티콘을 불러올 수 없습니다'.text.size(16).color(Colors.grey[400]!).make(),
        8.heightBox,
        error.toString().text.size(12).color(Colors.grey[600]!).align(TextAlign.center).make(),
        24.heightBox,
        TextButton.icon(
          onPressed: () {
            ref.read(giftishowProductsProvider.notifier).loadProducts();
          },
          icon: Icon(Icons.refresh, color: Colors.orangeAccent),
          label: '다시 시도'.text.color(Colors.orangeAccent).make(),
        ),
      ], crossAlignment: CrossAxisAlignment.center).centered(),
    );
  }

  // 기프티콘 상품 아이템 UI
  Widget _buildGiftProductItem(Goods goods) {
    // 기프트 상품 리스트에서 해당 상품의 money 값 찾기
    final giftProductsAsync = ref.watch(giftProductsProvider);

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => GiftishowDetailScreen(goods: goods),
          ),
        );
      },
      child: HStack([
        // 상품 이미지
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: Colors.grey[800],
            borderRadius: BorderRadius.circular(8.0),
            border: Border.all(color: Colors.orangeAccent.withOpacity(0.3), width: 1),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8.0),
            child: goods.goodsImgS.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: goods.goodsImgS,
                    fit: BoxFit.cover,
                    memCacheWidth: 160,
                    memCacheHeight: 160,
                    placeholder: (context, url) => Container(
                      color: Colors.grey[800],
                      child: Icon(Icons.card_giftcard, color: Colors.grey[600], size: 30).centered(),
                    ),
                    errorWidget: (context, url, error) =>
                        Icon(Icons.card_giftcard, color: Colors.orangeAccent, size: 40).centered(),
                  )
                : Icon(Icons.card_giftcard, color: Colors.orangeAccent, size: 40).centered(),
          ),
        ),
        16.widthBox,
        // 상품 정보
        VStack([
          goods.brandName.text.size(16).bold.white.make(),
          4.heightBox,
          giftProductsAsync.when(
            data: (giftProducts) {
              final matchedProduct = giftProducts.firstWhere(
                (p) => p.code == goods.goodsCode,
                orElse: () => GiftProduct(code: '', brand: '', money: 0, name: goods.goodsName),
              );
              return (matchedProduct.name.isNotEmpty ? matchedProduct.name : goods.goodsName).text
                  .size(14)
                  .color(Colors.grey[400]!)
                  .maxLines(1)
                  .ellipsis
                  .make();
            },
            loading: () => goods.goodsName.text.size(13).color(Colors.grey[400]!).maxLines(1).ellipsis.make(),
            error: (_, __) => goods.goodsName.text.size(13).color(Colors.grey[400]!).maxLines(1).ellipsis.make(),
          ),
          4.heightBox,
          HStack([
            _buildPriceText(goods, giftProductsAsync),
            8.widthBox,
          ]),
        ]).expand(),
      ]).p16(),
    ).material(color: Colors.transparent);
  }

  // 가격 표시 헬퍼 메소드
  Widget _buildPriceText(Goods goods, AsyncValue<List<GiftProduct>> giftProductsAsync) {
    return giftProductsAsync.when(
      data: (giftProducts) {
        // 상품 코드로 매칭되는 money 값 찾기
        final matchedProduct = giftProducts.firstWhere(
          (p) => p.code == goods.goodsCode,
          orElse: () => GiftProduct(code: '', brand: '', money: 3700000, name: ''), // 기본값
        );

        return '${_currencyFormat.format(matchedProduct.money)} M'.text.size(15).color(Colors.orangeAccent).bold.make();
      },
      loading: () => '${_currencyFormat.format(3700000)} M'.text.size(15).color(Colors.orangeAccent).bold.make(),
      error: (error, stack) => '${_currencyFormat.format(3700000)} M'.text.size(15).color(Colors.orangeAccent).bold.make(),
    );
  }
}
