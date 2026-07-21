import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 카카오 로그인 정보를 임시 저장하는 Provider
class KakaoSignupData {
  final String kakaoId;
  final String accessToken;
  final String accountEmail;

  KakaoSignupData({
    required this.kakaoId,
    required this.accessToken,
    required this.accountEmail,
  });
}

/// 카카오 회원가입 정보 Provider
final kakaoSignupDataProvider = StateProvider<KakaoSignupData?>((ref) => null);
