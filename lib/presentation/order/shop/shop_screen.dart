import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:velocity_x/velocity_x.dart';

import '../../../data/order/model/order.dart';
import '../../../data/product/model/product.dart';
import '../../provider/product_provider.dart';
import '../../provider/user_provider.dart';

class ShopScreen extends ConsumerStatefulWidget {
  const ShopScreen({super.key});

  @override
  ConsumerState<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends ConsumerState<ShopScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final NumberFormat _currencyFormat = NumberFormat.decimalPattern('ko_KR');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          // 탭 변경 시 UI 갱신
        });
      }
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
        child: Column(
          children: [
            // 탭 바
            TabBar(
              controller: _tabController,
              indicatorColor: Colors.transparent,
              dividerHeight: 0,
              labelPadding: EdgeInsets.symmetric(horizontal: 4.0),
              tabs: [
                _buildShopTab(text: '주문하기', isSelected: _tabController.index == 0).pOnly(right: 5),
                _buildShopTab(text: '주문내역', isSelected: _tabController.index == 1).pOnly(left: 5),
              ],
            ).pOnly(left: 28, right: 28, top: 15),
            // 탭 바 뷰 (컨텐츠)
            TabBarView(
              controller: _tabController,
              physics: NeverScrollableScrollPhysics(),
              children: [
                _buildProductList(),
                _buildOrderHistoryList(),
              ],
            ).expand(),
          ],
        ),
      ),
    );
  }

  // 상점 탭 UI 빌더
  Widget _buildShopTab({required String text, required bool isSelected}) {
    return Tab(
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Color(0xFF3A3A3A),
          borderRadius: BorderRadius.circular(10.0), // 이미지에서는 전체가 둥근 형태
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

  // '주문하기' 탭의 상품 목록 UI
  Widget _buildProductList() {
    final productsAsync = ref.watch(productsProvider);

    return productsAsync.when(
      loading: () => Center(
        child: CircularProgressIndicator(color: Color(0xFFFACC15)),
      ),
      error: (error, stack) => Center(
        child: Text('상품을 불러올 수 없습니다.', style: TextStyle(color: Colors.grey[400])),
      ),
      data: (products) => ListView.builder(
        padding: EdgeInsets.symmetric(horizontal: 16.0),
        itemCount: products.length,
        itemBuilder: (context, index) {
          final product = products[index];
          return InkWell(
            onTap: () {
              Navigator.pushNamed(context, '/productDetail', arguments: product);
            },
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8.0),
                  child: CachedNetworkImage(
                    imageUrl: product.imagePath,
                    width: 80,
                    height: 80,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      width: 80,
                      height: 80,
                      color: Colors.grey[800],
                      child: Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFFFACC15),
                        ),
                      ),
                    ),
                    errorWidget: (context, url, error) => Container(
                      width: 80,
                      height: 80,
                      color: Colors.grey[800],
                      child: Icon(Icons.error, color: Colors.grey),
                    ),
                  ),
                ),
                SizedBox(width: 16.0),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    SizedBox(height: 4.0),
                    '${_currencyFormat.format(product.price)} M'.text.size(15).color(Colors.orangeAccent).bold.make(),
                  ],
                ).expand(),
              ],
            ).p(16),
          ).material(color: Colors.transparent);
        },
      ),
    );
  }

  // 주문 취소 다이얼로그
  void _showCancelConfirmDialog(String orderNumber, int productPrice) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Color(0xFF2D2D2D),
        title: Text(
          '주문 취소',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text('이 주문을 취소하시겠습니까?\n취소 시 결제 금액이 환불됩니다.', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('아니오', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop(); // 다이얼로그 닫기

              // 컨텍스트 참조를 안전하게 저장
              final scaffoldMessenger = ScaffoldMessenger.of(context);
              final currentContext = context;

              // 로딩 다이얼로그 표시를 위한 BuildContext 변수 저장
              BuildContext? dialogContext;

              // 로딩 표시
              showDialog(
                context: currentContext,
                barrierDismissible: false,
                builder: (BuildContext ctx) {
                  dialogContext = ctx; // 로딩 다이얼로그 컨텍스트 저장
                  return AlertDialog(
                    backgroundColor: Color(0xFF2D2D2D),
                    content: Row(
                      children: [
                        CircularProgressIndicator(color: Color(0xFFFACC15)),
                        SizedBox(width: 20),
                        Text("취소 처리 중...", style: TextStyle(color: Colors.white)),
                      ],
                    ),
                  );
                },
              );

              // 서버에서 최신 주문 상태 확인
              final userNotifier = ref.read(currentUserProvider.notifier);
              final latestOrder = await userNotifier.getOrderByOrderNumber(orderNumber);

              print('====== 주문 취소 상태 확인 ======');
              print('주문번호: $orderNumber');
              print('users 컬렉션 orderHistory의 주문 상태: ${latestOrder?.status}');
              print('users 컬렉션 orderHistory의 주문 날짜: ${latestOrder?.orderDate}');
              print('화면에 표시된 상태: 주문 완료 (취소 버튼이 보였음)');
              print('================================');

              // 주문이 존재하지 않거나 이미 배송완료된 경우
              if (latestOrder == null || latestOrder.status != '주문 완료') {
                // 로딩 다이얼로그 닫기
                if (dialogContext != null && mounted) {
                  Navigator.of(dialogContext!).pop();
                }

                if (mounted) {
                  scaffoldMessenger.showSnackBar(
                    SnackBar(
                      content: Text(latestOrder == null ? '주문을 찾을 수 없습니다.' : '이미 배송이 완료된 상품입니다.'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  setState(() {}); // 화면 갱신
                }
                return;
              }

              // 주문 취소 처리
              final cancelSuccess = await userNotifier.cancelOrder(orderNumber);

              // 로딩 다이얼로그 닫기 (컨텍스트가 유효한지 확인)
              if (dialogContext != null && mounted) {
                Navigator.of(dialogContext!).pop();
              }

              if (mounted) {
                if (cancelSuccess) {
                  scaffoldMessenger.showSnackBar(
                    SnackBar(
                      content: Text('주문이 취소 되었습니다.'),
                      backgroundColor: Colors.green,
                    ),
                  );
                  setState(() {});
                } else {
                  scaffoldMessenger.showSnackBar(
                    SnackBar(
                      content: Text('주문 취소에 실패했습니다.'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: Text(
              '예',
              style: TextStyle(color: Color(0xFFFACC15), fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  // '주문내역' 탭의 UI
  Widget _buildOrderHistoryList() {
    // watch로 변경하여 주문 내역 변경 감지
    final orderHistory = ref.watch(currentUserProvider.notifier).getOrderHistory();

    final sortedOrderHistory = List<OrderHistory>.from(orderHistory)..sort((a, b) => b.orderDate.compareTo(a.orderDate));

    if (sortedOrderHistory.isEmpty) {
      return Center(
        child: Text('주문 내역이 없습니다.', style: TextStyle(color: Colors.grey[400], fontSize: 16)),
      );
    }
    return ListView.builder(
      padding: EdgeInsets.symmetric(horizontal: 30.0, vertical: 20),
      itemCount: sortedOrderHistory.length,
      itemBuilder: (context, index) {
        final order = sortedOrderHistory[index];

        // Firebase에서 상품 정보를 가져오기 위해 productsProvider 사용
        final productsAsync = ref.watch(productsProvider);

        return productsAsync.when(
          loading: () => Card(
            color: Color(0xFF1E1E1E),
            margin: EdgeInsets.only(bottom: 16.0),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Center(
                child: CircularProgressIndicator(color: Color(0xFFFACC15)),
              ),
            ),
          ),
          error: (error, stack) => Card(
            color: Color(0xFF1E1E1E),
            margin: EdgeInsets.only(bottom: 16.0),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text('상품 정보를 불러올 수 없습니다.', style: TextStyle(color: Colors.grey[400])),
            ),
          ),
          data: (products) {
            // productId로 상품 찾기 (이제 name으로 찾아야 함)
            Product? product;
            try {
              product = products.firstWhere(
                (p) => p.name == order.productId,
              );
            } catch (e) {
              product = null;
            }

            if (product == null) {
              return Card(
                color: Color(0xFF1E1E1E),
                margin: EdgeInsets.only(bottom: 16.0),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text('상품 정보를 찾을 수 없습니다.', style: TextStyle(color: Colors.grey[400])),
                ),
              );
            }

            return Card(
              color: Color(0xFF1E1E1E), // 카드 배경색 (어두운 회색)
              margin: EdgeInsets.only(bottom: 16.0),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12.0),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8.0),
                          child: CachedNetworkImage(
                            imageUrl: product.imagePath,
                            width: 80,
                            height: 80,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(
                              width: 80,
                              height: 80,
                              color: Colors.grey[800],
                              child: Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Color(0xFFFACC15),
                                ),
                              ),
                            ),
                            errorWidget: (context, url, error) => Container(
                              width: 80,
                              height: 80,
                              color: Colors.grey[800],
                              child: Icon(Icons.error, color: Colors.grey),
                            ),
                          ),
                        ),
                        SizedBox(width: 12.0),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                product.name,
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                              SizedBox(height: 4.0),
                              Text(
                                '${_currencyFormat.format(product.price)} M',
                                style: TextStyle(fontSize: 14, color: Colors.orangeAccent),
                              ),
                              SizedBox(height: 4.0),
                              Text(
                                order.status,
                                style: TextStyle(
                                  color: order.status == "배송완료" ? Colors.greenAccent : Colors.yellowAccent,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 16.0),
                    Divider(color: Colors.grey[700], height: 1),
                    SizedBox(height: 12.0),
                    _buildOrderInfoRow('주문일자:', DateFormat('y년 M월 d일', 'ko_KR').format(order.orderDate)),
                    _buildOrderInfoRow('주문번호:', order.orderNumber),
                    SizedBox(height: 8.0),
                    Text('배송정보:', style: TextStyle(color: Colors.grey[400], fontSize: 13)),
                    Padding(
                      padding: const EdgeInsets.only(left: 8.0, top: 4.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('이름: ${order.recipientName}', style: TextStyle(color: Colors.white70, fontSize: 13)),
                          Text('주소: ${order.address}', style: TextStyle(color: Colors.white70, fontSize: 13)),
                          Text('연락처: ${order.phoneNumber}', style: TextStyle(color: Colors.white70, fontSize: 13)),
                        ],
                      ),
                    ),
                    // 주문 취소 버튼 (주문 완료 상태인 경우에만 표시)
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildOrderInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        children: [
          Text(label, style: TextStyle(color: Colors.grey[400], fontSize: 13)),
          SizedBox(width: 8.0),
          Expanded(
            child: Text(value, style: TextStyle(color: Colors.white70, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
