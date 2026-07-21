import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../provider/user_provider.dart';

class DuplicateEarningCheckScreen extends ConsumerStatefulWidget {
  const DuplicateEarningCheckScreen({super.key});

  @override
  ConsumerState<DuplicateEarningCheckScreen> createState() =>
      _DuplicateEarningCheckScreenState();
}

class _DuplicateEarningCheckScreenState
    extends ConsumerState<DuplicateEarningCheckScreen> {
  bool _isScanning = false;
  bool _isDone = false;
  int _current = 0;
  int _total = 0;
  List<Map<String, dynamic>> _flaggedUsers = [];
  String? _errorMessage;

  final String _startDate = '2026-01-30';
  final String _endDate = '2026-02-17';
  final int _minConsecutive = 5;

  Future<void> _startScan() async {
    setState(() {
      _isScanning = true;
      _isDone = false;
      _current = 0;
      _total = 0;
      _flaggedUsers = [];
      _errorMessage = null;
    });

    try {
      final repository = ref.read(userRepositoryProvider);
      final results = await repository.findDuplicateEarningUsers(
        startDate: _startDate,
        endDate: _endDate,
        minConsecutive: _minConsecutive,
        onProgress: (current, total) {
          if (mounted) {
            setState(() {
              _current = current;
              _total = total;
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _flaggedUsers = results;
          _isScanning = false;
          _isDone = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isScanning = false;
          _isDone = true;
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat('#,###');

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16213E),
        title: const Text(
          '중복 적립 검증',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          // 검색 조건 카드
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF16213E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '검증 조건',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                _buildInfoRow('기간', '$_startDate ~ $_endDate'),
                const SizedBox(height: 4),
                _buildInfoRow('기준', '동일 amount 연속 $_minConsecutive회 이상'),
                const SizedBox(height: 4),
                _buildInfoRow('대상', 'dailyMoney 배열 (일별)'),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isScanning ? null : _startScan,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      disabledBackgroundColor: Colors.grey,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _isScanning
                        ? const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              ),
                              SizedBox(width: 12),
                              Text(
                                '스캔 중...',
                                style: TextStyle(
                                    color: Colors.white, fontSize: 16),
                              ),
                            ],
                          )
                        : const Text(
                            '스캔 시작',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),

          // 진행 상태
          if (_isScanning && _total > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  LinearProgressIndicator(
                    value: _current / _total,
                    backgroundColor: Colors.white12,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(Colors.amber),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$_current / $_total 사용자 검사 중...',
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),

          // 에러 메시지
          if (_errorMessage != null)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.redAccent),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error, color: Colors.redAccent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),

          // 결과 요약
          if (_isDone && _errorMessage == null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _flaggedUsers.isEmpty
                    ? Colors.green.withOpacity(0.2)
                    : Colors.red.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _flaggedUsers.isEmpty
                      ? Colors.greenAccent
                      : Colors.redAccent,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _flaggedUsers.isEmpty
                        ? Icons.check_circle
                        : Icons.warning_amber_rounded,
                    color: _flaggedUsers.isEmpty
                        ? Colors.greenAccent
                        : Colors.redAccent,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _flaggedUsers.isEmpty
                        ? '의심 사용자가 없습니다. (총 $_total명 검사)'
                        : '${_flaggedUsers.length}명의 의심 사용자 발견! (총 $_total명 검사)',
                    style: TextStyle(
                      color: _flaggedUsers.isEmpty
                          ? Colors.greenAccent
                          : Colors.redAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 8),

          // 결과 리스트
          Expanded(
            child: _flaggedUsers.isEmpty
                ? const SizedBox.shrink()
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _flaggedUsers.length,
                    itemBuilder: (context, index) {
                      final user = _flaggedUsers[index];
                      return _buildUserCard(user, index, formatter);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 50,
          child: Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 14),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
        ),
      ],
    );
  }

  Widget _buildUserCard(
      Map<String, dynamic> user, int index, NumberFormat formatter) {
    final maxConsecutive = user['maxConsecutive'] as int;
    final consecutiveAmount = user['consecutiveAmount'] as int?;
    final flaggedDate = user['flaggedDate'] as String?;
    final nickname = user['nickname'] as String;
    final giftCount = user['giftOrderHistoryCount'] as int;
    final totalEarnings = user['totalEarnings'] as int;
    final money = user['money'] as int;
    final totalEntries = user['totalEntries'] as int;

    // 위험도 색상
    Color severityColor;
    String severityLabel;
    if (maxConsecutive >= 20) {
      severityColor = Colors.red;
      severityLabel = '매우 높음';
    } else if (maxConsecutive >= 10) {
      severityColor = Colors.orange;
      severityLabel = '높음';
    } else {
      severityColor = Colors.yellow;
      severityLabel = '주의';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF16213E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: severityColor.withOpacity(0.5)),
      ),
      child: Column(
        children: [
          // 헤더
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: severityColor.withOpacity(0.15),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: severityColor,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    nickname,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: severityColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    severityLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 중복 정보
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: Colors.red.withOpacity(0.08),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.repeat, color: Colors.redAccent, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      '동일 금액 연속 $maxConsecutive회',
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
                if (consecutiveAmount != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '반복 금액: ${formatter.format(consecutiveAmount)}M  |  발생일: $flaggedDate',
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ),
                Text(
                  '기간 내 총 적립 횟수: $totalEntries건',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),

          // 사용자 정보
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildDetailRow(
                  Icons.card_giftcard,
                  '기프티콘 주문',
                  '$giftCount건',
                  giftCount > 0 ? Colors.amber : Colors.white70,
                ),
                const SizedBox(height: 8),
                _buildDetailRow(
                  Icons.trending_up,
                  '총 적립금 (totalEarnings)',
                  '${formatter.format(totalEarnings)}M',
                  Colors.white,
                ),
                const SizedBox(height: 8),
                _buildDetailRow(
                  Icons.account_balance_wallet,
                  '현재 잔액 (money)',
                  '${formatter.format(money)}M',
                  Colors.greenAccent,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(
      IconData icon, String label, String value, Color valueColor) {
    return Row(
      children: [
        Icon(icon, color: Colors.white38, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 14),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
      ],
    );
  }
}
