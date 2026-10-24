import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStorage {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static const String _tokenKey = 'thh_access_token';
  bool persistSession = true;
  String? _sessionToken;

  Future<void> saveToken(String token) async {
    _sessionToken = token;
    if (persistSession) {
      await _storage.write(key: _tokenKey, value: token);
    } else {
      await _storage.delete(key: _tokenKey);
    }
  }

  Future<String?> readToken() async {
    return _sessionToken ?? await _storage.read(key: _tokenKey);
  }

  Future<void> deleteToken() async {
    _sessionToken = null;
    await _storage.delete(key: _tokenKey);
  }
}
