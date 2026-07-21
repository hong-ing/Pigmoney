import 'dart:io';

import 'package:flutter/material.dart';
import 'package:velocity_x/velocity_x.dart';

// Data class for FAQ items
class FAQItem {
  FAQItem({
    required this.question,
    required this.answer,
    this.isExpanded = false,
  });

  String question;
  String answer;
  bool isExpanded;
}

class FAQScreen extends StatefulWidget {
  const FAQScreen({super.key});

  @override
  State<FAQScreen> createState() => _FAQScreenState();
}

class _FAQScreenState extends State<FAQScreen> {
  // Sample FAQ data - replace with your actual data

  final List<FAQItem> _faqItems = [
    FAQItem(
      question: '1. 피그머니는 무엇인가요?',
      answer: '피그머니는 머니톡톡과 머니팡팡 게임 및 만보기 등을 통해 머니를 모아 모바일 상품권이나 실물 상품(금,은) 등으로 교환할 수 있는 리워드앱입니다.',
    ),
    FAQItem(
      question: '2. 머니는 어떻게 적립하나요?',
      answer:
          '[하나] 출석체크 동전뽑기\n하루 2+1번 출석보상 GET!\n아침·저녁 출석을 모두 완료하면 행운의 동전뽑기 기회가 한번더!\n[둘] 자동적립\n홈화면의 돼지를 터치해 자동적립 시작!\n레벨이 높을수록 최대 5시간까지, 자동으로 머니가 쌓여요.\n[셋] 행운룰렛/주사위\n매일 무료 룰렛과 주사위로 머니를 획득하세요.\n미션을 통해 티켓을 모으면 추가 참여기회를 얻을 수 있습니다.\n[넷] 만보기\n건강도 챙기고 머니도 챙기고!\n하루 10회, 기본보상+걸음수보상을 얻을 수 있는 피그머니만의 특별한 보물상자를 열어보세요!\n[다섯] 머니톡톡\n동전을 터치해 머니를 모으세요!\n리필로 최대 50회까지 동전을 저장해두고, 원할 때 꺼내 쓸 수 있어요.\n리필을 많이 할수록 채워지는 속도는 느려집니다.\n[여섯] 머니팡팡\n저금통을 깨뜨려서 머니를 모으세요!\n저금통을 터치해서 내구도가 0이 되면 머니를 얻을 수 있어요.\n단계가 높아질수록 저금통 내구도가 높아지지만, 그만큼 더 많은 머니를 얻을 수 있습니다.\n[일곱] 적립 메뉴\n핑크/민트/브론즈/실버/골드저금통에서 다양한 미션과 쇼핑, 게임에 참여하면 머니를 무제한으로 획득할 수 있습니다.\n[여덟] 간편 메뉴\n회원가입, 설문조사, 퀴즈 등 간편한 미션으로 빠르고 쉽게 머니를 획득해보세요!\n[아홉] 친구 초대\n초대하는 친구수가 많아질수록 초대보상도 점점 커져요. 10명 초대시 총 550만 머니! 11명째부터는 1인당 30만 머니씩 무제한 적립!',
    ),
    FAQItem(
      question: '3. 앱 이용시 주의사항?',
      answer:
          '[하나]미션 초기화\n매일 새벽 5시, 출석체크ㆍ자동적립ㆍ머니톡톡ㆍ머니팡팡ㆍ만보기 상자가 초기화됩니다.\n단 자동적립은 머니를 수령한 후, 레벨 1부터 재시작되며 만보기 걸음수는 자정에 초기화됩니다.\n[둘] 1인 1기기 1계정\n하나의 기기에서는 한 개의 계정만 이용 가능하며, 마찬가지로 하나의 계정도 한 개의 기기에서만 이용 가능합니다.\n보유하신 계정의 접속기기를 2회 이상 변경할 경우에는 별도의 승인절차가 요구됩니다.\n[셋] 부정 이용 행위 제한\n앱 가입 후 고액 리워드 미션만 수행하고 상품권을 구매 후 탈퇴하는 등의 비정상적인 이용 행위(체리피킹 및 어뷰징)와, 서브폰 등을 활용하여 1인 다계정 이용 및 초대 보상을 악용하는 등의 부정 행위가 적발될 시, 사전 통보 없이 상품권 구매 제한 및 서비스 이용이 영구적으로 제한될 수 있습니다.',
    ),
    FAQItem(
      question: '4. 어떤 상품으로 교환할 수 있나요?',
      answer: '적립한 머니는 모바일상품권 혹은 금·은 등 실물 상품으로 교환할 수 있습니다.\n실물 배송까지는 약 2~3일이 소요됩니다.(주말·공휴일 제외)                             ',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        // Dark background color
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white70),
          onPressed: () {
            // Handle back button press
            Navigator.of(context).pop();
          },
        ),
        title: const Text(
          'FAQ',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: false,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16.0),
        itemCount: _faqItems.length,
        itemBuilder: (BuildContext context, int index) {
          return _buildFAQItem(_faqItems[index]).pOnly(bottom: index == _faqItems.length - 1 ? 80 : 0);
        },
      ),
    );
  }

  Widget _buildFAQItem(FAQItem item) {
    return Card(
      color: const Color(0xffE8ECF2), // Slightly lighter card background
      margin: const EdgeInsets.only(bottom: 12.0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10.0),
      ),
      child: ExpansionTile(
        key: PageStorageKey<String>(item.question),
        // Important for maintaining state
        title: Text(
          item.question,
          textAlign: TextAlign.left,
          style: const TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w500,
            fontSize: 16,
          ),
        ),
        iconColor: Colors.black,
        // Color for the default trailing icon when collapsed
        collapsedIconColor: Colors.black,
        // Color for the trailing icon when collapsed
        onExpansionChanged: (bool expanded) {
          setState(() {
            item.isExpanded = expanded;
          });
        },
        initiallyExpanded: item.isExpanded,
        // Custom trailing icon based on expansion state
        trailing: Icon(
          item.isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
          color: Colors.black,
        ),
        // Set initial state
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 0, 16.0, 16.0),
            child: Text(
              item.answer,
              textAlign: TextAlign.left,
              style: TextStyle(color: Colors.black.withOpacity(0.85), fontSize: 14, height: 1.5, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
