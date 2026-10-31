import 'package:flutter/material.dart';

import 'ds.dart';
import 'icons.dart';

class NavDest {
  const NavDest(this.label, this.icon, {this.iconSize = 24});
  final String label;
  final I3 icon;
  final double iconSize;
}

const navDestinations = [
  NavDest('Agent', Icx.sparkles, iconSize: 22),
  NavDest('Dashboard', Icx.dashboard),
  NavDest('Alert', Icx.bell),
  NavDest('Laporan', Icx.fileText),
  NavDest('Peta', Icx.map),
];

/// Five-tab bottom navigation (Agent, Dashboard, Alert, Laporan, Peta).
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({super.key, required this.index, required this.onTap, this.alertBadge = 0});
  final int index;
  final ValueChanged<int> onTap;
  final int alertBadge;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      decoration: BoxDecoration(color: p.surface, border: Border(top: BorderSide(color: p.rule))),
      padding: EdgeInsets.only(left: 4, right: 4, bottom: bottom),
      child: SizedBox(
        height: 81,
        child: Row(children: [
          for (var i = 0; i < navDestinations.length; i++)
            Expanded(child: _item(context, p, i)),
        ]),
      ),
    );
  }

  Widget _item(BuildContext context, Pal p, int i) {
    final d = navDestinations[i];
    final active = i == index;
    final badge = i == 2 && alertBadge > 0;
    return Semantics(
      selected: active,
      button: true,
      label: badge ? '${d.label}, $alertBadge baru' : d.label,
      child: InkWell(
        onTap: () => onTap(i),
        child: Stack(clipBehavior: Clip.none, children: [
          Column(children: [
            const SizedBox(height: 12),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 64,
              height: 32,
              decoration: BoxDecoration(
                color: active ? p.teal100 : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
              ),
              alignment: Alignment.center,
              child: Ic(d.icon, size: d.iconSize, color: active ? p.teal800 : p.mute),
            ),
            const SizedBox(height: 4),
            Text(d.label, maxLines: 1, style: ts(12, active ? w600 : w400, active ? p.teal800 : p.text2)),
          ]),
          if (badge)
            Positioned(
              left: 0,
              right: 0,
              top: 6,
              child: Align(
                alignment: const Alignment(.70, 0),
                child: Container(
                  constraints: const BoxConstraints(minWidth: 20),
                  height: 18,
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: BoxDecoration(
                    color: p.dangerSolid,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: p.surface, width: 2),
                  ),
                  child: Center(
                    widthFactor: 1,
                    child: Text(alertBadge > 99 ? '99+' : '$alertBadge', style: ts(10, w500, Colors.white, lh: 1.3)),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}
