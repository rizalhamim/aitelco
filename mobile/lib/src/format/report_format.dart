import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme.dart';

/// Canonical number formatting for the whole app.
///
/// This is the ONLY file allowed to call [NumberFormat]. Every screen and
/// widget delegates here so a value renders identically wherever it appears.
///
/// Locale is always `id` (comma decimal, dot thousands).
///
/// Null and zero policy:
///   null            -> [kReportNotAvailable]
///   observed zero   -> '0' (never 'N/A', never blank)

/// Magnitude tiers used by the adaptive formatter.
enum ReportMagnitude { plain, thousand, million, billion, trillion }

/// Whether a positive delta is good, bad, or carries no judgement.
enum ReportPolarity { higherIsBetter, lowerIsBetter, neutral }

/// Semantic kind inferred from a raw payload key.
enum ReportValueKind {
  count,
  currency,
  percent,
  gigabyte,
  speed,
  latency,
  identifier,
  coordinate,
  text,
  boolean,
}

const String kReportNotAvailable = 'N/A';

const String _kUp = '▲'; // filled up triangle
const String _kDown = '▼'; // filled down triangle

/// Builds an ICU pattern for [decimals] fraction digits.
///
/// `decimals <= 0` MUST yield `'#,##0'`. Concatenating `'#,##0.'` with an empty
/// fraction run produces a dangling group separator, so `3` renders as `3,`.
String reportPattern(int decimals) =>
    decimals <= 0 ? '#,##0' : '#,##0.${'0' * decimals}';

NumberFormat _nf(int decimals) => NumberFormat(reportPattern(decimals), 'id');

double? _toDouble(Object? value) {
  if (value == null) return null;
  if (value is num) return value.isFinite ? value.toDouble() : null;
  if (value is String) return double.tryParse(value.replaceAll(',', '.'));
  return null;
}

/// Fixed-decimal number with Indonesian separators, no unit attached.
String reportNumber(Object? value, {int decimals = 0, double divisor = 1}) {
  final n = _toDouble(value);
  if (n == null) return kReportNotAvailable;
  final scaled = divisor == 0 ? n : n / divisor;
  return _nf(decimals).format(scaled);
}

/// Picks the magnitude tier for [absValue].
ReportMagnitude _tierFor(double absValue, {required bool useThousand}) {
  if (absValue >= 1e12) return ReportMagnitude.trillion;
  if (absValue >= 1e9) return ReportMagnitude.billion;
  if (absValue >= 1e6) return ReportMagnitude.million;
  if (useThousand && absValue >= 1e3) return ReportMagnitude.thousand;
  return ReportMagnitude.plain;
}

double _divisorOf(ReportMagnitude tier) {
  switch (tier) {
    case ReportMagnitude.trillion:
      return 1e12;
    case ReportMagnitude.billion:
      return 1e9;
    case ReportMagnitude.million:
      return 1e6;
    case ReportMagnitude.thousand:
      return 1e3;
    case ReportMagnitude.plain:
      return 1;
  }
}

String _suffixOf(ReportMagnitude tier) {
  switch (tier) {
    case ReportMagnitude.trillion:
      return 'Tn';
    case ReportMagnitude.billion:
      return 'Bn';
    case ReportMagnitude.million:
      return 'Mn';
    case ReportMagnitude.thousand:
      return 'Thousand';
    case ReportMagnitude.plain:
      return '';
  }
}

/// Adaptive magnitude formatter.
///
/// Returns for example `1,2 Bn IDR`, `850,4 Mn`, `12,3 Thousand`, `742`.
/// Values in the plain tier drop the fraction when they are whole, so a count
/// of 450 renders `450` and not `450,0`.
///
/// Set [useThousand] to false when a value below one million reads better
/// ungrouped (raw counts such as subscribers or sites).
String reportMagnitude(
  Object? value, {
  ReportMagnitude? force,
  String unit = '',
  int decimals = 1,
  bool useThousand = true,
}) {
  final n = _toDouble(value);
  if (n == null) return kReportNotAvailable;
  final tier = force ?? _tierFor(n.abs(), useThousand: useThousand);
  final scaled = n / _divisorOf(tier);
  final isWhole = scaled == scaled.roundToDouble();
  final digits =
      tier == ReportMagnitude.plain && isWhole ? 0 : decimals;
  final text = _nf(digits).format(scaled);
  final suffix = _suffixOf(tier);
  final parts = <String>[
    text,
    if (suffix.isNotEmpty) suffix,
    if (unit.isNotEmpty) unit,
  ];
  return parts.join(' ');
}

