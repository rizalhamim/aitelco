import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../format/report_format.dart';
import '../theme.dart';

typedef PerformanceNumberFormatter = String Function(num value);

/// The caller owns metric polarity because a higher value is not always better.
enum PerformanceTone { favorable, unfavorable, neutral, warning }

/// One display-ready KPI. A null [value] is always rendered as N/A.
class PerformanceKpiDatum {
  final String label;
  final num? value;
  final String? formattedValue;
  final String prefix;
  final String suffix;
  final String? comparison;
  final String? context;
  final PerformanceTone tone;
  final Color? accentColor;
  final String? semanticLabel;
  final VoidCallback? onTap;

  const PerformanceKpiDatum({
    required this.label,
    required this.value,
    this.formattedValue,
    this.prefix = '',
    this.suffix = '',
    this.comparison,
    this.context,
    this.tone = PerformanceTone.neutral,
    this.accentColor,
    this.semanticLabel,
    this.onTap,
  });

  String get displayValue {
    final raw = value;
    if (raw == null || !raw.isFinite) return 'N/A';
    return formattedValue ?? '$prefix${_plainNumber(raw)}$suffix';
  }
}

/// A responsive KPI band that becomes a single column at large text scales.
class PerformanceKpiBand extends StatelessWidget {
  final List<PerformanceKpiDatum> items;
  final int maxColumns;
  final double minCardWidth;
  final EdgeInsetsGeometry padding;

  const PerformanceKpiBand({
    super.key,
    required this.items,
    this.maxColumns = 4,
    this.minCardWidth = 176,
    this.padding = EdgeInsets.zero,
  })  : assert(maxColumns > 0),
        assert(minCardWidth >= 120);

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Padding(
        padding: padding,
        child: Semantics(
          label: 'KPI summary. N/A',
          child: const ExcludeSemantics(child: Text('N/A')),
        ),
      );
    }

    return Padding(
      padding: padding,
      child: LayoutBuilder(
        builder: (context, constraints) {
          const gap = 8.0;
          final scale = MediaQuery.textScalerOf(context).scale(1);
          final width = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : minCardWidth;
          var columns =
              math.max(1, ((width + gap) / (minCardWidth + gap)).floor());
          columns = math.min(columns, math.min(maxColumns, items.length));
          if (scale >= 1.6) columns = 1;
          final cardWidth = math.max(
            0.0,
            (width - gap * (columns - 1)) / columns,
          );

          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final item in items)
                SizedBox(
                  width: cardWidth,
                  child: PerformanceKpiCard(data: item),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// An accessible KPI card. If [PerformanceKpiDatum.onTap] is set, the full
/// surface is a touch target with a minimum height greater than 48 logical px.
class PerformanceKpiCard extends StatelessWidget {
  final PerformanceKpiDatum data;

  const PerformanceKpiCard({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final accent = data.accentColor ?? _toneColor(context, data.tone);
    final details = <String>[
      if (data.comparison?.trim().isNotEmpty ?? false) data.comparison!.trim(),
      if (data.context?.trim().isNotEmpty ?? false) data.context!.trim(),
    ];
    final semantic = data.semanticLabel ??
        [data.label, data.displayValue, ...details].join('. ');

    final body = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 88),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 3,
              height: 50,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data.label,
                    style: TextStyle(
                      color: context.vMute,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    data.displayValue,
                    style: TextStyle(
                      color: context.vInk,
                      fontFamily: 'Poppins',
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      height: 1.15,
                    ),
                  ),
                  if (details.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    for (final detail in details)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          detail,
                          style: TextStyle(
                            color: context.vGrey,
                            fontSize: 11,
                            height: 1.3,
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
            if (data.onTap != null) ...[
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: context.vMute),
            ],
          ],
        ),
      ),
    );

    return Semantics(
      container: true,
      button: data.onTap != null,
      label: semantic,
      child: ExcludeSemantics(
        child: Material(
          color: context.vWhite,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: context.vRule),
          ),
          clipBehavior: Clip.antiAlias,
          child: data.onTap == null
              ? body
              : InkWell(
                  onTap: data.onTap,
                  child: body,
                ),
        ),
      ),
    );
  }
}

/// A paired Snapshot bucket. Keep buckets in strongest-to-weakest order.
/// Null means unavailable and zero means an observed count of zero.
class SnapshotBucketDatum {
  final String label;
  final int? declineCount;
  final int? growthCount;

