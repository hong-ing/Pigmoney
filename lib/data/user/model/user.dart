// lib/data/user/model/user.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../../gift_order/model/gift_order.dart';
import '../../order/model/order.dart';
import 'invite_friend.dart';

class User {
  final String uid;
  final String nickname;
  final String passwordHash;
  final String inviteCode;
  final String adId;
  final String deviceId;
  int money;
  int bonusMoney;
  int totalEarnings;
  int autoEarnPigLevel;
  int pigBankBreakLevel;
  int pincruxMoney;
  int myChipsMoney;
  int snapPlayMoney;
  int snapPlayRouletteMoney;
  int snapPlayDiceMoney;
  int gmotechMoney;
  final DateTime joinDate;
  final List<OrderHistory> orderHistory;
  final List<GiftOrderHistory> giftOrderHistory;
  DateTime? lastAccessTime;
  int luckyBagCount;
  int rewardRefillCount;
  Map<String, dynamic>? attendanceData; // 출석체크 데이터
  final String resetVersion; // 추가: 서버 리셋 버전 (yyyy-MM-dd 형태)
  final List<InviteFriend> inviteFriendList; // 초대한 친구 목록
  int purchaseValid; // 구매 검증 상태: 0=승인(기본값), 1=대기(관리자 확인 필요), 2=영구승인
  int deviceChangeCount; // 기기 변경 횟수: 0=변경없음, 1+=변경이력있음 (3회까지 허용)
  final String? ipAddress; // 사용자 IP 주소
  final String appVersion; // 앱 버전 (예: "2.5.3+112")
  final String platform; // 플랫폼 구분: "AOS"(Android) | "iOS" | ""(미설정)

  // Kakao login fields
  final String? kakaoId;
  final String? accountEmail;
  final bool isKakao; // 'kakao' or 'nickname'

  // Google login fields
  final String? googleId;
  final bool isGoogle;

  // Apple login fields
  final String? appleId;
  final bool isApple;

  User({
    required this.uid,
    required this.nickname,
    required this.passwordHash,
    required this.inviteCode,
    required this.adId,
    this.deviceId = '',
    required this.money,
    required this.joinDate,
    this.bonusMoney = 0,
    this.totalEarnings = 0,
    this.autoEarnPigLevel = 1,
    this.pigBankBreakLevel = 0,
    this.pincruxMoney = 0,
    this.myChipsMoney = 0,
    this.snapPlayMoney = 0,
    this.snapPlayRouletteMoney = 0,
    this.snapPlayDiceMoney = 0,
    this.gmotechMoney = 0,
    this.orderHistory = const [],
    this.giftOrderHistory = const [],
    this.lastAccessTime,
    this.luckyBagCount = 200,
    int rewardRefillCount = 50,
    this.attendanceData,
    String? resetVersion,
    this.inviteFriendList = const [],
    this.kakaoId,
    this.accountEmail,
    required this.isKakao,
    this.googleId,
    this.isGoogle = false,
    this.appleId,
    this.isApple = false,
    this.purchaseValid = 0,
    this.deviceChangeCount = 0,
    this.ipAddress,
    this.appVersion = '',
    this.platform = '',
  }) : rewardRefillCount = _capRewardRefillCount(rewardRefillCount),
       resetVersion = resetVersion ?? _getKoreanDateString();

  // 한국 시간 기준으로 기본값 생성
  static String _getKoreanDateString() {
    final now = DateTime.now().toUtc().add(Duration(hours: 9));
    return DateFormat('yyyy-MM-dd').format(now);
  }

  // rewardRefillCount를 50으로 제한하는 방어 코드 (50회차 시스템)
  static int _capRewardRefillCount(int count) {
    if (count > 50) {
      return 50;
    }
    return count;
  }

  factory User.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    List<OrderHistory> orders = [];
    if (data['orderHistory'] != null) {
      orders = (data['orderHistory'] as List).map((item) => OrderHistory.fromJson(item)).toList();
    }

