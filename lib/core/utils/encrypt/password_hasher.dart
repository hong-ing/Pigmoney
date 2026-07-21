// utils/password_hasher.dart
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:cryptography/cryptography.dart';

Uint8List _randomBytes(int length) {
  final rnd = Random.secure();
  return Uint8List.fromList(
    List<int>.generate(length, (_) => rnd.nextInt(256)),
  );
}

class PasswordHasher {
  static final _kdf = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 100000, // 50k↑ 권장
    bits: 256,
  );

  /// ⇢ base64(salt(16B) + hash)
  static Future<String> hash(String password) async {
    final salt = _randomBytes(16);
    final key = await _kdf.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
    final hash = await key.extractBytes();
    return base64Encode([...salt, ...hash]);
  }

  static Future<bool> verify(String password, String stored) async {
    final bytes = base64Decode(stored);
    final salt = bytes.sublist(0, 16);
    final storedHash = bytes.sublist(16);
    final newKey = await _kdf.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
    final newHash = await newKey.extractBytes();
    return const ListEquality().equals(storedHash, newHash);
  }
}
