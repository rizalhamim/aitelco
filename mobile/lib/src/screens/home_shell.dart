import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../ui/nav.dart';
import 'chat_screen.dart';
import 'dashboard_screen.dart';
import 'map_screen.dart';
import 'report_list_screen.dart';
import 'watchlist_screen.dart';

/// The five tabs behind the bottom nav: Agent, Dashboard, Alert, Laporan, Peta.
/// Tabs stay alive so a running answer or a map position survives a switch.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, this.initialTab = 1});
  final int initialTab;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  late int _tab = widget.initialTab;
  int _alerts = 0;
  Timer? _poll;
  final _chat = GlobalKey<ChatScreenState>();
  final _watch = GlobalKey<WatchlistScreenState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshCount();
    _poll = Timer.periodic(const Duration(minutes: 5), (_) => _refreshCount());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshCount();
  }

  Future<void> _refreshCount() async {
    try {
      final n = await ApiClient.alertCount();
      if (mounted) setState(() => _alerts = n);
    } catch (_) {/* badge is best-effort */}
  }

  void _go(int i) {
    if (i == 2 && _tab != 2) _watch.currentState?.reload();
    setState(() => _tab = i);
  }

  void _ask(String q) {
    setState(() => _tab = 0);
    WidgetsBinding.instance.addPostFrameCallback((_) => _chat.currentState?.ask(q));
  }

  void _watchFrom(String q) {
    setState(() => _tab = 2);
    WidgetsBinding.instance.addPostFrameCallback((_) => _watch.currentState?.createFrom(q));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _tab == 1,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _tab = 1);
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        body: IndexedStack(index: _tab, children: [
          ChatScreen(key: _chat, onWatch: _watchFrom),
          DashboardScreen(alertCount: _alerts, onAsk: _ask, onTab: _go),
          WatchlistScreen(key: _watch, onAsk: _ask, onCountChanged: (n) => setState(() => _alerts = n)),
          ReportListScreen(onAsk: _ask),
          MapScreen(onAsk: _ask),
        ]),
        bottomNavigationBar: AppBottomNav(index: _tab, alertBadge: _alerts, onTap: _go),
      ),
    );
  }
}
