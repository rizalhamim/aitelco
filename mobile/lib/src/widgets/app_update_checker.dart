import 'dart:async';

import 'package:flutter/material.dart';

import '../services/update_service.dart';
import 'update_dialog.dart';

/// Checks every route, including login, without stacking update dialogs.
class AppUpdateChecker extends StatefulWidget {
  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;
  final Future<UpdateInfo?> Function()? checkForUpdate;
  final Future<void> Function(BuildContext, UpdateInfo)? prompt;

  const AppUpdateChecker({
    super.key,
    required this.child,
    required this.navigatorKey,
    this.checkForUpdate,
    this.prompt,
  });

  @override
  State<AppUpdateChecker> createState() => _AppUpdateCheckerState();
}

class _AppUpdateCheckerState extends State<AppUpdateChecker>
    with WidgetsBindingObserver {
  Timer? _nextCheck;
  bool _checking = false;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _nextCheck?.cancel();
    if (_foreground) _check();
  }

  Future<void> _check() async {
    if (!mounted || !_foreground || _checking) return;
    _checking = true;
    _nextCheck?.cancel();
    var delay = const Duration(minutes: 5);
    try {
      final info = await (widget.checkForUpdate ?? UpdateService.check)();
      if (!mounted) return;
      final context = widget.navigatorKey.currentState?.overlay?.context;
      if (info != null && _foreground && context != null && context.mounted) {
        await (widget.prompt ?? showUpdateDialog)(context, info);
      } else if (info != null) {
        delay = const Duration(seconds: 30);
      }
    } catch (e) {
      // Offline is not up-to-date. Retry without interrupting normal app use.
      debugPrint('Automatic update check failed: $e');
      delay = const Duration(seconds: 30);
    } finally {
      _checking = false;
      if (mounted && _foreground) _nextCheck = Timer(delay, _check);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _nextCheck?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
