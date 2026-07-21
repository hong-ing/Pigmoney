import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:velocity_x/velocity_x.dart';

import '../../provider/game/game_provider.dart';
import 'animation_bouncing.dart';

/// 🧲 자석 버프 버튼 위젯 (항상 표시)
/// 상태별 동작:
/// ① 발동 중: 컬러 / 남은 초 표시
/// ② 쿨타임 중 & 자석 없음: 무채색 / 분:초 카운트다운 / 탭 → "지금은 사용할 수 없어요"
/// ③ 쿨타임 중 & 자석 보유: 컬러 / 분:초 카운트다운 / 탭 → "지금은 사용할 수 없어요"
/// ④ 쿨타임 끝 & 자석 보유: 컬러 / 탭 → 30초 자석 발동
/// ⑤ 쿨타임 끝 & 자석 없음: 무채색 / 탭 → "저금통 2배 수집 후에 활성화됩니다"
class MagnetBuffButton extends ConsumerWidget {
  const MagnetBuffButton({super.key});

  // 무채색(회색) 변환용 컬러 매트릭스
  static const ColorFilter _greyscaleFilter = ColorFilter.matrix(<double>[
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0, 0, 0, 1, 0,
  ]);

  String _formatCooldown(int seconds) {
    final min = seconds ~/ 60;
    final sec = seconds % 60;
    return '$min:${sec.toString().padLeft(2, '0')}';
  }

  void _showToast(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 기능 스위치가 꺼져있으면 버튼 자체를 표시하지 않음
    if (!GameNotifier.magnetBuffEnabled) {
      return const SizedBox.shrink();
    }

    final hasBuff = ref.watch(gameProvider.select((s) => s.magnetBuffCount > 0));
    final isMagnetModeActive = ref.watch(gameProvider.select((s) => s.isMagnetModeActive));
    final remainingSeconds = ref.watch(gameProvider.select((s) => s.magnetRemainingSeconds));
    final cooldownSeconds = ref.watch(gameProvider.select((s) => s.magnetCooldownRemainingSeconds));

    final inCooldown = cooldownSeconds > 0;
    // 컬러 조건: 발동 중이거나 자석을 확보한 상태
    final isColored = isMagnetModeActive || hasBuff;
    // 발동 가능 조건: 쿨타임 끝 & 자석 보유 (상태 ④)
    final canActivate = hasBuff && !inCooldown && !isMagnetModeActive;

    Widget magnetIcon = const Text('🧲', style: TextStyle(fontSize: 44));
    if (!isColored) {
      magnetIcon = ColorFiltered(colorFilter: _greyscaleFilter, child: magnetIcon);
    }
    if (canActivate) {
      magnetIcon = AnimatedBouncingWidget(child: magnetIcon);
    }

    return GestureDetector(
      onTap: () {
        if (isMagnetModeActive) return; // ① 이미 발동 중
        if (inCooldown) {
          _showToast(context, '지금은 사용할 수 없어요'); // ②③ 쿨타임 중
          return;
        }
        if (canActivate) {
          ref.read(gameProvider.notifier).activateMagnetBuff(); // ④ 발동
          return;
        }
        _showToast(context, '저금통 2배 수집 후에 활성화됩니다'); // ⑤ 자석 없음
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ① 발동 중: 남은 초 표시 (기존 방식 유지)
          if (isMagnetModeActive)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.redAccent,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 3,
                    spreadRadius: 1,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: '$remainingSeconds초'.text.size(14).letterSpacing(-0.2).heightRelaxed.white.bold.make(),
            ),
          const SizedBox(height: 2),
          magnetIcon,
          // ②③ 쿨타임 중: 남은 시간(분:초) 카운트다운 표시
          if (inCooldown && !isMagnetModeActive)
            _formatCooldown(cooldownSeconds).text.white.size(12).heightTight.semiBold.make(),
          // ④ 발동 가능: 안내 텍스트
          if (canActivate) '탭하여 발동'.text.white.size(11).heightTight.semiBold.make(),
        ],
      ),
    );
  }
}
