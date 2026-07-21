import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import '../user/model/user.dart' as app_user;

/// 구글 로그인 결과
class GoogleSignInResult {
  final app_user.User? user; // 기존 사용자인 경우
  final GoogleSignupData? signupData; // 신규 사용자인 경우
  final bool isNewUser;

  GoogleSignInResult({
    this.user,
    this.signupData,
    required this.isNewUser,
  });
}

/// 구글 회원가입 데이터
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

class GoogleAuthRepository {
  final _fs = FirebaseFirestore.instance;
  final _auth = fb.FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
  );

  Future<GoogleSignInResult?> signInWithGoogle() async {
    try {
      // 구글 로그인 시도
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        // 사용자가 로그인 취소
        return null;
      }

      // 구글 인증 정보 가져오기
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      if (googleAuth.idToken == null) {
        print('구글 ID 토큰을 가져올 수 없습니다');
        return null;
      }

      // Firebase에 구글 로그인 정보로 사용자 생성/로그인
      final user = await _createOrUpdateFirebaseUser(
        googleUser,
        googleAuth.idToken!,
      );

      if (user != null) {
        // 기존 사용자
        return GoogleSignInResult(
          user: user,
          isNewUser: false,
        );
      } else {
        // 신규 사용자 - 회원가입 필요
        return GoogleSignInResult(
          signupData: GoogleSignupData(
            googleId: googleUser.id,
            idToken: googleAuth.idToken!,
            accountEmail: googleUser.email,
          ),
          isNewUser: true,
        );
      }
    } catch (error) {
      print('구글 로그인 중 오류 발생: $error');
      return null;
    }
  }

  Future<app_user.User?> _createOrUpdateFirebaseUser(
    GoogleSignInAccount googleUser,
    String googleIdToken,
  ) async {
    try {
      print('🔐 Firebase 로그인 시도 - Google ID: ${googleUser.id}');

      // 1. Google credential로 Firebase에 로그인
      final credential = fb.GoogleAuthProvider.credential(
        idToken: googleIdToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);

      if (userCredential.user == null) {
        print('Firebase 로그인 실패');
        return null;
      }

      // 2. Firebase ID 토큰 가져오기
      final firebaseIdToken = await userCredential.user!.getIdToken();

      if (firebaseIdToken == null) {
        print('Firebase ID 토큰 가져오기 실패');
        return null;
      }

      // 3. Cloud Function 호출하여 Firestore에 사용자 확인
      print('🌐 백엔드 호출 시작: googleId=${googleUser.id}');
      final url = 'https://asia-northeast3-cashbank-a1c93.cloudfunctions.net/signInGoogle';
      final res = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'googleId': googleUser.id,
          'idToken': firebaseIdToken, // Firebase ID 토큰 전송
          'accountEmail': googleUser.email,
        }),
      );

      print('📡 백엔드 응답: ${res.statusCode} - ${res.body}');
      final responseData = jsonDecode(res.body);

      // 신규 사용자인 경우 (회원가입 필요)
      if (res.statusCode == 404 && responseData['isNewUser'] == true) {
        print('신규 사용자 - 회원가입 필요');
        // ✅ Firebase Auth 로그인 상태 유지 (회원가입 화면에서 재사용)
        return null;
      }

      if (res.statusCode != 200) {
        print('❌ Firestore 사용자 확인 실패: ${res.statusCode} - ${res.body}');
        return null;
      }

      // 4. 기존 사용자 - customToken으로 로그인 (닉네임+구글 연동 계정)
      final customToken = responseData['token'];
      final uid = responseData['uid'];

      if (customToken != null && uid != null) {
        print('🔄 기존 계정으로 전환: $uid');
        // customToken으로 로그인 (원래 계정으로 전환)
        await _auth.signInWithCustomToken(customToken);
        print('✅ 계정 전환 완료');
      }

      // 5. Firestore에서 사용자 정보 가져오기
      final currentUid = _auth.currentUser?.uid;
      if (currentUid == null) {
        print('❌ 로그인 세션 없음');
        return null;
      }

      final userDoc = await _fs.doc('users/$currentUid').get();
      if (userDoc.exists) {
        print('✅ 사용자 정보 로드 성공: $currentUid');
        return app_user.User.fromFirestore(userDoc);
      }

      print('⚠️ Firestore 데이터 없음: $currentUid');
      return null;
    } catch (e) {
      print('Firebase 사용자 처리 중 오류: $e');
      return null;
    }
  }

  // 구글 회원가입 (닉네임 + 추천인 코드)
  Future<app_user.User?> signUpWithGoogle({
    required String googleId,
    required String googleIdToken, // Google ID 토큰
    required String accountEmail,
    required String nickname,
    String? usedInviteCode,
    String? adId,
    String? deviceId,
  }) async {
    try {
      // ✅ 이미 signInWithGoogle에서 Firebase Auth 로그인 완료
      // 기존 세션 재사용
      final firebaseUser = _auth.currentUser;
      if (firebaseUser == null) {
        print('⚠️ Firebase Auth 세션 없음 - 재로그인 시도');
        // 세션이 없으면 재로그인
        final credential = fb.GoogleAuthProvider.credential(
          idToken: googleIdToken,
        );
        final userCredential = await _auth.signInWithCredential(credential);
        if (userCredential.user == null) {
          print('Firebase 로그인 실패');
          return null;
        }
      }

      // 2. Firebase ID 토큰 가져오기
      final firebaseIdToken = await _auth.currentUser!.getIdToken();

      if (firebaseIdToken == null) {
        print('Firebase ID 토큰 가져오기 실패');
        return null;
      }

      // 3. Cloud Function 호출하여 회원가입
      final url = 'https://asia-northeast3-cashbank-a1c93.cloudfunctions.net/signUpGoogle';
      final res = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'googleId': googleId,
          'idToken': firebaseIdToken, // Firebase ID 토큰 전송
          'accountEmail': accountEmail,
          'nickname': nickname,
          'usedInviteCode': usedInviteCode,
          'adId': adId,
          'deviceId': deviceId,
        }),
      );

      if (res.statusCode != 200) {
        print('구글 회원가입 실패: ${res.statusCode} - ${res.body}');
        final responseData = jsonDecode(res.body);

        // 에러 메시지 처리
        if (responseData['error'] != null) {
          // 409: 중복 에러 (이메일, 디바이스, 닉네임 등)
          if (res.statusCode == 409) {
            // ⚠️ 중복 에러 발생 시 로그아웃
            await _auth.signOut();
            await _googleSignIn.signOut();

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

      // 4. Firestore에서 사용자 정보 가져오기 (이미 Firebase Auth 로그인 완료)
      final currentUid = _auth.currentUser!.uid;
      final userDoc = await _fs.doc('users/$currentUid').get();
      if (userDoc.exists) {
        return app_user.User.fromFirestore(userDoc);
      }

      return null;
    } catch (e) {
      print('구글 회원가입 중 오류: $e');
      // ⚠️ Exception이면 이미 에러 처리됨 (중복 에러는 위에서 로그아웃 처리)
      // 다른 예외는 로그아웃 처리
      if (e is! Exception) {
        try {
          await _auth.signOut();
          await _googleSignIn.signOut();
        } catch (logoutError) {
          print('로그아웃 중 오류 (무시): $logoutError');
        }
      }
      rethrow;
    }
  }

  Future<void> signOut() async {
    try {
      // 구글 로그아웃
      await _googleSignIn.signOut();

      // Firebase 로그아웃
      await _auth.signOut();
    } catch (e) {
      print('로그아웃 중 오류: $e');
    }
  }

  Future<bool> deleteAccount() async {
    try {
      // Firebase에서 사용자 데이터 삭제
      final user = _auth.currentUser;
      if (user == null) {
        print('❌ 로그인된 사용자가 없습니다');
        return false;
      }

      print('🐷 PigMoney [DEBUG] 구글 회원 탈퇴 시작: ${user.uid}');

      // Cloud Function 호출하여 사용자 데이터 삭제
      final url = 'https://deleteaccount-s4bul2i7dq-du.a.run.app';
      final res = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'uid': user.uid,
        }),
      );

      print('🐷 PigMoney [DEBUG] 회원 탈퇴 응답: ${res.statusCode} - ${res.body}');

      if (res.statusCode == 200) {
        // 구글 로그아웃
        await _googleSignIn.signOut();

        // Firebase Auth에서 로그아웃
        await _auth.signOut();

        print('✅ 구글 회원 탈퇴 성공');
        return true;
      } else {
        print('❌ 회원 탈퇴 실패: ${res.statusCode} - ${res.body}');
        return false;
      }
    } catch (e) {
      print('❌ 회원 탈퇴 중 오류: $e');
      return false;
    }
  }

  // 기존 사용자 구글 계정 연동
  Future<bool> linkGoogleToExistingAccount(String originalUid) async {
    try {
      // 1. 구글 로그인 시도
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        print('구글 로그인 취소됨');
        return false;
      }

      // 2. 구글 인증 정보 가져오기
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      if (googleAuth.idToken == null) {
        print('구글 ID 토큰을 가져올 수 없습니다');
        await _googleSignIn.signOut();
        return false;
      }

      // 3. Firebase Auth에 일시적으로 구글 로그인 (Firebase ID 토큰 획득용)
      final credential = fb.GoogleAuthProvider.credential(
        idToken: googleAuth.idToken!,
      );

      final userCredential = await _auth.signInWithCredential(credential);

      if (userCredential.user == null) {
        print('Firebase 로그인 실패');
        await _googleSignIn.signOut();
        return false;
      }

      final googleFirebaseUid = userCredential.user!.uid;
      print('📱 구글 로그인으로 생성된 Firebase UID: $googleFirebaseUid');

      // 4. Firestore에서 해당 UID 확인 (orphan 계정 감지)
      final googleUserDoc = await _fs.doc('users/$googleFirebaseUid').get();

      if (googleUserDoc.exists) {
        // 이 구글 계정은 이미 다른 실제 사용자 계정과 연결되어 있음
        print('❌ 이 구글 계정은 이미 다른 계정과 연결되어 있습니다');
        await _googleSignIn.signOut();
        await _auth.signOut();
        throw Exception('이 구글 계정은 이미 다른 계정과 연결되어 있습니다.');
      }

      // Firestore에 데이터가 없음 = orphan 계정 (회원가입 실패로 인한 잔여 Firebase Auth 계정)
      print('🧹 Orphan Firebase Auth 계정 감지 - 정리 후 연동 진행');

      // 5. Firebase ID 토큰 가져오기
      final firebaseIdToken = await userCredential.user!.getIdToken();

      if (firebaseIdToken == null) {
        print('Firebase ID 토큰 가져오기 실패');
        await _googleSignIn.signOut();
        await _auth.signOut();
        return false;
      }

      print('🔑 Firebase ID 토큰 획득 성공');

      // 6. Cloud Function 호출하여 Firestore 업데이트
      final url = 'https://asia-northeast3-cashbank-a1c93.cloudfunctions.net/linkGoogleAccount';
      final res = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'uid': originalUid, // 원래 계정의 UID
          'googleId': googleUser.id,
          'idToken': firebaseIdToken, // Firebase ID 토큰 전달
          'accountEmail': googleUser.email,
          'cleanupOrphanUid': googleFirebaseUid, // orphan UID 전달 (백엔드에서 정리)
        }),
      );

      if (res.statusCode == 200) {
        print('✅ 구글 계정 연동 성공');

        final responseData = jsonDecode(res.body);
        final customToken = responseData['customToken'];

        if (customToken != null) {
          // 7. 커스텀 토큰으로 원래 계정에 재로그인
          print('🔄 원래 계정으로 복원 중...');
          await _auth.signInWithCustomToken(customToken);
          print('✅ 원래 계정 복원 완료');
        }

        // 8. 구글 로그아웃 (연동만 하고 구글 세션은 종료)
        await _googleSignIn.signOut();
        return true;
      } else {
        print('❌ 구글 계정 연동 실패: ${res.statusCode} - ${res.body}');
        final errorData = jsonDecode(res.body);
        final errorMessage = errorData['message'] ?? '구글 계정 연동에 실패했습니다';

        // 실패 시 정리
        await _googleSignIn.signOut();
        await _auth.signOut();
        throw Exception(errorMessage);
      }
    } catch (e) {
      print('❌ 구글 계정 연동 중 오류: $e');
      // 에러 발생 시 정리
      try {
        await _googleSignIn.signOut();
        await _auth.signOut();
      } catch (cleanupError) {
        print('정리 중 오류 (무시): $cleanupError');
      }
      rethrow;
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
        // ℹ️ Firestore에 데이터 없음 → 회원가입 진행 중일 수 있음 (정상 상황)
        print('ℹ️ Firestore 데이터 없음 (회원가입 진행 중일 수 있음)');
      }
      return null;
    } catch (e) {
      print('현재 사용자 정보 가져오기 실패: $e');
      return null;
    }
  }
}
