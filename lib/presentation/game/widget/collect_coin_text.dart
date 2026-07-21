import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:velocity_x/velocity_x.dart';

import '../../provider/game/game_provider.dart';

class CollectValueText extends ConsumerWidget {
  const CollectValueText({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = ref.watch(gameProvider.select((s) => s.collectValueText));
    if (text == null) return const SizedBox.shrink();
    return Text(
      text,
      style: const TextStyle(
        color: Colors.yellowAccent,
        fontSize: 24,
        fontWeight: FontWeight.bold,
        shadows: [Shadow(blurRadius: 3.0, color: Colors.black54, offset: Offset(2.0, 2.0))],
      ),
    ).pOnly(bottom: 10);
  }
}


