import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:velocity_x/velocity_x.dart';

import 'gift/gift_screen.dart';
import 'shop/shop_screen.dart';

class OrderMainScreen extends ConsumerWidget {
  const OrderMainScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              30.heightBox,

              // 기프티콘 주문하기 버튼
              _buildOrderButton(
                context: context,
                isGift: true,
                icon: Icons.card_giftcard_outlined,
                title: '기프티콘 구매하기',
                color: Color(0xFFC0C0C0),
                gradientColors: [Color(0xFFB5B5B5), Color(0xFFD1D1D1), Color(0xFFB5B5B5)],
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (context) => const GiftScreen()));
                },
              ),

              50.heightBox,

              // 금,은 주문하기 버튼
              if (Platform.isAndroid) ...{
                _buildOrderButton(
                  isGift: false,
                  context: context,
                  icon: Icons.diamond_outlined,
                  title: '금,은 주문하기',
                  color: Color(0xFFFFD700),
                  gradientColors: [Color(0xFFD4A52A), Color(0xFFEDDD72), Color(0xFFD4A52A)],
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const ShopScreen()));
                  },
                ),
                5.heightBox,
                '• 금,은 시세에 따라 주문에 필요한 머니는 변동될 수 있습니다.'.text.medium.letterSpacing(-0.2).center.scale(0.95).white.make(),
              },

              100.heightBox,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOrderButton({
    required BuildContext context,
    required bool isGift,
    required IconData icon,
    required String title,
    required Color color,
    required List<Color> gradientColors,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          height: isGift ? 230 : 120,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: gradientColors,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.3),
                blurRadius: 15,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 35, color: Colors.black),
              8.widthBox,
              title.text.size(26).bold.black.make(),
            ],
          ),
        ),
      ),
    );
  }
}
