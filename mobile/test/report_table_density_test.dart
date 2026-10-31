import 'package:bizplan_java_agent/src/theme.dart';
import 'package:bizplan_java_agent/src/widgets/report_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// A realistic Performance Outlook row: unit under the name, variance under growth.
ReportPeriodRow _row(String name) => ReportPeriodRow(
      name: name,
      subtitle: 'Bn',
      code: 'rev_total',
      cells: const {
        'llmtd': ReportPeriodCell('1.234,5'),
        'lmtd': ReportPeriodCell('1.250,1'),
        'mtd': ReportPeriodCell('1.301,9'),
        'growthMom': ReportPeriodCell('+4,1%', secondaryText: '+51,8', raw: 4.1),
        'lytd': ReportPeriodCell('10.980,2'),
        'ytd': ReportPeriodCell('11.402,7'),
        'growthYoy': ReportPeriodCell('+3,8%', secondaryText: '+422,5', raw: 3.8),
      },
    );

Future<List<double>> _rowHeights(WidgetTester tester, double textScale) async {
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light(),
    home: MediaQuery(
      data: MediaQueryData(
        size: const Size(360, 800),
        textScaler: TextScaler.linear(textScale),
      ),
      child: Scaffold(
        body: SingleChildScrollView(
          child: ReportPeriodTable(
            rows: [_row('Revenue Total'), _row('GA Biometric Trade % vs GA Trade')],
            band: Brands.of('ioh'),
            storageKey: 'density',
          ),
        ),
      ),
    ),
  ));
  expect(tester.takeException(), isNull, reason: 'overflow at scale $textScale');
  return [
    for (final name in ['Revenue Total', 'GA Biometric Trade % vs GA Trade'])
      tester.getSize(find.ancestor(
        of: find.text(name),
        matching: find.byType(Container),
      ).first).height,
  ];
}

void main() {
  testWidgets('period rows stay compact and never overflow', (tester) async {
    // Two text lines (value + variance) fit in 52 dp; was 70 before 1.48.3.
    final normal = await _rowHeights(tester, 1);
    expect(normal.first, lessThanOrEqualTo(52));
    // 200 percent text still lays out without clipping, just taller.
    final large = await _rowHeights(tester, 2);
    expect(large.first, greaterThan(normal.first));
  });
}
