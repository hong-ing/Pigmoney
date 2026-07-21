import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;

class KoreanTimeUtils {
  static late tz.Location _koreaLocation;
  static bool _initialized = false;

  /// 한국 시간 초기화
  static Future<void> initialize() async {
    if (_initialized) return;
    
    tz.initializeTimeZones();
    _koreaLocation = tz.getLocation('Asia/Seoul');
    _initialized = true;
  }

  /// 현재 한국 시간 반환
  static tz.TZDateTime getNow() {
    if (!_initialized) {
      throw Exception('KoreanTimeUtils가 초기화되지 않았습니다. initialize()를 먼저 호출하세요.');
    }
    return tz.TZDateTime.now(_koreaLocation);
  }

  /// 로컬 DateTime을 한국시간 TZDateTime으로 변환
  static tz.TZDateTime convertToKoreanTime(DateTime localDateTime) {
    if (!_initialized) {
      throw Exception('KoreanTimeUtils가 초기화되지 않았습니다. initialize()를 먼저 호출하세요.');
    }
    
    // 로컬 시간을 UTC로 변환한 후 한국시간으로 변환
    final utcDateTime = localDateTime.toUtc();
    return tz.TZDateTime.from(utcDateTime, _koreaLocation);
  }

  /// 현재 한국시간을 로컬 DateTime으로 반환 (저장용)
  static DateTime getNowAsLocalTime() {
    if (!_initialized) {
      throw Exception('KoreanTimeUtils가 초기화되지 않았습니다. initialize()를 먼저 호출하세요.');
    }
    
    final koreanNow = tz.TZDateTime.now(_koreaLocation);
    // 한국시간을 로컬 시간대로 변환하여 반환
    return koreanNow.toLocal();
  }

  /// ✅ 수정: 한국시간을 문자열로 직접 저장 (시간대 변환 제거)
  static String getNowAsKoreanDateString() {
    if (!_initialized) {
      throw Exception('KoreanTimeUtils가 초기화되지 않았습니다. initialize()를 먼저 호출하세요.');
    }
    
    final koreanNow = tz.TZDateTime.now(_koreaLocation);
    return '${koreanNow.year}-${koreanNow.month.toString().padLeft(2, '0')}-${koreanNow.day.toString().padLeft(2, '0')} ${koreanNow.hour.toString().padLeft(2, '0')}:${koreanNow.minute.toString().padLeft(2, '0')}:${koreanNow.second.toString().padLeft(2, '0')}';
  }

  /// ✅ 수정: 한국시간 문자열을 TZDateTime으로 파싱
  static tz.TZDateTime parseKoreanDateString(String dateString) {
    if (!_initialized) {
      throw Exception('KoreanTimeUtils가 초기화되지 않았습니다. initialize()를 먼저 호출하세요.');
    }
    
    try {
      final parts = dateString.split(' ');
      final dateParts = parts[0].split('-');
      final timeParts = parts[1].split(':');
      
      return tz.TZDateTime(
        _koreaLocation,
        int.parse(dateParts[0]), // year
        int.parse(dateParts[1]), // month
        int.parse(dateParts[2]), // day
        int.parse(timeParts[0]), // hour
        int.parse(timeParts[1]), // minute
        int.parse(timeParts[2]), // second
      );
    } catch (e) {
      print('한국시간 문자열 파싱 오류: $e, dateString: $dateString');
      // 파싱 실패 시 현재 한국시간 반환
      return tz.TZDateTime.now(_koreaLocation);
    }
  }

  /// 초기화 작업 시간인지 확인 (4시 55분 ~ 5시 5분)
  static bool isMaintenanceTime() {
    final now = getNow();
    final hour = now.hour;
    final minute = now.minute;
    
    // 4시 55분 ~ 5시 5분 사이인지 확인
    if (hour == 4 && minute >= 55) {
      return true; // 4시 55분 ~ 4시 59분
    } else if (hour == 5 && minute <= 5) {
      return true; // 5시 0분 ~ 5시 5분
    }
    
    return false;
  }

  /// 다음 초기화 시간(4시 55분)까지 남은 시간 계산
  static Duration timeUntilNextMaintenance() {
    final now = getNow();
    
    // 오늘 4시 55분
    var nextMaintenance = tz.TZDateTime(
      _koreaLocation,
      now.year,
      now.month,
      now.day,
      4,
      55,
    );
    
    // 현재 시간이 이미 4시 55분을 지났다면 다음날 4시 55분
    if (now.isAfter(nextMaintenance)) {
      nextMaintenance = nextMaintenance.add(const Duration(days: 1));
    }
    
    return nextMaintenance.difference(now);
  }

  /// 한국 시간을 문자열로 포맷팅
  static String formatKoreanTime(tz.TZDateTime dateTime) {
    return '${dateTime.hour.toString().padLeft(2, '0')}:'
        '${dateTime.minute.toString().padLeft(2, '0')}:'
        '${dateTime.second.toString().padLeft(2, '0')}';
  }

  // =================== 리셋 시간 관리 (새벽 5시) ===================
  
  /// 현재 게임 날짜 키 반환 (새벽 5시 기준)
  /// 예: 새벽 4시 -> 전날, 새벽 6시 -> 당일
  static String getCurrentGameDateKey() {
    final now = getNow();
    final gameDate = now.hour < 5 
        ? now.subtract(const Duration(days: 1))  // 새벽 5시 이전이면 전날로 계산
        : now;  // 새벽 5시 이후면 당일로 계산
    
    return '${gameDate.year}-${gameDate.month.toString().padLeft(2, '0')}-${gameDate.day.toString().padLeft(2, '0')}';
  }
  
  /// 두 시간이 같은 게임 날짜인지 확인 (새벽 5시 기준)
  static bool isSameGameDay(tz.TZDateTime time1, tz.TZDateTime time2) {
    final gameDate1 = time1.hour < 5 
        ? time1.subtract(const Duration(days: 1))
        : time1;
        
    final gameDate2 = time2.hour < 5 
        ? time2.subtract(const Duration(days: 1))
        : time2;
    
    return gameDate1.year == gameDate2.year &&
           gameDate1.month == gameDate2.month &&
           gameDate1.day == gameDate2.day;
  }
  
  /// 다음 리셋 시간(새벽 5시)까지 남은 시간 계산
  static Duration timeUntilNextReset() {
    final now = getNow();
    
    // 오늘 새벽 5시
    var nextReset = tz.TZDateTime(
      _koreaLocation,
      now.year,
      now.month,
      now.day,
      5,
      0,
    );
    
    // 현재 시간이 이미 새벽 5시를 지났다면 다음날 새벽 5시
    if (now.isAfter(nextReset)) {
      nextReset = nextReset.add(const Duration(days: 1));
    }
    
    return nextReset.difference(now);
  }

  // =================== 테스트용 메서드들 (배포 시 제거) ===================
  
  /// 테스트용: 현재 시간 기준 1분 후를 초기화 시간으로 설정
  static bool isMaintenanceTimeTest() {
    final now = getNow();
    final testMaintenanceStart = now.add(const Duration(minutes: 1));
    final testMaintenanceEnd = now.add(const Duration(minutes: 2));
    
    return now.isAfter(testMaintenanceStart) && now.isBefore(testMaintenanceEnd);
  }
  
  /// 테스트용: 1분 후까지의 시간 반환
  static Duration timeUntilNextMaintenanceTest() {
    final now = getNow();
    final nextMaintenance = now.add(const Duration(minutes: 1));
    return nextMaintenance.difference(now);
  }
} 