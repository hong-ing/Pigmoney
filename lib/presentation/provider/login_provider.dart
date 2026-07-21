import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/login/login_repository.dart';

final loginRepositoryProvider = Provider<LoginRepository>((ref) {
  return LoginRepository();
});
