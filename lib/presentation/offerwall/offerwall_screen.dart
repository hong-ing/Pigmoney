import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pigmoney/presentation/offerwall/widgets/mychips_piggy_widget.dart';
import 'package:velocity_x/velocity_x.dart';

import 'widgets/gmotech_piggy_widget.dart';
import 'widgets/pincrux_piggy_widget.dart';
import 'widgets/snapplay_piggy_widget.dart';
import 'widgets/tnk_piggy_widget.dart';

class OfferWallScreen extends ConsumerStatefulWidget {
  const OfferWallScreen({super.key});

  @override
  ConsumerState<OfferWallScreen> createState() => _OfferWallScreenState();
}

class _OfferWallScreenState extends ConsumerState<OfferWallScreen> with WidgetsBindingObserver {
  final _soundPlayer = AudioPlayer();
  final GlobalKey<TnkPiggyWidgetState> _tnkKey = GlobalKey();
  final GlobalKey<PincruxPiggyWidgetState> _pincruxKey = GlobalKey();
  final GlobalKey<MyChipsPiggyWidgetState> _mychipsKey = GlobalKey();
  final GlobalKey<SnapPlayPiggyWidgetState> _snapPlayKey = GlobalKey();
  final GlobalKey<GmotechPiggyWidgetState> _gmotechKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _soundPlayer.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed) {
      // 앱이 다시 활성화될 때 각 위젯의 포인트 체크
      _tnkKey.currentState?.checkPointsOnResume();
      _pincruxKey.currentState?.checkPointsOnResume();
      _mychipsKey.currentState?.checkPointsOnResume();
      _snapPlayKey.currentState?.checkPointsOnResume();
      _gmotechKey.currentState?.checkPointsOnResume();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Platform.isAndroid
              ? Column(
                  children: [
                    25.heightBox,

                    // 1줄: 핑크저금통(TNK), 민트저금통(Pincrux)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TnkPiggyWidget(key: _tnkKey, soundPlayer: _soundPlayer),
                        PincruxPiggyWidget(key: _pincruxKey, soundPlayer: _soundPlayer),
                      ],
                    ).pSymmetric(h: 35),

                    40.heightBox,

                    // 2줄: 브론즈저금통(SnapPlay) - 행운룰렛/행운주사위는 홈 화면으로 이동
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SnapPlayPiggyWidget(key: _snapPlayKey, soundPlayer: _soundPlayer),
                      ],
                    ).pSymmetric(h: 35),

                    40.heightBox,

                    // 3줄: 실버저금통(Gmotech), 골드저금통(MyChips)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        GmotechPiggyWidget(key: _gmotechKey, soundPlayer: _soundPlayer),
                        MyChipsPiggyWidget(key: _mychipsKey, soundPlayer: _soundPlayer),
                      ],
                    ).pSymmetric(h: 35),

                    60.heightBox,


                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        '• 오퍼(미션/게임/쇼핑 등) 수행 후 머니(M) 적립까지는'.text.letterSpacing(-0.2).white.make(),
                        Row(
                          children: [
                            ' 약간의 '.text.letterSpacing(-0.2).white.make(),
                            '딜레이'.text.letterSpacing(-0.2).amber400.make(),
                            '가 발생할 수 있어요.'.text.letterSpacing(-0.2).white.make(),
                          ],
                        ),
                      ],
                    ).pSymmetric(h: 35),
                    7.heightBox,
                    Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        '• 미적립 문의는 각 저금통 내의 '.text.letterSpacing(-0.2).white.make(),
                        '문의하기'.text.letterSpacing(-0.2).amber400.make(),
                        '를 이용해주세요.'.text.letterSpacing(-0.2).white.make(),
                      ],
                    ).pSymmetric(h: 35),
                  ],
                ).objectCenter().pSymmetric(v: 20)
              : Column(
                  children: [

                    60.heightBox,

                    // 핑크저금통(TNK), 브론즈저금통(SnapPlay)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TnkPiggyWidget(key: _tnkKey, soundPlayer: _soundPlayer),
                        SnapPlayPiggyWidget(key: _snapPlayKey, soundPlayer: _soundPlayer),
                      ],
                    ).pSymmetric(h: 35),

                    // ✅ 행운룰렛/행운주사위는 홈 화면으로 이동

                    60.heightBox,

                    // ✅ Apple 미관여 고지 (오퍼 수행 후 머니 안내 위)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        'Apple은 해당 경품 행사 또는 이벤트에 어떠한 방식으로도 관여하지 않습니다'
                            .text
                            .letterSpacing(-0.2)
                            .white
                            .make(),
                      ],
                    ).pSymmetric(h: 35),

                    7.heightBox,

                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        '• 오퍼(미션/게임/쇼핑 등) 수행 후 머니(M) 적립까지는'.text.letterSpacing(-0.2).white.make(),
                        Row(
                          children: [
                            ' 약간의 '.text.letterSpacing(-0.2).white.make(),
                            '딜레이'.text.letterSpacing(-0.2).amber400.make(),
                            '가 발생할 수 있어요.'.text.letterSpacing(-0.2).white.make(),
                          ],
                        ),
                      ],
                    ).pSymmetric(h: 35),
                    7.heightBox,
                    Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        '• 미적립 문의는 각 저금통 내의 '.text.letterSpacing(-0.2).white.make(),
                        '문의하기'.text.letterSpacing(-0.2).amber400.make(),
                        '를 이용해주세요.'.text.letterSpacing(-0.2).white.make(),
                      ],
                    ).pSymmetric(h: 35),
                  ],
                ),
        ),
      ),
    );
  }
}
