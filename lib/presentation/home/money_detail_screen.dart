import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:velocity_x/velocity_x.dart';

import '../../core/ads/admob_service.dart';
import '../provider/user_provider.dart';

class MoneyDetailScreen extends ConsumerStatefulWidget {
  const MoneyDetailScreen({super.key});

  @override
  ConsumerState<MoneyDetailScreen> createState() => _MoneyDetailScreenState();
}

class _MoneyDetailScreenState extends ConsumerState<MoneyDetailScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {});
      }
    });

    // 빌드가 완료된 후 데이터 로드
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _fetchEarningsData();
      }
    });
  }

  // 적립 데이터 갱신
  Future<void> _fetchEarningsData() async {
    final currentUser = ref.read(currentUserProvider);
    if (currentUser == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // 일별/월별 적립 데이터 갱신
      // ignore: unused_result
      ref.refresh(dailyEarningsProvider);
      // ignore: unused_result
      ref.refresh(monthlyEarningsProvider);
    } catch (e) {
      print('적립 데이터 로드 오류: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    admobService.disposeNativeAdByKey('money_detail_screen');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 현재 로그인한 사용자 정보
    final currentUser = ref.watch(currentUserProvider);

    if (currentUser == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }
    // 숫자 포맷터 (머니 표시용)
    final formatter = NumberFormat('#,###');
    final formattedMoney = formatter.format(currentUser.money);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Color(0xffE8ECF2),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            'BACK'.text.size(18).medium.black.make(),
            '$formattedMoney M'.text.size(18).medium.black.make(),
          ],
        ),
      ),
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            20.heightBox,

            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                minimumSize: Size(double.infinity, 60),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.0),
                ),
                elevation: 0,
              ),
              onPressed: () {},
              child: '누적합계  ${formatter.format(currentUser.totalEarnings)} M'.text.size(23).white.make().pSymmetric(v: 10),
            ).p(20),

            // 랭킹 탭
            SizedBox(
              height: 45,
              child: TabBar(
                controller: _tabController,
                indicatorColor: Colors.transparent,
                indicatorWeight: 0.1,
                dividerHeight: 0,
                dividerColor: Colors.transparent,
                tabs: [
                  _buildEarnTab(
                    text: '일별 적립(05시~)',
                    isSelected: _tabController.index == 0,
                  ),
                  _buildEarnTab(
                    text: '월별 적립',
                    isSelected: _tabController.index == 1,
                  ),
                ],
              ).pSymmetric(h: 4),
            ),

            // 적립 목록 (TabBarView)
            TabBarView(
              controller: _tabController,
              physics: NeverScrollableScrollPhysics(),
              children: [
                // 일별 적립 목록
                _buildDailyEarningsList(),

                // 월별 적립 목록
                _buildMonthlyEarningsList(),
              ],
            ).expand(),
          ],
        ),
      ),
    );
  }

  // 일별 적립 내역 위젯
  Widget _buildDailyEarningsList() {
    return Container(
      color: Colors.white,
      child: ref
          .watch(dailyEarningsProvider)
          .when(
            data: (earnings) {
              if (earnings.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      '일별 적립 내역이 없습니다.'.text.size(16).color(Colors.grey[700]!).make(),
                      20.heightBox,
                      ElevatedButton(
                        onPressed: _fetchEarningsData,
                        child: '새로고침'.text.make(),
                      ),
                    ],
                  ),
                );
              }

              return RefreshIndicator(
                onRefresh: _fetchEarningsData,
                child: ListView.builder(
                  padding: EdgeInsets.only(top: 8.0),
                  itemCount: earnings.length,
                  itemBuilder: (context, index) {
                    final earning = earnings[index];
                    final formatter = NumberFormat('#,###');

                    // 날짜 포맷팅
                    final dateStr = earning['date'] as String;
                    final dateParts = dateStr.split('-');
                    final displayDate = '${dateParts[0]}년 ${dateParts[1]}월 ${dateParts[2]}일';

                    return ListTile(
                      dense: true,
                      title: Text(
                        displayDate,
                        style: TextStyle(color: Colors.black87, fontSize: 15, fontWeight: FontWeight.normal),
                      ),
                      trailing: Text(
                        '${formatter.format(earning['amount'])}M',
                        style: TextStyle(color: Colors.red[700], fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    );
                  },
                ),
              );
            },
            loading: () => Center(child: CircularProgressIndicator()),
            error: (error, stack) => Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  '적립 내역을 불러오는 중 오류가 발생했습니다.'.text.size(16).color(Colors.grey[700]!).make(),
                  20.heightBox,
                  ElevatedButton(
                    onPressed: _fetchEarningsData,
                    child: '다시 시도'.text.make(),
                  ),
                ],
              ),
            ),
          ),
    ).pSymmetric(h: 20);
  }

  // 월별 적립 내역 위젯
  Widget _buildMonthlyEarningsList() {
    return Container(
      color: Colors.white,
      child: ref
          .watch(monthlyEarningsProvider)
          .when(
            data: (earnings) {
              if (earnings.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      '월별 적립 내역이 없습니다.'.text.size(16).color(Colors.grey[700]!).make(),
                      20.heightBox,
                      ElevatedButton(
                        onPressed: _fetchEarningsData,
                        child: '새로고침'.text.make(),
                      ),
                    ],
                  ),
                );
              }

              return RefreshIndicator(
                onRefresh: _fetchEarningsData,
                child: ListView.builder(
                  padding: EdgeInsets.only(top: 8.0),
                  itemCount: earnings.length,
                  itemBuilder: (context, index) {
                    final earning = earnings[index];
                    final formatter = NumberFormat('#,###');

                    // 날짜 포맷팅
                    final monthStr = earning['month'] as String;
                    final monthParts = monthStr.split('-');
                    final displayMonth = '${monthParts[0]}년 ${monthParts[1]}월';

                    return ListTile(
                      dense: true,
                      title: Text(
                        displayMonth,
                        style: TextStyle(color: Colors.black87, fontSize: 15, fontWeight: FontWeight.normal),
                      ),
                      trailing: Text(
                        '${formatter.format(earning['amount'])}M',
                        style: TextStyle(color: Colors.red[700], fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    );
                  },
                ),
              );
            },
            loading: () => Center(child: CircularProgressIndicator()),
            error: (error, stack) => Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  '적립 내역을 불러오는 중 오류가 발생했습니다.'.text.size(16).color(Colors.grey[700]!).make(),
                  20.heightBox,
                  ElevatedButton(
                    onPressed: _fetchEarningsData,
                    child: '다시 시도'.text.make(),
                  ),
                ],
              ),
            ),
          ),
    ).pSymmetric(h: 20);
  }

  // 탭 버튼 생성
  Widget _buildEarnTab({required String text, required bool isSelected}) {
    return Tab(
      child: Container(
        width: double.infinity,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Color(0xFF3A3A3A),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(12.0),
            topRight: Radius.circular(12.0),
          ),
        ),
        child: Text(
          text,
          style: TextStyle(color: isSelected ? Colors.black : Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
        ),
      ),
    );
  }
}
