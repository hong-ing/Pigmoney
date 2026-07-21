import '../giftishow_api.dart';
import '../models/coupon_model.dart';

/// 비즈머니 관리 서비스
/// 
/// 기프티쇼 비즈머니 잔액 조회 및 관리를 담당하는 서비스 클래스
class BizMoneyService {
  final GiftishowApi _api;

  BizMoneyService(this._api);

  /// 비즈머니 잔액 조회
  /// 
  /// [userId]: 사용자 ID
  Future<BizMoneyResponse> getBizMoney(String userId) async {
    if (userId.isEmpty) {
      throw ArgumentError('userId cannot be empty');
    }

    return await _api.getBizMoney(userId);
  }

  /// 비즈머니 잔액 조회 (정수형 반환)
  /// 
  /// [userId]: 사용자 ID
  Future<int> getBizMoneyAmount(String userId) async {
    final response = await getBizMoney(userId);
    
    if (!response.isSuccess) {
      throw GiftishowException('Failed to fetch biz money: ${response.message}');
    }

    return response.balanceAmount;
  }

  /// 비즈머니 잔액 조회 (포맷팅된 문자열 반환)
  /// 
  /// [userId]: 사용자 ID
  Future<String> getFormattedBizMoney(String userId) async {
    final response = await getBizMoney(userId);
    
    if (!response.isSuccess) {
      throw GiftishowException('Failed to fetch biz money: ${response.message}');
    }

    return response.formattedBalance;
  }

  /// 구매 가능 여부 확인
  /// 
  /// [userId]: 사용자 ID
  /// [requiredAmount]: 필요한 금액
  Future<bool> canAfford(String userId, int requiredAmount) async {
    if (requiredAmount <= 0) {
      throw ArgumentError('requiredAmount must be greater than 0');
    }

    try {
      final currentBalance = await getBizMoneyAmount(userId);
      return currentBalance >= requiredAmount;
    } catch (e) {
      return false;
    }
  }

  /// 잔액 부족 금액 계산
  /// 
  /// [userId]: 사용자 ID
  /// [requiredAmount]: 필요한 금액
  /// 반환값: 부족한 금액 (0이면 충분함)
  Future<int> getShortfallAmount(String userId, int requiredAmount) async {
    if (requiredAmount <= 0) {
      throw ArgumentError('requiredAmount must be greater than 0');
    }

    try {
      final currentBalance = await getBizMoneyAmount(userId);
      final shortfall = requiredAmount - currentBalance;
      return shortfall > 0 ? shortfall : 0;
    } catch (e) {
      return requiredAmount; // 에러 시 전체 금액이 부족한 것으로 처리
    }
  }

  /// 비즈머니 상태 확인
  /// 
  /// [userId]: 사용자 ID
  Future<BizMoneyStatus> getBizMoneyStatus(String userId) async {
    try {
      final amount = await getBizMoneyAmount(userId);
      
      if (amount >= 100000) {
        return BizMoneyStatus.sufficient;
      } else if (amount >= 10000) {
        return BizMoneyStatus.moderate;
      } else if (amount > 0) {
        return BizMoneyStatus.low;
      } else {
        return BizMoneyStatus.empty;
      }
    } catch (e) {
      return BizMoneyStatus.error;
    }
  }

  /// 다중 상품 구매 가능 여부 확인
  /// 
  /// [userId]: 사용자 ID
  /// [items]: 구매하려는 상품들의 가격 목록
  Future<MultiPurchaseResult> canAffordMultiple(
    String userId,
    List<int> items,
  ) async {
    if (items.isEmpty) {
      throw ArgumentError('items cannot be empty');
    }

    final totalRequired = items.fold<int>(0, (sum, price) => sum + price);
    final currentBalance = await getBizMoneyAmount(userId);
    
    final affordableItems = <int>[];
    int runningTotal = 0;
    
    // 가격 순으로 정렬하여 최대한 많은 상품을 구매할 수 있도록
    final sortedItems = List<int>.from(items)..sort();
    
    for (final price in sortedItems) {
      if (runningTotal + price <= currentBalance) {
        affordableItems.add(price);
        runningTotal += price;
      }
    }

    return MultiPurchaseResult(
      canAffordAll: currentBalance >= totalRequired,
      totalRequired: totalRequired,
      currentBalance: currentBalance,
      affordableItems: affordableItems,
      shortfallAmount: totalRequired > currentBalance ? totalRequired - currentBalance : 0,
    );
  }

