import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Local AraquariDesk TI account.
///
/// Passwords are never persisted. Only a PBKDF2-HMAC-SHA256 derived key and a
/// random salt are stored in the local account file.
class AraquariAdminAccount {
  AraquariAdminAccount({
    required this.username,
    required this.displayName,
    required this.salt,
    required this.hash,
    required this.iterations,
    required this.permissions,
  });

  final String username;
  String displayName;
  final String salt;
  final String hash;
  final int iterations;
  final List<String> permissions;

  bool get isMaster => username == 'admin';

  Map<String, dynamic> toJson() => {
        'username': username,
        'displayName': displayName,
        'salt': salt,
        'hash': hash,
        'iterations': iterations,
        'permissions': permissions,
      };

  factory AraquariAdminAccount.fromJson(Map<String, dynamic> json) {
    return AraquariAdminAccount(
      username: json['username'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      salt: json['salt'] as String? ?? '',
      hash: json['hash'] as String? ?? '',
      iterations: (json['iterations'] as num?)?.toInt() ?? 150000,
      permissions: (json['permissions'] as List?)
              ?.whereType<String>()
              .toList(growable: true) ??
          <String>['connect', 'view_peers'],
    );
  }
}

enum AraquariRole { common, admin }

class AraquariDeskAuth extends ChangeNotifier {
  AraquariDeskAuth._();

  static final AraquariDeskAuth instance = AraquariDeskAuth._();

  static const int _pbkdf2Iterations = 150000;
  static const int _saltBytes = 16;
  static const String _fileName = 'araquaridesk_admins.json';

  final List<AraquariAdminAccount> _admins = [];
  AraquariAdminAccount? currentAdmin;
  bool initialized = false;
  bool setupRequired = false;

  AraquariRole get role => currentAdmin == null ? AraquariRole.common : AraquariRole.admin;
  bool get isAdmin => currentAdmin != null;
  List<AraquariAdminAccount> get admins => List.unmodifiable(_admins);

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File('${dir.path}/$_fileName');
  }

  Future<void> initialize() async {
    if (initialized) return;
    initialized = true;
    try {
      final file = await _file();
      if (!await file.exists()) {
        setupRequired = true;
        notifyListeners();
        return;
      }
      final raw = jsonDecode(await file.readAsString());
      if (raw is Map<String, dynamic>) {
        final users = raw['admins'];
        if (users is List) {
          _admins
            ..clear()
            ..addAll(
              users
                  .whereType<Map>()
                  .map((e) => AraquariAdminAccount.fromJson(
                      Map<String, dynamic>.from(e)))
                  .where((e) => e.username.trim().isNotEmpty && e.hash.isNotEmpty),
            );
        }
      }
      setupRequired = _admins.isEmpty;
    } catch (_) {
      _admins.clear();
      setupRequired = true;
    }
    final requestedUser = Platform.environment['ARAQUARIDESK_ADMIN_USER'];
    if (requestedUser != null && requestedUser.trim().isNotEmpty) {
      activateSession(requestedUser.trim());
    }
    notifyListeners();
  }