  const SnapshotBucketDatum({
    required this.label,
    required this.declineCount,
    required this.growthCount,
  })  : assert(declineCount == null || declineCount >= 0),
        assert(growthCount == null || growthCount >= 0);
}

/// A compact 100 percent view of Snapshot counts.
///
/// Shares are calculated only from available counts. Missing bucket values stay
/// visible as N/A in the legend and are never changed to zero.
class SnapshotDistribution100 extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<SnapshotBucketDatum> buckets;
  final Color? declineColor;
  final Color? growthColor;
  final EdgeInsetsGeometry padding;

  const SnapshotDistribution100({
    super.key,
    required this.title,
    required this.buckets,
    this.subtitle,
    this.declineColor,
    this.growthColor,
    this.padding = const EdgeInsets.all(12),
  });

  @override
  Widget build(BuildContext context) {
    final decline = declineColor ?? Theme.of(context).colorScheme.error;
    final growth = growthColor ?? IOH.green;
    final counts = <int>[
      for (final bucket in buckets)
        if (bucket.declineCount != null) bucket.declineCount!,
      for (final bucket in buckets)
        if (bucket.growthCount != null) bucket.growthCount!,
    ];
    final total = counts.fold<int>(0, (sum, value) => sum + value);
    final partial = buckets.any(
      (bucket) => bucket.declineCount == null || bucket.growthCount == null,
    );
    final segments = <_SnapshotSegment>[
      for (var index = 0; index < buckets.length; index++)
        if (buckets[index].declineCount case final count?)
          _SnapshotSegment(
            count: count,
            color: _bucketShade(decline, index),
          ),
      for (var index = buckets.length - 1; index >= 0; index--)
        if (buckets[index].growthCount case final count?)
          _SnapshotSegment(
            count: count,
            color: _bucketShade(growth, index),
          ),
    ];
    final semantic = StringBuffer('$title. Total available count $total. ');
    for (final bucket in buckets) {
      semantic.write(
        '${bucket.label}, decline ${_countText(bucket.declineCount)}, '
        'growth ${_countText(bucket.growthCount)}. ',
      );
    }
    if (partial) semantic.write('Shares use available counts.');

    return Semantics(
      container: true,
      label: semantic.toString(),
      child: ExcludeSemantics(
        child: Container(
          padding: padding,
          decoration: _panelDecoration(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _VisualHeader(
                title: title,
                subtitle: subtitle,
                trailing: 'Total $total',
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  height: 12,
                  color: context.vSubtle,
                  child: total == 0
                      ? Center(
                          child: Text(
                            '0',
                            style: TextStyle(
                              color: context.vMute,
                              fontSize: 10,
                              height: 1,
                            ),
                          ),
                        )
                      : CustomPaint(
                          painter: _DistributionPainter(
                            segments: segments,
                            total: total,
                          ),
                          child: const SizedBox.expand(),
                        ),
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: Text('Bucket',
                          style: TextStyle(
                              color: context.vMute,
                              fontSize: 10,
                              fontWeight: FontWeight.w700)),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text('Decline',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                              color: decline,
                              fontSize: 10,
                              fontWeight: FontWeight.w700)),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text('Growth',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                              color: growth,
                              fontSize: 10,
                              fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              for (var index = 0; index < buckets.length; index++)
                _SnapshotLegendItem(
                  bucket: buckets[index],
                  total: total,
                  declineColor: _bucketShade(decline, index),
                  growthColor: _bucketShade(growth, index),
                ),
              if (partial) ...[
                const SizedBox(height: 12),
                Text(
                  'Some buckets are N/A. Shares use available counts only.',
                  style: TextStyle(
                    color: context.vMute,
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// An expanded mirrored view. Decline is encoded left and growth right.
class SnapshotMirroredBuckets extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<SnapshotBucketDatum> buckets;
  final Color? declineColor;
  final Color? growthColor;
  final EdgeInsetsGeometry padding;

  const SnapshotMirroredBuckets({
    super.key,
    required this.title,
    required this.buckets,
    this.subtitle,
    this.declineColor,
    this.growthColor,
    this.padding = const EdgeInsets.all(12),
  });

  @override
  Widget build(BuildContext context) {
    final decline = declineColor ?? Theme.of(context).colorScheme.error;
    final growth = growthColor ?? IOH.green;
    final validCounts = <int>[
      for (final bucket in buckets)
        if (bucket.declineCount != null) bucket.declineCount!,
      for (final bucket in buckets)
        if (bucket.growthCount != null) bucket.growthCount!,
    ];
    final maxCount = validCounts.fold<int>(0, math.max);
    final semantic = StringBuffer('$title. ');
    for (final bucket in buckets) {
      semantic.write(
        '${bucket.label}, decline ${_countText(bucket.declineCount)}, '
        'growth ${_countText(bucket.growthCount)}. ',
      );
    }

    return Semantics(
      container: true,
      label: semantic.toString(),
      child: ExcludeSemantics(
        child: Container(
          padding: padding,
          decoration: _panelDecoration(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _VisualHeader(title: title, subtitle: subtitle),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Decline',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: decline,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 32),
                  Expanded(
                    child: Text(
                      'Growth',
                      style: TextStyle(
                        color: growth,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              for (var index = 0; index < buckets.length; index++)
                _MirroredBucketRow(
                  bucket: buckets[index],
                  maxCount: maxCount,
                  declineColor: _bucketShade(decline, index),
                  growthColor: _bucketShade(growth, index),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A single stage or count. All values in one [PerformanceStageBars] instance
/// must use the same unit.
class PerformanceStageDatum {
  final String label;
  final num? value;
  final String? formattedValue;
  final String? detail;
  final Color? color;

  const PerformanceStageDatum({
    required this.label,
    required this.value,
    this.formattedValue,
    this.detail,
    this.color,
  }) : assert(value == null || value >= 0);

  String displayValue(PerformanceNumberFormatter? formatter) {
    final raw = value;
    if (raw == null || !raw.isFinite) return 'N/A';
    return formattedValue ?? formatter?.call(raw) ?? _plainNumber(raw);
  }
}

/// Independent stage bars. This widget does not infer funnel conversions.
class PerformanceStageBars extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String unitLabel;
  final List<PerformanceStageDatum> stages;
  final PerformanceNumberFormatter? valueFormatter;
  final Color? barColor;
  final EdgeInsetsGeometry padding;

  const PerformanceStageBars({
    super.key,
    required this.title,
    required this.unitLabel,
    required this.stages,
    this.subtitle,
    this.valueFormatter,
    this.barColor,
    this.padding = const EdgeInsets.all(12),
  });

  @override
  Widget build(BuildContext context) {
    final baseColor = barColor ?? Theme.of(context).colorScheme.primary;
    final values = stages
        .map((stage) => stage.value)
        .whereType<num>()
        .where((value) => value.isFinite)
        .toList();
    final maxValue = values.fold<num>(0, math.max);
    final semantic = StringBuffer('$title. Unit $unitLabel. ');
    for (final stage in stages) {
      semantic.write(
        '${stage.label}, ${stage.displayValue(valueFormatter)}. ',
      );
    }

    return Semantics(
      container: true,
      label: semantic.toString(),
      child: ExcludeSemantics(
        child: Container(
          padding: padding,
          decoration: _panelDecoration(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _VisualHeader(
                title: title,
                subtitle: subtitle,
                trailing: unitLabel,
              ),
              const SizedBox(height: 8),
              if (stages.isEmpty)
                Text('N/A', style: TextStyle(color: context.vMute))
              else
                for (final stage in stages)
                  _StageBarRow(
                    stage: stage,
                    maxValue: maxValue,
                    color: stage.color ?? baseColor,
                    valueFormatter: valueFormatter,
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One point in a single-unit metric trend. Null creates a visual gap.
class MetricTrendPoint {
  final String label;
  final num? value;

  const MetricTrendPoint({required this.label, required this.value});
}

/// A lightweight, single-series sparkline with no dependency on chart packages.
/// Every point is retained and exposed to assistive technology.
class MetricTrendSparkline extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String unitLabel;
  final List<MetricTrendPoint> points;
  final String? headline;
  final Color? color;
  final PerformanceNumberFormatter? valueFormatter;
  final double chartHeight;
  final EdgeInsetsGeometry padding;

  const MetricTrendSparkline({
    super.key,
    required this.title,
    required this.unitLabel,
    required this.points,
    this.subtitle,
    this.headline,
    this.color,
    this.valueFormatter,
    this.chartHeight = 72,
    this.padding = const EdgeInsets.all(12),
  }) : assert(chartHeight >= 64);

  @override
  Widget build(BuildContext context) {
    final lineColor = color ?? Theme.of(context).colorScheme.primary;
    final valid = points.where((point) {
      final value = point.value;
      return value != null && value.isFinite;
    }).toList();
    final semantic = StringBuffer('$title. Unit $unitLabel. ');
    for (final point in points) {
      semantic.write(
        '${point.label}, ${_metricText(point.value, valueFormatter)}. ',
      );
    }

    return Semantics(
      container: true,
      label: semantic.toString(),
      child: ExcludeSemantics(
        child: Container(
          padding: padding,
          decoration: _panelDecoration(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _VisualHeader(
                title: title,
                subtitle: subtitle,
                trailing: unitLabel,
              ),
              if (headline?.trim().isNotEmpty ?? false) ...[
                const SizedBox(height: 8),
                Text(
                  headline!.trim(),
                  style: TextStyle(
                    color: context.vInk,
                    fontFamily: 'Poppins',
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              SizedBox(
                height: chartHeight,
                width: double.infinity,
                child: valid.isEmpty
                    ? Center(
                        child: Text(
                          'N/A',
                          style: TextStyle(color: context.vMute),
                        ),
                      )
                    : CustomPaint(
                        painter: _SparklinePainter(
                          points: points,
                          color: lineColor,
                          ruleColor: context.vRule,
                        ),
                        child: const SizedBox.expand(),
                      ),
              ),
              if (points.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _EndpointLabel(
                        label: points.first.label,
                        value: _metricText(
                          points.first.value,
                          valueFormatter,
                        ),
                        align: TextAlign.start,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _EndpointLabel(
                        label: points.last.label,
                        value: _metricText(
                          points.last.value,
                          valueFormatter,
                        ),
                        align: TextAlign.end,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _VisualHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? trailing;

  const _VisualHeader({this.title = '', this.subtitle, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              title,
              style: TextStyle(
                color: context.vInk,
                fontFamily: 'Poppins',
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (trailing?.trim().isNotEmpty ?? false)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: context.vSubtle,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: context.vRule),
                ),
                child: Text(
                  trailing!.trim(),
                  style: TextStyle(
                    color: context.vGrey,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
        if (subtitle?.trim().isNotEmpty ?? false) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!.trim(),
            style: TextStyle(color: context.vMute, fontSize: 11, height: 1.4),
          ),
        ],
      ],
    );
  }
}

class _SnapshotLegendItem extends StatelessWidget {
  final SnapshotBucketDatum bucket;
  final int total;
  final Color declineColor;
  final Color growthColor;

  const _SnapshotLegendItem({
    required this.bucket,
    required this.total,
    required this.declineColor,
    required this.growthColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: context.vSubtle,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(
              bucket.label,
              softWrap: true,
              style: TextStyle(
                color: context.vInk,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: _LegendValue(
              count: bucket.declineCount,
              total: total,
              color: declineColor,
            ),
          ),
          Expanded(
            flex: 3,
            child: _LegendValue(
              count: bucket.growthCount,
              total: total,
              color: growthColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendValue extends StatelessWidget {
  final int? count;
  final int total;
  final Color color;

  const _LegendValue({
    required this.count,
    required this.total,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final share = count == null ? 'N/A' : _shareText(count!, total);
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text('${_countText(count)}\n$share',
              textAlign: TextAlign.right,
              style:
                  TextStyle(color: context.vGrey, fontSize: 10.5, height: 1.2)),
        ),
      ],
    );
  }
}

class _MirroredBucketRow extends StatelessWidget {
  final SnapshotBucketDatum bucket;
  final int maxCount;
  final Color declineColor;
  final Color growthColor;

  const _MirroredBucketRow({
    required this.bucket,
    required this.maxCount,
    required this.declineColor,
    required this.growthColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.vRule)),
      ),
      child: Column(
        children: [
          Text(
            bucket.label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.vInk,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _MirroredHalf(
                  count: bucket.declineCount,
                  maxCount: maxCount,
                  color: declineColor,
                  alignRight: true,
                ),
              ),
              Container(
                width: 1,
                height: 32,
                margin: const EdgeInsets.symmetric(horizontal: 8),
                color: context.vRule,
              ),
              Expanded(
                child: _MirroredHalf(
                  count: bucket.growthCount,
                  maxCount: maxCount,
                  color: growthColor,
                  alignRight: false,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MirroredHalf extends StatelessWidget {
  final int? count;
  final int maxCount;
  final Color color;
  final bool alignRight;

  const _MirroredHalf({
    required this.count,
    required this.maxCount,
    required this.color,
    required this.alignRight,
  });

  @override
  Widget build(BuildContext context) {
    final factor = count == null || maxCount == 0 ? 0.0 : count! / maxCount;
    final alignment = alignRight ? Alignment.centerRight : Alignment.centerLeft;
    return Column(
      crossAxisAlignment:
          alignRight ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          _countText(count),
          style: TextStyle(
            color: count == null ? context.vMute : context.vInk,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          height: 8,
          alignment: alignment,
          decoration: BoxDecoration(
            color: context.vSubtle,
            borderRadius: BorderRadius.circular(4),
          ),
          child: FractionallySizedBox(
            widthFactor: factor,
            alignment: alignment,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StageBarRow extends StatelessWidget {
  final PerformanceStageDatum stage;
  final num maxValue;
  final Color color;
  final PerformanceNumberFormatter? valueFormatter;

  const _StageBarRow({
    required this.stage,
    required this.maxValue,
    required this.color,
    required this.valueFormatter,
  });

  @override
  Widget build(BuildContext context) {
    final value = stage.value;
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.6;
    final factor = value == null || !value.isFinite || maxValue == 0
        ? 0.0
        : (value / maxValue).toDouble().clamp(0, 1).toDouble();
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.vRule)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (largeText)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _StageLabel(stage: stage),
                const SizedBox(height: 3),
                _StageValue(
                    stage: stage, value: value, valueFormatter: valueFormatter),
              ],
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _StageLabel(
                    stage: stage,
                  ),
                ),
                const SizedBox(width: 12),
                _StageValue(
                  stage: stage,
                  value: value,
                  valueFormatter: valueFormatter,
                ),
              ],
            ),
          const SizedBox(height: 4),
          Container(
            height: 6,
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              color: context.vSubtle,
              borderRadius: BorderRadius.circular(4),
            ),
            child: FractionallySizedBox(
              widthFactor: factor,
              alignment: Alignment.centerLeft,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
          if (stage.detail?.trim().isNotEmpty ?? false) ...[
            const SizedBox(height: 5),
            Text(
              stage.detail!.trim(),
              style:
                  TextStyle(color: context.vMute, fontSize: 10, height: 1.35),
            ),
          ],
        ],
      ),
    );
  }
}

class _StageLabel extends StatelessWidget {
  final PerformanceStageDatum stage;

  const _StageLabel({required this.stage});

  @override
  Widget build(BuildContext context) {
    return Text(
      stage.label,
      style: TextStyle(
        color: context.vInk,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _StageValue extends StatelessWidget {
  final PerformanceStageDatum stage;
  final num? value;
  final PerformanceNumberFormatter? valueFormatter;

  const _StageValue({
    required this.stage,
    required this.value,
    required this.valueFormatter,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      stage.displayValue(valueFormatter),
      textAlign: TextAlign.end,
      style: TextStyle(
        color: value == null ? context.vMute : context.vInk,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _EndpointLabel extends StatelessWidget {
  final String label;
  final String value;
  final TextAlign align;

  const _EndpointLabel({
    required this.label,
    required this.value,
    required this.align,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      '$label\n$value',
      textAlign: align,
      style: TextStyle(color: context.vMute, fontSize: 10, height: 1.35),
    );
  }
}

class _SnapshotSegment {
  final int count;
  final Color color;

  const _SnapshotSegment({required this.count, required this.color});
}

class _DistributionPainter extends CustomPainter {
  final List<_SnapshotSegment> segments;
  final int total;

  const _DistributionPainter({required this.segments, required this.total});

  @override
  void paint(Canvas canvas, Size size) {
    if (total <= 0 || size.isEmpty) return;
    var x = 0.0;
    for (var index = 0; index < segments.length; index++) {
      final segment = segments[index];
      final nextX = index == segments.length - 1
          ? size.width
          : x + size.width * segment.count / total;
      if (nextX > x) {
        canvas.drawRect(
          Rect.fromLTRB(x, 0, nextX, size.height),
          Paint()..color = segment.color,
        );
      }
      x = nextX;
    }
  }

  @override
  bool shouldRepaint(covariant _DistributionPainter oldDelegate) {
    if (oldDelegate.total != total ||
        oldDelegate.segments.length != segments.length) {
      return true;
    }
    for (var index = 0; index < segments.length; index++) {
      final old = oldDelegate.segments[index];
      final current = segments[index];
      if (old.count != current.count || old.color != current.color) return true;
    }
    return false;
  }
}

class _SparklinePainter extends CustomPainter {
  final List<MetricTrendPoint> points;
  final Color color;
  final Color ruleColor;

  const _SparklinePainter({
    required this.points,
    required this.color,
    required this.ruleColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || points.isEmpty) return;
    final values = points
        .map((point) => point.value)
        .whereType<num>()
        .where((value) => value.isFinite)
        .map((value) => value.toDouble())
        .toList();
    if (values.isEmpty) return;

    final minValue = values.reduce(math.min);
    final maxValue = values.reduce(math.max);
    final range = maxValue - minValue;
    const inset = 5.0;
    final drawingWidth = math.max(0.0, size.width - inset * 2);
    final drawingHeight = math.max(0.0, size.height - inset * 2);

    canvas.drawLine(
      Offset(inset, size.height - inset),
      Offset(size.width - inset, size.height - inset),
      Paint()
        ..color = ruleColor
        ..strokeWidth = 1,
    );

    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    Path? activePath;

    for (var index = 0; index < points.length; index++) {
      final value = points[index].value;
      if (value == null || !value.isFinite) {
        if (activePath != null) canvas.drawPath(activePath, linePaint);
        activePath = null;
        continue;
      }
      final x = points.length == 1
          ? size.width / 2
          : inset + drawingWidth * index / (points.length - 1);
      final y = range == 0
          ? size.height / 2
          : inset + drawingHeight * (maxValue - value.toDouble()) / range;
      final position = Offset(x, y);
      if (activePath == null) {
        activePath = Path()..moveTo(x, y);
      } else {
        activePath.lineTo(x, y);
      }
      if (points.length <= 24 || index == 0 || index == points.length - 1) {
        canvas.drawCircle(position, 2.8, dotPaint);
      }
    }
    if (activePath != null) canvas.drawPath(activePath, linePaint);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    if (oldDelegate.color != color ||
        oldDelegate.ruleColor != ruleColor ||
        oldDelegate.points.length != points.length) {
      return true;
    }
    for (var index = 0; index < points.length; index++) {
      final old = oldDelegate.points[index];
      final current = points[index];
      if (old.label != current.label || old.value != current.value) return true;
    }
    return false;
  }
}

BoxDecoration _panelDecoration(BuildContext context) {
  return BoxDecoration(
    color: context.vWhite,
    borderRadius: BorderRadius.circular(14),
    border: Border.all(color: context.vRule),
  );
}

Color _toneColor(BuildContext context, PerformanceTone tone) {
  return switch (tone) {
    PerformanceTone.favorable => IOH.green,
    PerformanceTone.unfavorable => Theme.of(context).colorScheme.error,
    PerformanceTone.warning => IOH.yellow,
    PerformanceTone.neutral => Theme.of(context).colorScheme.primary,
  };
}

Color _bucketShade(Color base, int index) {
  const alpha = <int>[255, 218, 181, 148, 128, 112];
  return base.withAlpha(alpha[math.min(index, alpha.length - 1)]);
}

String _countText(int? count) =>
    count == null ? kReportNotAvailable : reportNumber(count);

String _shareText(int count, int total) {
  if (total <= 0) return count == 0 ? '0%' : kReportNotAvailable;
  final value = count / total * 100;
  // Drop a trailing zero fraction so a clean share reads `40%`, not `40,0%`.
  final decimals = value == value.roundToDouble() ? 0 : 1;
  return reportPercent(value, decimals: decimals);
}

String _metricText(
  num? value,
  PerformanceNumberFormatter? formatter,
) {
  if (value == null || !value.isFinite) return kReportNotAvailable;
  return formatter?.call(value) ?? _plainNumber(value);
}

String _plainNumber(num value) {
  if (!value.isFinite) return kReportNotAvailable;
  return reportMagnitude(value, decimals: 1, useThousand: false);
}
