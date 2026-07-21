import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:http/http.dart' as http;
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../user/model/user.dart' as app_user;

/// 애플 로그인 결과
class AppleSignInResult {
  final app_user.User? user; // 기존 사용자
  final AppleSignupData? signupData; // 신규 사용자
  final bool isNewUser;

  AppleSignInResult({
    this.user,
    this.signupData,
    required this.isNewUser,
  });
}

/// 애플 회원가입 데이터
class AppleSignupData {
  final String appleId; // Apple userIdentifier (sub)
  final String idToken; // Firebase ID 토큰
  final String accountEmail;

  AppleSignupData({
    required this.appleId,
    required this.idToken,
    required this.accountEmail,
  });
}

class AppleAuthRepository {
  final _fs = FirebaseFirestore.instance;
  final _auth = fb.FirebaseAuth.instance;

  /// nonce 생성 (Apple 로그인 보안용)
  String _generateNonce([int length = 32]) {
    const charset = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)]).join();
  }

  String _sha256OfString(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<AppleSignInResult?> signInWithApple() async {
    try {
      // Apple 로그인 (nonce 사용)
      final rawNonce = _generateNonce();
      final hashedNonce = _sha256OfString(rawNonce);

      final AuthorizationCredentialAppleID appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );

      if (appleCredential.identityToken == null) {
        print('애플 identityToken이 없습니다');
        return null;
      }

      final appleId = appleCredential.userIdentifier;
      if (appleId == null || appleId.isEmpty) {
        print('애플 userIdentifier가 없습니다');
        return null;
      }

      // ⚠️ Apple identityToken은 일회성 토큰이므로 REST API는 단 한 번만 호출해야 함
      final restData = await _firebaseSignInWithApple(
        identityToken: appleCredential.identityToken!,
        rawNonce: rawNonce,
      );
      if (restData == null) {
        print('Firebase REST API 로그인 실패');
        return null;
      }

      final firebaseIdToken = restData['idToken'] as String?;
      final firebaseUid = restData['localId'] as String?;
      final restEmail = restData['email'] as String?;

      if (firebaseIdToken == null || firebaseUid == null) {
        print('Firebase REST API 응답에서 토큰/UID를 가져올 수 없습니다');
        return null;
      }

      final email = appleCredential.email ?? restEmail ?? '';

      // 백엔드 호출하여 기존/신규 사용자 확인
      final user = await _checkExistingUser(
        appleId: appleId,
        firebaseIdToken: firebaseIdToken,
        email: email,
      );

      if (user != null) {
        // 기존 사용자
        return AppleSignInResult(user: user, isNewUser: false);
      } else {
        // 신규 사용자 - 회원가입 화면에서 같은 idToken 재사용
        return AppleSignInResult(
          signupData: AppleSignupData(
            appleId: appleId,
            idToken: firebaseIdToken,
            accountEmail: email,
          ),
          isNewUser: true,
        );
      }
    } on SignInWithAppleAuthorizationException catch (e) {
      // 사용자가 취소했거나 인증 실패
      print('애플 로그인 인증 오류: ${e.code} - ${e.message}');
      return null;
    } catch (e) {
      print('애플 로그인 중 오류: $e');
      return null;
    }
  }

  // Firebase Web API Key (GoogleService-Info.plist의 API_KEY와 동일)
  static const String _firebaseApiKey = 'AIzaSyD6YvNoHOASzh4bgNElIAMJkWLgdU5rT9w';

  /// Apple identityToken으로 Firebase Identity Toolkit REST API에 직접 로그인.
  /// Flutter firebase_auth iOS SDK의 OAuthProvider("apple.com").credential 처리 버그 우회.
  Future<Map<String, dynamic>?> _firebaseSignInWithApple({
    required String identityToken,
    required String rawNonce,
  }) async {
    final url = 'https://identitytoolkit.googleapis.com/v1/accounts:signInWithIdp?key=$_firebaseApiKey';
    final res = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'postBody': 'id_token=$identityToken&providerId=apple.com&nonce=$rawNonce',
        'requestUri': 'http://localhost',
        'returnIdpCredential': true,
        'returnSecureToken': true,
      }),
    );

    if (res.statusCode != 200) {
      print('Firebase REST API 로그인 실패: ${res.statusCode} - ${res.body}');
      return null;
    }

    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// 백엔드(signInApple)로 기존 사용자 확인. 기존 사용자면 customToken으로 SDK 세션 생성.
  /// 신규 사용자면 null 반환 (호출자가 SignupData를 만들어 SignUpScreen으로 이동).
  Future<app_user.User?> _checkExistingUser({
    required String appleId,
    required String firebaseIdToken,
    required String email,
  }) async {
    try {
      final url = 'https://asia-northeast3-cashbank-a1c93.cloudfunctions.net/signInApple';
      final res = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'appleId': appleId,
          'idToken': firebaseIdToken,
          'accountEmail': email,
        }),
      );

      final responseData = jsonDecode(res.body);

      // 신규 사용자
      if (res.statusCode == 404 && responseData['isNewUser'] == true) {
        return null;
      }

      if (res.statusCode != 200) {
        print('애플 백엔드 사용자 확인 실패: ${res.statusCode} - ${res.body}');
        return null;
      }

      // 기존 사용자 - customToken으로 SDK 세션 생성
      final customToken = responseData['token'];
      final uid = responseData['uid'];

      if (customToken != null && uid != null) {
        await _auth.signInWithCustomToken(customToken);
      }

      final currentUid = _auth.currentUser?.uid;
      if (currentUid == null) return null;

      final userDoc = await _fs.doc('users/$currentUid').get();
      if (userDoc.exists) {
        return app_user.User.fromFirestore(userDoc);
      }

      return null;
    } catch (e) {
      print('애플 백엔드 사용자 확인 중 오류: $e');
      return null;
    }
  }

  /// 애플 회원가입 (닉네임 + 추천인 코드)
  /// signInWithApple에서 이미 REST API로 발급받은 Firebase idToken을 그대로 사용한다.
  Future<app_user.User?> signUpWithApple({
    required String appleId,
    required String appleIdToken, // signInWithApple에서 받은 Firebase ID 토큰 (REST API 발급)
    required String accountEmail,
    required String nickname,
    String? usedInviteCode,
    String? adId,
    String? deviceId,
  }) async {
    try {
      final url = 'https://asia-northeast3-cashbank-a1c93.cloudfunctions.net/signUpApple';
      final res = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'appleId': appleId,
          'idToken': appleIdToken,
          'accountEmail': accountEmail,
          'nickname': nickname,
          'usedInviteCode': usedInviteCode,
          'adId': adId,
          'deviceId': deviceId,
        }),
      );

      if (res.statusCode != 200) {
        print('애플 회원가입 실패: ${res.statusCode} - ${res.body}');
        final responseData = jsonDecode(res.body);

        if (responseData['error'] != null) {
          if (res.statusCode == 409) {
            try {
              await _auth.signOut();
            } catch (_) {}

            if (responseData['error'] == 'EMAIL_ALREADY_EXISTS') {
              throw Exception('이미 가입된 이메일입니다.');
            } else if (responseData['error'] == 'DEVICE_ALREADY_REGISTERED') {
              throw Exception('이미 가입된 기기입니다.');
            } else if (responseData['error'] == 'SAME_DEVICE_ERROR') {
              throw Exception('기기당 초대코드는 한 번만 입력 가능합니다.');
            } else if (responseData['error'] == 'NICKNAME_TAKEN') {
              throw Exception('이미 사용 중인 닉네임입니다.');
            }
          }
          throw Exception(responseData['message'] ?? '회원가입에 실패했습니다');
        }

        return null;
      }

      // 백엔드 응답의 customToken으로 SDK 세션 생성
      final responseData = jsonDecode(res.body);
      final customToken = responseData['token'];

      if (customToken == null) return null;
      await _auth.signInWithCustomToken(customToken);

      final currentUid = _auth.currentUser?.uid;
      if (currentUid == null) return null;

      final userDoc = await _fs.doc('users/$currentUid').get();
      if (userDoc.exists) {
        return app_user.User.fromFirestore(userDoc);
      }

      return null;
    } catch (e) {
      print('애플 회원가입 중 오류: $e');
      if (e is! Exception) {
        try {
          await _auth.signOut();
        } catch (_) {}
      }
      rethrow;
    }
  }

  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (e) {
      print('로그아웃 중 오류: $e');
    }
  }

  Future<bool> deleteAccount() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      final url = 'https://deleteaccount-s4bul2i7dq-du.a.run.app';
      final res = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'uid': user.uid}),
      );

      if (res.statusCode == 200) {
        await _auth.signOut();
        return true;
      } else {
        print('애플 회원 탈퇴 실패: ${res.statusCode} - ${res.body}');
        return false;
      }
    } catch (e) {
      print('애플 회원 탈퇴 중 오류: $e');
      return false;
    }
  }

  /// 기존 사용자 애플 계정 연동
  Future<bool> linkAppleToExistingAccount(String originalUid) async {
    try {
      // 1. 애플 로그인 (nonce 사용)
      final rawNonce = _generateNonce();
      final hashedNonce = _sha256OfString(rawNonce);

      final AuthorizationCredentialAppleID appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );

      if (appleCredential.identityToken == null) {
        print('애플 identityToken이 없습니다');
        return false;
      }

      final appleId = appleCredential.userIdentifier;
      if (appleId == null || appleId.isEmpty) {
        print('애플 userIdentifier가 없습니다');
        return false;
      }

      // 2. Firebase Auth에 일시적으로 애플 로그인 (REST API로 SDK 우회)
      final restData = await _firebaseSignInWithApple(
        identityToken: appleCredential.identityToken!,
        rawNonce: rawNonce,
      );
      if (restData == null) {
        print('Firebase REST API 로그인 실패');
        return false;
      }

      final appleFirebaseUid = restData['localId'] as String?;
      final firebaseIdToken = restData['idToken'] as String?;
      final restEmail = restData['email'] as String?;

      if (appleFirebaseUid == null || firebaseIdToken == null) {
        print('Firebase REST API 응답에서 UID/idToken 가져오기 실패');
        return false;
      }

      // 3. Firestore에서 해당 UID 확인 (orphan 계정 감지)
      final appleUserDoc = await _fs.doc('users/$appleFirebaseUid').get();
      if (appleUserDoc.exists) {
        throw Exception('이 애플 계정은 이미 다른 계정과 연결되어 있습니다.');
      }

      // 4. Cloud Function 호출하여 Firestore 업데이트
      final email = appleCredential.email ?? restEmail ?? '';
      final url = 'https://asia-northeast3-cashbank-a1c93.cloudfunctions.net/linkAppleAccount';
      final res = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'uid': originalUid,
          'appleId': appleId,
          'idToken': firebaseIdToken,
          'accountEmail': email,
          'cleanupOrphanUid': appleFirebaseUid,
        }),
      );

      if (res.statusCode == 200) {
        final responseData = jsonDecode(res.body);
        final customToken = responseData['customToken'];

        if (customToken != null) {
          await _auth.signInWithCustomToken(customToken);
        }

        return true;
      } else {
        final errorData = jsonDecode(res.body);
        final errorMessage = errorData['message'] ?? '애플 계정 연동에 실패했습니다';

        await _auth.signOut();
        throw Exception(errorMessage);
      }
    } on SignInWithAppleAuthorizationException catch (e) {
      print('애플 로그인 인증 오류: ${e.code} - ${e.message}');
      return false;
    } catch (e) {
      print('애플 계정 연동 중 오류: $e');
      try {
        await _auth.signOut();
      } catch (_) {}
      rethrow;
    }
  }

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
}
