import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:velocity_x/velocity_x.dart';

import '../../../core/giftishow/exceptions/giftishow_exceptions.dart';
import '../../../core/giftishow/models/goods_model.dart';
import '../../../data/gift/model/gift_product.dart';
import '../../../data/gift_order/model/gift_order.dart';
import '../../provider/giftishow_provider.dart';
import '../../provider/user_provider.dart';

class GiftishowDetailScreen extends ConsumerStatefulWidget {
  final Goods goods;

  const GiftishowDetailScreen({
    super.key,
    required this.goods,
  });

  @override
  ConsumerState<GiftishowDetailScreen> createState() => _GiftishowDetailScreenState();
}

class _GiftishowDetailScreenState extends ConsumerState<GiftishowDetailScreen> {
  final NumberFormat _currencyFormat = NumberFormat.decimalPattern('ko_KR');
  bool _isProcessing = false;

  @override
  Widget build(BuildContext context) {
    // 기프트 상품 리스트에서 해당 상품의 money 값 찾기
    final giftProductsAsync = ref.watch(giftProductsProvider);
    final giftProducts = giftProductsAsync.valueOrNull ?? [];

    // 상품 코드로 매칭되는 money 값 찾기
    final matchedProduct = giftProducts.firstWhere(
      (p) => p.code == widget.goods.goodsCode,
      orElse: () => GiftProduct(code: '', brand: '', money: 3700000, name: ''), // 기본값
    );

    final payPrice = matchedProduct.money;
    final currentUser = ref.watch(currentUserProvider);
    final userBalance = (currentUser?.money ?? 0);
    final canAfford = userBalance >= payPrice;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // 스크롤 가능한 컨텐츠
            SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 상단 이미지
                  Stack(
                    children: [
                      Container(
                        width: double.infinity,
                        height: 300,
                        color: Colors.grey[900],
                        child: widget.goods.goodsImgB.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: widget.goods.goodsImgB,
                                fit: BoxFit.contain,
                                memCacheWidth: 600,
                                memCacheHeight: 600,
                                placeholder: (context, url) => Center(
                                  child: CircularProgressIndicator(
                                    color: Colors.orangeAccent,
                                    strokeWidth: 2,
                                  ),
                                ),
                                errorWidget: (context, url, error) =>
                                    Center(child: Icon(Icons.card_giftcard, color: Colors.orangeAccent, size: 80)),
                              )
                            : Center(child: Icon(Icons.card_giftcard, color: Colors.orangeAccent, size: 80)),
                      ),
                      // 뒤로가기 버튼
                      CircleAvatar(
                        backgroundColor: Colors.black.withOpacity(0.5),
                        child: IconButton(
                          icon: Icon(Icons.arrow_back, color: Colors.white),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ).positioned(top: 16, left: 16),
                    ],
                  ),

                  // 상품 정보
                  Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 브랜드명
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.orangeAccent.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.orangeAccent, width: 1),
                          ),
                          child: Text(
                            widget.goods.brandName,
                            style: TextStyle(
                              color: Colors.orangeAccent,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        SizedBox(height: 16),

                        // 상품명
                        widget.goods.goodsName.text.size(24).white.bold.make(),
                        SizedBox(height: 8),

                        // 상품 설명
                        if (widget.goods.content.isNotEmpty) widget.goods.content.text.color(Colors.grey[300]).size(14).heightLoose.make(),

                        SizedBox(height: 24),

                        // 가격 정보
                        Container(
                          padding: EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Color(0xFF1E1E1E),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  '판매가'.text.size(16).color(Colors.grey[400]).make(),
                                  '${_currencyFormat.format(payPrice)} M'.text.size(24).bold.color(Colors.orangeAccent).make(),
                                ],
                              ),
                            ],
                          ),
                        ),

                        SizedBox(height: 16),

                        // 구매 전 확인사항
                        Container(
                          padding: EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.orange.withOpacity(0.3)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.warning_amber, color: Colors.orange, size: 20),
                                  SizedBox(width: 8),
                                  '구매 전 확인사항'.text.size(14).orange400.bold.make(),
                                ],
                              ),
                              SizedBox(height: 8),
                              Text('• 구매 후 취소/환불이 불가능합니다', style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                              Text('• 유효기간 내 사용하지 않으면 자동 소멸됩니다', style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                              Text('• 바코드는 구매 후 주문내역에서 확인 가능합니다', style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                            ],
                          ),
                        ),

                        // 하단 여백 (구매 버튼 공간)
                        SizedBox(height: 100),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // 하단 구매 버튼
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Color(0xffE8ECF2),
                border: Border(
                  top: BorderSide(color: Colors.grey[400]!, width: 1),
                ),
              ),
              child: Row(
                children: [
                  // 보유 머니 표시
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      '보유 머니'.text.size(12).color(Colors.grey[600]).semiBold.make(),
                      SizedBox(height: 4),
                      '${_currencyFormat.format(userBalance)} M'.text.size(16).bold.color(canAfford ? Colors.black : Colors.red).make(),
                    ],
                  ).expand(),

                  // 구매 버튼
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: canAfford && !_isProcessing ? Colors.orangeAccent : Colors.grey[700],
                      padding: EdgeInsets.symmetric(horizontal: 48, vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: canAfford && !_isProcessing ? () => _showPurchaseDialog(payPrice, matchedProduct) : null,
                    child: _isProcessing
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.grey[500],
                              strokeWidth: 2,
                            ),
                          )
                        : (canAfford ? '구매하기' : '머니 부족').text.color(canAfford ? Colors.black : Colors.grey[500]).size(16).bold.make(),
                  ),
                ],
              ),
            ).positioned(bottom: 0, right: 0, left: 0),
          ],
        ),
      ),
    );
  }

  void _showPurchaseDialog(int payPrice, GiftProduct matchedProduct) async {
    final currentUser = ref.read(currentUserProvider);

    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('사용자 정보를 불러올 수 없습니다'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // 0단계: IP 및 디바이스 차단 확인
    try {
      final userRepository = ref.read(userRepositoryProvider);
      final blockResult = await userRepository.checkPurchaseBlock(
        currentUser.deviceId,
        currentUser.uid,
      );

      if (blockResult['blocked'] == true) {
        // 사용자 정보 새로고침
        await ref.read(currentUserProvider.notifier).refreshUserData();

        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              backgroundColor: Color(0xFF2D2D2D),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text(
                '구매 제한',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(child: Icon(Icons.block, color: Colors.red, size: 48)),
                    SizedBox(height: 16),
                    Center(
                      child: Text(
                        '구매가 제한된 계정입니다.\n고객센터로 문의해주세요.',
                        style: TextStyle(color: Colors.white70, fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('확인', style: TextStyle(color: Colors.orangeAccent)),
                ),
              ],
            ),
          );
        }
        return;
      }
    } catch (e) {
      print('IP/디바이스 차단 확인 중 오류: $e');
    }

    if (mounted) {
      if (currentUser.purchaseValid == 2) {
        _showConfirmPurchaseDialog(payPrice, matchedProduct);
        return;
      }
    }

    // 1단계: purchaseValid 값 확인
    if (currentUser.purchaseValid == 1) {
      // 대기 상태 - 관리자 문의 필요
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: Color(0xFF2D2D2D),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(
              '구매 승인 필요',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(child: Icon(Icons.block, color: Colors.red, size: 48)),
                  SizedBox(height: 16),
                  Center(
                    child: Text(
                      '구매 승인이 필요합니다.\n고객센터로 문의해주세요.',
                      style: TextStyle(color: Colors.white70, fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('확인', style: TextStyle(color: Colors.orangeAccent)),
              ),
            ],
          ),
        );
      }
      return;
    }

    // 2단계: 같은 날짜에 3명 이상 초대된 이력 검증 (purchaseValid가 0과 1인 경우에만)
    // purchaseValid가 2(영구승인)인 경우 이 단계를 건너뛰고 3단계로 진행
    if (currentUser.purchaseValid == 0 || currentUser.purchaseValid == 1) {
      try {
        final inviteFriendList = currentUser.inviteFriendList;

        if (inviteFriendList.isNotEmpty) {
          // 날짜별로 그룹화하여 카운트
          Map<String, int> invitesByDate = {};

          for (var friend in inviteFriendList) {
            final dateKey = DateFormat('yyyy-MM-dd').format(friend.invitedAt);
            invitesByDate[dateKey] = (invitesByDate[dateKey] ?? 0) + 1;
          }

          // 3명 이상 초대된 날짜가 있는지 확인
          final hasSuspiciousInvites = invitesByDate.values.any((count) => count >= 3);

          if (hasSuspiciousInvites) {
            // purchaseValid를 1로 변경

            final userRepository = ref.read(userRepositoryProvider);
            if (currentUser.purchaseValid == 0) await userRepository.updatePurchaseValid(currentUser.uid, 1);

            // invites 컬렉션에 저장
            await userRepository.saveToInvitesCollection(
              uid: currentUser.uid,
              nickname: currentUser.nickname,
              inviteCount: inviteFriendList.length,
            );

            // 사용자 정보 새로고침
            await ref.read(currentUserProvider.notifier).refreshUserData();

            // 관리자 문의 메시지 표시
            if (mounted) {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  backgroundColor: Color(0xFF2D2D2D),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  title: Text(
                    '구매 승인 필요',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(child: Icon(Icons.block, color: Colors.red, size: 48)),
                        SizedBox(height: 16),
                        Center(
                          child: Text(
                            '구매 승인이 필요합니다.\n고객센터로 문의해주세요.',
                            style: TextStyle(color: Colors.white70, fontSize: 16),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text('확인', style: TextStyle(color: Colors.orangeAccent)),
                    ),
                  ],
                ),
              );
            }
            return;
          }
        }
      } catch (e) {
        print('초대 이력 검증 중 오류: $e');
        // 검증 오류 시에도 계속 진행 (다음 단계 검증으로)
      }
    }

    // 3단계: 서버 측 검증 (기존 3일 후 구매 조건)
    try {
      // Repository를 통한 서버 검증
      final repository = ref.read(giftOrderRepositoryProvider);
      final verificationResult = await repository.verifyPurchaseEligibility(currentUser.uid);

      // 디버깅: 결과 출력
      print('🔍 검증 결과: $verificationResult');
      print('🔍 UID: ${currentUser.uid}');
      print('🔍 eligible: ${verificationResult['eligible']}');
      print('🔍 error: ${verificationResult['error']}');
      print('🔍 message: ${verificationResult['message']}');

      if (verificationResult['eligible'] == false) {
        // 구매 불가
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              backgroundColor: Color(0xFF2D2D2D),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text(
                '구매 승인 필요',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(child: Icon(Icons.block, color: Colors.red, size: 48)),
                    SizedBox(height: 16),
                    Center(
                      child: Text(
                        verificationResult['message'] ?? '관리자의 확인이 필요한 계정입니다.\n고객센터로 문의 부탁드립니다.',
                        style: TextStyle(color: Colors.white70, fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    if (verificationResult['eligibleDate'] != null) ...[
                      SizedBox(height: 8),
                      Center(
                        child: Text(
                          '구매 가능일: ${DateFormat('yyyy.MM.dd HH:mm').format(DateTime.parse(verificationResult['eligibleDate']).toLocal())}',
                          style: TextStyle(color: Colors.orangeAccent, fontSize: 14),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('확인', style: TextStyle(color: Colors.orangeAccent)),
                ),
              ],
            ),
          );
        }
        return;
      }

      // 구매 가능 - 구매 확인 다이얼로그 표시
      if (mounted) {
        _showConfirmPurchaseDialog(payPrice, matchedProduct);
      }
    } catch (e) {
      // 로딩 닫기
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('구매 자격 확인 중 오류가 발생했습니다\n잠시 후 다시 시도해주세요'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  void _showConfirmPurchaseDialog(int payPrice, GiftProduct matchedProduct) {
    // 전화번호 입력 다이얼로그 표시
    final phoneController = TextEditingController();
    bool isNextPressed = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isValid = phoneController.text.length == 11 && !isNextPressed;
          return AlertDialog(
            backgroundColor: Color(0xFF2D2D2D),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(
              '휴대폰 번호 입력',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.card_giftcard, color: Colors.orangeAccent, size: 48),
                  SizedBox(height: 8),
                  widget.goods.goodsName.text.white.size(16).bold.center.make(),
                  SizedBox(height: 8),
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: '${_currencyFormat.format(payPrice)} M'.text.size(20).orange500.bold.make(),
                  ),
                  SizedBox(height: 16),
                  Text(
                    '기프티콘을 받을 휴대폰 번호를 입력해주세요',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 12),
                  TextField(
                    controller: phoneController,
                    keyboardType: TextInputType.number,
                    maxLength: 11,
                    enabled: !isNextPressed,
                    style: TextStyle(color: Colors.white, fontSize: 18, letterSpacing: 2),
                    textAlign: TextAlign.center,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(11),
                    ],
                    decoration: InputDecoration(
                      hintText: '01012345678',
                      hintStyle: TextStyle(color: Colors.grey[600]),
                      counterText: '',
                      filled: true,
                      fillColor: Colors.black.withOpacity(0.3),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.orangeAccent),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey[700]!),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.orangeAccent, width: 2),
                      ),
                    ),
                    onChanged: (value) {
                      setDialogState(() {});
                    },
                  ),
                  SizedBox(height: 8),
                  Text(
                    '구매 후 취소/환불이 불가능합니다',
                    style: TextStyle(color: Colors.red[300], fontSize: 12),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isNextPressed ? null : () => Navigator.of(dialogContext).pop(),
                child: Text('취소', style: TextStyle(color: isNextPressed ? Colors.grey[600] : Colors.grey)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isValid ? Colors.orangeAccent : Colors.grey[700],
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: isValid
                    ? () {
                        setDialogState(() {
                          isNextPressed = true;
                        });
                        Navigator.of(dialogContext).pop();
                        _showPhoneConfirmDialog(payPrice, matchedProduct, phoneController.text);
                      }
                    : null,
                child: Text(
                  '다음',
                  style: TextStyle(
                    color: isValid ? Colors.black : Colors.grey[500],
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showPhoneConfirmDialog(int payPrice, GiftProduct matchedProduct, String phoneNo) {
    // 전화번호 확인 다이얼로그 표시
    final formattedPhone = '${phoneNo.substring(0, 3)}-${phoneNo.substring(3, 7)}-${phoneNo.substring(7)}';
    bool isButtonDisabled = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: Color(0xFF2D2D2D),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(
              '번호 확인',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 48),
                  SizedBox(height: 16),
                  '입력하신 번호가 맞습니까?'.text.color(Colors.white70).size(14).make(),
                  SizedBox(height: 12),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orangeAccent, width: 2),
                    ),
                    child: formattedPhone.text.white.size(24).bold.letterSpacing(2).make(),
                  ),
                  SizedBox(height: 16),
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.withOpacity(0.3)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.error, color: Colors.red, size: 20),
                            SizedBox(width: 8),
                            '주의사항'.text.red400.size(14).bold.make(),
                          ],
                        ),
                        SizedBox(height: 8),
                        '상품권 발송 및 CS 대응을 위해 휴대전화 번호를 수집하며, 구매 내역에 저장됩니다.'.text.red400.size(14).letterSpacing(-0.2).bold.center.make(),
                      ],
                    ),
                  ),
                  SizedBox(height: 8),
                  '구매 후 취소/환불이 불가능합니다'.text.red300.size(12).make(),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isButtonDisabled
                    ? null
                    : () {
                        Navigator.of(dialogContext).pop();
                        _showConfirmPurchaseDialog(payPrice, matchedProduct);
                      },
                child: Text('번호 수정', style: TextStyle(color: isButtonDisabled ? Colors.grey[600] : Colors.grey)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isButtonDisabled ? Colors.grey[700] : Colors.orangeAccent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: isButtonDisabled
                    ? null
                    : () async {
                        setDialogState(() {
                          isButtonDisabled = true;
                        });
                        Navigator.of(dialogContext).pop();
                        await _processPurchase(payPrice, matchedProduct, phoneNo);
                      },
                child: isButtonDisabled
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey[500]),
                      )
                    : Text(
                        '구매 확인',
                        style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _processPurchase(int payPrice, GiftProduct matchedProduct, String phoneNo) async {
    // 이미 처리 중이면 리턴
    if (_isProcessing) return;

    // 처리 상태 설정
    setState(() {
      _isProcessing = true;
    });
    // Navigator 참조를 미리 저장
    final navigator = Navigator.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    try {
      final user = ref.watch(currentUserProvider);

      if (user == null) {
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text('유저 정보가 없습니다. 재 로그인 후 시도 바랍니다.'), backgroundColor: Colors.red, duration: Duration(seconds: 4)),
        );
        return;
      }

      // 잔액 확인
      if (user.money < payPrice) {
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text('잔액이 부족합니다.'), backgroundColor: Colors.red, duration: Duration(seconds: 4)),
        );
        return;
      }

      // 로딩 표시
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Center(
          child: CircularProgressIndicator(color: Colors.orangeAccent),
        ),
      );

      // 2. Repository 가져오기 (Cloud Functions를 통해 기프티쇼 API 호출)
      final repository = ref.read(giftOrderRepositoryProvider);

      // 3. TR_ID 생성 (고유값, 25자 이하)
      final trId = repository.generateTrId();

      // 4. Cloud Functions를 통해 기프티쇼 MMS 발송 요청
      // IP 화이트리스트가 적용된 서버를 통해 API 호출
      final couponResponse = await repository.sendGiftishowCoupon(
        goodsCode: widget.goods.goodsCode,
        phoneNo: phoneNo,
        callbackNo: '15880108',
        userId: 'admin@reviewtube.co.kr',
        trId: trId,
        mmsTitle: '피그머니',
        mmsMsg: '피그머니에서 구매한 기프티콘입니다.',
        uid: user.uid,
      );

      if (couponResponse['success'] != true) {
        throw GiftishowException(
          couponResponse['message'] ?? 'MMS 발송에 실패했습니다',
          code: couponResponse['code'],
        );
      }

      // 5. Firebase gift_orders에 저장 + 머니 차감 (트랜잭션)
      final giftOrder = GiftOrderHistory(
        orderId: trId,
        userId: user.uid,
        goodsCode: widget.goods.goodsCode,
        goodsName: widget.goods.goodsName,
        brandCode: widget.goods.brandCode,
        brandName: widget.goods.brandName,
        goodsImgUrl: widget.goods.goodsImgS,
        price: payPrice,
        orderDate: DateTime.now(),
        status: 'MMS발송완료',
        trId: trId,
        phoneNumber: phoneNo,
      );

      await repository.purchaseGiftWithTransaction(
        order: giftOrder,
        price: payPrice,
      );

      // 6. 로컬 상태 업데이트
      await ref.read(currentUserProvider.notifier).refreshUserData();

      // 로딩 닫기
      navigator.pop();

      // 7. 구매 완료 다이얼로그 표시
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });

        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: Color(0xFF2D2D2D),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(
              '구매 완료',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 64),
                SizedBox(height: 16),
                Text(
                  '기프티콘이 문자로 발송되었습니다!',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 8),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${phoneNo.substring(0, 3)}-${phoneNo.substring(3, 7)}-${phoneNo.substring(7)}',
                    style: TextStyle(
                      color: Colors.orangeAccent,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                SizedBox(height: 16),
                Text(
                  '위 번호로 기프티콘 MMS가 발송되었습니다.\n문자 수신까지 약간의 시간이 소요될 수 있습니다.',
                  style: TextStyle(color: Colors.grey[400], fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orangeAccent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  Navigator.of(context).pop(); // 상세화면 닫기
                },
                child: Text(
                  '확인',
                  style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      // 로딩 닫기
      if (navigator.canPop()) {
        navigator.pop();
      }

      // 처리 상태 해제
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }

      // 사용자 친화적인 에러 메시지 표시
      String errorMessage = '구매 중 오류가 발생했습니다';
      if (e is GiftishowException) {
        errorMessage = e.userFriendlyMessage;
      } else if (e is Exception) {
        errorMessage = e.toString().replaceFirst('Exception: ', '');
      }

      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 4),
        ),
      );
    }
  }
}
