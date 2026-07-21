import 'dart:collection';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tnk_flutter_rwd/tnk_flutter_rwd.dart';
import 'package:velocity_x/velocity_x.dart';

import '../../../core/utils/log/logger.dart';
import '../../game/widget/animation_bouncing.dart';
import '../../provider/settings_provider.dart';
import '../../provider/user_provider.dart';

class TnkPiggyWidget extends ConsumerStatefulWidget {
  final AudioPlayer soundPlayer;

  const TnkPiggyWidget({
    super.key,
    required this.soundPlayer,
  });

  @override
  ConsumerState<TnkPiggyWidget> createState() => TnkPiggyWidgetState();
}

class TnkPiggyWidgetState extends ConsumerState<TnkPiggyWidget> {
  final _tnkFlutterRwdPlugin = TnkFlutterRwd();
  int? _queryPoint = 0;
  bool _isClaimingPoints = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _initTnkChannel();
    _setUserData();
    _checkPoints();
  }

  // TNK MethodChannel 초기화
  void _initTnkChannel() {
    MethodChannel channel = const MethodChannel('tnk_flutter_rwd');
    channel.setMethodCallHandler(_handleTnkEvent);
    setCustomUnitIcon();
  }

  Future<void> setCustomUnitIcon() async {
    try {
      HashMap<String, String> paramMap = HashMap();
      paramMap.addAll({
        "option": "3", // 재화 단위만 표시
      });
      await _tnkFlutterRwdPlugin.setCustomUnitIcon(paramMap);
    } on Exception {
      return;
    }
  }

  // TNK 이벤트 핸들러
  Future<void> _handleTnkEvent(MethodCall methodCall) async {
    if (methodCall.method == 'didOfferwallRemoved') {
      logger.d('TNK 오퍼월이 닫혔습니다');
      await _checkPoints();
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // TNK에 사용자 정보 설정
  Future<void> _setUserData() async {
    try {
      final user = ref.read(currentUserProvider);
      if (user != null) {
        await _tnkFlutterRwdPlugin.setUserName(user.uid);
        await _tnkFlutterRwdPlugin.setCOPPA(false);
        _tnkFlutterRwdPlugin.setUseTermsPopup(false);
        logger.d('TNK 사용자 ID 설정 완료: ${user.uid}');
      }
    } catch (e) {
      logger.e('TNK 사용자 설정 중 오류: $e');
    }
  }

  // 포인트 확인
  Future<void> _checkPoints() async {
    try {
      final newQueryPoint = await _tnkFlutterRwdPlugin.getQueryPoint();
      logger.d('TNK queryPoint $newQueryPoint');

      if (mounted) {
        setState(() {
          _queryPoint = newQueryPoint;
        });
      }
    } catch (e) {
      logger.e('TNK 포인트 확인 중 오류: $e');
      if (mounted) {
        setState(() {
          _queryPoint = 0;
        });
      }
    }
  }

  // 포인트 적립
  Future<void> _pointsUpdate() async {
    if (_isClaimingPoints) return;

    if (_queryPoint != null && _queryPoint! > 0) {
      if (_isClaimingPoints) return;

      setState(() => _isClaimingPoints = true);

      try {
        final earnAmount = _queryPoint!;
        logger.d('TNK 적립 포인트: $earnAmount');

        // 사운드 재생
        final settings = ref.read(settingsProvider);
        if (settings.isSfxEnabled) {
          await widget.soundPlayer.play(AssetSource('audio/pig_deposit_sound.mp3'));
        }

        final userRepo = ref.read(userRepositoryProvider);
        await userRepo.addEarning(amount: earnAmount);
        await ref.read(currentUserProvider.notifier).refreshUserData();

        // TNK 포인트 인출
        await _tnkFlutterRwdPlugin.withdrawPoints(earnAmount.toString());

        if (mounted) {
          setState(() => _queryPoint = 0);
        }
      } catch (e) {
        logger.e('TNK 포인트 업데이트 중 오류: $e');
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
          setState(() => _isClaimingPoints = false);
        }
      }
    }
  }

  // 오퍼월 표시
  Future<void> _showOfferwall() async {
    // 사운드 재생
    final settings = ref.read(settingsProvider);
    if (settings.isSfxEnabled) {
      await widget.soundPlayer.play(AssetSource('audio/pig_touch.mp3'));
    }

    setState(() => _isLoading = true);

    try {
      final user = ref.read(currentUserProvider);
      if (user == null) {
        throw Exception('사용자 정보가 없습니다. 다시 로그인해주세요.');
      }

      // TNK 설정 재확인
      await _tnkFlutterRwdPlugin.setUserName(user.uid);
      await _tnkFlutterRwdPlugin.setCOPPA(false);
      _tnkFlutterRwdPlugin.setUseTermsPopup(false);

      // iOS ATT 권한 요청
      try {
        await _tnkFlutterRwdPlugin.showATTPopup();
      } catch (e) {
        logger.d('ATT 팝업 표시 중 오류 (Android에서는 정상): $e');
      }

      // 오퍼월 표시
      final result = await _tnkFlutterRwdPlugin.showAdList('피그머니 적립');
      logger.d('TNK 오퍼월 표시 결과: $result');

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      logger.e('TNK 오퍼월 표시 중 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('오퍼월을 불러올 수 없습니다: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  // 앱 재개 시 포인트 체크
  void checkPointsOnResume() {
    _tnkFlutterRwdPlugin.closeAdDetail();
    _tnkFlutterRwdPlugin.closeOfferwall();
    _checkPoints();
  }

  @override
  Widget build(BuildContext context) {
    Widget tnkWidget = Image.asset('assets/icons/ic_tnk.png', width: 150);

    if (_queryPoint != 0) {
      tnkWidget = AnimatedBouncingWidget(
        child: tnkWidget,
      );
    }

    return Column(
      children: [
        if (_queryPoint != 0)
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
            child: '${NumberFormat('#,###').format(_queryPoint)}M'.text.size(20).black.bold.make(),
          ),
        5.heightBox,
        GestureDetector(
          onTap: _isClaimingPoints ? null : (_queryPoint != 0 ? _pointsUpdate : _showOfferwall),
          child: Stack(
            alignment: Alignment.center,
            children: [
              tnkWidget,
              if (_isClaimingPoints)
                const Center(
                  child: CircularProgressIndicator(
                    color: Colors.amber,
                    strokeWidth: 3,
                  ),
                ),
            ],
          ),
        ),
        5.heightBox,
        Column(
          children: [
            '핑크저금통'.text.white.center.size(18).semiBold.make(),
            '(간단한 종합미션)'.text.white.center.size(15).medium.make(),
          ],
        ),
      ],
    );
  }
}
