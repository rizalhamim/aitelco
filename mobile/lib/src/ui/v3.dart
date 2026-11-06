// Agent Java v3 building blocks for the Android screens of design/mockup-v3
// (Brief Pagi, Diagnosa, Klasemen, Ruang Saya, Tindak Lanjut, Simulasi Target).
// Sizes and colors follow the mockup CSS so the screens match the mockup PNGs
// (test/golden_v3). Text styles come from V2.d (Poppins) and V2.b (Prompt).
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import 'mock_icons.dart';
import 'v2.dart';

class V3 {
  V3._();
  static const green = Color(0xFF1F7A3A);
  static const green2 = Color(0xFF2FA84F);
  static const amber = Color(0xFFF5A623);
  static const purple = Color(0xFF6A4CB5);
  static const faint = Color(0xFF8A9A97);
  static const line = Color(0xFF9FB1AD);
  static const axis = Color(0xFFB9C6C3);
  static const minus = '−';

  static BoxDecoration card({double radius = 20, Color color = Colors.white, Color border = V2.rule, double width = 1, List<BoxShadow>? shadow}) =>
      BoxDecoration(color: color, borderRadius: BorderRadius.circular(radius), border: Border.all(color: border, width: width), boxShadow: shadow);

  /// "1,5" style numbers (id-ID): fixed [d] decimals, dot thousands.
  static String num(double v, [int d = 0]) {
    final neg = v < 0;
    final s = v.abs().toStringAsFixed(d);
    final parts = s.split('.');
    final b = StringBuffer();
    final ip = parts[0];
    for (var i = 0; i < ip.length; i++) {
      if (i > 0 && (ip.length - i) % 3 == 0) b.write('.');
      b.write(ip[i]);
    }
    if (parts.length > 1) b.write(',${parts[1]}');
    return '${neg ? minus : ''}$b';
  }

  static String sign(double v) => v > 0 ? '+' : v < 0 ? minus : '';

  /// v3_common.rp: "Rp 1,87 T", "Rp 61,7 M", "Rp 25 jt".
  static String rp(double v, {bool signed = false}) {
    final pre = signed ? sign(v) : (v < 0 ? minus : '');
    final a = v.abs();
    for (final (div, u, d) in const [(1e12, 'T', 2), (1e9, 'M', 1), (1e6, 'jt', 0)]) {
      if (a >= div * (d == 2 ? 0.995 : 0.95)) return '${pre}Rp ${num(a / div, d)} $u';
    }
    return '${pre}Rp ${num(a)}';
  }

  /// Always Rp miliar; whole numbers from Rp 10 M unless signed.
  static String rpm(double v, {bool signed = false}) =>
      '${signed ? sign(v) : (v < 0 ? minus : '')}Rp ${num(v.abs() / 1e9, v.abs() >= 1e10 && !signed ? 0 : 1)} M';

  static Color hex(String? s, [Color fallback = V2.mute]) {
    if (s == null || !s.startsWith('#') || s.length != 7) return fallback;
    return Color(int.parse('FF${s.substring(1)}', radix: 16));
  }
}

/// The ".seg" switch: grey (or white with a border) track, white "on" button.
class V3Seg extends StatelessWidget {
  const V3Seg({super.key, required this.options, required this.selected, required this.onTap, this.white = false, this.padX = 11});
  final List<(String, String)> options;
  final String selected;
  final ValueChanged<String> onTap;
  final bool white;
  final double padX;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: white ? Colors.white : V2.rule2,
        borderRadius: BorderRadius.circular(10),
        border: white ? Border.all(color: V2.rule) : null,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < options.length; i++) ...[
          if (i > 0) const SizedBox(width: 2),
          Semantics(
            button: true,
            selected: options[i].$1 == selected,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onTap(options[i].$1),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: padX, vertical: 7),
                decoration: options[i].$1 == selected
                    ? BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), boxShadow: [cssShadow(const Color(0x1F0F1F1D), 0, 1, 3)])
                    : null,
                child: Text(options[i].$2,
                    style: V2.d(12, FontWeight.w600, options[i].$1 == selected ? V2.teal700 : V2.ink2, lh: 1)),
              ),
            ),
          ),
        ],
      ]),
    );
  }
}

