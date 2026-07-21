import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:velocity_x/velocity_x.dart';

import '../../presentation/provider/settings_provider.dart';
import '../../presentation/provider/user_provider.dart';
import '../utils/log/logger.dart';

class BonusMoneyPopupDialog extends ConsumerStatefulWidget {
  final int bonusMoney;

  const BonusMoneyPopupDialog({
    super.key,
    required this.bonusMoney,
  });

  @override
  ConsumerState<BonusMoneyPopupDialog> createState() => _BonusMoneyPopupDialogState();
}

class _BonusMoneyPopupDialogState extends ConsumerState<BonusMoneyPopupDialog> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isProcessing = false;

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _claimBonusMoney() async {
    if (_isProcessing) return;

    setState(() => _isProcessing = true);

    try {
      logger.d('보너스머니 적립 시작: ${widget.bonusMoney}M');

      // 사운드 재생 및 완료 대기
      final settings = ref.read(settingsProvider);
      if (settings.isSfxEnabled) {
        await _audioPlayer.play(AssetSource('audio/pig_deposit_sound.mp3'));

        // 사운드 재생 완료 대기
        await _audioPlayer.onPlayerComplete.first;
      }

      // bonusMoney를 일반 money로 전환
      final userRepo = ref.read(userRepositoryProvider);

      // 1. addEarning으로 보너스머니만큼 일반머니 추가
      await userRepo.addEarning(amount: widget.bonusMoney);

      // 2. Firestore에서 bonusMoney를 0으로 업데이트
      await userRepo.clearBonusMoney();

      // 3. 유저 데이터 새로고침
      await ref.read(currentUserProvider.notifier).refreshUserData();

      logger.d('보너스머니 적립 완료: ${widget.bonusMoney}M');

      if (mounted) {
        Navigator.of(context).pop();

        // 성공 메시지 표시
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${NumberFormat('#,###').format(widget.bonusMoney)}M이 적립되었어요!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      logger.e('보너스머니 적립 중 오류: $e');

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
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final formattedMoney = NumberFormat('#,###').format(widget.bonusMoney);

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      elevation: 0,
      backgroundColor: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 타이틀
            '머니가 도착했어요!'.text.size(20).bold.color(const Color(0xFFBD15D6)).make().pOnly(bottom: 10),

            // 머니 금액 표시
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFFC107),
                borderRadius: BorderRadius.circular(12),
              ),
              child: '${formattedMoney}M'.text.size(18).bold.make(),
            ).pOnly(bottom: 10),
            InkWell(
              onTap: _isProcessing ? null : _claimBonusMoney,
              child: _isProcessing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.amber),
                      ),
                    )
                  : Image.asset('assets/icons/ic_game2_coins.png', width: 120),
            ),
          ],
        ),
      ),
    );
  }
}
