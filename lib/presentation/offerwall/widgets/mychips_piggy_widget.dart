import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:my_chips_flutter_sdk/my_chips_flutter_sdk.dart';
import 'package:velocity_x/velocity_x.dart';

import '../../../core/utils/log/logger.dart';
import '../../game/widget/animation_bouncing.dart';
import '../../provider/settings_provider.dart';
import '../../provider/user_provider.dart';

class MyChipsPiggyWidget extends ConsumerStatefulWidget {
  final AudioPlayer soundPlayer;

  const MyChipsPiggyWidget({
    super.key,
    required this.soundPlayer,
  });

  @override
  ConsumerState<MyChipsPiggyWidget> createState() => MyChipsPiggyWidgetState();
}

class MyChipsPiggyWidgetState extends ConsumerState<MyChipsPiggyWidget> {
  int? _myChipsPoint = 0;
  bool _isClaimingMyChipsPoints = false;
  bool _isCheckingPoints = false;

  @override
  void initState() {
    super.initState();
    _initMyChips();
    _checkMyChipsPoints();
  }

  // 마이칩스 초기화
  Future<void> _initMyChips() async {
    try {
      final user = ref.read(currentUserProvider);
      if (user != null) {
        // 마이칩스 초기화 (PUBKEY: 912065, USERKEY: Firebase UID)
        await MCOfferwallSdk.instance.init("166c1e81d8b44a6c952b073cd917d5a4");
        await MCOfferwallSdk.instance.setUserId(user.uid);
      } else {
        logger.w('마이칩스 초기화 실패: 사용자 정보 없음');
      }
    } catch (e, stackTrace) {
      logger.e('마이칩스 초기화 중 오류: $e');
      logger.e('Stack trace: $stackTrace');
    }
  }

  // 마이칩스 포인트 확인
  Future<void> _checkMyChipsPoints() async {
    try {
      logger.d('========== 마이칩스 포인트 확인 시작 ==========');
      final user = ref.read(currentUserProvider);
      if (user != null) {
        final newPoints = user.myChipsMoney;
        if (mounted) {
          setState(() {
            _myChipsPoint = newPoints;
          });
          if (newPoints > 0) {
            logger.d('✅ 마이칩스 포인트 발견: $newPoints');
            logger.d('포인트 차이: ${newPoints - (_myChipsPoint ?? 0)}');
          } else {
            logger.d('포인트 없음 (0)');
          }
        }
      } else {
        logger.w('사용자 정보 없음');
      }
      logger.d('========== 마이칩스 포인트 확인 완료 ==========');
    } catch (e, stackTrace) {
      logger.e('마이칩스 포인트 확인 중 오류: $e');
      logger.e('Stack trace: $stackTrace');
      if (mounted) {
        setState(() {
          _myChipsPoint = 0;
        });
      }
    }
  }

