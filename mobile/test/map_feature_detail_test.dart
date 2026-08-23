import 'package:bizplan_java_agent/src/screens/map_query_screen.dart';
import 'package:bizplan_java_agent/src/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('map field formatting preserves null zero and nested exact values', () {
    expect(mapFeatureRawValue(null), 'N/A');
    expect(mapFeatureRawValue(0), '0');
    expect(mapFeatureRawValue(12.3456), '12.3456');
    expect(mapFeatureRawValue({'mtd': 12}), contains('"mtd": 12'));
    expect(mapFeatureFieldLabel('growth_yoy_pct'), 'Growth YOY PCT');
    expect(mapFeatureScalarValue(false), 'Tidak');
    expect(mapFeatureGrowthValue(-2.5), '-2,5%');

    // The key decides the unit, so an identifier is never comma-grouped and a
    // revenue picks the magnitude that fits its own value.
    expect(mapFeatureScalarValue(202608, key: 'month_id'), '202608');
    expect(mapFeatureScalarValue(12345678, key: 'site_id'), '12345678');
    expect(mapFeatureScalarValue(1250000, key: 'rev_prepaid'), '1,3 Mn IDR');
    expect(mapFeatureScalarValue(4500000000, key: 'rev_prepaid'), '4,5 Bn IDR');
    expect(mapFeatureScalarValue(450, key: 'vlr_daily'), '450');
    expect(mapFeatureScalarValue(1234567, key: 'vlr_daily'), '1,2 Mn');
    expect(mapFeatureScalarValue(-2.5, key: 'growth_pct'), '-2,5%');
    // No key means no unit inference, only separators.
    expect(mapFeatureScalarValue(12.3456), '12,3');
    expect(mapFeatureScalarValue(null), 'N/A');
  });

  test('a field becomes an attribute row with a humanised label', () {
    final attribute = mapFeatureAttribute('rev_prepaid', 1250000);
    expect(attribute.label, 'REV Prepaid');
    expect(attribute.sublabel, 'rev_prepaid');
    expect(attribute.value, '1,3 Mn IDR');
  });

  testWidgets(
      'map feature fields render performance and nested data without JSON',
      (tester) async {
    final fields = <MapEntry<String, dynamic>>[
      const MapEntry('territory_name', 'KOTA SURABAYA'),
      const MapEntry('mtd_value', 0),
      const MapEntry('growth_pct', -2.5),
      const MapEntry('missing_value', null),
      MapEntry('perf', {'rev_prepaid': 1250000, 'vlr_daily': 450}),
      MapEntry('mom', {'rev_prepaid': -2.5, 'vlr_daily': 0}),
      MapEntry('yoy', {'rev_prepaid': 8.25, 'vlr_daily': null}),
      MapEntry('nested_context', {'month_id': 202608}),
    ];
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 900),
          textScaler: TextScaler.linear(2),
        ),
        child: Scaffold(
          body: CustomScrollView(
            cacheExtent: 5000,
            slivers: [MapFeatureFieldSliver(fields: fields)],
          ),
        ),
      ),
    ));

    expect(find.byKey(const ValueKey('map-performance-comparison')),
        findsOneWidget);
    expect(find.text('REV Prepaid'), findsOneWidget);
    expect(find.text('MoM Growth'), findsOneWidget);
    expect(find.text('YoY Growth'), findsOneWidget);
    // growth_pct is a scalar field and also the MoM cell of rev_prepaid, so
    // the same reading legitimately appears twice.
    expect(find.text('-2,5%'), findsNWidgets(2));
    expect(find.text('+8,3%'), findsOneWidget);
    expect(find.text('N/A'), findsWidgets);
    expect(find.text('0'), findsOneWidget);
    expect(find.textContaining('{'), findsNothing);
    expect(find.textContaining('"month_id"'), findsNothing);

    // Structured fields render open inside their own panel, so their contents
    // need scrolling to but no tap to reveal.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -2400));
    await tester.pumpAndSettle();
    expect(find.textContaining('nested_context'), findsWidgets);
    expect(find.text('NESTED CONTEXT'), findsOneWidget);
    expect(find.text('Month ID'), findsOneWidget);
    // Identifiers must not be comma-grouped.
    expect(find.text('202608'), findsOneWidget);
    expect(find.text('202.608'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
