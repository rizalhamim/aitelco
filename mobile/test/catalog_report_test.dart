import 'package:bizplan_java_agent/src/widgets/catalog_report.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('executive projection maps exactly seven visible period roles', () {
    final projection = CatalogExecutiveProjection.fromColumns(const [
      'LLMTD',
      'LMTD',
      'MTD',
      'VAR',
      'VAR_PCT',
      'LYTD',
      'YTD',
      'VAR_YOY',
      'YOY_PCT',
    ]);

    expect(projection, isNotNull);
    expect(projection!.llmtd, 'LLMTD');
    expect(projection.growthMom, 'VAR_PCT');
    expect(projection.varianceMom, 'VAR');
    expect(projection.growthYoy, 'YOY_PCT');
    expect(projection.varianceYoy, 'VAR_YOY');
  });

  test('custom periods are not forced into executive projection', () {
    final projection = CatalogExecutiveProjection.fromColumns(
      const ['202607', '202608', 'Rank 202608', 'MoM'],
    );

    expect(projection, isNull);
  });

  test('product summary adapter preserves every metric and value column', () {
    final payload = <String, dynamic>{
      'title': 'FWA Summary',
      'columns': ['LMTD', 'MTD', 'Growth'],
      'brands': ['IOH', 'IM3', '3ID'],
      'rows': List.generate(
        64,
        (index) => {
          'code': 'metric_$index',
          'label': 'Metric $index',
          'category': index.isEven ? 'Acquisition' : 'Revenue',
          'unit': 'Subs',
          'brands': {
            'IOH': {'LMTD': index, 'MTD': index + 1, 'Growth': 1.0},
          },
        },
      ),
    };

    final report = CatalogReportData.fromPayload(payload);

    expect(report.metrics, hasLength(64));
    expect(report.sections, hasLength(2));
    expect(report.columns, ['LMTD', 'MTD', 'Growth']);
    expect(report.metrics.last.valueFor('IOH', 'MTD'), 64);
  });

  test('competitive grid adapter retains brands periods ranks and deltas', () {
    final payload = <String, dynamic>{
      'competitive': {
        'page': 'competitive',
        'periods': ['202607', '202608'],
        'brands': ['IOH', 'TSEL'],
        'delta_basis': [
          {'key': 'mom', 'caption': 'MoM'},
        ],
        'sections': [
          {
            'section_id': 'speed',
            'title': 'Speed',
            'metrics': [
              {
                'metric_id': 'download_speed',
                'display_name': 'Download Speed',
                'rows': [
                  {
                    'brand': 'IOH',
                    'values': [20.0, 22.0],
                    'ranks': [2, 1],
                    'deltas': {'mom': 2.0},
                  },
                  {
                    'brand': 'TSEL',
                    'values': [21.0, 21.5],
                    'ranks': [1, 2],
                    'deltas': {'mom': 0.5},
                  },
                ],
              },
            ],
          },
        ],
      },
    };

    final report = CatalogReportData.fromPayload(payload);
    final metric = report.metrics.single;

    expect(report.brands, ['IOH', 'TSEL']);
    expect(report.columns,
        containsAll(['202607', '202608', 'Rank 202608', 'MoM']));
    expect(metric.valueFor('IOH', '202608'), 22.0);
    expect(metric.valueFor('IOH', 'Rank 202608'), 1);
    expect(metric.valueFor('TSEL', 'MoM'), 0.5);
  });

  test('internal adapter keeps unavailable catalog metrics reachable', () {
    final payload = <String, dynamic>{
      'page': 'internal',
      'periods': <String>[],
      'sections': [
        {
          'section_id': 'availability',
          'title': 'Availability',
          'metrics': [
            {
              'metric_id': 'unmapped_metric',
              'display_name': 'Unmapped Metric',
              '_served_availability': 'unmapped',
              '_unavailable_reason': 'No verified source column',
            },
          ],
        },
      ],
    };

    final report = CatalogReportData.fromPayload(payload);

    expect(report.metrics, hasLength(1));
    expect(report.metrics.single.id, 'unmapped_metric');
    expect(report.metrics.single.valuesByBrand, isEmpty);
  });
}