  // 마이칩스 포인트 적립
  Future<void> _myChipsPointsUpdate() async {
    if (_isClaimingMyChipsPoints) {
      logger.w('이미 적립 진행 중...');
      return;
    }

    if (_myChipsPoint != null && _myChipsPoint! > 0) {
      setState(() => _isClaimingMyChipsPoints = true);

      try {
        final earnAmount = _myChipsPoint!;
        logger.d('========== 마이칩스 포인트 적립 시작 ==========');
        logger.d('적립할 포인트: $earnAmount');

        // 사운드 재생
        final settings = ref.read(settingsProvider);
        if (settings.isSfxEnabled) {
          logger.d('사운드 재생 중...');
          await widget.soundPlayer.play(AssetSource('audio/pig_deposit_sound.mp3'));
        }

        final userRepo = ref.read(userRepositoryProvider);
        await userRepo.addEarning(amount: earnAmount, source: 'offerwall_mychips');

        // 2. myChipsMoney 차감
        final user = ref.read(currentUserProvider);
        if (user != null) {
          final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
          await userRef.update({
            'myChipsMoney': FieldValue.increment(-earnAmount),
          });
        }

        await ref.read(currentUserProvider.notifier).refreshUserData();

        // UI 업데이트
        if (mounted) {
          setState(() => _myChipsPoint = 0);
          logger.d('UI 업데이트 완료 - _myChipsPoint를 0으로 설정');
        }
      } catch (e, stackTrace) {
        logger.e('마이칩스 포인트 적립 중 오류: $e');
        logger.e('Stack trace: $stackTrace');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('적립 중 오류가 발생했습니다: ${e.toString()}'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isClaimingMyChipsPoints = false);
          logger.d('_isClaimingMyChipsPoints = false로 설정');
        }
      }
    } else {
      logger.w('적립할 포인트가 없음: $_myChipsPoint');
    }
  }

  // 마이칩스 오퍼월 표시
  Future<void> _showPincruxOfferwall() async {
    // 사운드 재생
    final settings = ref.read(settingsProvider);
    if (settings.isSfxEnabled) {
      await widget.soundPlayer.play(AssetSource('audio/pig_touch.mp3'));
    }

    try {
      final user = ref.read(currentUserProvider);
      if (user == null) {
        logger.e('사용자 정보 없음 - 오퍼월 표시 불가');
        throw Exception('사용자 정보가 없습니다. 다시 로그인해주세요.');
      }

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(
              backgroundColor: Colors.black,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () {
                  logger.d('오퍼월 페이지 닫기');
                  Navigator.of(context).pop();
                },
              ),
              title: const Text(
                '골드저금통',
                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
              ),
              centerTitle: true,
              elevation: 0,
            ),
            body: OfferwallPage(adunitId: "5c61352e-dac8-4c75-8466-cbc2ac6a9822"),
          ),
        ),
      );

      Future.delayed(const Duration(seconds: 1), () {
        logger.d('포인트 재확인 실행');
        _checkMyChipsPoints();
      });
    } catch (e, stackTrace) {
      logger.e('마이칩스 오퍼월 표시 중 오류: $e');
      logger.e('Stack trace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('오퍼월을 불러올 수 없습니다: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  // 앱 재개 시 포인트 체크 (사용자 데이터 새로고침 포함)
  void checkPointsOnResume() async {
    // 로딩 시작
    if (mounted) {
      setState(() => _isCheckingPoints = true);
    }

    try {
      await Future.delayed(const Duration(milliseconds: 100));

      await ref.read(currentUserProvider.notifier).refreshUserData();
      await _checkMyChipsPoints();
    } catch (e, stackTrace) {
      logger.e('앱 재개 시 포인트 체크 오류: $e');
      logger.e('Stack trace: $stackTrace');
    } finally {
      // 로딩 종료
      if (mounted) {
        setState(() => _isCheckingPoints = false);
        logger.d('로딩 상태 종료: _isCheckingPoints = false');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget pincruxWidget = Image.asset('assets/icons/ic_mychips.png', width: 150);

    if (_myChipsPoint != 0) {
      pincruxWidget = AnimatedBouncingWidget(
        child: pincruxWidget,
      );
    }

    return Column(
      children: [
        if (_myChipsPoint != 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.amber,
              borderRadius: BorderRadius.circular(13),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 3,
                  spreadRadius: 1,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: '${NumberFormat('#,###').format(_myChipsPoint)}M'.text.size(20).black.bold.make(),
          ),
        5.heightBox,
        GestureDetector(
          onTap: (_isClaimingMyChipsPoints || _isCheckingPoints)
              ? null
              : (_myChipsPoint != 0 ? _myChipsPointsUpdate : _showPincruxOfferwall),
          child: Stack(
            alignment: Alignment.center,
            children: [
              pincruxWidget,
              if (_isClaimingMyChipsPoints || _isCheckingPoints)
                const Center(
                  child: CircularProgressIndicator(
                    color: Colors.teal,
                    strokeWidth: 3,
                  ),
                ),
            ],
          ),
        ),
        10.heightBox,
        Column(
          children: [
            '골드저금통'.text.white.center.size(18).semiBold.make(),
            '(추천 게임미션)'.text.white.center.size(15).medium.make(),
          ],
        ),
      ],
    );
  }
}
