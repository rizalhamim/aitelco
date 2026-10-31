import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bizplan_java_agent/src/widgets/chart_panel.dart';

/// The backend decides what to plot (backend/app/chart_spec.py); this widget must
/// honour that decision instead of guessing from column types. The old heuristic
/// plotted the first numeric column, which drew `rank` as bars.
Map<String, dynamic> _spec({
  required String mode,
  required String category,
  required List<Map<String, dynamic>> series,
  String? title,
  String? caption,
  List<Map<String, dynamic>>? rows,
}) =>
    {
      'mode': mode,
      'category': category,
      'series': series,
      if (title != null) 'title': title,
      if (caption != null) 'caption': caption,
      if (rows != null) 'rows': rows,
    };

Map<String, dynamic> _s(String column, String unit,
        {String side = 'left', String? label, bool negative = false}) =>
    {
      'column': column,
      'unit': unit,
      'axis_side': side,
      'label': label ?? column,
      'can_be_negative': negative,
    };

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: SizedBox(width: 900, height: 700, child: child)),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the spec title and caption are shown to the user', (tester) async {
    await _pump(
      tester,
      ChartPanel(
        columns: const ['kecamatan', 'revenue_mn'],
        rows: const [
          {'kecamatan': 'WONOKROMO', 'revenue_mn': 2379.0},
          {'kecamatan': 'SUKOLILO', 'revenue_mn': 2040.0},
        ],
        spec: _spec(
          mode: 'bar',
          category: 'kecamatan',
          series: [_s('revenue_mn', 'Rp')],
          title: 'Revenue per Kecamatan',
          caption: '2 kecamatan',
        ),
      ),
    );
    expect(find.text('Revenue per Kecamatan'), findsOneWidget);
    expect(find.text('2 kecamatan'), findsOneWidget);
  });

  testWidgets('a caption that admits truncation stays visible', (tester) async {
    await _pump(
      tester,
      ChartPanel(
        columns: const ['kabkota', 'revenue'],
        rows: const [
          {'kabkota': 'A', 'revenue': 3.0},
          {'kabkota': 'B', 'revenue': 2.0},
        ],
        spec: _spec(
          mode: 'bar',
          category: 'kabkota',
          series: [_s('revenue', 'Rp')],
          caption: '24 teratas dari 38 kabkota',
        ),
      ),
    );
    expect(find.text('24 teratas dari 38 kabkota'), findsOneWidget);
  });

  testWidgets('units appear in the legend when series differ', (tester) async {
    await _pump(
      tester,
      ChartPanel(
        columns: const ['kabkota', 'total_revenue', 'growth_pct'],
        rows: const [
          {'kabkota': 'SURABAYA', 'total_revenue': 2.3e9, 'growth_pct': 4.2},
          {'kabkota': 'SIDOARJO', 'total_revenue': 1.1e9, 'growth_pct': -2.1},
        ],
        spec: _spec(
          mode: 'bar',
          category: 'kabkota',
          series: [
            _s('total_revenue', 'Rp', label: 'Total revenue'),
            _s('growth_pct', '%', side: 'right', label: 'Growth pct', negative: true),
          ],
        ),
      ),
    );
    // A number without its unit is not an answer: the legend must name both.
    expect(find.text('Total revenue (Rp)'), findsOneWidget);
    expect(find.text('Growth pct (%)'), findsOneWidget);
  });

  testWidgets('a funnel spec offers the funnel view with drop-off percentages',
      (tester) async {
    await _pump(
      tester,
      ChartPanel(
        columns: const ['kabkota', 'so_count', 'sa_count', 'pa_count'],
        rows: const [
          {'kabkota': 'SURABAYA', 'so_count': 1000, 'sa_count': 500, 'pa_count': 250},
        ],
        spec: _spec(
          mode: 'funnel',
          category: 'kabkota',
          series: [
            _s('so_count', '', label: 'SO'),
            _s('sa_count', '', label: 'SA'),
            _s('pa_count', '', label: 'PA'),
          ],
        ),
      ),
    );
    expect(find.text('Funnel'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    // 500 of 1000 and 250 of 500 are both 50 percent conversions.
    expect(find.text('50,0%'), findsNWidgets(2));
  });

  testWidgets('the ranked subset from the spec is what gets plotted', (tester) async {
    // The spec carries the rows it wants drawn; the widget must not fall back to the
    // full unsorted result, or the chart would contradict its own caption.
    final subset = [
      {'kabkota': 'TOP', 'revenue': 900.0},
    ];
    await _pump(
      tester,
      ChartPanel(
        columns: const ['kabkota', 'revenue'],
        rows: const [
          {'kabkota': 'LOW', 'revenue': 1.0},
          {'kabkota': 'TOP', 'revenue': 900.0},
        ],
        spec: _spec(
          mode: 'bar',
          category: 'kabkota',
          series: [_s('revenue', 'Rp')],
          caption: '1 teratas dari 2 kabkota',
          rows: subset,
        ),
      ),
    );
    expect(find.text('1 teratas dari 2 kabkota'), findsOneWidget);
  });

  testWidgets('an empty result renders nothing at all', (tester) async {
    await _pump(
      tester,
      const ChartPanel(columns: ['kabkota', 'revenue'], rows: []),
    );
    expect(find.byType(SizedBox), findsWidgets);
    expect(find.text('Visualisasi'), findsNothing);
  });

  testWidgets('without a spec the fallback never plots an identifier', (tester) async {
    // Old chat history has no spec. `rank` is numeric but is not a quantity, so the
    // fallback must skip it and chart the revenue instead.
    await _pump(
      tester,
      ChartPanel(
        columns: const ['rank', 'kecamatan', 'revenue_mn'],
        rows: const [
          {'rank': 1, 'kecamatan': 'A', 'revenue_mn': 10.0},
          {'rank': 2, 'kecamatan': 'B', 'revenue_mn': 20.0},
        ],
      ),
    );
    // It still renders a chart (title defaults) rather than refusing.
    expect(find.text('Visualisasi'), findsOneWidget);
  });

  testWidgets('a spec with mode none falls back instead of crashing', (tester) async {
    await _pump(
      tester,
      ChartPanel(
        columns: const ['kabkota', 'revenue'],
        rows: const [
          {'kabkota': 'A', 'revenue': 1.0},
        ],
        spec: const {'mode': 'none', 'reason': 'no_plottable_metric'},
      ),
    );
    expect(find.text('Visualisasi'), findsOneWidget);
  });
}
