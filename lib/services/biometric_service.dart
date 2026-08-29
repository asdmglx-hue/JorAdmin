import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

// ── BiometricService ──────────────────────────────────────────────────────────
// Wraps local_auth + flutter_secure_storage for fingerprint login.
//
// Credentials (CNIC + password) are stored in the OS secure keychain/keystore
// — never in SharedPreferences or plain storage. Biometric is optional and
// opt-in; the admin can always fall back to password login.
// ─────────────────────────────────────────────────────────────────────────────
class BiometricService {
  BiometricService._();
  static final instance = BiometricService._();

  final _auth    = LocalAuthentication();
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static const _keyCnic     = 'bio_admin_cnic';
  static const _keyPassword = 'bio_admin_password';
  static const _keyEnabled  = 'bio_admin_enabled';

  // ── Capability checks ─────────────────────────────────────────────────────

  /// True if the device supports biometrics AND has enrolled fingers/face.
  Future<bool> isAvailable() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final isSupported = await _auth.isDeviceSupported();
      if (!canCheck || !isSupported) return false;
      final types = await _auth.getAvailableBiometrics();
      return types.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// True if the admin has previously enabled biometric login on this device.
  Future<bool> isEnabled() async {
    final val = await _storage.read(key: _keyEnabled);
    return val == 'true';
  }

  // ── Save / clear credentials ──────────────────────────────────────────────

  /// Called after a successful password login when the admin opts in.
  Future<void> saveCredentials(String cnic, String password) async {
    await _storage.write(key: _keyCnic,     value: cnic);
    await _storage.write(key: _keyPassword, value: password);
    await _storage.write(key: _keyEnabled,  value: 'true');
  }

  /// Disables biometric login and wipes stored credentials.
  Future<void> clearCredentials() async {
    await _storage.deleteAll();
  }

  // ── Authenticate ──────────────────────────────────────────────────────────

  /// Shows the OS fingerprint/face prompt. Returns the stored (cnic, password)
  /// on success, or null if the user cancelled / failed.
  Future<({String cnic, String password})?> authenticate() async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: 'Use fingerprint to sign in to the admin panel',
        options: const AuthenticationOptions(
          biometricOnly: false, // allow device PIN as fallback
          stickyAuth: true,     // keep prompt alive if app goes background
        ),
      );
      if (!ok) return null;

      final cnic     = await _storage.read(key: _keyCnic);
      final password = await _storage.read(key: _keyPassword);
      if (cnic == null || password == null) return null;

      return (cnic: cnic, password: password);
    } on PlatformException {
      return null;
    }
  }
}