/// The ".chip" pill (".chip.teal" when [teal]).
class V3Chip extends StatelessWidget {
  const V3Chip({super.key, required this.label, this.icon, this.teal = false, this.height = 36, this.onTap});
  final String label;
  final String? icon;
  final bool teal;
  final double height;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = teal ? V2.teal700 : V2.ink2;
    return Semantics(
      button: onTap != null,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: teal ? V2.teal50 : Colors.white,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: teal ? V2.teal200 : V2.rule),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[MIcon(icon!, size: 16, color: c), const SizedBox(width: 7)],
            Text(label, style: V2.d(13, FontWeight.w500, c, lh: 1)),
          ]),
        ),
      ),
    );
  }
}

/// ".bul": achievement bar with the 100% marker at 80%.
class V3Bullet extends StatelessWidget {
  const V3Bullet({super.key, required this.fraction, required this.color, this.height = 6, this.markerOut = 2});
  final double fraction;
  final Color color;
  final double height;
  final double markerOut;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      return SizedBox(
        height: height,
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(color: V2.rule2, borderRadius: BorderRadius.circular(6)))),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: w * fraction.clamp(0, 1),
            child: DecoratedBox(decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6))),
          ),
          Positioned(left: w * .8, top: -markerOut, bottom: -markerOut, width: 2, child: const ColoredBox(color: V2.ink)),
        ]),
      );
    });
  }
}

/// Loads a v3 endpoint unless preview data is given (golden tests, offline demo).
class V3Loader extends StatefulWidget {
  const V3Loader({super.key, required this.path, this.query, this.preview, required this.builder});
  final String path;
  final Map<String, String>? query;
  final Map<String, dynamic>? preview;
  final Widget Function(BuildContext context, Map<String, dynamic> data, Future<void> Function() reload) builder;

  @override
  State<V3Loader> createState() => _V3LoaderState();
}

class _V3LoaderState extends State<V3Loader> {
  Map<String, dynamic>? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    _data = widget.preview;
    if (_data == null) _load();
  }

  @override
  void didUpdateWidget(V3Loader old) {
    super.didUpdateWidget(old);
    if (widget.preview == null && (old.path != widget.path || old.query.toString() != widget.query.toString())) _load();
  }

  Future<void> _load() async {
    try {
      final d = await ApiClient.v3Get(widget.path, widget.query);
      if (mounted) setState(() { _data = d; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_data != null) return widget.builder(context, _data!, _load);
    if (_error != null) return V3Message(text: _error!, onRetry: _load);
    return const Center(child: SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.5, color: V2.teal600)));
  }
}

class V3Message extends StatelessWidget {
  const V3Message({super.key, required this.text, this.onRetry});
  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const MIcon('warn', size: 22, color: Color(0xFFB7791F)),
          const SizedBox(height: 8),
          Text(text, textAlign: TextAlign.center, style: V2.b(13, FontWeight.w400, V2.ink2, lh: 1.45)),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            TextButton(onPressed: onRetry, child: Text('Coba lagi', style: V2.d(13, FontWeight.w600, V2.teal700))),
          ],
        ]),
      ),
    );
  }
}

void v3Toast(BuildContext context, String text) {
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
    content: Text(text, style: V2.d(13, FontWeight.w500, Colors.white)),
    behavior: SnackBarBehavior.floating,
    backgroundColor: V2.ink,
    duration: const Duration(milliseconds: 2400),
  ));
}

/// draw.js sparkline: line plus optional area fill, 2 px inset like the mockup.
class V3Spark extends StatelessWidget {
  const V3Spark({super.key, required this.values, required this.color, required this.width, required this.height, this.area = true});
  final List<double> values;
  final Color color;
  final double width, height;
  final bool area;

  @override
  Widget build(BuildContext context) =>
      SizedBox(width: width, height: height, child: CustomPaint(painter: _SparkPainter(values, color, area)));
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.v, this.color, this.area);
  final List<double> v;
  final Color color;
  final bool area;

  @override
  void paint(Canvas canvas, Size s) {
    if (v.length < 2) return;
    final mn = v.reduce(math.min), mx = v.reduce(math.max);
    double x(int i) => 2 + (s.width - 6) * i / (v.length - 1);
    double y(double a) => 3 + (s.height - 8) * (1 - (a - mn) / ((mx - mn) == 0 ? 1 : (mx - mn)));
    final p = Path()..moveTo(x(0), y(v[0]));
    for (var i = 1; i < v.length; i++) {
      p.lineTo(x(i), y(v[i]));
    }
    if (area) {
      final a = Path.from(p)
        ..lineTo(x(v.length - 1), s.height)
        ..lineTo(x(0), s.height)
        ..close();
      canvas.drawPath(
          a,
          Paint()
            ..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [color.withValues(alpha: .2), color.withValues(alpha: 0)])
                .createShader(Offset.zero & s));
    }
    canvas.drawPath(
        p,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = color
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round);
    canvas.drawCircle(Offset(x(v.length - 1), y(v.last)), 3, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SparkPainter o) => o.v != v || o.color != color;
}

