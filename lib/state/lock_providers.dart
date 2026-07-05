import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import 'app_providers.dart';

/// Persisted "App lock" preference. Stored in the (encrypted) settings table.
const _appLockKey = 'app_lock_enabled';

final appLockEnabledProvider =
    AsyncNotifierProvider<AppLockEnabledNotifier, bool>(
  AppLockEnabledNotifier.new,
);

class AppLockEnabledNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final v = await ref.watch(databaseProvider).setting(_appLockKey);
    return v == 'true';
  }

  Future<void> set(bool enabled) async {
    await ref
        .read(databaseProvider)
        .setSetting(_appLockKey, enabled ? 'true' : 'false');
    state = AsyncData(enabled);
  }
}

/// Platform biometric/device-credential authenticator.
final localAuthProvider =
    Provider<LocalAuthentication>((_) => LocalAuthentication());

/// Whether the app is currently locked (content hidden behind the lock screen).
/// Cold start begins unlocked; [LockGate] locks it on launch when the pref is on.
final lockStateProvider =
    NotifierProvider<LockController, bool>(LockController.new);

class LockController extends Notifier<bool> {
  @override
  bool build() => false;

  void lock() => state = true;
  void unlock() => state = false;
}
