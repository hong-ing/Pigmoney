class InviteFriend {
  final String ipAddress;      // IP 주소 (기존 adId 대체)
  final String nickname;       // 친구 닉네임
  final bool isCollected;      // 수령 여부
  final DateTime invitedAt;    // 초대 날짜

  InviteFriend({
    required this.ipAddress,
    required this.nickname,
    required this.isCollected,
    required this.invitedAt,
  });

  factory InviteFriend.fromJson(Map<String, dynamic> json) {
    // invitedAt 필드를 유연하게 처리
    DateTime parsedDate;
    final invitedAtField = json['invitedAt'];

    if (invitedAtField == null) {
      parsedDate = DateTime.now();
    } else if (invitedAtField is String) {
      // String 형태인 경우
      parsedDate = DateTime.parse(invitedAtField);
    } else {
      // Firestore Timestamp 형태인 경우
      try {
        // Timestamp 객체인 경우 toDate() 메서드 사용
        parsedDate = invitedAtField.toDate();
      } catch (e) {
        // 혹시 Map 형태로 왔을 경우 (seconds, nanoseconds)
        if (invitedAtField is Map && invitedAtField['seconds'] != null) {
          parsedDate = DateTime.fromMillisecondsSinceEpoch(
            invitedAtField['seconds'] * 1000
          );
        } else {
          parsedDate = DateTime.now();
        }
      }
    }

    return InviteFriend(
      // ipAddress 우선, 없으면 deviceId, 그것도 없으면 기존 adId 값 사용 (하위 호환성)
      ipAddress: json['ipAddress'] ?? json['deviceId'] ?? json['adId'] ?? '',
      nickname: json['nickname'] ?? '',
      isCollected: json['isCollected'] ?? false,
      invitedAt: parsedDate,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ipAddress': ipAddress,
      'nickname': nickname,
      'isCollected': isCollected,
      'invitedAt': invitedAt.toIso8601String(),
    };
  }

  InviteFriend copyWith({
    String? ipAddress,
    String? nickname,
    bool? isCollected,
    DateTime? invitedAt,
  }) {
    return InviteFriend(
      ipAddress: ipAddress ?? this.ipAddress,
      nickname: nickname ?? this.nickname,
      isCollected: isCollected ?? this.isCollected,
      invitedAt: invitedAt ?? this.invitedAt,
    );
  }
}