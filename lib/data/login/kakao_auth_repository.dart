import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/services.dart';
import 'package:kakao_flutter_sdk/kakao_flutter_sdk.dart';
import 'package:http/http.dart' as http;
import '../user/model/user.dart' as app_user;

/// 카카오 로그인 결과
class KakaoSignInResult {
  final app_user.User? user; // 기존 사용자인 경우
  final KakaoSignupData? signupData; // 신규 사용자인 경우
  final bool isNewUser;

  KakaoSignInResult({
    this.user,
    this.signupData,
    required this.isNewUser,
  });
}

/// 카카오 회원가입 데이터
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

class KakaoAuthRepository {
  final _fs = FirebaseFirestore.instance;
  final _auth = fb.FirebaseAuth.instance;

  Future<KakaoSignInResult?> signInWithKakao() async {
    try {
      // 카카오 로그인 시도
      OAuthToken? token;

      // 카카오톡 설치 여부 확인
      if (await isKakaoTalkInstalled()) {
        try {
          // 카카오톡으로 로그인
          token = await UserApi.instance.loginWithKakaoTalk();
        } catch (error) {
          print('카카오톡 로그인 실패: $error');

          // 사용자가 카카오톡 설치 후 디바이스 권한 요청 화면에서 로그인을 취소한 경우,
          // 의도적인 로그인 취소로 보고 카카오계정으로 로그인 시도 없이 로그인 취소로 처리 (예: 뒤로 가기)
          if (error is PlatformException && error.code == 'CANCELED') {
            return null;
          }

          // 카카오톡에 연결된 카카오계정이 없는 경우, 카카오계정으로 로그인
          try {
            token = await UserApi.instance.loginWithKakaoAccount();
          } catch (error) {
            print('카카오계정 로그인 실패: $error');
            return null;
          }
        }
      } else {
        // 카카오톡이 설치되어 있지 않으면 카카오계정으로 로그인
        try {
          token = await UserApi.instance.loginWithKakaoAccount();
        } catch (error) {
          print('카카오계정 로그인 실패: $error');
          return null;
        }
      }

      // 로그인 성공 후 사용자 정보 가져오기
      try {
        User kakaoUser = await UserApi.instance.me();

        // Firebase에 카카오 로그인 정보로 사용자 생성/로그인
        final user = await _createOrUpdateFirebaseUser(kakaoUser, token.accessToken);

        if (user != null) {
          // 기존 사용자
          return KakaoSignInResult(
            user: user,
            isNewUser: false,
          );
        } else {
          // 신규 사용자 - 회원가입 필요
          return KakaoSignInResult(
            signupData: KakaoSignupData(
              kakaoId: kakaoUser.id.toString(),
              accessToken: token.accessToken,
              accountEmail: kakaoUser.kakaoAccount?.email ?? '',
            ),
            isNewUser: true,
          );
        }
      } catch (error) {
        print('사용자 정보 가져오기 실패: $error');
        return null;
      }
    } catch (error) {
      print('카카오 로그인 중 오류 발생: $error');
      return null;
    }
  }

