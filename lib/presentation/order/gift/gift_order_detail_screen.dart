import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_review/in_app_review.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:velocity_x/velocity_x.dart';

import '../../../data/gift_order/model/gift_order.dart';
import '../../provider/user_provider.dart';

class GiftOrderDetailScreen extends ConsumerStatefulWidget {
  final String orderId;
  final String? userId;

  const GiftOrderDetailScreen({
    super.key,
    required this.orderId,
    this.userId,
  });

  @override
  ConsumerState<GiftOrderDetailScreen> createState() => _GiftOrderDetailScreenState();
}

class _GiftOrderDetailScreenState extends ConsumerState<GiftOrderDetailScreen> {
  final NumberFormat _currencyFormat = NumberFormat.decimalPattern('ko_KR');
  final DateFormat _dateFormat = DateFormat('yyyy년 M월 d일', 'ko_KR');

  final InAppReview _inAppReview = InAppReview.instance;

  GiftOrderHistory? _orderData;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadOrderData();
  }

  Future<void> _loadOrderData() async {
    final repository = ref.read(giftOrderRepositoryProvider);
    try {
      GiftOrderHistory? order;

      // userId가 있으면 최적화된 메서드 사용 (OOM 방지)
      final userId = widget.userId ?? ref.read(currentUserProvider)?.uid;
      if (userId != null) {
        order = await repository.getGiftOrderByUserId(userId, widget.orderId);
      } else {
        // fallback: 비효율적인 전체 조회 (가능하면 사용 안함)
        // ignore: deprecated_member_use_from_same_package
        order = await repository.getGiftOrder(widget.orderId);
      }

      if (mounted) {
        setState(() {
          _orderData = order;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _checkAndRequestReview() async {
    Future.delayed(Duration(seconds: 2), () async {
      if (await _inAppReview.isAvailable()) {
        _inAppReview.requestReview();
      }
    });
  }
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: CircularProgressIndicator(color: Colors.orangeAccent).centered(),
      );
    }

    if (_error != null || _orderData == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          title: '주문 상세'.text.make(),
        ),
        body: VStack([
          Icon(Icons.error_outline, color: Colors.red, size: 48),
          16.heightBox,
          '주문 정보를 불러올 수 없습니다'.text.white.size(16).make(),
          8.heightBox,
          (_error ?? '').text.color(Colors.grey[400]!).size(14).make(),
        ], crossAlignment: CrossAxisAlignment.center).centered(),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: '기프티콘 상세'.text.white.make(),
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        child: VStack([
          // 바코드 섹션
          Stack(
            children: [
              VStack([
                // 브랜드명
                _orderData!.brandName.text.black.size(20).bold.make(),
                8.heightBox,
                // 상품명
                _orderData!.goodsName.text.color(Colors.grey[700]!).size(16).align(TextAlign.center).make(),
                24.heightBox,
                // 바코드 이미지 (캐싱 및 크기 제한 적용)
                _orderData!.barcodeImageUrl != null && _orderData!.barcodeImageUrl!.isNotEmpty
                    ? ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width - 48,
                        ),
                        child: CachedNetworkImage(
                          imageUrl: _orderData!.barcodeImageUrl!,
                          fit: BoxFit.contain,
                          memCacheWidth: 800, // 메모리 캐시 이미지 최대 너비 제한
                          placeholder: (context, url) => VStack([
                            CircularProgressIndicator(color: Colors.orangeAccent),
                            8.heightBox,
                            '바코드 로딩 중...'.text.color(Colors.grey).size(14).make(),
                          ], crossAlignment: CrossAxisAlignment.center).box.width(280).height(150).color(Colors.grey[200]!).make().centered(),
                          errorWidget: (context, url, error) => VStack(
                            [
                              Icon(Icons.error_outline, color: Colors.grey, size: 32),
                              8.heightBox,
                              '바코드를 불러올 수 없습니다'.text.color(Colors.grey).size(14).make(),
                            ],
                            crossAlignment: CrossAxisAlignment.center,
                          ).box.width(280).height(100).color(Colors.grey[200]!).make().centered(),
                        ),
                      )
                    : VStack([
                        Icon(Icons.qr_code, color: Colors.grey, size: 48),
                        8.heightBox,
                        '바코드 정보가 없습니다'.text.color(Colors.grey).size(14).make(),
                      ], crossAlignment: CrossAxisAlignment.center).box.width(280).height(100).color(Colors.grey[200]!).make().centered(),
                16.heightBox,
                // 사용 완료 상태 표시
                if (_orderData!.status == '사용완료')
                  VStack([
                    HStack([
                      Icon(Icons.check_circle, color: Colors.green, size: 20),
                      8.widthBox,
                      '사용 완료'.text.color(Colors.green).size(16).bold.make(),
                    ], crossAlignment: CrossAxisAlignment.center).centered(),
                    8.heightBox,
                    '이미 사용된 기프티콘입니다'.text.color(Colors.grey[600]!).size(14).make().centered(),
                  ])
                // 바코드 이미지 공유 및 코드 복사 버튼 (사용 완료가 아닌 경우만)
                else if (_orderData!.barcodeImageUrl != null && _orderData!.barcodeImageUrl!.isNotEmpty && !_orderData!.isExpired)
                  Row(
                    children: [
                      // 이미지 공유 버튼
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: Colors.orangeAccent),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                          ),
                          onPressed: () => _shareBarcodeImage(),
                          icon: Icon(Icons.share, color: Colors.orangeAccent, size: 20),
                          label: '이미지 공유'.text.orange400.make(),
                        ),
                      ),
                      8.widthBox,
                      // 코드 복사 버튼
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: Colors.orangeAccent),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                          ),
                          onPressed: () => _copyBarcodeNumber(),
                          icon: Icon(Icons.copy, color: Colors.orangeAccent, size: 20),
                          label: '코드 복사'.text.orange400.make(),
                        ),
                      ),
                    ],
                  ),
              ]).p24().box.white.make(),
              // 사용 완료 오버레이
              if (_orderData!.status == '사용완료')
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(0),
                    ),
                  ),
                ),
            ],
          ),

          // 상품 정보
          VStack([
            '상품 정보'.text.white.size(18).bold.make(),
            16.heightBox,
            _buildInfoRow('브랜드', _orderData!.brandName),
            8.heightBox,
            _buildInfoRow('상품명', _orderData!.goodsName),
            8.heightBox,
            _buildInfoRow('금액', '${_currencyFormat.format(_orderData!.price)} M'),
            8.heightBox,
            _buildInfoRow('주문일자', _dateFormat.format(_orderData!.orderDate)),
            8.heightBox,
            _buildInfoRow('상태', _orderData!.status, isStatus: true),
            // 구매 시 입력한 휴대폰 번호 (잘못 입력했는지 확인용 - 마스킹 없이 전체 표시)
            if (_orderData!.phoneNumber != null && _orderData!.phoneNumber!.isNotEmpty) ...[
              8.heightBox,
              _buildInfoRow('휴대폰 번호', _orderData!.phoneNumber!),
            ],
            if (_orderData!.expiryDate != null) ...[
              8.heightBox,
              _buildInfoRow(
                '유효기간',
                _orderData!.isExpired ? '만료됨' : '${_dateFormat.format(_orderData!.expiryDate!)}까지',
                isExpired: _orderData!.isExpired,
              ),
            ],
          ]).p16(),

          // 사용 방법
          VStack([
            '사용 방법'.text.white.size(18).bold.make(),
            10.heightBox,
            ?_orderData?.goodsDetail?['content'].toString().text.gray400.make(),
          ]).p16().box.color(Color(0xFF1E1E1E)).rounded.make().p16(),

          // 주의사항
          VStack([
                HStack([
                  Icon(Icons.warning_amber, color: Colors.orange, size: 20),
                  8.widthBox,
                  '주의사항'.text.orange50.size(16).bold.make(),
                ]),
                12.heightBox,
                '• 바코드는 1회만 사용 가능합니다'.text.color(Colors.grey[400]!).size(13).make(),
                4.heightBox,
                '• 유효기간이 지나면 사용할 수 없습니다'.text.color(Colors.grey[400]!).size(13).make(),
                4.heightBox,
                '• 환불 및 취소가 불가능합니다'.text.color(Colors.grey[400]!).size(13).make(),
                4.heightBox,
                '• 캡처한 이미지로는 사용이 제한될 수 있습니다'.text.color(Colors.grey[400]!).size(13).make(),
              ])
              .p16()
              .box
              .color(Colors.orange.withOpacity(0.1))
              .border(color: Colors.orange.withOpacity(0.3))
              .rounded
              .make()
              .wFull(context)
              .p16(),

          50.heightBox,
        ]),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {bool isExpired = false, bool isStatus = false}) {
    Color textColor = Colors.white;
    if (isExpired) {
      textColor = Colors.red;
    } else if (isStatus) {
      switch (value) {
        case '구매완료':
          textColor = Colors.orangeAccent;
          break;
        case '사용완료':
          textColor = Colors.green;
          break;
        case '만료':
          textColor = Colors.red;
          break;
      }
    }

    return HStack([
      label.text.color(Colors.grey[400]!).size(14).make().box.width(80).make(),
      value.text.color(textColor).size(14).semiBold.make().expand(),
    ]);
  }

  /// 바코드 이미지 공유 (권한 불필요)
  Future<void> _shareBarcodeImage() async {
    try {
      // 로딩 표시
      _showLoadingDialog();

      // 바코드 이미지 URL에서 이미지 다운로드
      final response = await http.get(Uri.parse(_orderData!.barcodeImageUrl!));
      if (response.statusCode != 200) {
        throw Exception('이미지 다운로드 실패: ${response.statusCode}');
      }

      final Uint8List bytes = response.bodyBytes;

      // 임시 디렉토리에 파일 저장
      final tempDir = await getTemporaryDirectory();
      final fileName = 'pigmoney_barcode_${_orderData!.brandName}_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(bytes);

      // 로딩 다이얼로그 닫기
      if (mounted) Navigator.of(context).pop();

      // 공유 실행 (권한 불필요)
      await Share.shareXFiles(
        [XFile(file.path)],
        text: '${_orderData!.brandName} - ${_orderData!.goodsName}',
      );
    } catch (e) {
      // 로딩 다이얼로그 닫기
      if (mounted) Navigator.of(context).pop();

      // 에러 메시지
      _showErrorDialog(e.toString());
    }
  }

  /// 로딩 다이얼로그 표시
  void _showLoadingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Color(0xFF2A2A2A),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.orangeAccent),
            SizedBox(height: 16),
            Text('바코드 이미지를 준비하고 있습니다...', style: TextStyle(color: Colors.white, fontSize: 14)),
          ],
        ),
      ),
    );
  }

  /// 에러 다이얼로그 표시
  void _showErrorDialog(String error) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Color(0xFF2A2A2A),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: Colors.red, size: 24),
            SizedBox(width: 8),
            Text(
              '공유 실패',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('이미지 공유에 실패했습니다.', style: TextStyle(color: Colors.grey[300], fontSize: 14)),
            SizedBox(height: 8),
            Text(error, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('확인', style: TextStyle(color: Colors.orange[400])),
          ),
        ],
      ),
    );
  }

  /// 바코드 번호 복사
  Future<void> _copyBarcodeNumber() async {
    try {
      if (_orderData?.barcodeNumber == null || _orderData!.barcodeNumber!.isEmpty) {
        _showCopyErrorDialog('바코드 번호가 없습니다.');
        return;
      }

      // 클립보드에 복사
      await Clipboard.setData(ClipboardData(text: _orderData!.barcodeNumber!));

      // 성공 메시지
      _showCopySuccessDialog();
    } catch (e) {
      _showCopyErrorDialog('복사 중 오류가 발생했습니다: ${e.toString()}');
    }
  }

  /// 복사 성공 다이얼로그
  void _showCopySuccessDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Color(0xFF2A2A2A),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 24),
            SizedBox(width: 8),
            Text(
              '복사 완료',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text('바코드 번호가 복사되었습니다.', style: TextStyle(color: Colors.grey[300], fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('확인', style: TextStyle(color: Colors.orange[400])),
          ),
        ],
      ),
    );
  }

  /// 복사 에러 다이얼로그
  void _showCopyErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Color(0xFF2A2A2A),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: Colors.red, size: 24),
            SizedBox(width: 8),
            Text(
              '복사 실패',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(message, style: TextStyle(color: Colors.grey[300], fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('확인', style: TextStyle(color: Colors.orange[400])),
          ),
        ],
      ),
    );
  }
}