/// Inline pill whose words may wrap across lines like a CSS inline box
/// (rounded at its start and end only), for "Basis kecil" next to a name.
List<InlineSpan> v3InlinePill(String text, {required TextStyle style, required Color bg, double padX = 6, double padY = 3, double dy = -2}) {
  final words = text.split(' ');
  return [
    for (var i = 0; i < words.length; i++) ...[
      if (i > 0) TextSpan(text: ' ', style: style.copyWith(backgroundColor: bg)),
      WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: Transform.translate(
          offset: Offset(0, dy),
          child: Container(
            padding: EdgeInsets.only(left: i == 0 ? padX : 0, right: i == words.length - 1 ? padX : 0, top: padY, bottom: padY),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.horizontal(
                left: i == 0 ? const Radius.circular(99) : Radius.zero,
                right: i == words.length - 1 ? const Radius.circular(99) : Radius.zero,
              ),
            ),
            child: Text(words[i], style: style),
          ),
        ),
      ),
    ],
  ];
}

/// CSS `border: <w>px dashed <color>` on a rounded box (Chrome draws dashes of
/// 2 x the width with gaps of 4/3 x the width).
/// A 16 px Prompt line box (24.2 px in Chrome): inline text sitting directly in a
/// mockup div gets this strut.
const v3Strut = StrutStyle(fontFamily: V2.body, fontSize: 16, height: 1.5125, forceStrutHeight: true, leadingDistribution: TextLeadingDistribution.even);

class V3Dashed extends StatelessWidget {
  const V3Dashed({super.key, required this.child, this.radius = 16, this.color = V3.line, this.width = 1.5, this.padding = EdgeInsets.zero, this.fill});
  final Widget child;
  final double radius, width;
  final Color color;
  final Color? fill;
  final EdgeInsets padding;

  /// Chrome (the mockup renderer) floors border widths of 1px and up to whole CSS px.
  double get _w => width >= 1 ? width.floorToDouble() : width;

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _DashPainter(radius, color, _w, fill),
        child: Padding(padding: padding + EdgeInsets.all(_w), child: child),
      );
}

class _DashPainter extends CustomPainter {
  _DashPainter(this.r, this.color, this.w, this.fill);
  final double r, w;
  final Color color;
  final Color? fill;