  Future<void> _save() async {
    final file = await _file();
    final payload = <String, dynamic>{
      'version': 1,
      'admins': _admins.map((e) => e.toJson()).toList(),
    };
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
      flush: true,
    );
  }

  Uint8List _randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }

  Uint8List _pbkdf2(String password, Uint8List salt, int iterations) {
    final hmac = Hmac(sha256, utf8.encode(password));
    final block = <int>[...salt, 0, 0, 0, 1];
    var u = hmac.convert(block).bytes;
    final t = Uint8List.fromList(u);
    for (var i = 1; i < iterations; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < t.length; j++) {
        t[j] ^= u[j];
      }
    }
    return t;
  }

  bool _constantTimeEquals(List<int> a, List<int> b) {
    var diff = a.length ^ b.length;
    final length = min(a.length, b.length);
    for (var i = 0; i < length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  AraquariAdminAccount? _find(String username) {
    final normalized = username.trim().toLowerCase();
    for (final admin in _admins) {
      if (admin.username.toLowerCase() == normalized) return admin;
    }
    return null;
  }

  AraquariAdminAccount? _findByDisplayName(String displayName) {
    final normalized = displayName.trim().toLowerCase();
    for (final admin in _admins) {
      if (admin.displayName.toLowerCase() == normalized) return admin;
    }
    return null;
  }

  void activateSession(String usernameOrDisplayName) {
    currentAdmin =
        _find(usernameOrDisplayName) ?? _findByDisplayName(usernameOrDisplayName);
    notifyListeners();
  }

  Future<bool> setupMaster({
    required String password,
    required String displayName,
  }) async {
    await initialize();
    if (_admins.isNotEmpty) return false;
    final account = _createAccount(
      username: 'admin',
      displayName: displayName,
      password: password,
      permissions: const ['connect', 'view_peers', 'manage_users'],
    );
    _admins.add(account);
    currentAdmin = account;
    setupRequired = false;
    await _save();
    notifyListeners();
    return true;
  }

  AraquariAdminAccount _createAccount({
    required String username,
    required String displayName,
    required String password,
    required List<String> permissions,
  }) {
    final salt = _randomBytes(_saltBytes);
    final derived = _pbkdf2(password, salt, _pbkdf2Iterations);
    return AraquariAdminAccount(
      username: username.trim(),
      displayName: displayName.trim(),
      salt: base64Encode(salt),
      hash: base64Encode(derived),
      iterations: _pbkdf2Iterations,
      permissions: List<String>.from(permissions),
    );
  }

  Future<AraquariAdminAccount?> login(
      String username, String password) async {
    await initialize();
    final account = _find(username);
    if (account == null) return null;
    try {
      final salt = base64Decode(account.salt);
      final expected = base64Decode(account.hash);
      final actual = _pbkdf2(password, salt, account.iterations);
      if (!_constantTimeEquals(actual, expected)) return null;
    } catch (_) {
      return null;
    }
    currentAdmin = account;
    notifyListeners();
    return account;
  }

  Future<bool> addAdmin({
    required String username,
    required String password,
    required String displayName,
  }) async {
    await initialize();
    if (!isAdmin) return false;
    final normalized = username.trim();
    final normalizedDisplay = displayName.trim();
    if (normalized.isEmpty || normalized.toLowerCase() == 'admin') return false;
    if (normalizedDisplay.isEmpty) return false;
    if (_find(normalized) != null || _findByDisplayName(normalizedDisplay) != null) {
      return false;
    }
    _admins.add(_createAccount(
      username: normalized,
      displayName: normalizedDisplay,
      password: password,
      permissions: const ['connect', 'view_peers'],
    ));
    await _save();
    notifyListeners();
    return true;
  }

  Future<bool> updateDisplayName(
      String username, String displayName) async {
    if (!isAdmin) return false;
    final account = _find(username);
    final normalizedDisplay = displayName.trim();
    if (account == null || normalizedDisplay.isEmpty) return false;
    final existing = _findByDisplayName(normalizedDisplay);
    if (existing != null && existing.username != account.username) return false;
    account.displayName = normalizedDisplay;
    await _save();
    notifyListeners();
    return true;
  }

  Future<bool> changePassword(String username, String password) async {
    if (!isAdmin) return false;
    final account = _find(username);
    if (account == null || password.isEmpty) return false;
    final replacement = _createAccount(
      username: account.username,
      displayName: account.displayName,
      password: password,
      permissions: account.permissions,
    );
    final index = _admins.indexOf(account);
    _admins[index] = replacement;
    if (currentAdmin?.username == username) {
      currentAdmin = replacement;
    }
    await _save();
    notifyListeners();
    return true;
  }

  Future<bool> removeAdmin(String username) async {
    if (!isAdmin || username.trim().toLowerCase() == 'admin') return false;
    final account = _find(username);
    if (account == null) return false;
    _admins.remove(account);
    await _save();
    notifyListeners();
    return true;
  }

  void logout() {
    currentAdmin = null;
    notifyListeners();
  }
}
