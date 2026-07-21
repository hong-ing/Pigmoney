import 'package:pigmoney/core/utils/korean_time_utils.dart';

// ──────────────────────────────────Enums & Models───────────────────────────────────

enum AttendanceStatus { pending, active, completed, missed, allCompleted }

enum CoinType { none, bronze, silver, gold }

extension CoinTypeX on CoinType {
  String get assetPath {
    switch (this) {
      case CoinType.bronze:
        return 'assets/icons/ic_bronze_coin.png';
      case CoinType.silver:
        return 'assets/icons/ic_silver_coin.png';
      case CoinType.gold:
        return 'assets/icons/ic_gold_coin.png';
      case CoinType.none:
        return 'assets/icons/ic_random_coin.png'; // placeholder
    }
  }
}

class AttendanceSlotData {
  final String id; // unique per day (e.g. 'morning-20250613')
  final String timeName; // 아침, 점심…
  final String timeRangeLabel; // "7-9시" …
  final int startHour; // inclusive, local time
  final int endHour; // exclusive
  AttendanceStatus status;
  CoinType coinType;
  int reward; // 머니

  AttendanceSlotData({
    required this.id,
    required this.timeName,
    required this.timeRangeLabel,
    required this.startHour,
    required this.endHour,
    this.status = AttendanceStatus.pending,
    this.coinType = CoinType.none,
    this.reward = 0,
  });

  // 완료 여부 확인 getter
  // 완료 여부 확인 getter - allCompleted도 완료로 처리
  bool get isCompleted => status == AttendanceStatus.completed || status == AttendanceStatus.allCompleted;

  // JSON 직렬화
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'timeName': timeName,
      'timeRangeLabel': timeRangeLabel,
      'startHour': startHour,
      'endHour': endHour,
      'status': status.index,
      'coinType': coinType.index,
      'reward': reward,
    };
  }

  // JSON 역직렬화
  factory AttendanceSlotData.fromJson(Map<String, dynamic> json) {
    return AttendanceSlotData(
      id: json['id'] as String? ?? '',
      timeName: json['timeName'] as String? ?? '',
      timeRangeLabel: json['timeRangeLabel'] as String? ?? '',
      startHour: json['startHour'] as int? ?? 0,
      endHour: json['endHour'] as int? ?? 0,
      status: AttendanceStatus.values[(json['status'] as int?) ?? 0],
      coinType: CoinType.values[(json['coinType'] as int?) ?? 0],
      reward: json['reward'] as int? ?? 0,
    );
  }
}

// 출석체크 데이터 모델 (User 모델의 attendanceData 필드에 저장)
class AttendanceData {
  final List<AttendanceSlotData> slots; // 출석체크 슬롯 데이터
  final bool showAllClearCelebration; // ALL 출석 축하 배너 표시 여부

  AttendanceData({
    required this.slots,
    this.showAllClearCelebration = false,
  });

  // JSON 직렬화
  Map<String, dynamic> toJson() {
    return {
      'slots': slots.map((slot) => slot.toJson()).toList(),
      'showAllClearCelebration': showAllClearCelebration,
    };
  }

  // JSON 역직렬화
  factory AttendanceData.fromJson(Map<String, dynamic> json) {
    // null 안전 처리 추가
    final slotsData = json['slots'];
    List<AttendanceSlotData> slots = [];
    
    if (slotsData != null && slotsData is List) {
      // 중복 방지를 위한 Set
      final processedIds = <String>{};
      
      for (var slotJson in slotsData) {
        if (slotJson is Map<String, dynamic>) {
          try {
            final slot = AttendanceSlotData.fromJson(slotJson);
            // ID 중복 체크
            if (!processedIds.contains(slot.id)) {
              slots.add(slot);
              processedIds.add(slot.id);
            }
          } catch (e) {
            // 개별 슬롯 파싱 실패 시 건너뛰기
            print('슬롯 파싱 오류: $e');
          }
        }
      }
    }
    
    // 슬롯이 비어있거나 3개가 아닌 경우 새로 생성
    if (slots.isEmpty || slots.length != 3) {
      final newData = AttendanceData.createNew();
      slots = newData.slots;
    }
    
    return AttendanceData(
      slots: slots,
      showAllClearCelebration: json['showAllClearCelebration'] as bool? ?? false,
    );
  }

  // 새로운 출석체크 데이터 생성
  factory AttendanceData.createNew() {
    // ✅ 한국시간 기준 게임 날짜 키 사용 (새벽 5시 기준)
    final gameDate = KoreanTimeUtils.getCurrentGameDateKey();

    return AttendanceData(
      slots: [
        AttendanceSlotData(id: 'morning-$gameDate', timeName: '아침', timeRangeLabel: '07-10시', startHour: 7, endHour: 10),
        AttendanceSlotData(id: 'dinner-$gameDate', timeName: '저녁', timeRangeLabel: '19-22시', startHour: 19, endHour: 22),
        AttendanceSlotData(
          id: 'all-$gameDate',
          timeName: '완벽출석',
          timeRangeLabel: '한번더!',
          startHour: 0,
          endHour: 0,
          status: AttendanceStatus.pending,
        )
      ],
      showAllClearCelebration: false,
    );
  }
}
