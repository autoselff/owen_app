import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/lock_providers.dart';

/// Wraps the app and, when "App lock" is enabled, hides its content behind a
/// lock screen until the user authenticates (biometrics or device credential).
///
/// Re-locks whenever the app is sent to the background, so a resumed session
/// always asks again.
class LockGate extends ConsumerStatefulWidget {
  const LockGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<LockGate> createState() => _LockGateState();
}

class _LockGateState extends ConsumerState<LockGate>
    with WidgetsBindingObserver {
  bool _authenticating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // On cold start, lock immediately if the preference is on, then prompt.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final enabled = await ref.read(appLockEnabledProvider.future);
      if (!mounted || !enabled) return;
      ref.read(lockStateProvider.notifier).lock();
      _authenticate();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final enabled = ref.read(appLockEnabledProvider).value ?? false;
    if (!enabled) return;
    switch (state) {
      case AppLifecycleState.resumed:
        if (ref.read(lockStateProvider) && !_authenticating) _authenticate();
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        // Don't re-lock while our own auth dialog is what pushed us to the
        // background, or we'd cancel the in-flight prompt.
        if (!_authenticating) ref.read(lockStateProvider.notifier).lock();
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  Future<void> _authenticate() async {
    if (_authenticating) return;
    _authenticating = true;
    try {
      final ok = await ref.read(localAuthProvider).authenticate(
            localizedReason: 'Unlock Owen',
            // Allow the device PIN/pattern as a fallback so the lock works even
            // without enrolled biometrics; resume the prompt after backgrounding.
            biometricOnly: false,
            persistAcrossBackgrounding: true,
          );
      if (ok) ref.read(lockStateProvider.notifier).unlock();
    } on Object {
      // Stay locked; the user can retry from the lock screen.
    } finally {
      _authenticating = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(appLockEnabledProvider).value ?? false;
    final locked = ref.watch(lockStateProvider);

    return Stack(
      children: [
        widget.child,
        if (enabled && locked)
          _LockScreen(onUnlock: _authenticate),
      ],
    );
  }
}

class _LockScreen extends StatelessWidget {
  const _LockScreen({required this.onUnlock});

  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 56, color: scheme.onSurfaceVariant),
            const SizedBox(height: 20),
            Text('Owen is locked',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onUnlock,
              icon: const Icon(Icons.fingerprint),
              label: const Text('Unlock'),
            ),
          ],
        ),
      ),
    );
  }
}
