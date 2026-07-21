import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:velocity_x/velocity_x.dart';

import '../../core/services/deep_link_service.dart';
import '../../core/utils/advertising_id_helper.dart';
import '../../core/utils/invite_code_generator.dart';
import '../../core/widgets/user_data_builder.dart';
import '../../data/user/model/invite_friend.dart';
import '../../data/user/user_repository.dart';
import '../provider/user_provider.dart';

class FriendInviteScreen extends ConsumerStatefulWidget {
  const FriendInviteScreen({super.key});

  @override
  ConsumerState<FriendInviteScreen> createState() => _FriendInviteScreenState();
}

class _FriendInviteScreenState extends ConsumerState<FriendInviteScreen> with TickerProviderStateMixin {
  final NumberFormat _currencyFormat = NumberFormat.decimalPattern('ko_KR');
  final UserRepository _userRepository = UserRepository();
  bool _isLoading = false;

  // 애니메이션 컨트롤러들을 리스트로 관리
  late List<AnimationController> _animationControllers;
  late List<Animation<double>> _scaleAnimations;

  @override
  void initState() {
    super.initState();

    // 무제한 개의 버튼에 대한 애니메이션 컨트롤러 초기화 (무제한 친구 초대 지원)
    _animationControllers = List.generate(
      200,
      (index) => AnimationController(duration: const Duration(milliseconds: 1000), vsync: this),
    );

    // 스케일 애니메이션 초기화
    _scaleAnimations = _animationControllers.map((controller) {
      return Tween<double>(
        begin: 1.0,
        end: 1.12,
      ).animate(
        CurvedAnimation(
          parent: controller,
          curve: Curves.easeInOut,
        ),
      );
    }).toList();

    // 화면 진입 시 초대코드 및 광고 ID 체크
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndGenerateInviteCode();
      _checkAndUpdateAdvertisingId();
    });
  }

  @override
  void dispose() {
    // 애니메이션 컨트롤러들 정리
    for (var controller in _animationControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  // 초대코드 체크 및 생성 (기존 유저를 위한 로직)
  Future<void> _checkAndGenerateInviteCode() async {
    final currentUser = ref.read(currentUserProvider);
    if (currentUser == null) return;

    // 초대코드가 없거나 빈 문자열인 경우
    if (currentUser.inviteCode.isEmpty) {
      // 초대코드 생성
      final inviteCode = InviteCodeGenerator.generateInviteCode(currentUser.nickname);

      // DB에 저장
      final success = await _userRepository.updateInviteCode(currentUser.uid, inviteCode);

      if (success) {
        // 로컬 상태 업데이트
        await ref.read(currentUserProvider.notifier).refreshUserData();
        print('초대코드 생성 및 저장 완료: $inviteCode');
      } else {
        print('초대코드 저장 실패');
      }
    }
  }

  // 광고 ID 체크 및 업데이트 (기존 유저를 위한 로직)
  Future<void> _checkAndUpdateAdvertisingId() async {
    final currentUser = ref.read(currentUserProvider);
    if (currentUser == null) return;

    // 광고 ID가 없거나 빈 문자열인 경우
    if (currentUser.adId.isEmpty) {
      // 광고 ID 가져오기
      final adId = await AdvertisingIdHelper.getAdvertisingId();

      // 유효한 광고 ID인 경우만 저장
      if (AdvertisingIdHelper.isValidAdvertisingId(adId)) {
        // DB에 저장
        final success = await _userRepository.updateAdvertisingId(currentUser.uid, adId);

        if (success) {
          // 로컬 상태 업데이트
          await ref.read(currentUserProvider.notifier).refreshUserData();
          print('광고 ID 생성 및 저장 완료: $adId');
        } else {
          print('광고 ID 저장 실패');
        }
      } else {
        print('유효하지 않은 광고 ID: $adId');
      }
    } else {
      print('기존 광고 ID 존재: ${currentUser.adId}');
    }
  }

  // 초대코드만 복사 (코드 옆 아이콘용)
  void _copyInviteCode(String code) {
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('초대코드가 복사되었습니다'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  // 공유 메시지 전체 복사 (링크 복사하기 버튼용)
  void _copyShareMessage(String code) {
    final inviteLink = DeepLinkService().generateInviteLink(code);
    final shareText =
        '쉽고 재미있게 용돈 버는 앱테크, 피그머니! 지금 가입하면 300,000머니 즉시 적립!\n'
        '*초대코드: $code\n'
        '▼지금 다운로드▼\n'
        '$inviteLink';
    Clipboard.setData(ClipboardData(text: shareText));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('초대 메시지가 복사되었습니다'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  // 링크 공유하기
  void _shareInviteLink(String code) {
    final inviteLink = DeepLinkService().generateInviteLink(code);
    final shareText =
        '쉽고 재미있게 용돈 버는 앱테크, 피그머니! 지금 가입하면 300,000머니 즉시 적립!\n'
        '*초대코드: $code\n'
        '▼지금 다운로드▼\n'
        '$inviteLink';
    Share.share(shareText, subject: '피그머니 친구 초대');
  }

  // 수령 버튼 빌더 (애니메이션 유무와 관계없이 공통 사용)
  Widget _buildCollectButton(String uid, int index, int reward) {
    return GestureDetector(
      onTap: !_isLoading
          ? () async {
              // 로딩 상태 시작
              setState(() {
                _isLoading = true;
              });

              // 보상 수령 처리
              final success = await _userRepository.collectInviteReward(
                uid,
                index,
              );

              if (success) {
                // 애니메이션 중지 (200명 이내인 경우)
                if (index < _animationControllers.length) {
                  _animationControllers[index].stop();
                  _animationControllers[index].reset();
                }

                // 상태 업데이트
                await ref.read(currentUserProvider.notifier).refreshUserData();

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('${_currencyFormat.format(reward)} 머니를 받았습니다!'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              } else {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('보상 수령에 실패했습니다'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              }

              // 로딩 상태 종료
              if (mounted) {
                setState(() {
                  _isLoading = false;
                });
              }
            }
          : null,
      child: Container(
        width: 140,
        padding: EdgeInsets.symmetric(vertical: 3),
        decoration: BoxDecoration(
          color: Color(0xFFFFC107),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Color(0xFFFFC107).withOpacity(0.4),
              blurRadius: 8,
              spreadRadius: 2,
            ),
          ],
        ),
        child: '${_currencyFormat.format(reward)} M'.text.size(15).fontFamily('BMJUA').center.color(Colors.grey[850]).make(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return UserDataBuilder(
      builder: (context, user, animatedMoney) {
        // 초대코드: DB에 저장된 값 사용, 없으면 생성된 값 사용
        final inviteCode = user.inviteCode.isNotEmpty ? user.inviteCode : InviteCodeGenerator.generateInviteCode(user.nickname);

        // Friend list with rewards (11 base slots + 300,000 for each additional friend)
        final friendRewards = [
          100000, // 1st friend
          200000, // 2nd friend
          300000, // 3rd friend
          400000, // 4th friend
          500000, // 5th friend
          600000, // 6th friend
          700000, // 7th friend
          800000, // 8th friend
          900000, // 9th friend
          1000000, // 10th friend
          300000, // 11th friend (무제한 친구 초대 시작)
        ];

        // 실제 초대한 친구 목록
        final invitedFriends = user.inviteFriendList;
        final invitedCount = invitedFriends.length;

        // 11명 이상의 친구를 위한 보상 계산 함수
        int getRewardForIndex(int index) {
          if (index < friendRewards.length) {
            return friendRewards[index];
          }
          return 300000; // 12번째 친구부터는 30만 머니 고정
        }

        // 표시할 슬롯 개수 계산 (기본 11개, 12번째부터는 실제 친구 수만큼)
        final totalSlots = invitedCount > 11 ? invitedCount : 11;

        // 애니메이션 시작/중지 처리 (최대 200명까지 애니메이션 지원)
        for (int i = 0; i < totalSlots && i < _animationControllers.length; i++) {
          if (i < invitedFriends.length && !invitedFriends[i].isCollected) {
            // 수령 가능한 상태면 애니메이션 시작
            if (!_animationControllers[i].isAnimating) {
              _animationControllers[i].repeat();
            }
          } else {
            // 그 외의 경우 애니메이션 중지
            if (_animationControllers[i].isAnimating) {
              _animationControllers[i].stop();
              _animationControllers[i].reset();
            }
          }
        }

        return Stack(
          children: [
            Scaffold(
              backgroundColor: Colors.black,
              body: SafeArea(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      // White container with main content
                      Container(
                        margin: EdgeInsets.all(20),
                        padding: EdgeInsets.symmetric(vertical: 30, horizontal: 15),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          children: [
                            // Header pig icon
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Image.asset('assets/icons/ic_friend_pig_header.png', width: 70, height: 70),
                                '피그머니 친구초대'.text.size(27).fontFamily('SsangmunDong').black.make(),
                              ],
                            ),

                            // Subtitle
                            '친구를 초대할수록'.text.size(25).fontFamily('BMJUA').black.make(),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                '눈덩이처럼'.text.size(25).fontFamily('BMJUA').letterSpacing(-0.2).heightSnug.color(Colors.red).make(),
                                ' 불어나는 보상!'.text.size(25).fontFamily('BMJUA').letterSpacing(-0.2).heightSnug.black.make(),
                              ],
                            ),
                            SizedBox(height: 30),

                            // Reward stages
                            Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Image.asset('assets/icons/ic_friend_pig_on.png', width: 40, height: 40),
                                    SizedBox(width: 10),
                                    '1명 초대시 '.text.size(21).fontFamily('BMJUA').black.make(),
                                    '100,000 M'.text.size(21).fontFamily('BMJUA').color(Colors.red).make(),
                                  ],
                                ),
                                SizedBox(height: 5),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Image.asset('assets/icons/ic_friend_pig_on.png', width: 40, height: 40),
                                    SizedBox(width: 10),
                                    '2명 초대시 '.text.size(21).fontFamily('BMJUA').black.make(),
                                    '+200,000 M'.text.size(21).fontFamily('BMJUA').color(Colors.red).make(),
                                  ],
                                ),
                                SizedBox(height: 8),
                                '•'.text.size(16).color(Colors.grey[900]).heightRelaxed.make(),
                                '•'.text.size(16).color(Colors.grey[900]).heightRelaxed.make(),
                                '•'.text.size(16).color(Colors.grey[900]).heightRelaxed.make(),
                                SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Image.asset('assets/icons/ic_friend_pig_on.png', width: 40, height: 40),
                                    SizedBox(width: 10),
                                    '10명 초대시 '.text.size(21).fontFamily('BMJUA').black.make(),
                                    '+1,000,000 M'.text.size(21).fontFamily('BMJUA').color(Colors.red).make(),
                                  ],
                                ),
                              ],
                            ),
                            SizedBox(height: 30),

                            // Max reward text
                            '10명 = 550만 M!'.text.size(33).fontFamily('SsangmunDong').color(Colors.red).make(),
                            '이후 1인당 +30만 M(무제한)'.text.size(20).fontFamily('BMJUA').color(Colors.orange).make(),
                            SizedBox(height: 8),
                            '*초대받은 친구는 30만 머니 즉시 적립!'.text.size(16).fontFamily('BMJUA').color(Colors.grey[700]).make(),
                          ],
                        ),
                      ),

                      SizedBox(height: 10),
                      // Invite code section - 새로운 디자인
                      Container(
                        margin: EdgeInsets.symmetric(horizontal: 20),
                        padding: EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.grey[600]!, width: 1),
                        ),
                        child: Column(
                          children: [
                            // 초대코드 + 복사 아이콘 행
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                '내 초대코드'.text.size(18).fontFamily('BMJUA').white.make(),
                                SizedBox(width: 15),
                                inviteCode.text.size(22).fontFamily('BMJUA').bold.white.make(),
                                SizedBox(width: 10),
                                GestureDetector(
                                  onTap: () => _copyInviteCode(inviteCode),
                                  child: Icon(Icons.content_copy, size: 22, color: Colors.white),
                                ),
                              ],
                            ),
                            SizedBox(height: 20),
                            // 링크 복사하기 / 링크 공유하기 버튼
                            Row(
                              children: [
                                // 링크 복사하기 버튼 (노란색)
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () => _copyShareMessage(inviteCode),
                                    child: Container(
                                      padding: EdgeInsets.symmetric(vertical: 16),
                                      decoration: BoxDecoration(
                                        color: Color(0xFFFFC107),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: '링크 복사하기'.text.size(18).fontFamily('BMJUA').black.center.make(),
                                    ),
                                  ),
                                ),
                                SizedBox(width: 12),
                                // 링크 공유하기 버튼 (빨간색)
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () => _shareInviteLink(inviteCode),
                                    child: Container(
                                      padding: EdgeInsets.symmetric(vertical: 16),
                                      decoration: BoxDecoration(
                                        color: Color(0xFFFF5252),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: '링크 공유하기'.text.size(18).fontFamily('BMJUA').white.center.make(),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 30),

                      // Friend status section
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          '친구 $invitedCount명'.text.size(18).bold.amber400.make().centered(),
                          SizedBox(height: 15),

                          // Friend list (기본 11개 슬롯 + 12번째부터 동적 생성)
                          ...List.generate(totalSlots, (index) {
                            bool hasInvitedFriend = index < invitedFriends.length;
                            InviteFriend? friend = hasInvitedFriend ? invitedFriends[index] : null;
                            final reward = getRewardForIndex(index);

                            return Container(
                              margin: EdgeInsets.only(bottom: 10),
                              child: Row(
                                children: [
                                  Image.asset(
                                    hasInvitedFriend ? 'assets/icons/ic_friend_pig_on.png' : 'assets/icons/ic_friend_pig_off.png',
                                    width: 35,
                                    height: 35,
                                  ),
                                  SizedBox(width: 15),
                                  Expanded(
                                    child: hasInvitedFriend
                                        ? friend!.nickname.text.size(18).fontFamily('BMJUA').white.make()
                                        : '친구 ${index + 1}'.text.size(18).fontFamily('BMJUA').color(Colors.grey).make(),
                                  ),
                                  // 수령 가능한 버튼 처리
                                  hasInvitedFriend && !friend!.isCollected
                                      ? (index < _animationControllers.length
                                            // 200명 이하: 애니메이션 있는 수령 버튼
                                            ? AnimatedBuilder(
                                                animation: _scaleAnimations[index],
                                                builder: (context, child) {
                                                  return Transform.scale(
                                                    scale: _scaleAnimations[index].value,
                                                    child: child,
                                                  );
                                                },
                                                child: _buildCollectButton(user.uid, index, reward),
                                              )
                                            // 200명 초과: 애니메이션 없는 수령 버튼
                                            : _buildCollectButton(user.uid, index, reward))
                                      : GestureDetector(
                                          onTap: null,
                                          child: Container(
                                            width: 140,
                                            padding: EdgeInsets.symmetric(vertical: 3),
                                            decoration: BoxDecoration(
                                              color: hasInvitedFriend ? Color(0xFFFF5252) : Color(0xFF757575),
                                              borderRadius: BorderRadius.circular(20),
                                            ),
                                            child: (hasInvitedFriend ? '수령완료' : '${_currencyFormat.format(reward)} M').text
                                                .size(15)
                                                .fontFamily('BMJUA')
                                                .center
                                                .color(hasInvitedFriend ? Colors.white : Colors.grey[850])
                                                .make(),
                                          ),
                                        ),
                                ],
                              ),
                            );
                          }),

                          // 무제한 친구초대 안내 텍스트
                          SizedBox(height: 10),
                          '(무제한 친구초대)'.text.size(16).fontFamily('BMJUA').color(Colors.grey).make().centered(),
                        ],
                      ).pSymmetric(h: 20),
                      SizedBox(height: 30),

                      // Bottom information text
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                '• 초대코드는 '.text.size(16).letterSpacing(-0.1).medium.white.make(),
                                '회원가입시'.text.size(16).medium.letterSpacing(-0.1).color(Colors.amber).make(),
                                '에만 입력할 수 있어요.'.text.size(16).letterSpacing(-0.1).medium.white.make(),
                              ],
                            ),
                            SizedBox(height: 30),
                            Row(
                              children: [
                                '• 초대코드는 '.text.size(16).medium.letterSpacing(-0.1).white.make(),
                                '딱 한번'.text.size(16).medium.letterSpacing(-0.1).color(Color(0xFFFFC107)).make(),
                                '만 입력할 수 있어요. (탈퇴 후'.text.size(16).medium.letterSpacing(-0.1).white.make(),
                              ],
                            ),
                            SizedBox(height: 5),
                            '재가입 포함)'.text.size(16).medium.letterSpacing(-0.1).white.make(),
                            SizedBox(height: 30),
                            '• 친구초대 보상은 당사 사정에 의해 사전 공지 없이'.text.size(16).medium.letterSpacing(-0.1).white.make(),
                            '보상이 변경되거나 종료될 수 있어요.'.text.size(16).medium.letterSpacing(-0.1).white.make(),
                          ],
                        ),
                      ),
                      SizedBox(height: 50),
                    ],
                  ),
                ),
              ),
            ),
            // 로딩 오버레이
            if (_isLoading)
              Container(
                color: Colors.black54,
                child: Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFFC107)),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
