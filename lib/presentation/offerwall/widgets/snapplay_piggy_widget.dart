import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:velocity_x/velocity_x.dart';

import '../../../core/services/snapplay_service.dart';
import '../../../core/utils/log/logger.dart';
import '../../game/widget/animation_bouncing.dart';
import '../../provider/settings_provider.dart';
import '../../provider/user_provider.dart';

class SnapPlayPiggyWidget extends ConsumerStatefulWidget {
  final AudioPlayer soundPlayer;

  const SnapPlayPiggyWidget({
    super.key,
    required this.soundPlayer,
  });

  @override
  ConsumerState<SnapPlayPiggyWidget> createState() => SnapPlayPiggyWidgetState();
}

class SnapPlayPiggyWidgetState extends ConsumerState<SnapPlayPiggyWidget> {
  int? _snapPlayPoint = 0;
  bool _isClaimingSnapPlayPoints = false;
  bool _isCheckingPoints = false;
  final _snapPlayService = SnapPlayService.instance;

  @override
  void initState() {
    super.initState();
    _initSnapPlay();
    _checkSnapPlayPoints();
  }

  // 스냅플레이 초기화
  Future<void> _initSnapPlay() async {
    final user = ref.read(currentUserProvider);
    if (user != null) {
      await _snapPlayService.initialize(user.uid, user.nickname);
    } else {
      logger.w('스냅플레이 초기화 실패: 사용자 정보 없음');
    }
  }

  // 스냅플레이 포인트 확인
  Future<void> _checkSnapPlayPoints() async {
    try {
      logger.d('========== 스냅플레이 포인트 확인 시작 ==========');
      final user = ref.read(currentUserProvider);
      if (user != null) {
        final newPoints = user.snapPlayMoney;
        if (mounted) {
          setState(() {
            _snapPlayPoint = newPoints;
          });
          if (newPoints > 0) {
            logger.d('✅ 스냅플레이 포인트 발견: $newPoints');
            logger.d('포인트 차이: ${newPoints - (_snapPlayPoint ?? 0)}');
          } else {
            logger.d('포인트 없음 (0)');
          }
        }
      } else {
        logger.w('사용자 정보 없음');
      }
      logger.d('========== 스냅플레이 포인트 확인 완료 ==========');
    } catch (e, stackTrace) {
      logger.e('스냅플레이 포인트 확인 중 오류: $e');
      logger.e('Stack trace: $stackTrace');
      if (mounted) {
        setState(() {
          _snapPlayPoint = 0;
        });
      }
    }
  }

  // 스냅플레이 포인트 적립
  Future<void> _snapPlayPointsUpdate() async {
    if (_isClaimingSnapPlayPoints) {
      logger.w('이미 적립 진행 중...');
      return;
    }

    if (_snapPlayPoint != null && _snapPlayPoint! > 0) {
      setState(() => _isClaimingSnapPlayPoints = true);

      try {
        final earnAmount = _snapPlayPoint!;
        logger.d('========== 스냅플레이 포인트 적립 시작 ==========');
        logger.d('적립할 포인트: $earnAmount');

        // 사운드 재생
        final settings = ref.read(settingsProvider);
        if (settings.isSfxEnabled) {
          logger.d('사운드 재생 중...');
          await widget.soundPlayer.play(AssetSource('audio/pig_deposit_sound.mp3'));
        }

        final userRepo = ref.read(userRepositoryProvider);
        await userRepo.addEarning(amount: earnAmount);

        // 2. snapPlayMoney 차감
        final user = ref.read(currentUserProvider);
        if (user != null) {
          final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
          await userRef.update({
            'snapPlayMoney': FieldValue.increment(-earnAmount),
          });
        }

        await ref.read(currentUserProvider.notifier).refreshUserData();

        // UI 업데이트
        if (mounted) {
          setState(() => _snapPlayPoint = 0);
          logger.d('UI 업데이트 완료 - _snapPlayPoint를 0으로 설정');
        }
      } catch (e, stackTrace) {
        logger.e('스냅플레이 포인트 적립 중 오류: $e');
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
          setState(() => _isClaimingSnapPlayPoints = false);
          logger.d('_isClaimingSnapPlayPoints = false로 설정');
        }
      }
    } else {
      logger.w('적립할 포인트가 없음: $_snapPlayPoint');
    }
  }

  // 스냅플레이 오퍼월 표시
  Future<void> _showSnapPlayOfferwall() async {
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

      // 초기화 확인
      if (!_snapPlayService.isInitialized) {
        logger.d('스냅플레이 재초기화 시도...');
        await _initSnapPlay();
        if (!_snapPlayService.isInitialized) {
          throw Exception('스냅플레이 초기화에 실패했습니다.');
        }
      }

      logger.d('스냅플레이 오퍼월 표시 시작');

      // 스냅플레이 메인 오퍼월 표시
      await _snapPlayService.showMainOfferwall();

      logger.d('스냅플레이 오퍼월 표시 완료');

      // 오퍼월 닫힌 후 포인트 재확인
      Future.delayed(const Duration(seconds: 1), () {
        logger.d('포인트 재확인 실행');
        _checkSnapPlayPoints();
      });
    } catch (e, stackTrace) {
      logger.e('스냅플레이 오퍼월 표시 중 오류: $e');
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
      await _checkSnapPlayPoints();
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
    Widget snapPlayWidget = Image.asset(
      'assets/icons/ic_snapplay.png',
      width: 150,
      errorBuilder: (context, error, stackTrace) {
        // 아이콘이 없을 경우 대체 아이콘 표시
        return Container(
          width: 150,
          height: 150,
          decoration: BoxDecoration(
            color: Colors.amber.shade100,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Center(
            child: Text(
              '스냅플레이',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ),
        );
      },
    );

    if (_snapPlayPoint != 0) {
      snapPlayWidget = AnimatedBouncingWidget(
        child: snapPlayWidget,
      );
    }

    return Column(
      children: [
        if (_snapPlayPoint != 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.amber,
              borderRadius: BorderRadius.circular(13),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 3,
                  spreadRadius: 1,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: '${NumberFormat('#,###').format(_snapPlayPoint)}M'.text.size(20).black.bold.make(),
          ),
        5.heightBox,
        GestureDetector(
          onTap: (_isClaimingSnapPlayPoints || _isCheckingPoints)
              ? null
              : (_snapPlayPoint != 0 ? _snapPlayPointsUpdate : _showSnapPlayOfferwall),
          child: Stack(
            alignment: Alignment.center,
            children: [
              snapPlayWidget,
              if (_isClaimingSnapPlayPoints || _isCheckingPoints)
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
            '브론즈저금통'.text.white.center.size(18).semiBold.make(),
            '(맞춤형 추천미션)'.text.white.center.size(15).medium.make(),
          ],
        ),
      ],
    );
  }
}
