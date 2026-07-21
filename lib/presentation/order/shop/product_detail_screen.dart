import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:intl/intl.dart';
import 'package:velocity_x/velocity_x.dart';

import '../../../core/ads/admob_service.dart';
import '../../../core/widgets/user_data_builder.dart';
import '../../../data/order/model/order.dart';
import '../../../data/product/model/product.dart';
import '../../../data/user/model/user.dart';
import '../../provider/user_provider.dart';

const _kGoldGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFFD4A52A), Color(0xFFEDDD72), Color(0xFFD4A52A)],
);

final _currencyFmt = NumberFormat.decimalPattern('ko_KR');

class ProductDetailScreen extends ConsumerStatefulWidget {
  const ProductDetailScreen({super.key, required this.product});

  final Product product;

  @override
  ConsumerState<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends ConsumerState<ProductDetailScreen> with SingleTickerProviderStateMixin {
  bool _isProcessing = false;
  final InAppReview _inAppReview = InAppReview.instance;

  @override
  void initState() {
    super.initState();
    _loadNativeAd();
  }

  @override
  void dispose() {
    admobService.disposeNativeAdByKey('product_detail_screen');
    super.dispose();
  }

  void _loadNativeAd() {
    admobService.createNativeAdWithKey(
      adKey: 'product_detail_screen',
      templateStyle: NativeTemplateStyle(templateType: TemplateType.small),
      onAdLoaded: () => mounted ? setState(() {}) : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return UserDataBuilder(
      builder: (context, user, formattedMoney) {
        return Scaffold(
          backgroundColor: Colors.black,
          appBar: _TopAppBar(formattedMoney: formattedMoney, user: user),
          body: _ProductBody(
            product: widget.product,
            user: user,
            screenSize: screenSize,
            onReloadAd: _loadNativeAd,
            onOrderRequest: () => _startOrderFlow(context, user),
            isProcessing: _isProcessing,
          ),
        );
      },
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  //  Order Flow
  // ───────────────────────────────────────────────────────────────────────────

  Future<void> _startOrderFlow(BuildContext context, User user) async {
    // 이미 처리 중이면 리턴
    if (_isProcessing) return;

    final orderInfo = await _OrderInputDialog.collect(context, widget.product);
    if (orderInfo == null) return; // 취소

    final confirmed = await _OrderConfirmDialog.confirm(context, widget.product, orderInfo);
    if (!confirmed) return;

    await _processOrder(context, user, orderInfo);
  }

  void _checkAndRequestReview() async {
    Future.delayed(Duration(seconds: 1), () async {
      if (await _inAppReview.isAvailable()) {
        _inAppReview.requestReview();
      }
    });
  }

  Future<void> _processOrder(BuildContext context, User user, _OrderData info) async {
    // 이미 처리 중이면 리턴
    if (_isProcessing) return;

    // 처리 상태 설정
    setState(() {
      _isProcessing = true;
    });

    try {
      final orderNumber = OrderHistory.generateOrderNumber(info.phone);
      final OrderHistory order = OrderHistory(
        uid: user.uid,
        nickname: user.nickname,
        orderNumber: orderNumber,
        orderDate: DateTime.now(),
        recipientName: info.recipient,
        address: info.address,
        phoneNumber: info.phone,
        status: '주문 완료',
        productId: widget.product.name,
        price: widget.product.price,
        productName: widget.product.name,
      );

      // 로딩 다이얼로그
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (c) => const _LoadingDialog(),
      );

      final notifier = ref.read(currentUserProvider.notifier);
      final success = await notifier.addOrderHistory(order);

      if (mounted) Navigator.of(context).pop(); // close loading

      final snackBar = SnackBar(
        content: Text(success ? '주문이 정상적으로 처리되었습니다.\n주문번호: $orderNumber' : '주문 처리 중 오류가 발생했습니다. 다시 시도해주세요.'),
        backgroundColor: success ? Colors.green : Colors.red,
      );
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(snackBar);

      // 주문 성공 시 인앱 리뷰 요청
      if (success) {
        _checkAndRequestReview();
      }
    } finally {
      // 처리 상태 해제
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Top AppBar
// ─────────────────────────────────────────────────────────────────────────────

class _TopAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _TopAppBar({required this.formattedMoney, required this.user});

  final String formattedMoney;
  final User user;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: const Color(0xffE8ECF2),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          'BACK'.text.size(18).medium.black.make(),
          GestureDetector(
            onTap: () => Navigator.pushNamed(context, '/money'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                '$formattedMoney M'.text.size(18).medium.black.make(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Body (image, info, button, ad)
// ─────────────────────────────────────────────────────────────────────────────

class _ProductBody extends StatelessWidget {
  const _ProductBody({
    required this.product,
    required this.user,
    required this.screenSize,
    required this.onReloadAd,
    required this.onOrderRequest,
    required this.isProcessing,
  });

  final Product product;
  final User user;
  final Size screenSize;
  final VoidCallback onReloadAd;
  final VoidCallback onOrderRequest;
  final bool isProcessing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 35, left: 35, top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ProductImage(imagePath: product.imagePath, screenSize: screenSize),
          const SizedBox(height: 20),
          _ProductInfo(product: product),
          const SizedBox(height: 25),
          _OrderButton(product: product, user: user, onPressed: onOrderRequest, isProcessing: isProcessing),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Sub‑Widgets
// ─────────────────────────────────────────────────────────────────────────────

class _ProductImage extends StatelessWidget {
  const _ProductImage({required this.imagePath, required this.screenSize});

  final String imagePath;
  final Size screenSize;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: CachedNetworkImage(
        imageUrl: imagePath,
        height: screenSize.width * 0.7,
        width: double.infinity,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(
          height: screenSize.width * 0.7,
          color: Colors.grey[850],
          child: Center(
            child: CircularProgressIndicator(
              color: Color(0xFFFACC15),
            ),
          ),
        ),
        errorWidget: (context, url, error) => Container(
          height: screenSize.width * 0.7,
          color: Colors.grey[850],
          child: Center(
            child: Icon(
              Icons.error,
              color: Colors.grey,
              size: 50,
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductInfo extends StatelessWidget {
  const _ProductInfo({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      product.name.text.size(22).bold.white.make(),
      const SizedBox(height: 10),
      '${_currencyFmt.format(product.price)} M'.text.size(20).bold.color(Colors.orangeAccent).make(),
    ],
  );
}

class _OrderButton extends StatelessWidget {
  const _OrderButton({required this.product, required this.user, required this.onPressed, required this.isProcessing});

  final Product product;
  final User user;
  final VoidCallback onPressed;
  final bool isProcessing;

  @override
  Widget build(BuildContext context) {
    final canAfford = user.money >= product.price;
    final isEnabled = canAfford && !isProcessing;

    return Container(
      decoration: BoxDecoration(
        gradient: isEnabled
            ? _kGoldGradient
            : const LinearGradient(
                colors: [Colors.grey, Colors.grey],
              ),
        borderRadius: BorderRadius.circular(15),
      ),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          padding: EdgeInsets.zero,
        ),
        onPressed: isEnabled
            ? () {
                if (!canAfford) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('머니가 부족합니다.'), backgroundColor: Colors.red),
                  );
                  return;
                }
                onPressed();
              }
            : null,
        child: isProcessing
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.black54,
                      strokeWidth: 2,
                    ),
                  ),
                  const SizedBox(width: 8),
                  '처리 중...'.text.size(18).bold.color(Colors.black54).make(),
                ],
              )
            : (canAfford ? '주문하기' : '머니 부족').text.size(18).bold.color(isEnabled ? Colors.black : Colors.grey[600]!).make(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Dialogs & DTO
// ─────────────────────────────────────────────────────────────────────────────

class _LoadingDialog extends StatelessWidget {
  const _LoadingDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF2D2D2D),
      content: Row(
        children: const [
          CircularProgressIndicator(color: Color(0xFFFACC15)),
          SizedBox(width: 20),
          Text('주문 처리 중...', style: TextStyle(color: Colors.white)),
        ],
      ),
    );
  }
}

class _OrderData {
  const _OrderData({required this.recipient, required this.address, required this.phone});

  final String recipient;
  final String address;
  final String phone;
}

class _OrderInputDialog extends StatefulWidget {
  const _OrderInputDialog({required this.product});

  final Product product;

  static Future<_OrderData?> collect(BuildContext context, Product product) {
    return showDialog<_OrderData>(
      context: context,
      builder: (_) => _OrderInputDialog(product: product),
    );
  }

  @override
  State<_OrderInputDialog> createState() => _OrderInputDialogState();
}

class _OrderInputDialogState extends State<_OrderInputDialog> {
  final _nameCtrl = TextEditingController();
  final _addrCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF2D2D2D),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: const Text(
        '주문 정보 입력',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('상품명: ${widget.product.name}', style: const TextStyle(color: Colors.white70)),
            Text('가격: ${_currencyFmt.format(widget.product.price)} M', style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 16),
            _buildTextField(_nameCtrl, '수령인'),
            const SizedBox(height: 12),
            _buildTextField(_addrCtrl, '배송 주소'),
            const SizedBox(height: 12),
            _buildTextField(_phoneCtrl, '연락처 (- 없이 입력)', keyboard: TextInputType.phone),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('취소', style: TextStyle(color: Colors.grey[400])),
        ),
        TextButton(
          onPressed: _submit,
          child: const Text(
            '주문하기',
            style: TextStyle(color: Color(0xFFFACC15), fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  Widget _buildTextField(TextEditingController ctrl, String label, {TextInputType keyboard = TextInputType.text}) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboard,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
        focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFFACC15))),
      ),
    );
  }

  void _submit() {
    if (_nameCtrl.text.trim().isEmpty || _addrCtrl.text.trim().isEmpty || _phoneCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('모든 항목을 입력해주세요'), backgroundColor: Colors.red),
      );
      return;
    }

    Navigator.pop(
      context,
      _OrderData(
        recipient: _nameCtrl.text.trim(),
        address: _addrCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
      ),
    );
  }
}

class _OrderConfirmDialog extends StatelessWidget {
  const _OrderConfirmDialog({required this.product, required this.data});

  final Product product;
  final _OrderData data;

  static Future<bool> confirm(BuildContext context, Product product, _OrderData data) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _OrderConfirmDialog(product: product, data: data),
    );
    return result == true;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF2D2D2D),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: const Text(
        '주문 확인',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '이대로 주문하시겠습니까?',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Text('상품명: ${product.name}', style: const TextStyle(color: Colors.white70)),
            Text('가격: ${_currencyFmt.format(product.price)} M', style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 16),
            _deliveryInfo('수령인', data.recipient),
            _deliveryInfo('배송주소', data.address),
            _deliveryInfo('연락처', data.phone),
          ],
        ),
      ),
      actions: [
        TextButton(
          child: Text('취소', style: TextStyle(color: Colors.grey[400])),
          onPressed: () => Navigator.pop(context, false),
        ),
        TextButton(
          child: const Text(
            '확인',
            style: TextStyle(color: Color(0xFFFACC15), fontWeight: FontWeight.bold),
          ),
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    );
  }

  Widget _deliveryInfo(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      children: [
        SizedBox(
          width: 80,
          child: Text('$label:', style: const TextStyle(color: Colors.white70)),
        ),
        Expanded(
          child: Text(value, style: const TextStyle(color: Colors.white)),
        ),
      ],
    ),
  );
}
