import 'dart:convert';
import 'package:crypto/crypto.dart';

class InviteCodeGenerator {
  // Generate 6 character invite code from nickname (A-Z only)
  static String generateInviteCode(String nickname) {
    if (nickname.isEmpty) return 'AAAAAA';
    
    // Use multiple hash functions for better distribution
    // This reduces collision probability for up to 50K users
    
    // Step 1: Create multiple hash values from nickname
    var bytes = utf8.encode(nickname);
    var sha256Hash = sha256.convert(bytes);
    var sha256Hex = sha256Hash.toString();
    
    // Step 2: Extract 6 different segments from the hash for better distribution
    // SHA256 gives us 64 hex characters, we'll use different positions
    String code = '';
    
    // Use 6 different positions in the hash to minimize collisions
    List<int> positions = [0, 10, 20, 30, 40, 50];
    
    for (int pos in positions) {
      // Get 2 hex characters and convert to a letter (A-Z)
      if (pos + 1 < sha256Hex.length) {
        String hexPair = sha256Hex.substring(pos, pos + 2);
        int value = int.parse(hexPair, radix: 16);
        // Map 0-255 to 0-25 (A-Z)
        int letterIndex = value % 26;
        code += String.fromCharCode(65 + letterIndex); // 65 = 'A'
      }
    }
    
    // Ensure exactly 6 characters (should always be 6, but just in case)
    if (code.length < 6) {
      code = code.padRight(6, 'A');
    } else if (code.length > 6) {
      code = code.substring(0, 6);
    }
    
    return code;
  }
}