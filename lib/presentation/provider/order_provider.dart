import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/order/order_repository.dart';
import 'user_provider.dart';

// Order 저장소 프로바이더
final orderRepositoryProvider = Provider<OrderRepository>((ref) {
  // UserRepository를 주입받아서 사용
  final userRepository = ref.watch(userRepositoryProvider);
  return OrderRepository(userRepository: userRepository);
});
