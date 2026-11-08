// Navigation glue for the v3 screens. They open on top of the five-tab shell
// (from the Dashboard, a notification or another v3 screen) yet keep the
// shell's bottom nav, bell and avatar, so the shell registers its callbacks here.
import 'package:flutter/material.dart';

import '../../ui/v2.dart';

class V3Nav {
  V3Nav._();
  static ValueChanged<int>? goTab;
  static Future<void> Function([String? question])? openAlerts;
  static void Function(String question)? ask;
  static int alerts = 0;
  static void Function(String kabupaten, String metric)? openMap;

  static Future<T?> push<T>(BuildContext context, Widget screen) =>
      Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => screen));

  /// Back to the shell, then switch tab.
  static void tab(BuildContext context, int i) {
    Navigator.of(context).popUntil((r) => r.isFirst);
    goTab?.call(i);
  }
}

/// Scaffold of a pushed v3 screen: v2 app bar, body, Dashboard-selected bottom nav.
class V3Page extends StatelessWidget {
  const V3Page({super.key, required this.title, this.subtitle, required this.body, this.fab, this.bottomNav = true, this.actions = const []});
  final String title;
  final String? subtitle;
  final Widget body;
  final Widget? fab;
  final bool bottomNav;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: V2.bg,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          V2AppBar(
            title: title,
            subtitle: subtitle,
            subtitleDot: subtitle == null ? null : const Color(0xFF2E9E57),
            actions: actions,
            alertCount: V3Nav.alerts,
            onBell: () => V3Nav.openAlerts?.call(),
          ),
          Expanded(child: fab == null ? body : Stack(children: [Positioned.fill(child: body), Positioned(right: 16, bottom: 16, child: fab!)])),
        ]),
      ),
      bottomNavigationBar: bottomNav ? V2BottomNav(index: 1, onTap: (i) => V3Nav.tab(context, i)) : null,
    );
  }
}