/// Chooses one tier for a whole column or table, derived from its peak value.
///
/// Callers format every cell with the returned divisor so a column stays on a
/// single scale, and show [label] once in the header or the metric name.
({double divisor, String label}) reportMagnitudeTier(
  double peakAbs, {
  String unit = '',
}) {
  final tier = _tierFor(peakAbs, useThousand: true);
  final suffix = _suffixOf(tier);
  final parts = <String>[
    if (suffix.isNotEmpty) suffix,
    if (unit.isNotEmpty) unit,
  ];
  return (divisor: _divisorOf(tier), label: parts.join(' '));
}

/// Formats against a divisor chosen by [reportMagnitudeTier].
String reportScaled(Object? value, double divisor, {int decimals = 1}) =>
    reportNumber(value, decimals: decimals, divisor: divisor);

/// Percent value. [signed] prefixes a `+` on positive values.
String reportPercent(
  Object? value, {
  int decimals = 1,
  bool signed = false,
}) {
  final n = _toDouble(value);
  if (n == null) return kReportNotAvailable;
  final sign = signed && n > 0 ? '+' : '';
  return '$sign${_nf(decimals).format(n)}%';
}

/// Signed absolute delta with the canonical arrow glyphs.
String reportVariance(
  Object? value, {
  double divisor = 1,
  int decimals = 1,
  String unit = '',
}) {
  final n = _toDouble(value);
  if (n == null) return kReportNotAvailable;
  final scaled = divisor == 0 ? n : n / divisor;
  final glyph = scaled >= 0 ? _kUp : _kDown;
  final text = _nf(decimals).format(scaled.abs());
  return unit.isEmpty ? '$glyph $text' : '$glyph $text $unit';
}

/// Growth reading with an arrow glyph and a percent style suffix.
///
/// Use `suffix: 'pp'` when the underlying value is a percentage point move
/// (a share going from 24,6% to 25,1% grew by 0,5 pp, not by 0,5%).
String reportGrowth(
  Object? value, {
  int decimals = 1,
  String suffix = '%',
}) {
  final n = _toDouble(value);
  if (n == null) return kReportNotAvailable;
  final glyph = n >= 0 ? _kUp : _kDown;
  return '$glyph ${_nf(decimals).format(n.abs())}$suffix';
}

/// Signed absolute delta that picks its own magnitude tier.
String reportVarianceMagnitude(
  Object? value, {
  String unit = '',
  int decimals = 1,
  bool useThousand = true,
}) {
  final n = _toDouble(value);
  if (n == null) return kReportNotAvailable;
  final glyph = n >= 0 ? _kUp : _kDown;
  final text = reportMagnitude(
    n.abs(),
    unit: unit,
    decimals: decimals,
    useThousand: useThousand,
  );
  return '$glyph $text';
}

/// Magnitude words a catalog `uom` may already carry, mapped to their base.
const Map<String, double> _kPreScaledUnits = {
  'tn': 1e12,
  'bn': 1e9,
  'mn': 1e6,
  'k': 1e3,
};

/// Splits a unit label such as `IDR Bn` into its base multiplier and the
/// remaining unit text (`IDR`). Returns a multiplier of 1 when the label
/// carries no magnitude word.
({double base, String unit}) reportUnitBase(String unit) {
  final parts = unit.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty) return (base: 1, unit: '');
  final last = parts.last.toLowerCase();
  final base = _kPreScaledUnits[last];
  if (base == null) return (base: 1, unit: unit.trim());
  return (base: base, unit: parts.sublist(0, parts.length - 1).join(' '));
}

/// Re-scales a value that is already expressed in a fixed magnitude unit.
///
/// A catalog metric with `uom: "IDR Bn"` stores 0.042 for 42 million rupiah.
/// Rendering that verbatim gives `0,0 Bn`, so lift it back to absolute and let
/// [reportMagnitude] pick the tier that actually fits.
String reportPreScaled(Object? value, String unit, {int decimals = 1}) {
  final n = _toDouble(value);
  if (n == null) return kReportNotAvailable;
  final parsed = reportUnitBase(unit);
  if (parsed.base == 1) {
    return reportMagnitude(n, unit: parsed.unit, decimals: decimals);
  }
  return reportMagnitude(
    n * parsed.base,
    unit: parsed.unit,
    decimals: decimals,
  );
}

const List<String> _kLowerIsBetter = [
  'churn',
  'latency',
  'downtime',
  'days_down',
  'down_day',
  'below_sla',
  'low_tur',
  'lowsite',
  'failure',
  'complaint',
];

const List<String> _kNeutral = [
  'signal',
  'ratio',
  'contribution',
  'product',
  'insight',
  'rank',
  'share',
  'soga',
  '_ms',
  'fb_ms',
];