  /// 비즈머니 히스토리 시뮬레이션 (실제 API에서는 제공하지 않음)
  /// 실제 사용 시에는 클라이언트에서 거래 내역을 관리해야 함
  Future<List<BizMoneyTransaction>> getBizMoneyHistory(String userId) async {
    // 실제로는 API에서 제공하지 않으므로 로컬 저장소에서 조회해야 함
    // 여기서는 예시 구현
    throw UnimplementedError(
      'BizMoney history is not provided by the API. '
      'You need to track transactions locally in your app.',
    );
  }

  /// 예상 사용량 계산
  /// 
  /// [userId]: 사용자 ID
  /// [plannedPurchases]: 계획된 구매 목록
  Future<UsageProjection> calculateUsageProjection(
    String userId,
    List<int> plannedPurchases,
  ) async {
    final currentBalance = await getBizMoneyAmount(userId);
    final totalPlanned = plannedPurchases.fold<int>(0, (sum, price) => sum + price);
    final remainingAfterPurchases = currentBalance - totalPlanned;

    return UsageProjection(
      currentBalance: currentBalance,
      plannedSpending: totalPlanned,
      projectedBalance: remainingAfterPurchases,
      needsTopUp: remainingAfterPurchases < 0,
      recommendedTopUp: remainingAfterPurchases < 0 ? -remainingAfterPurchases : 0,
    );
  }
}

/// 비즈머니 상태 열거형
enum BizMoneyStatus {
  sufficient('충분'),
  moderate('보통'),
  low('부족'),
  empty('없음'),
  error('오류');

  const BizMoneyStatus(this.displayName);
  final String displayName;

  /// 상태에 따른 색상 (UI에서 활용)
  String get colorName {
    switch (this) {
      case BizMoneyStatus.sufficient:
        return 'green';
      case BizMoneyStatus.moderate:
        return 'yellow';
      case BizMoneyStatus.low:
        return 'orange';
      case BizMoneyStatus.empty:
        return 'red';
      case BizMoneyStatus.error:
        return 'gray';
    }
  }
}

/// 다중 구매 결과 모델
class MultiPurchaseResult {
  final bool canAffordAll;
  final int totalRequired;
  final int currentBalance;
  final List<int> affordableItems;
  final int shortfallAmount;

  const MultiPurchaseResult({
    required this.canAffordAll,
    required this.totalRequired,
    required this.currentBalance,
    required this.affordableItems,
    required this.shortfallAmount,
  });

  /// 구매 가능한 상품 개수
  int get affordableCount => affordableItems.length;

  /// 구매 가능한 상품들의 총 가격
  int get affordableTotal => affordableItems.fold<int>(0, (sum, price) => sum + price);

  /// 구매 후 남는 잔액
  int get remainingBalance => currentBalance - affordableTotal;
}

/// 사용량 예측 모델
class UsageProjection {
  final int currentBalance;
  final int plannedSpending;
  final int projectedBalance;
  final bool needsTopUp;
  final int recommendedTopUp;

  const UsageProjection({
    required this.currentBalance,
    required this.plannedSpending,
    required this.projectedBalance,
    required this.needsTopUp,
    required this.recommendedTopUp,
  });

  /// 포맷팅된 현재 잔액
  String get formattedCurrentBalance =>
      '${currentBalance.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}원';

  /// 포맷팅된 계획 지출
  String get formattedPlannedSpending =>
      '${plannedSpending.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}원';

  /// 포맷팅된 예상 잔액
  String get formattedProjectedBalance =>
      '${projectedBalance.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}원';
}

/// 비즈머니 거래 내역 모델 (로컬 관리용)
class BizMoneyTransaction {
  final String id;
  final DateTime timestamp;
  final BizMoneyTransactionType type;
  final int amount;
  final int balanceAfter;
  final String? description;
  final String? relatedTrId;

  const BizMoneyTransaction({
    required this.id,
    required this.timestamp,
    required this.type,
    required this.amount,
    required this.balanceAfter,
    this.description,
    this.relatedTrId,
  });

  /// 포맷팅된 금액
  String get formattedAmount {
    final prefix = type == BizMoneyTransactionType.spend ? '-' : '+';
    return '$prefix${amount.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}원';
  }

  /// 포맷팅된 잔액
  String get formattedBalance =>
      '${balanceAfter.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}원';
}

/// 비즈머니 거래 타입
enum BizMoneyTransactionType {
  spend('지출'),
  topup('충전'),
  refund('환불');

  const BizMoneyTransactionType(this.displayName);
  final String displayName;
}