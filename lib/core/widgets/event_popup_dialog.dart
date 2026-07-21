// event_popup_dialog.dart
// 이벤트 팝업 다이얼로그 위젯
// 2025-07-29

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pigmoney/core/firebase/event_popup_model.dart';
import 'package:pigmoney/presentation/provider/event_popup_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:velocity_x/velocity_x.dart';

/// 이벤트 팝업 다이얼로그 - 피그머니 앱 스타일에 맞는 깔끔한 디자인
class EventPopupDialog extends ConsumerStatefulWidget {
  final EventPopupModel popup;

  const EventPopupDialog({
    super.key,
    required this.popup,
  });

  @override
  ConsumerState<EventPopupDialog> createState() => _EventPopupDialogState();
}

class _EventPopupDialogState extends ConsumerState<EventPopupDialog> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutBack),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return FadeTransition(
          opacity: _fadeAnimation,
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: AlertDialog(
              backgroundColor: Colors.transparent,
              contentPadding: EdgeInsets.zero,
              content: Container(
                width: double.maxFinite,
                constraints: const BoxConstraints(maxWidth: 350, maxHeight: 680),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 헤더 영역 - 피그머니 돼지 테마
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(24, 20, 24, 10),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Colors.amber.shade400, Colors.amber.shade600],
                        ),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(20),
                          topRight: Radius.circular(20),
                        ),
                      ),
                      child: Column(
                        children: [
                          // 돼지 이모지와 함께 더 귀여운 아이콘
                          Container(
                            width: 65,
                            height: 65,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: Center(child: Image.asset('assets/icons/ic_pig_level_1.png').p(10)),
                          ),
                          const SizedBox(height: 8),
                          // 제목
                          widget.popup.title.text.size(17).bold.white.center.make().pSymmetric(h: 30),
                        ],
                      ),
                    ),

                    // 내용 영역 - 메시지 길이에 따라 자동 조정
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 메시지 - 길이에 따라 자동 조정, 최대 높이 제한 시에만 스크롤
                        if (widget.popup.message.isNotEmpty) ...[
                          Flexible(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                maxHeight: 300, // 메시지 최대 높이 제한
                              ),
                              child: Scrollbar(
                                thumbVisibility: true,
                                // 스크롤바 항상 표시
                                radius: const Radius.circular(4),
                                thickness: 4,
                                trackVisibility: false,
                                // 트랙은 숨김
                                child: SingleChildScrollView(
                                  padding: EdgeInsets.zero,
                                  child: widget.popup.message.text
                                      .size(15)
                                      .color(Colors.grey[700])
                                      .medium
                                      .make()
                                      .pOnly(top: 15, bottom: 10, right: 35, left: 35), // 스크롤바 공간 확보
                                ),
                              ),
                            ),
                          ),
                        ],

                        // 링크 표시 (링크가 있는 경우)
                        if (widget.popup.hasLink) ...[
                          InkWell(
                            onTap: () async {
                              final uri = Uri.parse(widget.popup.linkUrl);
                              if (await canLaunchUrl(uri)) {
                                await launchUrl(uri, mode: LaunchMode.externalApplication);
                              }
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.blue.shade200,
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.link,
                                    size: 18,
                                    color: Colors.blue.shade700,
                                  ),
                                  const SizedBox(width: 6),
                                  widget.popup.linkTitle.text.size(14).color(Colors.blue.shade700).semiBold.underline.make(),
                                ],
                              ),
                            ),
                          ).pOnly(left: 24, right: 24, top: 12),
                        ],
                      ],
                    ),

                    // 버튼 영역 - 하단 고정
                    Row(
                      children: [
                        // '다시 보지 않기' 버튼
                        TextButton(
                          onPressed: () async {
                            await _animationController.reverse();
                            if (mounted) {
                              ref.read(eventPopupProvider.notifier).dismissPopupPermanently();
                              Navigator.of(context).pop();
                            }
                          },
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            foregroundColor: Colors.grey.shade600,
                          ),
                          child: '다시 보지 않기'.text.size(15).semiBold.make(),
                        ).expand(),

                        12.widthBox,

                        // '확인' 버튼 - 피그머니 메인 컬러
                        ElevatedButton(
                          onPressed: () async {
                            await _animationController.reverse();
                            if (mounted) {
                              ref.read(eventPopupProvider.notifier).dismissPopup();
                              Navigator.of(context).pop();
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.amber,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            elevation: 2,
                            shadowColor: Colors.amber.withValues(alpha: 0.3),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: '확인'.text.size(15).bold.white.make(),
                        ).expand(),
                      ],
                    ).px(24).py(20),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 이벤트 팝업을 표시하는 헬퍼 함수
Future<void> showEventPopupDialog(BuildContext context, EventPopupModel popup) async {
  await showDialog(
    context: context,
    barrierDismissible: true, // 바깥쪽 터치로 닫기 가능
    builder: (BuildContext context) {
      return EventPopupDialog(popup: popup);
    },
  );
}
