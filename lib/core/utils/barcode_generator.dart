import 'dart:math';

/// 바코드 생성 유틸리티
class BarcodeGenerator {
  /// 13자리 EAN-13 바코드 번호 생성
  static String generateEAN13() {
    final random = Random();
    
    // 앞 12자리 생성 (국가코드 880으로 시작 - 한국)
    String barcode = '880';
    
    // 제조사 코드 (4자리)
    for (int i = 0; i < 4; i++) {
      barcode += random.nextInt(10).toString();
    }
    
    // 상품 코드 (5자리)
    for (int i = 0; i < 5; i++) {
      barcode += random.nextInt(10).toString();
    }
    
    // 체크섬 계산 (13번째 자리)
    int sum = 0;
    for (int i = 0; i < 12; i++) {
      int digit = int.parse(barcode[i]);
      sum += (i % 2 == 0) ? digit : digit * 3;
    }
    int checksum = (10 - (sum % 10)) % 10;
    barcode += checksum.toString();
    
    return barcode;
  }
  
  /// 기프티콘용 고유 번호 생성 (16자리)
  static String generateGiftCardNumber() {
    final random = Random();
    String number = '';
    
    // 4자리씩 4그룹으로 생성
    for (int group = 0; group < 4; group++) {
      if (group > 0) number += '-';
      for (int i = 0; i < 4; i++) {
        number += random.nextInt(10).toString();
      }
    }
    
    return number;
  }
  
  /// 바코드 이미지 URL 생성 (실제로는 Firebase Storage에 업로드)
  /// 여기서는 임시 URL 반환
  static String generateBarcodeImageUrl(String barcodeNumber) {
    // 실제 구현에서는 바코드 이미지를 생성하여 Firebase Storage에 업로드하고 URL 반환
    // 임시로 플레이스홀더 URL 반환
    return 'barcode://$barcodeNumber';
  }
}