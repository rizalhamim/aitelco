import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../ui/ds.dart';
import '../ui/kit.dart';

/// Android · Splash: teal hero, kawung motif, AI orb, logo and a progress bar.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.autoRoute = true, this.progress});

  /// Off in previews and golden tests, which also pin [progress].
  final bool autoRoute;
  final double? progress;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _bar = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void initState() {
    super.initState();
    if (widget.progress == null) _bar.forward();
    if (widget.autoRoute) {
      _bar.addStatusListener((s) {
        if (s == AnimationStatus.completed && mounted) {
          Navigator.of(context).pushReplacementNamed(AuthState.isLoggedIn ? '/home' : '/login');
        }
      });
    }
  }

  @override
  void dispose() {
    _bar.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF04332E),
      body: LayoutBuilder(builder: (context, c) {
        final h = c.maxHeight, w = c.maxWidth;
        // The mockup centres the logo block at y 399.5 of an 844 frame.
        final mid = h / 2 - 22.5;
        return Stack(children: [
          const Positioned.fill(child: HeroFill(kawung: .14)),
          Positioned(left: w / 2 - 260, top: mid + 60.5 - 260, width: 520, height: 520,
              child: const Glow(color: Color(0xFF33BCAD), alpha: .33)),
          Positioned(
            left: w / 2 - 215,
            top: mid - 98.5 - 215,
            width: 430,
            height: 430,
            child: const IgnorePointer(child: Opacity(opacity: .5, child: Image(image: AssetImage('assets/img/ai_orb.webp')))),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: mid - 99.5,
            child: Column(children: [
              const AppLogo(size: 112, radius: 31.36, border: Colors.white, borderWidth: 2, shadow: true),
              const SizedBox(height: 16),
              Text('Bizplan Java Agent', style: ts(24, w700, Colors.white, lh: 1.3, ls: -.003)),
              const SizedBox(height: 16),
              Text('Winning Every Second', style: ts(16, w400, const Color(0xFF8FDFD7), lh: 1.5)),
            ]),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 109,
            child: Column(children: [
              Container(
                width: 120,
                height: 4,
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: .18), borderRadius: BorderRadius.circular(999)),
                child: AnimatedBuilder(
                  animation: _bar,
                  builder: (_, __) => FractionallySizedBox(
                    widthFactor: widget.progress ?? (.15 + .85 * Curves.easeOut.transform(_bar.value)),
                    child: Container(decoration: BoxDecoration(color: const Color(0xFF5BCEC3), borderRadius: BorderRadius.circular(999))),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text('Didukung oleh Indosat Ooredoo Hutchison', style: ts(12, w400, const Color(0xFFC0EDE8))),
            ]),
          ),
        ]);
      }),
    );
  }
}
