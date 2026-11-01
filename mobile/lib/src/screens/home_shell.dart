import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../ui/v2.dart';
import 'chat_screen.dart';
import 'dashboard_screen.dart';
import 'map_screen.dart';
import 'report_list_screen.dart';
import 'performance_screen.dart';
import 'watchlist_screen.dart';

/// The five tabs behind the v2 bottom nav: Agent, Dashboard, Performa, Peta, Laporan.
/// Alert (Watchlist) opens from the bell in every app bar and Profil from the avatar.
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
  final _map = GlobalKey<MapScreenState>();

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

  void _go(int i) => setState(() => _tab = i);

  void _ask(String q) {
    Navigator.of(context).popUntil((r) => r.isFirst);
    setState(() => _tab = 0);
    WidgetsBinding.instance.addPostFrameCallback((_) => _chat.currentState?.ask(q));
  }

  /// Opens Watchlist dan Alert on top of the tabs; [question] pre-fills a new watch.
  Future<void> _openAlerts([String? question]) async {
    final key = GlobalKey<WatchlistScreenState>();
    if (question != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => key.currentState?.createFrom(question));
    }
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => WatchlistScreen(key: key, onAsk: _ask, onCountChanged: (n) => setState(() => _alerts = n)),
    ));
    _refreshCount();
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
        body: V2Scope(
          alerts: _alerts,
          openAlerts: _openAlerts,
          child: IndexedStack(index: _tab, children: [
            ChatScreen(key: _chat, onWatch: _openAlerts, onOpenMap: () => _go(3)),
            DashboardScreen(onAsk: _ask, onAlerts: _openAlerts, onPerformance: () => _go(2)),
            PerformanceScreen(onAsk: _ask, onOpenMap: (site) {
              _go(3);
              _map.currentState?.focusSite(site);
            }),
            MapScreen(key: _map, onAsk: _ask),
            ReportListScreen(onAsk: _ask),
          ]),
        ),
        bottomNavigationBar: V2BottomNav(index: _tab, onTap: _go),
      ),
    );
  }
}