  @override
  void paint(Canvas canvas, Size s) {
    final rr = RRect.fromRectAndRadius((Offset.zero & s).deflate(w / 2), Radius.circular(r - w / 2));
    if (fill != null) canvas.drawRRect(rr, Paint()..color = fill!);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..color = color;
    final dash = w * 3, gap = w * 2;
    for (final m in (Path()..addRRect(rr)).computeMetrics()) {
      // spread the gaps so the pattern closes evenly
      final n = (m.length / (dash + gap)).floor().clamp(1, 100000);
      final step = m.length / n;
      for (var i = 0; i < n; i++) {
        canvas.drawPath(m.extractPath(i * step, i * step + dash), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashPainter o) => o.color != color || o.r != r || o.w != w;
}

/// Rich text segments from the API ({t, s?: "b"|"e"}): b = bold [b], e = bold [e].
TextSpan v3Rich(List? segs, {required TextStyle base, required TextStyle b, TextStyle? e}) => TextSpan(children: [
      for (final s in segs ?? const [])
        TextSpan(
          text: (s as Map)['t']?.toString() ?? '',
          style: s['s'] == 'b' ? b : s['s'] == 'e' ? (e ?? b) : base,
        ),
    ]);

/// One CSS `radial-gradient(<rx>px <ry>px at <x>% <y>%, color, transparent)` layer.
class V3Glow {
  const V3Glow(this.x, this.y, this.rx, this.ry, this.color, [this.alpha = 1]);
  final double x, y, rx, ry, alpha;
  final Color color;
}

/// Box painted like the mockup CSS backgrounds: a linear gradient (degrees, stops)
/// under elliptical radial glows, clipped to [radius].
class V3CssBg extends StatelessWidget {
  const V3CssBg({super.key, required this.deg, required this.colors, this.stops, this.glows = const [], this.radius = 0, required this.child, this.padding = EdgeInsets.zero});
  final double deg;
  final List<Color> colors;
  final List<double>? stops;
  final List<V3Glow> glows;
  final double radius;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: CustomPaint(painter: _CssBgPainter(this), child: Padding(padding: padding, child: child)),
      );
}

class _CssBgPainter extends CustomPainter {
  _CssBgPainter(this.w);
  final V3CssBg w;

  @override
  void paint(Canvas canvas, Size s) {
    final r = Offset.zero & s;
    canvas.drawRect(r, Paint()..shader = cssLinear(w.deg, w.colors, s, stops: w.stops).createShader(r));
    for (final g in w.glows) {
      final c = Offset(s.width * g.x, s.height * g.y);
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.scale(1, g.ry / g.rx);
      final rr = Rect.fromCircle(center: Offset.zero, radius: g.rx);
      canvas.drawRect(
          Rect.fromLTRB(-c.dx, -c.dy * g.rx / g.ry, s.width - c.dx, (s.height - c.dy) * g.rx / g.ry),
          Paint()..shader = RadialGradient(colors: [g.color.withValues(alpha: g.alpha), g.color.withValues(alpha: 0)]).createShader(rr));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_CssBgPainter o) => true;
}

/// SVG-like text: [x],[y] is the baseline anchor (start, middle or end).
void v3Text(Canvas canvas, String s, double x, double y, TextStyle style, {String anchor = 'start'}) {
  final tp = TextPainter(text: TextSpan(text: s, style: style), textDirection: TextDirection.ltr)..layout();
  final base = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
  final dx = anchor == 'end' ? tp.width : anchor == 'middle' ? tp.width / 2 : 0.0;
  tp.paint(canvas, Offset(x - dx, y - base));
  tp.dispose();
}

void v3Dash(Canvas canvas, Path path, Paint paint, double on, double off) {
  for (final m in path.computeMetrics()) {
    for (var t = 0.0; t < m.length; t += on + off) {
      canvas.drawPath(m.extractPath(t, math.min(t + on, m.length)), paint);
    }
  }
}

/// draw.js forecast fan, signed against the target path (same as the web Fan).
class V3FanData {
  const V3FanData({required this.days, required this.today, required this.min, required this.max, required this.ticks, required this.act,
      required this.mid, required this.lo, required this.hi, this.alt, required this.targetLabel, required this.midLabel, this.altLabel = '', required this.month});
  final int days, today;
  final double min, max;
  final List<double> ticks, act, mid, lo, hi;
  final List<double>? alt;
  final String targetLabel, midLabel, altLabel, month;
}

class V3Fan extends StatelessWidget {
  const V3Fan({super.key, required this.f, required this.width, required this.height, this.pr = 70});
  final V3FanData f;
  final double width, height, pr;

  @override
  Widget build(BuildContext context) => SizedBox(width: width, height: height, child: CustomPaint(painter: _FanPainter(f, pr)));
}

class _FanPainter extends CustomPainter {
  _FanPainter(this.f, this.pr);
  final V3FanData f;
  final double pr;

  @override
  void paint(Canvas canvas, Size s) {
    const pl = 52.0, pt = 14.0, pb = 30.0, c = V2.teal600;
    final iw = s.width - pl - pr, ih = s.height - pt - pb;
    double x(num d) => pl + iw * (d - 1) / (f.days - 1);
    double y(double v) => pt + ih * (1 - (v - f.min) / (f.max - f.min));
    TextStyle st(double size, FontWeight w, Color col) => TextStyle(fontFamily: V2.display, fontSize: size, fontWeight: w, color: col, height: 1, letterSpacing: 0);
    for (final t in f.ticks) {
      canvas.drawLine(Offset(pl, y(t) + .5), Offset(s.width - pr, y(t) + .5), Paint()..color = t == 0 ? V3.axis : V2.rule2);
      v3Text(canvas, '${t > 0 ? '+' : ''}${V3.num(t)}', pl - 8, y(t) + 4, st(11, FontWeight.w400, V2.mute), anchor: 'end');
    }
    for (final d in [1, 8, 15, 22, f.days]) {
      v3Text(canvas, '$d ${f.month}', x(d), s.height - 8, st(11, FontWeight.w400, V2.mute), anchor: 'middle');
    }
    Path line(List<double> v, int d0) {
      final p = Path();
      for (var i = 0; i < v.length; i++) {
        i == 0 ? p.moveTo(x(d0 + i), y(v[i])) : p.lineTo(x(d0 + i), y(v[i]));
      }
      return p;
    }

    final s0 = f.today;
    if (f.mid.isNotEmpty) {
      final band = line(f.lo, s0);
      for (var i = f.hi.length - 1; i >= 0; i--) {
        band.lineTo(x(s0 + i), y(f.hi[i]));
      }
      band.close();
      canvas.drawPath(band, Paint()..color = c.withValues(alpha: .14));
    }
    final stroke = Paint()..style = PaintingStyle.stroke;
    if (f.alt != null) v3Dash(canvas, line(f.alt!, s0), Paint.from(stroke)..color = V3.purple..strokeWidth = 2.5, 7, 5);
    if (f.mid.isNotEmpty) v3Dash(canvas, line(f.mid, s0), Paint.from(stroke)..color = c..strokeWidth = 2, 5, 5);
    canvas.drawPath(line(f.act, 1), Paint.from(stroke)..color = c..strokeWidth = 3..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round);
    final dot = Offset(x(s0), y(f.act[s0 - 1]));
    canvas.drawCircle(dot, 5, Paint()..color = Colors.white);
    canvas.drawCircle(dot, 5, Paint.from(stroke)..color = c..strokeWidth = 2.5);
    v3Dash(canvas, Path()..moveTo(x(s0), pt)..lineTo(x(s0), pt + ih), Paint.from(stroke)..color = V2.ink.withValues(alpha: .5)..strokeWidth = 1, 2, 3);
    v3Text(canvas, 'Hari ini', x(s0) + 6, pt + 10, st(10.5, FontWeight.w600, V2.ink));
    canvas.drawLine(Offset(pl, y(0)), Offset(s.width - pr, y(0)), Paint()..color = V2.red..strokeWidth = 1.5);
    v3Text(canvas, f.targetLabel, s.width - pr + 6, y(0) + 4, st(11, FontWeight.w700, V2.red));
    if (f.mid.isNotEmpty) v3Text(canvas, f.midLabel, s.width - pr + 6, y(f.mid.last) + 4, st(11, FontWeight.w700, c));
    if (f.alt != null) v3Text(canvas, f.altLabel, s.width - pr + 6, y(f.alt!.last) - 4, st(11, FontWeight.w700, V3.purple));
  }

  @override
  bool shouldRepaint(_FanPainter o) => true;
}

/// Rank move "▲9" / "▼1": Poppins has no triangle glyphs (Chrome falls back to a
/// system font), so the triangle is drawn at the fallback glyph's size.
class V3Move extends StatelessWidget {
  const V3Move(this.move, {super.key, this.size = 9.5});
  final int move;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = move > 0 ? V3.green : move < 0 ? V2.red : V2.mute;
    final style = V2.d(size, FontWeight.w600, c, lh: 1.2);
    if (move == 0) return Text('=', style: style);
    return Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.center, children: [
      CustomPaint(size: Size(size * .8, size * .7), painter: _Tri(up: move > 0, color: c)),
      SizedBox(width: size * .08),
      Text('${move.abs()}', style: style),
    ]);
  }
}

/// A delta label as an inline span; a leading ▲ or ▼ (missing in Poppins) is drawn.
InlineSpan v3Delta(String label, TextStyle style) {
  if (label.isEmpty || (label[0] != '▲' && label[0] != '▼')) return TextSpan(text: label, style: style);
  final size = style.fontSize ?? 12;
  return TextSpan(children: [
    WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: Padding(
        padding: EdgeInsets.only(right: size * .08),
        child: CustomPaint(size: Size(size * .8, size * .7), painter: _Tri(up: label[0] == '▲', color: style.color ?? V2.ink)),
      ),
    ),
    TextSpan(text: label.substring(1), style: style),
  ]);
}

class _Tri extends CustomPainter {
  _Tri({required this.up, required this.color});
  final bool up;
  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    final p = up
        ? (Path()..moveTo(s.width / 2, 0)..lineTo(s.width, s.height)..lineTo(0, s.height)..close())
        : (Path()..moveTo(0, 0)..lineTo(s.width, 0)..lineTo(s.width / 2, s.height)..close());
    canvas.drawPath(p, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_Tri o) => o.up != up || o.color != color;
}
