import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:pigmoney/core/utils/log/logger.dart';

import '../order/model/order.dart';
import 'model/invite_friend.dart';
import 'model/user.dart';

class UserRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _collection = 'users';
  final fb.FirebaseAuth _auth = fb.FirebaseAuth.instance;

  // 현재 로그인한 사용자 정보 가져오기
  Future<User?> getCurrentUser({bool forceRefresh = true}) async {
    try {
      // Firebase Auth 상태 강제 새로고침 (필요시)
      if (forceRefresh) {
        await _auth.currentUser?.reload();
      }

      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        logger.d('Firebase Auth currentUser is null');
        return null;
      }

      // ✅ 서버 연결 실패 시 캐시 사용
      DocumentSnapshot userDoc;
      bool fromCache = false;

      try {
        // 먼저 서버에서 가져오기 시도
        userDoc = await _firestore
            .collection(_collection)
            .doc(currentUser.uid)
            .get(const GetOptions(source: Source.server))
            .timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            logger.e('서버 응답 타임아웃 (10초)');
            throw Exception('Server timeout');
          },
        );
      } catch (e) {
        // 네트워크 오류 시 캐시에서 가져오기 시도
        logger.w('서버 연결 실패, 캐시 데이터 사용 시도: $e');

        try {
          userDoc = await _firestore.collection(_collection).doc(currentUser.uid).get(const GetOptions(source: Source.cache));
          fromCache = true;
          logger.d('캐시에서 데이터 가져옴');
        } catch (cacheError) {
          logger.e('캐시 데이터도 없음: $cacheError');
          throw Exception('Network error and no cache data');
        }
      }

      // 사용자가 존재하면 User 객체로 변하여 반환
      if (userDoc.exists) {
        final user = User.fromFirestore(userDoc);

        // ✅ 캐시 데이터인 경우 경고
        if (fromCache) {
          logger.w('⚠️ 캐시 데이터 사용중: ${user.nickname}, money: ${user.money}');
        } else if (user.money == 0) {
          logger.w('⚠️ 서버에서 가져온 머니가 0: ${user.nickname}');
        } else {
          logger.d('userInfo: ${user.nickname}, money: ${user.money}');
        }

        return user;
      }

      return null;
    } catch (e) {
      logger.e('사용자 정보 조회 오류: $e');

      // ✅ 네트워크 오류와 캐시 없음 예외는 그대로 전파
      if (e.toString().contains('Network error and no cache data')) {
        throw e;
      }

      return null;
    }
  }

  // 강제 상태 정리 및 새로고침 (로그아웃 후 사용)
  Future<void> clearCachedUserData() async {
    try {
      logger.d('사용자 캐시 데이터 정리 시작');

      // Firebase Auth 상태 강제 새로고침
      final currentUser = _auth.currentUser;
      if (currentUser != null) {
        try {
          await currentUser.reload();
          // ID 토큰 강제 갱신 시도
          await currentUser.getIdToken(true); // forceRefresh = true
        } catch (e) {
          logger.w('Firebase Auth 토큰 갱신 중 오류 (로그아웃 진행): $e');
        }
      }

      // Firestore 캐시 정리 (가능한 경우만)
      try {
        // 캐시 정리는 조건부로만 수행
        if (_auth.currentUser == null) {
          await _firestore.clearPersistence();
          logger.d('Firestore 캐시 정리 완료');
        } else {
          logger.d('로그인 상태에서는 Firestore 캐시 정리 건너뜀');
        }
      } catch (e) {
        // 이 오류는 정상적인 상황에서도 발생할 수 있으므로 무시
        logger.d('Firestore 캐시 정리 건너뜀 (정상): ${e.toString().split('.').first}');
      }

      logger.d('사용자 캐시 데이터 정리 완료');
    } catch (e) {
      logger.e('캐시 정리 중 오류: $e');
    }
  }

  // 닉네임으로 사용자 정보 가져오기
  Future<User?> getUserByNickname(String nickname) async {
    try {
      // ✅ 항상 서버에서 강제로 가져오기
      final nmap = await _firestore.doc('nicknames/$nickname').get(const GetOptions(source: Source.server));
      if (!nmap.exists) return null;

      final uid = (nmap.data()!['uid'] as String);
      // ✅ 항상 서버에서 강제로 가져오기
      final snap = await _firestore.doc('users/$uid').get(const GetOptions(source: Source.server));
      return snap.exists ? User.fromFirestore(snap) : null;
    } catch (e) {
      print('사용자 정보 조회 오류: $e');
      return null;
    }
  }

  // 마지막 접속 시간 업데이트
  Future<bool> updateLastAccessTime(String nickname) async {
    try {
      // 닉네임으로 uid 조회
      final nmap = await _firestore.doc('nicknames/$nickname').get();
      if (!nmap.exists) return false;

      final uid = (nmap.data()!['uid'] as String);

      await _firestore.doc('users/$uid').update({
        'lastAccessTime': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      print('마지막 접속 시간 업데이트 오류: $e');
      return false;
    }
  }

  // 앱 버전 업데이트 (기존 유저 포함 - 앱 실행 시 자동 호출)
  Future<bool> updateAppVersion(String uid, String appVersion) async {
    try {
      await _firestore.doc('users/$uid').update({
        'appVersion': appVersion,
      });
      logger.d('앱 버전 업데이트 성공: $appVersion');
      return true;
    } catch (e) {
      logger.e('앱 버전 업데이트 오류: $e');
      return false;
    }
  }

  // 플랫폼 정보 업데이트 (값 없는 유저 1회 백필 - "AOS" | "iOS")
  Future<bool> updatePlatform(String uid, String platform) async {
    try {
      await _firestore.doc('users/$uid').update({
        'platform': platform,
      });
      logger.d('플랫폼 정보 업데이트 성공: $platform');
      return true;
    } catch (e) {
      logger.e('플랫폼 정보 업데이트 오류: $e');
      return false;
    }
  }

  // 초대코드 업데이트 (기존 유저들을 위한 메서드)
  Future<bool> updateInviteCode(String uid, String inviteCode) async {
    try {
      await _firestore.doc('users/$uid').update({
        'inviteCode': inviteCode,
      });
      logger.d('초대코드 업데이트 성공: $inviteCode');
      return true;
    } catch (e) {
      logger.e('초대코드 업데이트 오류: $e');
      return false;
    }
  }

  // 광고 ID 업데이트 (기존 유저들을 위한 메서드)
  Future<bool> updateAdvertisingId(String uid, String adId) async {
    try {
      await _firestore.doc('users/$uid').update({
        'adId': adId,
      });
      logger.d('광고 ID 업데이트 성공: $adId');
      return true;
    } catch (e) {
      logger.e('광고 ID 업데이트 오류: $e');
      return false;
    }
  }

  Future<bool> changePassword(String oldPw, String newPw) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return false;

    final url = Uri.parse('https://changepassword-s4bul2i7dq-du.a.run.app');
    final res = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(
        {
          'nickname': currentUser.uid,
          'oldPassword': oldPw,
          'newPassword': newPw,
        },
      ),
    );

    if (res.statusCode == 200) {
      return true;
    } else if (res.statusCode == 401) {
      return false; // 기존 비번 불일치
    } else {
      throw Exception('changePw error ${res.statusCode}: ${res.body}');
    }
  }

  /// 적립 출처(source) 값 목록 - 출처별 통계용
  /// moneyTalk(머니톡톡) / moneyPang(머니팡팡) / roulette(행운룰렛) / dice(행운주사위)
  /// work(만보기) / attendance(출석체크) / autoEarn(자동적립) / invite(친구초대)
  /// bonus(보너스머니 전환) / offerwall_xxx(오퍼월 제휴사별) / etc(기타)
  Future<void> addEarning({
    required int amount, // 0이면 '돈' 갱신 생략
    int? luckyBagCount, // null → 변경 없음
    int? rewardRefillCount, // null → 변경 없음
    DateTime? ts,
    String source = 'etc', // ✅ 적립 출처 (기본값 etc - 기존 호출부 호환)
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        logger.d('addEarning: 로그인되지 않은 상태 - 저장 건너뜀');
        throw Exception('로그인이 필요합니다.');
      }

      final uid = user.uid;
      final now = ts ?? DateTime.now(); // 타임스탬프

      // ✅ 새벽 5시 기준 게임 날짜 계산 (Cloud Function 로직과 동일)
      // UTC를 기준으로 KST 계산 (UTC+9)
      final utcNow = now.toUtc();
      final kstNow = utcNow.add(const Duration(hours: 9)); // KST = UTC+9
      final gameDate = kstNow.hour < 5 ? kstNow.subtract(const Duration(days: 1)) : kstNow;

      final dateKey = DateFormat('yyyy-MM-dd').format(gameDate);
      final monthKey = DateFormat('yyyy-MM').format(gameDate);

      final dailyRef = _firestore.doc('users/$uid/daily/$dateKey');
      final monthlyRef = _firestore.doc('users/$uid/monthly/$monthKey');
      final userRef = _firestore.doc('users/$uid');

      // ✅ 랭킹 경로 추가
      final dailyRankRef = _firestore.doc('rankings/daily/$dateKey/$uid');
      final monthlyRankRef = _firestore.doc('rankings/monthly/$monthKey/$uid');

      // ───── 트랜잭션으로 변경하여 원자성 보장 ─────
      await _firestore.runTransaction((transaction) async {
        // 먼저 현재 유저 데이터를 읽어서 검증 (닉네임용)
        final userDoc = await transaction.get(userRef);
        if (!userDoc.exists) {
          throw Exception('사용자 문서가 존재하지 않습니다');
        }

        final userData = userDoc.data();
        if (userData == null) {
          throw Exception('사용자 데이터가 null입니다');
        }

        final nickname = userData['nickname'] as String? ?? uid; // 닉네임 가져오기

        // 이벤트 로그는 amount가 0보다 클 때만 생성
        if (amount > 0) {
          // 2) 일별 집계 (배열 + 합계 + 출처별 누적)
          transaction.set(
            dailyRef,
            {
              'dailyMoney': FieldValue.arrayUnion([
                {'amount': amount, 'ts': Timestamp.fromDate(now), 'source': source},
              ]), // 타임스탬프 포함으로 중복 허용
              'total': FieldValue.increment(amount), // 합계
              // ✅ 출처별 누적 (merge:true로 다른 출처 키는 보존됨)
              'bySource': {source: FieldValue.increment(amount)},
            },
            SetOptions(merge: true),
          );

          // 3) 월별 집계
          transaction.set(
            monthlyRef,
            {'monthMoney': FieldValue.increment(amount)},
            SetOptions(merge: true),
          );

          // ✅ 4) 일별 랭킹 업데이트
          transaction.set(
            dailyRankRef,
            {
              'score': FieldValue.increment(amount),
              'nickname': nickname,
            },
            SetOptions(merge: true),
          );

          // ✅ 5) 월별 랭킹 업데이트
          transaction.set(
            monthlyRankRef,
            {
              'score': FieldValue.increment(amount),
              'nickname': nickname,
            },
            SetOptions(merge: true),
          );
        }

        // 6) 유저 프로필 업데이트 - FieldValue.increment 사용
        final Map<String, dynamic> userUpdate = {};

        if (amount != 0) {
          userUpdate['money'] = FieldValue.increment(amount);
          userUpdate['totalEarnings'] = FieldValue.increment(amount);
        }

        if (luckyBagCount != null) userUpdate['luckyBagCount'] = luckyBagCount;
        if (rewardRefillCount != null) userUpdate['rewardRefillCount'] = rewardRefillCount;

        if (userUpdate.isNotEmpty) {
          transaction.update(userRef, userUpdate);
        }
      });
    } catch (e) {
      logger.e('addEarning 오류: $e');
      // 권한 오류 등은 무시
      if (e.toString().contains('permission-denied')) {
        logger.w('권한 오류 - 로그인이 필요합니다');
      }
    }
  }

  /// 오늘(새벽 5시 기준 게임 날짜) 적립 합계 조회 - 사이클 완주 모달 표시용
  /// 실패하거나 문서가 없으면 null (호출부에서 해당 줄을 생략)
  /// 오늘(게임 날짜 기준) 적립 합계 조회
  /// [source]를 주면 해당 출처만(bySource.{source}), 없으면 전체 합계(total)
  Future<int?> getTodayTotalEarnings({String? source}) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return null;

      // addEarning과 동일한 게임 날짜 계산 (KST 기준, 새벽 5시 경계)
      final kstNow = DateTime.now().toUtc().add(const Duration(hours: 9));
      final gameDate = kstNow.hour < 5 ? kstNow.subtract(const Duration(days: 1)) : kstNow;
      final dateKey = DateFormat('yyyy-MM-dd').format(gameDate);

      final doc = await _firestore.doc('users/${user.uid}/daily/$dateKey').get();
      if (!doc.exists) return null;

      // source가 지정되면 bySource.{source} 값만, 아니면 전체 합계(total)
      if (source != null) {
        final bySource = doc.data()?['bySource'] as Map<String, dynamic>?;
        return (bySource?[source] as num?)?.toInt();
      }
      return (doc.data()?['total'] as num?)?.toInt();
    } catch (e) {
      logger.e('오늘 적립 합계 조회 오류: $e');
      return null;
    }
  }

  Future<void> purchaseProduct({required int amount}) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        logger.d('addEarning: 로그인되지 않은 상태 - 저장 건너뜀');
        throw Exception('로그인이 필요합니다.');
      }

      final uid = user.uid;
      final userRef = _firestore.doc('users/$uid');

      await _firestore.runTransaction((transaction) async {
        final Map<String, dynamic> userUpdate = {};

        if (amount != 0) {
          userUpdate['money'] = FieldValue.increment(amount);
        }

        if (userUpdate.isNotEmpty) {
          transaction.update(userRef, userUpdate);
        }
      });
    } catch (e) {
      logger.e('addEarning 오류: $e');
      if (e.toString().contains('permission-denied')) {
        logger.w('권한 오류 - 로그인이 필요합니다');
      }
    }
  }

  // 보너스머니를 0으로 초기화
  Future<void> clearBonusMoney() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        logger.d('clearBonusMoney: 로그인되지 않은 상태');
        throw Exception('로그인이 필요합니다.');
      }

      final uid = user.uid;
      final userRef = _firestore.doc('users/$uid');

      await userRef.update({'bonusMoney': 0});

      logger.d('보너스머니 초기화 완료');
    } catch (e) {
      logger.e('보너스머니 초기화 오류: $e');
      throw e;
    }
  }

  Future<List<Map<String, dynamic>>> getDailyEarnings(String uid) async {
    try {
      final coll = _firestore.collection('users').doc(uid).collection('daily');

      final snaps = await coll.orderBy(FieldPath.documentId).get();
      final docs = snaps.docs.reversed;

      return docs.map((doc) {
        final date = doc.id; // yyyy-MM-dd
        final amt = (doc.data()['total'] ?? 0) as int;
        return {
          'date': date,
          'displayDate': date,
          'amount': amt,
        };
      }).toList();
    } catch (e) {
      print('일별 적립 데이터 조회 오류: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getMonthlyEarnings(String uid) async {
    try {
      final coll = _firestore.collection('users').doc(uid).collection('monthly');

      final snaps = await coll.orderBy(FieldPath.documentId).get();
      final docs = snaps.docs.reversed;

      return docs.map((doc) {
        final month = doc.id; // yyyy-MM
        final amt = (doc.data()['monthMoney'] ?? 0) as int;
        return {
          'month': month,
          'displayMonth': month,
          'amount': amt,
        };
      }).toList();
    } catch (e) {
      print('월별 적립 데이터 조회 오류: $e');
      return [];
    }
  }

  // 일별 랭킹 데이터 조회 (5분마다 갱신되는 캐시 문서 1개만 읽음)
  Future<List<Map<String, dynamic>>> getDailyRankings() async {
    try {
      // Firebase Auth 상태 확인
      if (_auth.currentUser == null) {
        print('로그인되지 않은 상태에서 랭킹 조회 시도');
        return [];
      }

      // 🚀 캐시 문서 1개만 읽음 (Cloud Function이 5분마다 미리 계산해둠)
      final cacheDoc = await _firestore.doc('rankingsCache/daily_current').get();

      if (!cacheDoc.exists) return [];

      final currentUid = _auth.currentUser?.uid;
      final rankings = (cacheDoc.data()?['rankings'] as List? ?? []).cast<Map<String, dynamic>>();

      return rankings.map((entry) {
        return {
          'rank': entry['rank'],
          'nickname': entry['nickname'] as String? ?? entry['uid'],
          'score': entry['score'] as int? ?? 0,
          'isCurrentUser': entry['uid'] == currentUid,
        };
      }).toList();
    } catch (e) {
      print('일별 랭킹 데이터 조회 오류: $e');
      // 권한 오류인 경우 빈 배열 반환
      if (e.toString().contains('permission-denied')) {
        print('권한 오류 - 로그인이 필요합니다');
      }
      return [];
    }
  }

  // 월별 랭킹 데이터 조회 (5분마다 갱신되는 캐시 문서 1개만 읽음)
  Future<List<Map<String, dynamic>>> getMonthlyRankings() async {
    try {
      // Firebase Auth 상태 확인
      if (_auth.currentUser == null) {
        print('로그인되지 않은 상태에서 랭킹 조회 시도');
        return [];
      }

      // 🚀 캐시 문서 1개만 읽음 (Cloud Function이 5분마다 미리 계산해둠)
      final cacheDoc = await _firestore.doc('rankingsCache/monthly_current').get();

      if (!cacheDoc.exists) {
        print('📊 월간 랭킹 캐시 데이터 없음');
        return [];
      }

      final currentUid = _auth.currentUser?.uid;
      final rankings = (cacheDoc.data()?['rankings'] as List? ?? []).cast<Map<String, dynamic>>();

      return rankings.map((entry) {
        return {
          'rank': entry['rank'],
          'nickname': entry['nickname'] as String? ?? entry['uid'],
          'score': entry['score'] as int? ?? 0,
          'isCurrentUser': entry['uid'] == currentUid,
        };
      }).toList();
    } catch (e) {
      print('월별 랭킹 데이터 조회 오류: $e');
      // 권한 오류인 경우 빈 배열 반환
      if (e.toString().contains('permission-denied')) {
        print('권한 오류 - 로그인이 필요합니다');
      }
      return [];
    }
  }

  // 회원 탈퇴 - Cloud Function 호출
  Future<bool> deleteAccount(String password) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return false;

      final uid = currentUser.uid;
      logger.d('회원 탈퇴 시작: $uid');

      // Cloud Function 호출
      final url = Uri.parse('https://deleteaccount-s4bul2i7dq-du.a.run.app');
      final res = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'uid': uid,
          'password': password,
        }),
      );

      if (res.statusCode == 200) {
        logger.d('회원 탈퇴 완료: $uid');
        return true;
      } else if (res.statusCode == 401) {
        logger.e('비밀번호 불일치');
        return false;
      } else {
        logger.e('회원 탈퇴 실패: ${res.statusCode}, ${res.body}');
        return false;
      }
    } catch (e) {
      logger.e('회원 탈퇴 오류: $e');
      return false;
    }
  }

  // 주문 번호로 단일 주문 조회
  Future<OrderHistory?> getOrderByOrderNumber(String orderNumber) async {
    try {
      logger.d('getOrderByOrderNumber 호출 - 주문번호: $orderNumber');

      final currentUser = _auth.currentUser;
      if (currentUser == null) return null;

      // ✅ 항상 서버에서 강제로 최신 사용자 데이터 가져오기
      final userDoc = await _firestore.collection(_collection).doc(currentUser.uid).get(const GetOptions(source: Source.server));

      if (!userDoc.exists) {
        logger.d('사용자 문서가 존재하지 않음');
        return null;
      }

      // User 객체로 변환
      final user = User.fromFirestore(userDoc);

      // orderHistory 배열에서 해당 주문번호 찾기
      final order = user.orderHistory.firstWhere(
            (order) => order.orderNumber == orderNumber,
        orElse: () => null as dynamic,
      );

      if (order != null) {
        logger.d('서버에서 가져온 주문 상태: ${order.status}');
      } else {
        logger.d('주문을 찾을 수 없음: $orderNumber');
      }

      return order;
    } catch (e) {
      logger.e('주문 조회 오류: $e');
      return null;
    }
  }

  // 자동적립 레벨 업데이트
  Future<bool> updateAutoEarnPigLevel(int level) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        logger.e('updateAutoEarnPigLevel: 로그인되지 않은 상태');
        return false;
      }

      await _firestore.doc('users/${currentUser.uid}').update({
        'autoEarnPigLevel': level,
      });

      logger.d('자동적립 레벨 업데이트 완료: Level $level');
      return true;
    } catch (e) {
      logger.e('자동적립 레벨 업데이트 오류: $e');
      return false;
    }
  }

  // 자동적립 레벨 업데이트 (Transaction 사용 - 서버 레벨 기준)
  Future<bool> updateAutoEarnPigLevelWithTransaction({
    required String userId,
    required int Function(int serverLevel) onUpdate,
  }) async {
    try {
      final userRef = _firestore.doc('users/$userId');

      await _firestore.runTransaction((transaction) async {
        // 1. 서버의 최신 레벨 조회
        final userDoc = await transaction.get(userRef);
        if (!userDoc.exists) {
          throw Exception('사용자 문서가 존재하지 않습니다: $userId');
        }

        final userData = userDoc.data();
        if (userData == null) {
          throw Exception('사용자 데이터가 null입니다: $userId');
        }

        final serverLevel = userData['autoEarnPigLevel'] as int? ?? 1;
        logger.d('🔍 서버 레벨 조회: $serverLevel');

        // 2. 콜백 함수를 통해 다음 레벨 결정
        final nextLevel = onUpdate(serverLevel);
        logger.d('🎯 업데이트할 레벨: $nextLevel');

        // 3. Transaction으로 레벨 업데이트
        transaction.update(userRef, {
          'autoEarnPigLevel': nextLevel,
        });
      });

      logger.d('✅ 자동적립 레벨 Transaction 업데이트 완료');
      return true;
    } catch (e) {
      logger.e('❌ 자동적립 레벨 Transaction 업데이트 오류: $e');
      return false;
    }
  }

  /// 리필 횟수 직접 설정 (구버전 시드 5→50 마이그레이션용)
  /// 성공 여부를 명확히 반환 - 실패 시 false (예외 삼키지 않고 결과 보장)
  Future<bool> setRewardRefillCount(int count) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        logger.e('setRewardRefillCount: 로그인되지 않은 상태');
        return false;
      }

      await _firestore.doc('users/${currentUser.uid}').update({
        'rewardRefillCount': count,
      });

      logger.d('rewardRefillCount 설정 완료: $count');
      return true;
    } catch (e) {
      logger.e('rewardRefillCount 설정 오류: $e');
      return false;
    }
  }

  // 저금통깨기 레벨 업데이트
  Future<bool> updatePigBankBreakLevel(int level) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        logger.e('updatePigBankBreakLevel: 로그인되지 않은 상태');
        return false;
      }

      await _firestore.doc('users/${currentUser.uid}').update({
        'pigBankBreakLevel': level,
      });

      logger.d('저금통깨기 레벨 업데이트 완료: Level $level');
      return true;
    } catch (e) {
      logger.e('저금통깨기 레벨 업데이트 오류: $e');
      return false;
    }
  }

  // purchaseValid 값 업데이트
  Future<bool> updatePurchaseValid(String uid, int value) async {
    try {
      await _firestore.doc('users/$uid').update({
        'purchaseValid': value,
      });
      logger.d('purchaseValid 업데이트 완료: $value');
      return true;
    } catch (e) {
      logger.e('purchaseValid 업데이트 오류: $e');
      return false;
    }
  }

  // invites 컬렉션에 의심 사용자 정보 저장
  Future<bool> saveToInvitesCollection({
    required String uid,
    required String nickname,
    required int inviteCount,
  }) async {
    try {
      await _firestore.doc('invites/$uid').set({
        'uid': uid,
        'nickname': nickname,
        'inviteCount': inviteCount,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'pending', // pending: 대기, approved: 승인, rejected: 거부
      });
      logger.d('invites 컬렉션에 저장 완료: $uid, $nickname, $inviteCount');
      return true;
    } catch (e) {
      logger.e('invites 컬렉션 저장 오류: $e');
      return false;
    }
  }

  // 친구 초대 보상 수령
  Future<bool> collectInviteReward(String uid, int friendIndex) async {
    try {
      // 1. 현재 사용자 데이터 가져오기
      final userDoc = await _firestore.doc('users/$uid').get(const GetOptions(source: Source.server));
      if (!userDoc.exists) {
        logger.e('사용자를 찾을 수 없습니다: $uid');
        return false;
      }

      final userData = userDoc.data()!;

      // 원본 JSON 배열을 직접 사용 (다른 필드 손실 방지)
      final rawList = (userData['inviteFriendList'] as List? ?? []).map((item) => Map<String, dynamic>.from(item as Map)).toList();

      // 2. 친구 인덱스 유효성 검사
      if (friendIndex < 0 || friendIndex >= rawList.length) {
        logger.e('유효하지 않은 친구 인덱스: $friendIndex');
        return false;
      }

      // 3. 이미 수령했는지 확인
      if (rawList[friendIndex]['isCollected'] == true) {
        logger.w('이미 수령한 보상입니다: 친구 $friendIndex');
        return false;
      }

      // 4. 보상 금액 계산 (1-10번째: 100,000~1,000,000, 11번째 이후: 300,000 고정)
      final rewardAmount = friendIndex < 10 ? (friendIndex + 1) * 100000 : 300000;

      // 5. 해당 항목만 isCollected를 true로 변경 (원본 필드 유지)
      rawList[friendIndex]['isCollected'] = true;

      // 6. addEarning을 사용하여 머니 추가 (일별/월별 집계 포함)
      await addEarning(amount: rewardAmount, source: 'invite');

      // 7. inviteFriendList 업데이트 (원본 필드 구조 유지)
      final userRef = _firestore.doc('users/$uid');
      await userRef.update({
        'inviteFriendList': rawList,
      });

      logger.d('친구 초대 보상 수령 완료: ${friendIndex + 1}번째 친구, ${rewardAmount}원');
      return true;
    } catch (e) {
      logger.e('친구 초대 보상 수령 오류: $e');
      return false;
    }
  }

  // 중복 적립 의심 사용자 검색 (dailyMoney에서 동일 amount가 연속 N회 이상)
  // 페이징으로 유저를 배치 단위 로드하여 OOM 방지
  Future<List<Map<String, dynamic>>> findDuplicateEarningUsers({
    required String startDate,
    required String endDate,
    int minConsecutive = 5,
    void Function(int current, int total)? onProgress,
  }) async {
    const batchSize = 30;
    final List<Map<String, dynamic>> flaggedUsers = [];
    int processed = 0;

    // 1. 전체 유저 수 먼저 파악 (count만 가져옴)
    final countSnapshot = await _firestore.collection('users').count().get();
    final total = countSnapshot.count ?? 0;

    if (total == 0) return flaggedUsers;

    // 2. 페이징으로 배치 단위 처리 (uid만으로 daily 조회 → 의심자만 유저 정보 조회)
    DocumentSnapshot? lastDoc;

    while (true) {
      // uid 기준 정렬, 배치 단위 조회
      Query query = _firestore.collection('users').orderBy(FieldPath.documentId).limit(batchSize);

      if (lastDoc != null) {
        query = query.startAfterDocument(lastDoc);
      }

      final batch = await query.get();
      if (batch.docs.isEmpty) break;

      lastDoc = batch.docs.last;

      for (final userDoc in batch.docs) {
        processed++;
        final uid = userDoc.id;

        onProgress?.call(processed, total);

        // 3. 해당 기간의 daily 문서만 조회 (가벼운 서브컬렉션)
        final dailySnapshot = await _firestore
            .collection('users/$uid/daily')
            .where(FieldPath.documentId, isGreaterThanOrEqualTo: startDate)
            .where(FieldPath.documentId, isLessThanOrEqualTo: endDate)
            .get();

        if (dailySnapshot.docs.isEmpty) continue;

        // 4. 각 날짜별 dailyMoney 배열에서 연속 동일 amount 검사
        int overallMaxConsecutive = 0;
        int? flaggedAmount;
        String? flaggedDate;
        int totalEntries = 0;

        for (final dailyDoc in dailySnapshot.docs) {
          final dailyMoney = dailyDoc.data()['dailyMoney'] as List?;
          if (dailyMoney == null || dailyMoney.length < minConsecutive) continue;

          // Map 타입 엔트리만 필터 (로그아웃 차감은 int로 들어감)
          final entries = dailyMoney.where((e) => e is Map).toList();
          totalEntries += entries.length;

          if (entries.length < minConsecutive) continue;

          int currentConsecutive = 1;

          for (int i = 1; i < entries.length; i++) {
            final prevAmount = (entries[i - 1] as Map)['amount'];
            final currAmount = (entries[i] as Map)['amount'];

            if (prevAmount != null && currAmount != null && prevAmount == currAmount) {
              currentConsecutive++;
              if (currentConsecutive > overallMaxConsecutive) {
                overallMaxConsecutive = currentConsecutive;
                flaggedAmount = currAmount is int ? currAmount : (currAmount as num).toInt();
                flaggedDate = dailyDoc.id;
              }
            } else {
              currentConsecutive = 1;
            }
          }
        }

        if (overallMaxConsecutive >= minConsecutive) {
          // 5. 의심 사용자만 유저 문서에서 필요한 필드 추출
          final userData = userDoc.data() as Map<String, dynamic>;
          final giftOrderHistory = userData['giftOrderHistory'] as List? ?? [];
          final rawTotalEarnings = userData['totalEarnings'] ?? 0;
          final rawMoney = userData['money'] ?? 0;
          final nickname = userData['nickname'] as String? ?? 'unknown';

          flaggedUsers.add({
            'nickname': nickname,
            'uid': uid,
            'giftOrderHistoryCount': giftOrderHistory.length,
            'totalEarnings': rawTotalEarnings is int ? rawTotalEarnings : (rawTotalEarnings as num).toInt(),
            'money': rawMoney is int ? rawMoney : (rawMoney as num).toInt(),
            'maxConsecutive': overallMaxConsecutive,
            'consecutiveAmount': flaggedAmount,
            'flaggedDate': flaggedDate,
            'totalEntries': totalEntries,
          });
        }
      }

      // 마지막 배치가 batchSize보다 적으면 종료
      if (batch.docs.length < batchSize) break;
    }

    // 연속 횟수 내림차순 정렬
    flaggedUsers.sort((a, b) => (b['maxConsecutive'] as int).compareTo(a['maxConsecutive'] as int));

    return flaggedUsers;
  }

  // IP 및 디바이스 차단 확인 (Cloud Function 호출)
  // 서버에서 요청 IP를 직접 확인하고, 차단 시 blockDeviceIdList에 추가
  Future<Map<String, dynamic>> checkPurchaseBlock(String deviceId, String uid) async {
    try {
      final url = Uri.parse('https://checkipblock-s4bul2i7dq-du.a.run.app');
      final response = await http
          .post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'uid': uid,
          'deviceId': deviceId,
        }),
      )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['blocked'] == true) {
          logger.w('IP 차단 감지: ${data['ip']} (uid: $uid, 일괄차단: ${data['blockedUsers']}명)');
        }
        return data;
      }

      return {'blocked': false};
    } catch (e) {
      logger.e('IP 차단 확인 오류: $e');
      return {'blocked': false};
    }
  }

  // deviceId 마이그레이션 - 기존 사용자의 deviceId가 없으면 서버에 등록
  Future<bool> migrateDeviceId(String deviceId) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        logger.e('migrateDeviceId: 로그인되지 않은 상태');
        return false;
      }

      // deviceId 유효성 검사
      if (deviceId.isEmpty || deviceId == 'unknown' || deviceId == 'null') {
        logger.w('migrateDeviceId: 유효하지 않은 deviceId');
        return false;
      }

      final uid = currentUser.uid;
      logger.d('deviceId 마이그레이션 시작: uid=$uid, deviceId=$deviceId');

      // Cloud Function 호출
      final url = 'https://asia-northeast3-cashbank-a1c93.cloudfunctions.net/migrateDeviceId';
      final res = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'uid': uid,
          'deviceId': deviceId,
        }),
      );

      if (res.statusCode == 200) {
        final responseData = jsonDecode(res.body);
        if (responseData['success'] == true) {
          logger.d('deviceId 마이그레이션 성공: ${responseData['message']}');
          return true;
        }
      }

      // 에러 응답 처리
      logger.w('deviceId 마이그레이션 응답: ${res.statusCode} - ${res.body}');
      return false;
    } catch (e) {
      logger.e('deviceId 마이그레이션 오류: $e');
      return false;
    }
  }
}