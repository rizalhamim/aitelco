import 'package:bizplan_java_agent/src/theme.dart';
import 'package:bizplan_java_agent/src/widgets/performance_visuals.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child, {double textScale = 1}) {
  return MaterialApp(
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    home: MediaQuery(
      data: MediaQueryData(
        size: const Size(320, 800),
        textScaler: TextScaler.linear(textScale),
      ),
      child: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: child,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('KPI band keeps null and zero distinct at 200 percent text scale',
      (tester) async {
    await tester.pumpWidget(_app(
      const PerformanceKpiBand(items: [
        PerformanceKpiDatum(label: 'Unavailable', value: null),
        PerformanceKpiDatum(label: 'Observed zero', value: 0),
      ]),
      textScale: 2,
    ));

    expect(find.text('N/A'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Snapshot visual retains every paired bucket', (tester) async {
    const buckets = [
      SnapshotBucketDatum(label: '> 5%', declineCount: 2, growthCount: 4),
      SnapshotBucketDatum(label: '3% to 5%', declineCount: 0, growthCount: 3),
      SnapshotBucketDatum(label: '1% to 3%', declineCount: 1, growthCount: 2),
      SnapshotBucketDatum(
          label: '0% to 1%', declineCount: null, growthCount: 1),
    ];
    await tester.pumpWidget(_app(
      const SnapshotDistribution100(
        title: 'Kecamatan Health',
        buckets: buckets,
      ),
    ));

    for (final bucket in buckets) {
      expect(find.text(bucket.label), findsOneWidget);
    }
    expect(find.textContaining('N/A'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Stage bars do not infer conversion', (tester) async {
    await tester.pumpWidget(_app(
      const PerformanceStageBars(
        title: 'FTTH Stage Values',
        unitLabel: 'Orders',
        stages: [
          PerformanceStageDatum(label: 'SO', value: 10),
          PerformanceStageDatum(label: 'SA', value: 14),
          PerformanceStageDatum(label: 'PA', value: 8),
        ],
      ),
    ));

    expect(find.textContaining('conversion'), findsNothing);
    expect(find.text('SO'), findsOneWidget);
    expect(find.text('SA'), findsOneWidget);
    expect(find.text('PA'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