    List<GiftOrderHistory> giftOrders = [];
    if (data['giftOrderHistory'] != null) {
      giftOrders = (data['giftOrderHistory'] as List).map((item) => GiftOrderHistory.fromJson(item)).toList();
    }

    // 마지막 접속 시간 파싱
    DateTime? lastAccessTime;
    if (data['lastAccessTime'] != null) {
      lastAccessTime = (data['lastAccessTime'] as Timestamp).toDate();
    }

    // 출석체크 데이터 파싱
    Map<String, dynamic>? attendanceData;
    if (data['attendanceData'] != null) {
      attendanceData = data['attendanceData'] as Map<String, dynamic>;
    }

    // 초대한 친구 목록 파싱
    List<InviteFriend> inviteFriendList = [];
    if (data['inviteFriendList'] != null) {
      inviteFriendList = (data['inviteFriendList'] as List).map((item) => InviteFriend.fromJson(item)).toList();
    }

    // ✅ money가 null인 경우만 0으로, 명시적인 0은 유지
    int parsedMoney = 0;
    if (data['money'] != null) {
      parsedMoney = data['money'] is int ? data['money'] : (data['money'] as num).toInt();
    }

    return User(
      uid: doc.id,
      nickname: data['nickname'] ?? '',
      passwordHash: data['passwordHash'] ?? '',
      inviteCode: data['inviteCode'] ?? '',
      adId: data['adId'] ?? '',
      deviceId: data['deviceId'] ?? '',
      money: parsedMoney,
      bonusMoney: data['bonusMoney'] ?? 0,
      totalEarnings: data['totalEarnings'] ?? 0,
      autoEarnPigLevel: data['autoEarnPigLevel'] ?? 1,
      pigBankBreakLevel: data['pigBankBreakLevel'] ?? 0,
      pincruxMoney: data['pincruxMoney'] ?? 0,
      myChipsMoney: data['myChipsMoney'] ?? 0,
      snapPlayMoney: data['snapPlayMoney'] ?? 0,
      snapPlayRouletteMoney: data['snapPlayRouletteMoney'] ?? 0,
      snapPlayDiceMoney: data['snapPlayDiceMoney'] ?? 0,
      gmotechMoney: data['gmotechMoney'] ?? 0,
      joinDate: (data['joinDate'] as Timestamp).toDate(),
      orderHistory: orders,
      giftOrderHistory: giftOrders,
      lastAccessTime: lastAccessTime,
      luckyBagCount: data['luckyBagCount'] ?? 0,
      rewardRefillCount: _capRewardRefillCount(data['rewardRefillCount'] ?? 50),
      attendanceData: attendanceData,
      resetVersion: data['resetVersion'] ?? _getKoreanDateString(),
      inviteFriendList: inviteFriendList,
      kakaoId: data['kakaoId'],
      accountEmail: data['accountEmail'],
      isKakao: data['isKakao'] ?? false,
      googleId: data['googleId'],
      isGoogle: data['isGoogle'] ?? false,
      appleId: data['appleId'],
      isApple: data['isApple'] ?? false,
      purchaseValid: data['purchaseValid'] ?? 0,
      deviceChangeCount: data['deviceChangeCount'] ?? 0,
      ipAddress: data['ipAddress'],
      appVersion: data['appVersion'] ?? '',
      platform: data['platform'] ?? '',
    );
  }

  factory User.fromJson(Map<String, dynamic> json) => User(
    uid: json['uid'] as String,
    nickname: json['nickname'] as String,
    passwordHash: json['passwordHash'] as String,
    inviteCode: json['inviteCode'] as String,
    adId: json['adId'] as String,
    deviceId: (json['deviceId'] ?? '') as String,
    money: (json['money'] as num).toInt(),
    bonusMoney: (json['bonusMoney'] ?? 0) as int,
    totalEarnings: (json['totalEarnings'] ?? 0) as int,
    autoEarnPigLevel: (json['autoEarnPigLevel'] ?? 1) as int,
    pigBankBreakLevel: (json['pigBankBreakLevel'] ?? 0) as int,
    pincruxMoney: (json['pincruxMoney'] ?? 0) as int,
    myChipsMoney: (json['myChipsMoney'] ?? 0) as int,
    snapPlayMoney: (json['snapPlayMoney'] ?? 0) as int,
    snapPlayRouletteMoney: (json['snapPlayRouletteMoney'] ?? 0) as int,
    snapPlayDiceMoney: (json['snapPlayDiceMoney'] ?? 0) as int,
    gmotechMoney: (json['gmotechMoney'] ?? 0) as int,
    joinDate: (json['joinDate'] as Timestamp).toDate(),
    orderHistory: (json['orderHistory'] as List<dynamic>? ?? []).map((e) => OrderHistory.fromJson(e as Map<String, dynamic>)).toList(),
    giftOrderHistory: (json['giftOrderHistory'] as List<dynamic>? ?? [])
        .map((e) => GiftOrderHistory.fromJson(e as Map<String, dynamic>))
        .toList(),
    lastAccessTime: json['lastAccessTime'] != null ? (json['lastAccessTime'] as Timestamp).toDate() : null,
    luckyBagCount: (json['luckyBagCount'] ?? 0) as int,
    rewardRefillCount: _capRewardRefillCount((json['rewardRefillCount'] ?? 50) as int),
    attendanceData: json['attendanceData'] as Map<String, dynamic>?,
    resetVersion: json['resetVersion'] ?? _getKoreanDateString(),
    inviteFriendList: (json['inviteFriendList'] as List<dynamic>? ?? [])
        .map((e) => InviteFriend.fromJson(e as Map<String, dynamic>))
        .toList(),
    kakaoId: json['kakaoId'] as String?,
    accountEmail: json['accountEmail'] as String?,
    isKakao: (json['isKakao'] ?? false) as bool,
    googleId: json['googleId'] as String?,
    isGoogle: (json['isGoogle'] ?? false) as bool,
    appleId: json['appleId'] as String?,
    isApple: (json['isApple'] ?? false) as bool,
    purchaseValid: (json['purchaseValid'] ?? 0) as int,
    deviceChangeCount: (json['deviceChangeCount'] ?? 0) as int,
    ipAddress: json['ipAddress'] as String?,
    appVersion: (json['appVersion'] ?? '') as String,
    platform: (json['platform'] ?? '') as String,
  );

  Map<String, dynamic> toJson() => {
    'uid': uid,
    'nickname': nickname,
    'passwordHash': passwordHash,
    'inviteCode': inviteCode,
    'adId': adId,
    'deviceId': deviceId,
    'money': money,
    'bonusMoney': bonusMoney,
    'totalEarnings': totalEarnings,
    'autoEarnPigLevel': autoEarnPigLevel,
    'pigBankBreakLevel': pigBankBreakLevel,
    'pincruxMoney': pincruxMoney,
    'myChipsMoney': myChipsMoney,
    'snapPlayMoney': snapPlayMoney,
    'snapPlayRouletteMoney': snapPlayRouletteMoney,
    'snapPlayDiceMoney': snapPlayDiceMoney,
    'gmotechMoney': gmotechMoney,
    'joinDate': Timestamp.fromDate(joinDate),
    'orderHistory': orderHistory.map((e) => e.toJson()).toList(),
    'giftOrderHistory': giftOrderHistory.map((e) => e.toJson()).toList(),
    'lastAccessTime': lastAccessTime != null ? Timestamp.fromDate(lastAccessTime!) : null,
    'luckyBagCount': luckyBagCount,
    'rewardRefillCount': rewardRefillCount,
    'attendanceData': attendanceData,
    'resetVersion': resetVersion,
    'inviteFriendList': inviteFriendList.map((e) => e.toJson()).toList(),
    'kakaoId': kakaoId,
    'accountEmail': accountEmail,
    'isKakao': isKakao,
    'googleId': googleId,
    'isGoogle': isGoogle,
    'appleId': appleId,
    'isApple': isApple,
    'purchaseValid': purchaseValid,
    'deviceChangeCount': deviceChangeCount,
    'ipAddress': ipAddress,
    'appVersion': appVersion,
    'platform': platform,
  };

  User copyWith({
    String? uid,
    String? nickname,
    String? passwordHash,
    String? inviteCode,
    String? adId,
    String? deviceId,
    int? money,
    int? bonusMoney,
    int? totalEarnings,
    int? autoEarnPigLevel,
    int? pigBankBreakLevel,
    int? pincruxMoney,
    int? myChipsMoney,
    int? snapPlayMoney,
    int? snapPlayRouletteMoney,
    int? snapPlayDiceMoney,
    int? gmotechMoney,
    DateTime? joinDate,
    List<OrderHistory>? orderHistory,
    List<GiftOrderHistory>? giftOrderHistory,
    DateTime? lastAccessTime,
    int? luckyBagCount,
    int? rewardRefillCount,
    Map<String, dynamic>? attendanceData,
    String? resetVersion,
    List<InviteFriend>? inviteFriendList,
    String? kakaoId,
    String? accountEmail,
    String? phoneNumber,
    bool? isKakao,
    String? googleId,
    bool? isGoogle,
    String? appleId,
    bool? isApple,
    int? purchaseValid,
    int? deviceChangeCount,
    String? ipAddress,
    String? appVersion,
    String? platform,
  }) => User(
    uid: uid ?? this.uid,
    nickname: nickname ?? this.nickname,
    passwordHash: passwordHash ?? this.passwordHash,
    inviteCode: inviteCode ?? this.inviteCode,
    adId: adId ?? this.adId,
    deviceId: deviceId ?? this.deviceId,
    money: money ?? this.money,
    bonusMoney: bonusMoney ?? this.bonusMoney,
    totalEarnings: totalEarnings ?? this.totalEarnings,
    autoEarnPigLevel: autoEarnPigLevel ?? this.autoEarnPigLevel,
    pigBankBreakLevel: pigBankBreakLevel ?? this.pigBankBreakLevel,
    pincruxMoney: pincruxMoney ?? this.pincruxMoney,
    myChipsMoney: myChipsMoney ?? this.myChipsMoney,
    snapPlayMoney: snapPlayMoney ?? this.snapPlayMoney,
    snapPlayRouletteMoney: snapPlayRouletteMoney ?? this.snapPlayRouletteMoney,
    snapPlayDiceMoney: snapPlayDiceMoney ?? this.snapPlayDiceMoney,
    gmotechMoney: gmotechMoney ?? this.gmotechMoney,
    joinDate: joinDate ?? this.joinDate,
    orderHistory: orderHistory ?? this.orderHistory,
    giftOrderHistory: giftOrderHistory ?? this.giftOrderHistory,
    lastAccessTime: lastAccessTime ?? this.lastAccessTime,
    luckyBagCount: luckyBagCount ?? this.luckyBagCount,
    rewardRefillCount: rewardRefillCount != null ? _capRewardRefillCount(rewardRefillCount) : this.rewardRefillCount,
    attendanceData: attendanceData ?? this.attendanceData,
    resetVersion: resetVersion ?? this.resetVersion,
    inviteFriendList: inviteFriendList ?? this.inviteFriendList,
    kakaoId: kakaoId ?? this.kakaoId,
    accountEmail: accountEmail ?? this.accountEmail,
    isKakao: isKakao ?? this.isKakao,
    googleId: googleId ?? this.googleId,
    isGoogle: isGoogle ?? this.isGoogle,
    appleId: appleId ?? this.appleId,
    isApple: isApple ?? this.isApple,
    purchaseValid: purchaseValid ?? this.purchaseValid,
    deviceChangeCount: deviceChangeCount ?? this.deviceChangeCount,
    ipAddress: ipAddress ?? this.ipAddress,
    appVersion: appVersion ?? this.appVersion,
    platform: platform ?? this.platform,
  );
}
