import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pigmoney/presentation/offerwall/widgets/mychips_piggy_widget.dart';
import 'package:velocity_x/velocity_x.dart';

import '../../core/services/snapplay_service.dart';
import '../../core/utils/log/logger.dart';
import '../game/widget/animation_bouncing.dart';
import '../provider/settings_provider.dart';
import '../provider/user_provider.dart';
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

  // ✅ 홈에서 이동: 스냅플레이 룰렛/주사위
  final _snapPlayService = SnapPlayService.instance;
  bool _isClaimingRouletteMoney = false;
  bool _isClaimingDiceMoney = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // ✅ 룰렛/주사위용 스냅플레이 초기화
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeSnapPlay();
    });
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

                    // 2줄: 행운룰렛, 브론즈저금통(SnapPlay), 행운주사위
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _buildRouletteButton(),
                        SnapPlayPiggyWidget(key: _snapPlayKey, soundPlayer: _soundPlayer),
                        _buildDiceButton(),
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

                    40.heightBox,

                    // ✅ 아랫줄: 행운룰렛, 행운주사위
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildRouletteButton(),
                        _buildDiceButton(),
                      ],
                    ).pSymmetric(h: 10),

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

  // 스냅플레이 초기화
  Future<void> _initializeSnapPlay() async {
    try {
      final user = ref.read(currentUserProvider);
      if (user != null) {
        await _snapPlayService.initialize(user.uid, user.nickname);
        logger.d('적립탭: 스냅플레이 초기화 완료');
      }
    } catch (e) {
      logger.e('적립탭: 스냅플레이 초기화 실패: $e');
    }
  }

  // 룰렛 버튼 위젯
  Widget _buildRouletteButton() {
    final user = ref.watch(currentUserProvider);
    final rouletteMoney = user?.snapPlayRouletteMoney ?? 0;

    // 기본 룰렛 위젯 (자동적립 돼지와 동일한 스타일)
    Widget rouletteWidget = Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none, // 잘림 방지
      children: [
        // 룰렛 이미지 (자동적립 돼지와 동일한 크기)
        Image.asset('assets/icons/ic_roulette.png', width: 80, height: 80).pOnly(bottom: 10),

        // 룰렛 위에 머니 표시
        if (rouletteMoney > 0) ...{
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.amber,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 3,
                  spreadRadius: 1,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: '${rouletteMoney}M'.text.size(14).black.bold.make(),
          ).positioned(top: -10),
        },
        // 하단 텍스트
        '행운룰렛'.text.size(13).white.semiBold.letterSpacing(-0.2).make().positioned(bottom: -12),
      ],
    );

    // 머니가 있을 때 바운스 애니메이션 추가 (자동적립 돼지와 동일)
    if (rouletteMoney > 0) {
      rouletteWidget = AnimatedBouncingWidget(
        child: rouletteWidget,
      );
    }

    return GestureDetector(
      onTap: _isClaimingRouletteMoney ? null : (rouletteMoney > 0 ? _claimRouletteMoney : _showSnapPlayRoulette),
      child: Stack(
        alignment: Alignment.center,
        children: [
          rouletteWidget,
          // 로딩 상태일 때 로딩 인디케이터 표시
          if (_isClaimingRouletteMoney)
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(color: Colors.amber, strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // 주사위 버튼 위젯
  Widget _buildDiceButton() {
    final user = ref.watch(currentUserProvider);
    final diceMoney = user?.snapPlayDiceMoney ?? 0;

    // 기본 룰렛 위젯 (자동적립 돼지와 동일한 스타일)
    Widget diceWidget = Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none, // 잘림 방지
      children: [
        // 룰렛 이미지 (자동적립 돼지와 동일한 크기)
        Image.asset('assets/icons/ic_dice.png', width: 80, height: 80).pOnly(bottom: 10),

        // 룰렛 위에 머니 표시
        if (diceMoney > 0) ...{
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.amber,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 3,
                  spreadRadius: 1,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: '${diceMoney}M'.text.size(14).black.bold.make(),
          ).positioned(top: -10),
        },
        // 하단 텍스트
        '행운주사위'.text.size(13).white.semiBold.letterSpacing(-0.2).make().positioned(bottom: -12),
      ],
    );

    // 머니가 있을 때 바운스 애니메이션 추가 (자동적립 돼지와 동일)
    if (diceMoney > 0) {
      diceWidget = AnimatedBouncingWidget(
        child: diceWidget,
      );
    }

    return GestureDetector(
      onTap: _isClaimingDiceMoney ? null : (diceMoney > 0 ? _claimDiceMoney : _showSnapPlayDice),
      child: Stack(
        alignment: Alignment.center,
        children: [
          diceWidget,
          // 로딩 상태일 때 로딩 인디케이터 표시
          if (_isClaimingDiceMoney)
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(color: Colors.amber, strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // 룰렛 머니 적립
  Future<void> _claimRouletteMoney() async {
    // 이미 처리 중이면 중복 실행 방지
    if (_isClaimingRouletteMoney) return;

    setState(() => _isClaimingRouletteMoney = true);

    try {
      final user = ref.read(currentUserProvider);
      if (user == null || user.snapPlayRouletteMoney <= 0) return;

      final earnAmount = user.snapPlayRouletteMoney;
      logger.d('========== 룰렛 포인트 적립 시작 ==========');
      logger.d('적립할 포인트: $earnAmount');

      // 사운드 재생
      final settings = ref.read(settingsProvider);
      if (settings.isSfxEnabled) {
        await _soundPlayer.play(AssetSource('audio/pig_deposit_sound.mp3'));
      }

      // 1. 머니 증가
      final userRepo = ref.read(userRepositoryProvider);
      await userRepo.addEarning(amount: earnAmount);

      // 2. snapPlayRouletteMoney 차감
      final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
      await userRef.update({
        'snapPlayRouletteMoney': FieldValue.increment(-earnAmount),
      });

      // 3. 사용자 데이터 새로고침
      await ref.read(currentUserProvider.notifier).refreshUserData();

      logger.d('========== 룰렛 포인트 적립 완료 ==========');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${earnAmount}M이 적립되었습니다!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      logger.e('룰렛 포인트 적립 중 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('적립 중 오류가 발생했습니다 : ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isClaimingRouletteMoney = false);
      }
    }
  }

  // 주사위 머니 적립
  Future<void> _claimDiceMoney() async {
    // 이미 처리 중이면 중복 실행 방지
    if (_isClaimingDiceMoney) return;

    setState(() => _isClaimingDiceMoney = true);

    try {
      final user = ref.read(currentUserProvider);
      if (user == null || user.snapPlayDiceMoney <= 0) return;

      final earnAmount = user.snapPlayDiceMoney;
      logger.d('========== 주사위 포인트 적립 시작 ==========');
      logger.d('적립할 포인트: $earnAmount');

      // 사운드 재생
      final settings = ref.read(settingsProvider);
      if (settings.isSfxEnabled) {
        await _soundPlayer.play(AssetSource('audio/pig_deposit_sound.mp3'));
      }

      // 1. 머니 증가
      final userRepo = ref.read(userRepositoryProvider);
      await userRepo.addEarning(amount: earnAmount);

      // 2. snapPlayDiceMoney 차감
      final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
      await userRef.update({
        'snapPlayDiceMoney': FieldValue.increment(-earnAmount),
      });

      // 3. 사용자 데이터 새로고침
      await ref.read(currentUserProvider.notifier).refreshUserData();

      logger.d('========== 주사위 포인트 적립 완료 ==========');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${earnAmount}M이 적립되었습니다!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      logger.e('주사위 포인트 적립 중 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('적립 중 오류가 발생했습니다 : ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isClaimingDiceMoney = false);
      }
    }
  }

  // 스냅플레이 룰렛 오퍼월 표시
  Future<void> _showSnapPlayRoulette() async {
    try {
      final user = ref.read(currentUserProvider);
      if (user == null) {
        logger.e('사용자 정보 없음 - 룰렛 표시 불가');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('로그인이 필요합니다.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // 스냅플레이 초기화 확인
      if (!_snapPlayService.isInitialized || _snapPlayService.currentUserId != user.uid) {
        logger.d('스냅플레이 재초기화 필요');
        final success = await _snapPlayService.initialize(user.uid, user.nickname);
        if (!success) {
          throw Exception('스냅플레이 초기화 실패');
        }
      }

      logger.d('스냅플레이 룰렛 오퍼월 표시');
      await _snapPlayService.showRouletteOfferwall();
    } catch (e) {
      logger.e('스냅플레이 룰렛 표시 중 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('룰렛을 불러올 수 없습니다: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // 스냅플레이 주사위 오퍼월 표시
  Future<void> _showSnapPlayDice() async {
    try {
      final user = ref.read(currentUserProvider);
      if (user == null) {
        logger.e('사용자 정보 없음 - 주사위 표시 불가');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('로그인이 필요합니다.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // 스냅플레이 초기화 확인
      if (!_snapPlayService.isInitialized || _snapPlayService.currentUserId != user.uid) {
        logger.d('스냅플레이 재초기화 필요');
        final success = await _snapPlayService.initialize(user.uid, user.nickname);
        if (!success) {
          throw Exception('스냅플레이 초기화 실패');
        }
      }

      logger.d('스냅플레이 주사위 오퍼월 표시');
      await _snapPlayService.showDiceOfferwall();
    } catch (e) {
      logger.e('스냅플레이 주사위 표시 중 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('주사위를 불러올 수 없습니다: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
