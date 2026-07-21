import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 구글 로그인 정보를 임시 저장하는 Provider
class GoogleSignupData {
  final String googleId;
  final String idToken;
  final String accountEmail;

  GoogleSignupData({
    required this.googleId,
    required this.idToken,
    required this.accountEmail,
  });
}

/// 구글 회원가입 정보 Provider
final googleSignupDataProvider = StateProvider<GoogleSignupData?>((ref) => null);
