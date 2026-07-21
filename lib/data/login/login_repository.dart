import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:http/http.dart' as http;

import '../user/model/user.dart';
import '../user/model/invite_friend.dart';

class LoginRepository {
  final _fs = FirebaseFirestore.instance;

  Future<bool> signUp(String nickname, String password, String inviteCode, String adId, String deviceId, String? usedInviteCode) async {
    /* 1) Cloud Function signUpNickname 호출 */
    final url = 'https://asia-northeast3-cashbank-a1c93.cloudfunctions.net/signUpNickname';
    final res = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'nickname': nickname,
        'password': password,
        'inviteCode': inviteCode,  // 초대코드 추가
        'adId': adId,  // 광고 ID 추가 (참고용)
        'deviceId': deviceId,  // 기기 ID 추가 (필수)
        'usedInviteCode': usedInviteCode,  // 사용한 초대코드 (옵션)
      }),
    );

    print('signUp response: ${res.statusCode} - ${res.body}');
    
    if (res.statusCode == 409) {
      // 닉네임 중복
      print('닉네임 중복: $nickname');
      return false;
    }
    
    if (res.statusCode != 200) {
      print('회원가입 실패: ${res.statusCode} - ${res.body}');
      return false;
    }

    /* 2) Custom Token → Auth 로그인 */
    try {
      final responseBody = jsonDecode(res.body);
      if (responseBody['token'] == null) {
        print('토큰이 없습니다: ${res.body}');
        return false;
      }
      
      final token = responseBody['token'];
      final cred = await fb.FirebaseAuth.instance.signInWithCustomToken(token);
      
      /* 3) Firestore users/{uid} 는 함수가 이미 생성 */
      return cred.user != null;
    } catch (e) {
      print('회원가입 처리 중 오류: $e');
      return false;
    }
  }

  Future<User?> login(String nickname, String password) async {
    final url = 'https://asia-northeast3-cashbank-a1c93.cloudfunctions.net/signInNickname';

    final res = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'nickname': nickname, 'password': password}),
    );

    if (res.statusCode != 200) return null;
    final token = jsonDecode(res.body)['token'];

    /* 1) Firebase Auth 세션 */
    await fb.FirebaseAuth.instance.signInWithCustomToken(token);
    final uid = fb.FirebaseAuth.instance.currentUser!.uid;

    /* 2) users/{uid} 로 문서 읽기 */
    final snap = await _fs.doc('users/$uid').get();
    if (!snap.exists) return null;

    return User.fromFirestore(snap);
  }

  // 초대코드 유효성 검사 (Cloud Function 호출)
  Future<Map<String, dynamic>?> validateInviteCode(String inviteCode, String deviceId) async {
    try {
      final url = 'https://asia-northeast3-cashbank-a1c93.cloudfunctions.net/validateInviteCode';
      final res = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'inviteCode': inviteCode,
          'deviceId': deviceId,  // 기기 ID로 중복 체크
        }),
      );
      
      if (res.statusCode != 200) {
        print('초대코드 검증 실패: ${res.statusCode}');
        return null;
      }
      
      final data = jsonDecode(res.body);
      
      if (data['valid'] == true) {
        return {
          'inviterUid': data['inviterUid'],
          'inviterNickname': data['inviterNickname'],
        };
      }
      
      // 유효하지 않은 초대코드 또는 기기 중복
      print('초대코드 검증 실패: ${data['message']}');
      return {
        'error': data['message'],
        'detail': data['detail'] ?? '',
      };
    } catch (e) {
      print('초대코드 검증 오류: $e');
      return null;
    }
  }
}