  Future<app_user.User?> _createOrUpdateFirebaseUser(User kakaoUser, String accessToken) async {
    try {
      // Cloud Function 호출하여 로그인 시도
      final url = 'https://asia-northeast3-cashbank-a1c93.cloudfunctions.net/signInKakao';
      final res = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'kakaoId': kakaoUser.id.toString(),
          'accessToken': accessToken,
          'accountEmail': kakaoUser.kakaoAccount?.email ?? '',
        }),
      );

      final responseData = jsonDecode(res.body);

      // 신규 사용자인 경우 (회원가입 필요)
      if (res.statusCode == 404 && responseData['isNewUser'] == true) {
        print('신규 사용자 - 회원가입 필요');
        // null을 반환하여 회원가입 화면으로 이동하도록 함
        // kakaoId와 accessToken은 별도로 저장해야 함
        return null;
      }

      if (res.statusCode != 200) {
        print('Firebase 사용자 로그인 실패: ${res.statusCode} - ${res.body}');
        return null;
      }

      // Firebase Auth 커스텀 토큰으로 로그인
      if (responseData['token'] != null) {
        final token = responseData['token'];
        final cred = await _auth.signInWithCustomToken(token);

        if (cred.user != null) {
          // Firestore에서 사용자 정보 가져오기
          final userDoc = await _fs.doc('users/${cred.user!.uid}').get();
          if (userDoc.exists) {
            return app_user.User.fromFirestore(userDoc);
          }
        }
      }

      return null;
    } catch (e) {
      print('Firebase 사용자 처리 중 오류: $e');
      return null;
    }
  }

  // 카카오 회원가입 (닉네임 + 추천인 코드)
  Future<app_user.User?> signUpWithKakao({
    required String kakaoId,
    required String accessToken,
    required String accountEmail,
    required String nickname,
    String? usedInviteCode,
    String? adId,
    String? deviceId,
  }) async {
    try {
      final url = 'https://asia-northeast3-cashbank-a1c93.cloudfunctions.net/signUpKakao';
      final res = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'kakaoId': kakaoId,
          'accessToken': accessToken,
          'accountEmail': accountEmail,
          'nickname': nickname,
          'usedInviteCode': usedInviteCode,
          'adId': adId,
          'deviceId': deviceId,
        }),
      );

      if (res.statusCode != 200) {
        print('카카오 회원가입 실패: ${res.statusCode} - ${res.body}');

        // ⚠️ 회원가입 실패 시 로그아웃 (불일치 상태 방지)
        try {
          await _auth.signOut();
          await UserApi.instance.logout();
        } catch (logoutError) {
          // 로그아웃 실패 무시 (이미 로그아웃 상태일 수 있음)
          print('로그아웃 중 오류 (무시): $logoutError');
        }

        final responseData = jsonDecode(res.body);

        // 에러 메시지 처리
        if (responseData['error'] != null) {
          // 409: 이메일 중복, 디바이스 중복 등
          if (res.statusCode == 409) {
            if (responseData['error'] == 'EMAIL_ALREADY_EXISTS') {
              throw Exception('이미 가입된 이메일입니다.');
            } else if (responseData['error'] == 'DEVICE_ALREADY_REGISTERED') {
              throw Exception('이미 가입된 기기입니다.');
            } else if (responseData['error'] == 'SAME_DEVICE_ERROR') {
              throw Exception('기기당 초대코드는 한 번만 입력 가능합니다.');
            }
          }
          throw Exception(responseData['message'] ?? '회원가입에 실패했습니다');
        }
        return null;
      }

      final responseData = jsonDecode(res.body);

      // Firebase Auth 커스텀 토큰으로 로그인
      if (responseData['token'] != null) {
        final token = responseData['token'];
        final cred = await _auth.signInWithCustomToken(token);

        if (cred.user != null) {
          // Firestore에서 사용자 정보 가져오기
          final userDoc = await _fs.doc('users/${cred.user!.uid}').get();
          if (userDoc.exists) {
            return app_user.User.fromFirestore(userDoc);
          }
        }
      }

      return null;
    } catch (e) {
      print('카카오 회원가입 중 오류: $e');
      // ⚠️ 에러 발생 시에도 Firebase Auth 로그아웃
      try {
        await _auth.signOut();
        await UserApi.instance.logout();
      } catch (logoutError) {
        print('로그아웃 중 오류 (무시): $logoutError');
      }
      rethrow;
    }
  }

  // 기존 사용자 카카오 계정 연동
  Future<bool> linkKakaoToExistingAccount(String uid) async {
    try {
      // 카카오 로그인 먼저 진행
      OAuthToken? token;

      if (await isKakaoTalkInstalled()) {
        try {
          token = await UserApi.instance.loginWithKakaoTalk();
        } catch (error) {
          print('카카오톡 로그인 실패: $error');
          if (error is PlatformException && error.code == 'CANCELED') {
            return false;
          }
          try {
            token = await UserApi.instance.loginWithKakaoAccount();
          } catch (error) {
            print('카카오계정 로그인 실패: $error');
            return false;
          }
        }
      } else {
        try {
          token = await UserApi.instance.loginWithKakaoAccount();
        } catch (error) {
          print('카카오계정 로그인 실패: $error');
          return false;
        }
      }

      // 카카오 사용자 정보 가져오기
      User kakaoUser = await UserApi.instance.me();

      // Cloud Function 호출
      final url = 'https://asia-northeast3-cashbank-a1c93.cloudfunctions.net/linkKakaoAccount';
      final res = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'uid': uid,
          'kakaoId': kakaoUser.id.toString(),
          'accessToken': token.accessToken,
          'accountEmail': kakaoUser.kakaoAccount?.email ?? '',
        }),
      );

      if (res.statusCode == 200) {
        print('카카오 계정 연동 성공');
        return true;
      } else {
        print('카카오 계정 연동 실패: ${res.statusCode} - ${res.body}');
        return false;
      }
    } catch (e) {
      print('카카오 계정 연동 중 오류: $e');
      return false;
    }
  }

  Future<void> signOut() async {
    try {
      // 카카오 로그아웃
      await UserApi.instance.logout();

      // Firebase 로그아웃
      await _auth.signOut();
    } catch (e) {
      print('로그아웃 중 오류: $e');
    }
  }

  Future<void> unlinkKakao() async {
    try {
      // 카카오 연결 끊기 (회원 탈퇴)
      await UserApi.instance.unlink();

      // Firebase에서도 사용자 삭제
      final user = _auth.currentUser;
      if (user != null) {
        // Cloud Function 호출하여 사용자 데이터 삭제
        final url = 'https://deleteaccount-s4bul2i7dq-du.a.run.app';
        await http.post(
          Uri.parse(url),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'uid': user.uid,
          }),
        );

        // Firebase Auth에서 로그아웃
        await _auth.signOut();
      }
    } catch (e) {
      print('회원 탈퇴 중 오류: $e');
    }
  }

  // 현재 로그인된 사용자 정보 가져오기
  Future<app_user.User?> getCurrentUser() async {
    try {
      final firebaseUser = _auth.currentUser;
      if (firebaseUser != null) {
        final userDoc = await _fs.doc('users/${firebaseUser.uid}').get();
        if (userDoc.exists) {
          return app_user.User.fromFirestore(userDoc);
        }
      }
      return null;
    } catch (e) {
      print('현재 사용자 정보 가져오기 실패: $e');
      return null;
    }
  }

  // 카카오 토큰 갱신
  Future<bool> refreshKakaoToken() async {
    try {
      // 토큰 갱신 가능 여부 체크
      if (await AuthApi.instance.hasToken()) {
        try {
          AccessTokenInfo tokenInfo = await UserApi.instance.accessTokenInfo();
          print('토큰 유효기간: ${tokenInfo.expiresIn}초');

          // 토큰이 만료되었거나 곧 만료될 예정이면 갱신
          if (tokenInfo.expiresIn < 60) {
            OAuthToken token = await AuthApi.instance.refreshToken();
            print('토큰 갱신 성공');
            return true;
          }

          return true;
        } catch (error) {
          print('토큰 정보 조회 실패: $error');
          return false;
        }
      }

      return false;
    } catch (e) {
      print('토큰 갱신 실패: $e');
      return false;
    }
  }
}