import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:velocity_x/velocity_x.dart';

import '../../../core/giftishow/models/goods_model.dart';
import '../../../data/gift/model/gift_product.dart';
import '../../../data/gift_order/model/gift_order.dart';
import '../../provider/giftishow_provider.dart';
import '../../provider/user_provider.dart';
import 'gift_order_detail_screen.dart';
import 'giftishow_detail_screen.dart';

class GiftScreen extends ConsumerStatefulWidget {
  /// 탭 루트로 쓰일 때는 false (뒤로가기 버튼 숨김)
  final bool showBackButton;

  const GiftScreen({super.key, this.showBackButton = true});

  @override
  ConsumerState<GiftScreen> createState() => _GiftScreenState();
}

class _GiftScreenState extends ConsumerState<GiftScreen> with SingleTickerProviderStateMixin {
  final NumberFormat _currencyFormat = NumberFormat.decimalPattern('ko_KR');
  final DateFormat _dateFormat = DateFormat('yyyy.MM.dd');
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // 탭 전환 시 선택 스타일 갱신
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);
    final formattedMoney = currentUser != null ? '${_currencyFormat.format(currentUser.money)} M' : '0 M';

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Color(0xffE8ECF2),
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        leading: widget.showBackButton
            ? IconButton(
                icon: Icon(Icons.arrow_back, color: Colors.black),
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
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
        child: Column(
          children: [
            // 탭 바 (shop_screen과 동일 스타일)
            TabBar(
              controller: _tabController,
              indicatorColor: Colors.transparent,
              dividerHeight: 0,
              labelPadding: EdgeInsets.symmetric(horizontal: 4.0),
              tabs: [
                _buildGiftTab(text: '구매하기', isSelected: _tabController.index == 0).pOnly(right: 5),
                _buildGiftTab(text: '구매내역', isSelected: _tabController.index == 1).pOnly(left: 5),
              ],
            ).pOnly(left: 28, right: 28, top: 15),
            // 탭 컨텐츠
            TabBarView(
              controller: _tabController,
              physics: NeverScrollableScrollPhysics(),
              children: [
                _buildGiftProductList(),
                _buildGiftOrderHistoryList(),
              ],
            ).expand(),
          ],
        ),
      ),
    );
  }

  // 탭 UI 빌더 (shop_screen의 _buildShopTab과 동일 스타일)
  Widget _buildGiftTab({required String text, required bool isSelected}) {
    return Tab(
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Color(0xFF3A3A3A),
          borderRadius: BorderRadius.circular(10.0),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: isSelected ? Colors.black : Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
      ),
    );
  }

  // '구매내역' 탭 UI - users/{uid}.giftOrderHistory 실시간 조회 (최신순)
  Widget _buildGiftOrderHistoryList() {
    final currentUser = ref.watch(currentUserProvider);
    if (currentUser == null) {
      return '로그인이 필요합니다'.text.size(16).color(Colors.grey[400]!).make().centered();
    }

    final repository = ref.read(giftOrderRepositoryProvider);

    return StreamBuilder<List<GiftOrderHistory>>(
      stream: repository.getUserGiftOrdersStream(currentUser.uid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return CircularProgressIndicator(color: Colors.orangeAccent).centered();
        }

        if (snapshot.hasError) {
          return VStack([
            Icon(Icons.error_outline, color: Colors.grey[400], size: 48),
            16.heightBox,
            '구매내역을 불러올 수 없습니다'.text.size(16).color(Colors.grey[400]!).make(),
          ], crossAlignment: CrossAxisAlignment.center).centered();
        }

        final orders = List<GiftOrderHistory>.from(snapshot.data ?? []);
        if (orders.isEmpty) {
          return VStack([
            Icon(Icons.receipt_long, color: Colors.grey[400], size: 48),
            16.heightBox,
            '구매 내역이 없습니다'.text.size(16).color(Colors.grey[400]!).make(),
          ], crossAlignment: CrossAxisAlignment.center).centered();
        }

        // 최신순 정렬
        orders.sort((a, b) => b.orderDate.compareTo(a.orderDate));

        return ListView.builder(
          padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          itemCount: orders.length,
          itemBuilder: (context, index) => _buildGiftOrderItem(orders[index]),
        );
      },
    );
  }

  // 구매내역 항목 (상품명/금액/주문일자/상태/휴대폰번호)
  Widget _buildGiftOrderItem(GiftOrderHistory order) {
    Color statusColor = Colors.orangeAccent;
    switch (order.status) {
      case '사용완료':
        statusColor = Colors.green;
        break;
      case '만료':
        statusColor = Colors.red;
        break;
    }

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => GiftOrderDetailScreen(
              orderId: order.orderId,
              userId: order.userId,
            ),
          ),
        );
      },
      child: VStack([
        HStack([
          order.goodsName.text.white.size(15).semiBold.make().expand(),
          8.widthBox,
          order.status.text.color(statusColor).size(13).bold.make(),
        ]),
        6.heightBox,
        HStack([
          '${_currencyFormat.format(order.price)} M'.text.color(Color(0xFFFACC15)).size(14).bold.make(),
          12.widthBox,
          _dateFormat.format(order.orderDate).text.color(Colors.grey[500]!).size(13).make(),
        ]),
        if (order.phoneNumber != null && order.phoneNumber!.isNotEmpty) ...[
          6.heightBox,
          HStack([
            Icon(Icons.phone_android, color: Colors.grey[500], size: 14),
            4.widthBox,
            order.phoneNumber!.text.color(Colors.grey[400]!).size(13).make(),
          ]),
        ],
      ])
          .p16()
          .box
          .color(Color(0xFF1E1E1E))
          .rounded
          .make()
          .pOnly(bottom: 10),
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