/// Single source of truth for metric polarity.
///
/// Replaces the competing lists that used to live in the reports screen and the
/// site performance screen.
ReportPolarity reportPolarityFor(String code) {
  final c = code.toLowerCase();
  if (_kLowerIsBetter.any(c.contains)) return ReportPolarity.lowerIsBetter;
  if (_kNeutral.any(c.contains)) return ReportPolarity.neutral;
  return ReportPolarity.higherIsBetter;
}

/// Colour for a growth or delta value.
///
/// Returns null for a neutral metric or a non numeric value so the caller falls
/// back to the normal ink colour.
Color? reportGrowthColor(
  BuildContext context,
  Object? value, {
  ReportPolarity polarity = ReportPolarity.higherIsBetter,
}) {
  if (polarity == ReportPolarity.neutral) return null;
  final n = _toDouble(value);
  if (n == null) return null;
  if (n == 0) return context.vMute;
  final favorable =
      polarity == ReportPolarity.lowerIsBetter ? n < 0 : n > 0;
  return favorable ? IOH.teal600 : IOH.danger;
}

/// Screen reader suffix so colour is never the only carrier of meaning.
String reportGrowthSemantics(
  Object? value, {
  ReportPolarity polarity = ReportPolarity.higherIsBetter,
}) {
  if (polarity == ReportPolarity.neutral) return '';
  final n = _toDouble(value);
  if (n == null || n == 0) return '';
  return n > 0 ? ', naik' : ', turun';
}

bool _matchesAny(String key, List<String> needles) =>
    needles.any(key.contains);

/// Infers a semantic kind from a raw payload key.
///
/// The identifier guard must stay first among the numeric rules. Without it
/// `month_id: 202608` renders as `202.608` and `site_id` gets mangled.
ReportValueKind reportKindForKey(String key) {
  final k = key.toLowerCase();
  if (k == 'lat' ||
      k == 'lon' ||
      k == 'lng' ||
      _matchesAny(k, const ['latitude', 'longitude'])) {
    return ReportValueKind.coordinate;
  }
  if (k == 'id' ||
      k.endsWith('_id') ||
      k.endsWith('_code') ||
      _matchesAny(k, const ['site_id', 'kec_id', 'month_id', 'nomor', 'msisdn'])) {
    return ReportValueKind.identifier;
  }
  if (_matchesAny(k, const ['latency', 'rtt', 'delay'])) {
    return ReportValueKind.latency;
  }
  if (_matchesAny(k, const ['dl_speed', 'ul_speed', 'throughput', 'speed', 'tput'])) {
    return ReportValueKind.speed;
  }
  if (k.endsWith('_gb') ||
      _matchesAny(k, const ['_gb_', 'usg_data', 'usage', 'payload', 'volume_gb'])) {
    return ReportValueKind.gigabyte;
  }
  if (_matchesAny(k, const ['pct', 'percent', 'share', 'soga', 'growth', '_ms'])) {
    return ReportValueKind.percent;
  }
  if (_matchesAny(k, const ['rev', 'arpu', 'arpt', '_idr', 'idr_', 'price', 'harga', 'billing'])) {
    return ReportValueKind.currency;
  }
  return ReportValueKind.count;
}

/// Formats a free form payload value using the kind inferred from its key.
///
/// Used by the map feature sheet, where keys arrive from arbitrary agent SQL
/// and there is no metric catalog to consult.
String reportValueForKey(String key, Object? value) {
  if (value == null) return kReportNotAvailable;
  if (value is bool) return value ? 'Ya' : 'Tidak';
  if (value is! num) {
    final text = value.toString();
    return text.isEmpty ? kReportNotAvailable : text;
  }
  if (!value.isFinite) return kReportNotAvailable;
  switch (reportKindForKey(key)) {
    case ReportValueKind.identifier:
    case ReportValueKind.text:
      return value.toString();
    case ReportValueKind.coordinate:
      return value.toDouble().toStringAsFixed(5);
    case ReportValueKind.percent:
      return reportPercent(value, decimals: 1);
    case ReportValueKind.currency:
      return reportMagnitude(value, unit: 'IDR', decimals: 1);
    case ReportValueKind.gigabyte:
      return '${reportNumber(value, decimals: 1)} GB';
    case ReportValueKind.speed:
      return '${reportNumber(value, decimals: 1)} Mbps';
    case ReportValueKind.latency:
      return '${reportNumber(value, decimals: 1)} ms';
    case ReportValueKind.count:
    case ReportValueKind.boolean:
      return reportMagnitude(value, decimals: 1, useThousand: false);
  }
}
