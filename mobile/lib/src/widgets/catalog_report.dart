import 'package:flutter/material.dart';

import '../format/report_format.dart';
import '../theme.dart';
import 'report_ui.dart';

/// Normalized, additive report contract used by the large catalog reports.
///
/// The adapter accepts product-summary rows, registry/grid sections, and the
/// existing section metric shape. This lets the mobile client adopt versioned
/// contracts without making older report payloads unreadable.
class CatalogReportData {
  final String title;
  final String subtitle;
  final String? source;
  final String? dataAsOf;
  final String? schemaVersion;
  final List<String> columns;
  final List<String> brands;
  final List<CatalogReportSection> sections;

  const CatalogReportData({
    required this.title,
    required this.subtitle,
    required this.columns,
    required this.brands,
    required this.sections,
    this.source,
    this.dataAsOf,
    this.schemaVersion,
  });

  factory CatalogReportData.fromPayload(Map<String, dynamic>? payload) {
    if (payload == null) return CatalogReportData.empty();
    var root = Map<String, dynamic>.from(payload);
    for (final key in const [
      'data',
      'catalog',
      'competitive',
      'grid',
      'report'
    ]) {
      final candidate = _stringMap(payload[key]);
      if (candidate['sections'] is List || candidate['rows'] is List) {
        root = candidate;
        break;
      }
    }
    final meta = _stringMap(payload['meta']);
    for (final key in const [
      'data_as_of',
      'source',
      'schema_version',
      'version'
    ]) {
      if (root[key] == null && meta[key] != null) root[key] = meta[key];
    }
    final productRows = _mapList(root['rows']);
    if (productRows.isNotEmpty) return _fromProduct(root, productRows);
    return _fromSections(root);
  }

  factory CatalogReportData.empty() => const CatalogReportData(
        title: '',
        subtitle: '',
        columns: [],
        brands: [],
        sections: [],
      );

  bool get hasMetrics => sections.any((section) => section.metrics.isNotEmpty);

  List<CatalogReportMetric> get metrics => [
        for (final section in sections) ...section.metrics,
      ];

  List<String> get categories {
    final result = <String>[];
    for (final section in sections) {
      if (section.category.isNotEmpty && !result.contains(section.category)) {
        result.add(section.category);
      }
    }
    return result;
  }

  static CatalogReportData _fromProduct(
    Map<String, dynamic> root,
    List<Map<String, dynamic>> rows,
  ) {
    final columns = _strings(root['columns']);
    final brands = _strings(root['brands']);
    final sections = <CatalogReportSection>[];
    final byCategory = <String, List<CatalogReportMetric>>{};
    for (final row in rows) {
      final category = _firstText(row, ['category', 'group'], 'Metrics');
      final brandValues = <String, Map<String, dynamic>>{};
      final rawBrands = _stringMap(row['brands']);
      rawBrands.forEach((key, value) {
        brandValues[key] = _stringMap(value);
      });
      final metric = CatalogReportMetric(
        id: _firstText(row, ['id', 'metric_id', 'code'], 'metric'),
        label: _firstText(row, ['label', 'name'], 'Metric'),
        unit: _firstText(row, ['uom', 'unit'], ''),
        format: _firstText(row, ['format', 'value_format'], ''),
        direction: _firstText(row, ['direction', 'polarity'], 'na'),
        kind: _firstText(row, ['kind', 'temporal_type'], ''),
        threshold: row['threshold'],
        detail: _metricDetail(row),
        valuesByBrand: brandValues,
      );
      byCategory.putIfAbsent(category, () => []).add(metric);
    }
    byCategory.forEach((category, metrics) {
      sections.add(CatalogReportSection(
        id: _slug(category),
        title: category,
        category: category,
        metrics: metrics,
      ));
    });
    return CatalogReportData(
      title: _firstText(root, ['title'], ''),
      subtitle: _firstText(root, ['subtitle', 'product'], ''),
      source: _optionalText(root, ['source']),
      dataAsOf: _optionalText(root, ['data_as_of']) ??
          _optionalText(_stringMap(root['scope']), ['data_as_of']),
      schemaVersion: _optionalText(root,
          ['schema_version', 'contract_version', 'catalog_version', 'version']),
      columns: columns.isEmpty ? _discoverColumns(sections) : columns,
      brands: brands.isEmpty ? _discoverBrands(sections) : brands,
      sections: sections,
    );
  }

  static CatalogReportData _fromSections(Map<String, dynamic> root) {
    final rawSections = _mapList(root['sections']);
    final page = _firstText(root, ['page', 'family', 'report'], '');
    final periods = _strings(root['periods']);
    final configuredColumns = _strings(root['columns']);
    final deltaBasis = _mapList(root['delta_basis']);
    final rootBrands = _strings(root['brands']);
    final comparison = _stringMap(root['comparison']);
    final basisPeriod = _firstText(comparison, ['basis_period'], '');
    final absoluteChangeColumn =
        basisPeriod.isEmpty ? 'Absolute Change' : 'Absolute vs $basisPeriod';
    final percentChangeColumn =
        basisPeriod.isEmpty ? 'Percent Change' : 'Growth vs $basisPeriod';
    final sections = <CatalogReportSection>[];
    var hasRanks = false;
    var hasCompare = false;
    var hasPreviousComparison = false;

    for (final rawSection in rawSections) {
      final id = _firstText(rawSection, ['section_id', 'id', 'code'],
          'section-${sections.length + 1}');
      final title = _firstText(rawSection, ['title', 'name'], id);
      final category = _firstText(
        rawSection,
        ['domain', 'category', 'group'],
        _domainForSection(page, id, title),
      );
      final metrics = <CatalogReportMetric>[];
      for (final rawMetric in _mapList(rawSection['metrics'])) {
        final valuesByBrand = <String, Map<String, dynamic>>{};
        final gridRows = _mapList(rawMetric['rows']);
        if (gridRows.isNotEmpty) {
          for (final row in gridRows) {
            final brand = _firstText(row, ['brand', 'operator'], 'IOH');
            final values = <String, dynamic>{};
            final series = row['values'] as List? ?? const [];
            for (var index = 0; index < periods.length; index++) {
              values[periods[index]] =
                  index < series.length ? series[index] : null;
            }
            final ranks = row['ranks'] as List?;
            if (ranks != null) {
              for (var index = 0; index < periods.length; index++) {
                final rank = index < ranks.length ? ranks[index] : null;
                values['Rank ${periods[index]}'] = rank;
                if (rank != null) hasRanks = true;
              }
            }
            final deltas = _stringMap(row['deltas']);
            for (final basis in deltaBasis) {
              final key = _firstText(basis, ['key'], 'delta');
              final caption = _firstText(basis, ['caption'], key.toUpperCase());
              values[caption] = deltas[key];
            }
            if (row.containsKey('compare_delta')) {
              values['Compare'] = row['compare_delta'];
              if (row['compare_delta'] != null) hasCompare = true;
            }
            valuesByBrand[brand] = values;
          }
        } else {
          final rawSeries = _stringMap(rawMetric['series']);
          final rawComparison = _stringMap(rawMetric['previous_december']);
          rawSeries.forEach((brand, value) {
            final values = <String, dynamic>{};
            for (final point in _mapList(value)) {
              final period = _firstText(point, ['period'], '');
              if (period.isEmpty) continue;
              values[period] = point['value'];
              if (point['rank'] != null) {
                values['Rank $period'] = point['rank'];
                hasRanks = true;
              }
            }
            final comparison = _stringMap(rawComparison[brand]);
            if (comparison.isNotEmpty) {
              values[absoluteChangeColumn] = comparison['absolute'];
              values[percentChangeColumn] = comparison['percent'];
              hasPreviousComparison = true;
            }
            valuesByBrand[brand] = values;
          });
          final rawBrands = _stringMap(rawMetric['brands']);
          if (valuesByBrand.isEmpty) {
            rawBrands.forEach((key, value) {
              valuesByBrand[key] = _stringMap(value);
            });
          }
          if (valuesByBrand.isEmpty) {
            for (final brand in const ['ioh', 'im3', '3id']) {
              final value = _stringMap(rawMetric[brand]);
              if (value.isNotEmpty) valuesByBrand[brand.toUpperCase()] = value;
            }
          }
          if (valuesByBrand.isEmpty) {
            final rawValues = _stringMap(rawMetric['values']);
            if (rawValues.isNotEmpty) {
              final nested = rawValues.values.any((value) => value is Map);
              if (nested) {
                rawValues.forEach((key, value) {
                  valuesByBrand[key] = _stringMap(value);
                });
              } else {
                valuesByBrand['IOH'] = rawValues;
              }
            }
          }
        }
        metrics.add(CatalogReportMetric(
          id: _firstText(rawMetric, ['metric_id', 'id', 'code'], 'metric'),
          label: _firstText(
              rawMetric, ['display_name', 'name', 'label'], 'Metric'),
          unit: _firstText(rawMetric, ['uom', 'unit'], ''),
          format: _firstText(rawMetric, ['value_format', 'format'], ''),
          direction: _firstText(rawMetric, ['direction', 'polarity'], 'na'),
          kind: _firstText(rawMetric, ['kind', 'temporal_type'], ''),
          threshold: rawMetric['threshold'],
          detail: _metricDetail(rawMetric),
          isHeader: rawMetric['is_header'] == true,
          valuesByBrand: valuesByBrand,
        ));
      }
      sections.add(CatalogReportSection(
        id: id,
        title: title,
        category: category,
        metrics: metrics,
      ));
    }

    final columns = <String>[
      if (configuredColumns.isNotEmpty) ...configuredColumns else ...periods,
      if (hasRanks)
        for (final period in periods) 'Rank $period',
      if (hasPreviousComparison) ...[
        absoluteChangeColumn,
        percentChangeColumn,
      ],
      for (final basis in deltaBasis)
        _firstText(basis, ['caption'],
            _firstText(basis, ['key'], 'Delta').toUpperCase()),
      if (hasCompare) 'Compare',
    ];
    return CatalogReportData(
      title: _firstText(
        root,
        ['title'],
        page.toLowerCase().contains('internal')
            ? 'Internal Net Performance'
            : page.toLowerCase().contains('competitive')
                ? 'Network Benchmark'
                : '',
      ),
      subtitle: _firstText(root, ['subtitle', 'filter_log'], ''),
      source: _optionalText(root, ['source']),
      dataAsOf: _optionalText(root, ['data_as_of']) ??
          _optionalText(_stringMap(root['scope']), ['data_as_of']),
      schemaVersion: _optionalText(root,
          ['schema_version', 'contract_version', 'catalog_version', 'version']),
      columns: columns.isEmpty ? _discoverColumns(sections) : columns,
      brands: rootBrands.isEmpty ? _discoverBrands(sections) : rootBrands,
      sections: sections,
    );
  }
}

class CatalogReportSection {
  final String id;
  final String title;
  final String category;
  final List<CatalogReportMetric> metrics;

  const CatalogReportSection({
    required this.id,
    required this.title,
    required this.category,
    required this.metrics,
  });
}

class CatalogReportMetric {
  final String id;
  final String label;
  final String unit;
  final String format;
  final String direction;
  final String kind;
  final Object? threshold;
  final String detail;
  final bool isHeader;
  final Map<String, Map<String, dynamic>> valuesByBrand;

  const CatalogReportMetric({
    required this.id,
    required this.label,
    required this.unit,
    required this.format,
    required this.direction,
    required this.kind,
    required this.threshold,
    required this.detail,
    required this.valuesByBrand,
    this.isHeader = false,
  });

  List<String> get brands => valuesByBrand.keys.toList();

  Map<String, dynamic> valuesFor(String preferredBrand) {
    final preferred = preferredBrand.toUpperCase();
    for (final entry in valuesByBrand.entries) {
      if (entry.key.toUpperCase() == preferred) return entry.value;
    }
    return valuesByBrand.isEmpty ? const {} : valuesByBrand.values.first;
  }

  dynamic valueFor(String preferredBrand, String column) {
    final values = valuesFor(preferredBrand);
    if (values.containsKey(column)) return values[column];
    final wanted = column.toLowerCase();
    for (final entry in values.entries) {
      if (entry.key.toLowerCase() == wanted) return entry.value;
    }
    return null;
  }

  String formatValue(dynamic value, {String? column}) {
    if (value == null) return kReportNotAvailable;
    if (value is! num) return value.toString();
    final number = value.toDouble();
    final normalized = format.toLowerCase();
    final isRank = column?.toLowerCase().startsWith('rank ') == true;
    final isPercent = normalized.contains('%') ||
        normalized.startsWith('pct') ||
        unit == '%' ||
        unit.toLowerCase() == 'percent' ||
        column?.toUpperCase().endsWith('_PCT') == true ||
        column?.toUpperCase().contains('PERCENT') == true ||
        column?.toUpperCase().startsWith('GROWTH ') == true;
    if (isRank) return reportNumber(number);
    if (isPercent) {
      final decimals =
          normalized.contains('0.0') || normalized.endsWith('1') ? 1 : 0;
      return reportPercent(number, decimals: decimals);
    }
    // Catalog units may already carry a magnitude word (for example `IDR Bn`).
    // Lift the value back to absolute so a small revenue shows Mn, not `0,0 Bn`.
    final parsed = reportUnitBase(unit);
    if (parsed.base > 1) return reportPreScaled(number, unit);
    final decimals = normalized.contains('0.00') || normalized.endsWith('2')
        ? 2
        : normalized.contains('0.0') || normalized.endsWith('1')
            ? 1
            : 0;
    return reportNumber(number, decimals: decimals);
  }
}

class CatalogReportView extends StatelessWidget {
  final CatalogReportData data;
  final String reportKey;
  final String selectedBrand;
  final bool includeAllBrands;
  final String query;
  final String category;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<String> onCategoryChanged;
  final Set<String> expandedSections;
  final bool expandAll;
  final void Function(String sectionTitle, bool expanded) onExpansionChanged;

  const CatalogReportView({
    super.key,
    required this.data,
    required this.reportKey,
    required this.selectedBrand,
    required this.includeAllBrands,
    required this.query,
    required this.category,
    required this.onQueryChanged,
    required this.onCategoryChanged,
    required this.expandedSections,
    required this.expandAll,
    required this.onExpansionChanged,
  });

  @override
  Widget build(BuildContext context) {
    final normalizedQuery = query.trim().toLowerCase();
    final visible = <CatalogReportSection>[];
    var visibleMetricCount = 0;
    for (final section in data.sections) {
      if (category.isNotEmpty && section.category != category) continue;
      final metrics = normalizedQuery.isEmpty
          ? section.metrics
          : section.metrics.where((metric) {
              return '${metric.label} ${metric.id} ${metric.unit} ${section.title} ${section.category}'
                  .toLowerCase()
                  .contains(normalizedQuery);
            }).toList();
      if (metrics.isEmpty) continue;
      visible.add(CatalogReportSection(
        id: section.id,
        title: section.title,
        category: section.category,
        metrics: metrics,
      ));
      visibleMetricCount += metrics.where((metric) => !metric.isHeader).length;
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _CatalogControlPanel(
        data: data,
        query: query,
        category: category,
        visibleMetricCount: visibleMetricCount,
        onQueryChanged: onQueryChanged,
        onCategoryChanged: onCategoryChanged,
      ),
      const SizedBox(height: 10),
      if (visible.isEmpty)
        Semantics(
          container: true,
          label: 'Tidak ada metrik yang cocok',
          child: Container(
            constraints: const BoxConstraints(minHeight: 96),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: context.vWhite,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.vRule),
            ),
            child: Text(
              'Tidak ada metrik yang cocok. Ubah pencarian atau kategori.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.vMute, fontSize: 12),
            ),
          ),
        )
      else
        for (var index = 0; index < visible.length; index++) ...[
          _catalogChapter(context, visible[index], normalizedQuery.isNotEmpty),
          if (index < visible.length - 1) const SizedBox(height: 10),
        ],
    ]);
  }

  Widget _catalogChapter(
    BuildContext context,
    CatalogReportSection section,
    bool searching,
  ) {
    final key = '$reportKey|${section.title}';
    final metricCount =
        section.metrics.where((metric) => !metric.isHeader).length;
    final expanded = searching || expandAll || expandedSections.contains(key);
    return ReportChapter(
      key: ValueKey(key),
      title: section.title,
      summary: '$metricCount metrik, seluruh nilai tersedia',
      badge: section.category == section.title ? null : section.category,
      expanded: expanded,
      onExpansionChanged: (value) => onExpansionChanged(section.title, value),
      contentBuilder: (_) => _CatalogMetricTable(
        section: section,
        columns: data.columns,
        selectedBrand: selectedBrand,
        includeAllBrands: includeAllBrands,
      ),
    );
  }
}

class _CatalogControlPanel extends StatelessWidget {
  final CatalogReportData data;
  final String query;
  final String category;
  final int visibleMetricCount;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<String> onCategoryChanged;

  const _CatalogControlPanel({
    required this.data,
    required this.query,
    required this.category,
    required this.visibleMetricCount,
    required this.onQueryChanged,
    required this.onCategoryChanged,
  });

  @override
  Widget build(BuildContext context) {
    final categories = data.categories;
    final meta = <String>[
      '$visibleMetricCount metrik',
      if (data.brands.isNotEmpty) 'Brand ${data.brands.join(', ')}',
      if (data.source != null) data.source!,
      if (data.dataAsOf != null) 'Data ${data.dataAsOf}',
      if (data.schemaVersion != null) 'Schema ${data.schemaVersion}',
    ];
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.vWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.vRule),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(
              data.title.isEmpty ? 'Metric Explorer' : data.title,
              style: TextStyle(
                color: context.vInk,
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          Text(
            '$visibleMetricCount',
            style: const TextStyle(
              color: IOH.teal600,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ]),
        if (meta.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(meta.join(' | '),
              style: TextStyle(color: context.vMute, fontSize: 10.5)),
        ],
        const SizedBox(height: 8),
        _CatalogSearchField(
          value: query,
          onChanged: onQueryChanged,
        ),
        if (categories.length > 1) ...[
          const SizedBox(height: 6),
          Semantics(
            container: true,
            label: 'Filter kategori metrik',
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                _CategoryButton(
                  label: 'Semua',
                  selected: category.isEmpty,
                  onTap: () => onCategoryChanged(''),
                ),
                for (final item in categories)
                  _CategoryButton(
                    label: item,
                    selected: category == item,
                    onTap: () => onCategoryChanged(item),
                  ),
              ]),
            ),
          ),
        ],
      ]),
    );
  }
}

class _CatalogSearchField extends StatefulWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _CatalogSearchField({
    required this.value,
    required this.onChanged,
  });

  @override
  State<_CatalogSearchField> createState() => _CatalogSearchFieldState();
}

class _CatalogSearchFieldState extends State<_CatalogSearchField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(covariant _CatalogSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: TextField(
        controller: _controller,
        onChanged: widget.onChanged,
        textInputAction: TextInputAction.search,
        style: TextStyle(color: context.vInk, fontSize: 12),
        decoration: InputDecoration(
          hintText: 'Cari nama atau kode metrik',
          prefixIcon: const Icon(Icons.search, size: 18),
          suffixIcon: widget.value.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Hapus pencarian',
                  onPressed: () => widget.onChanged(''),
                  icon: const Icon(Icons.close, size: 18),
                ),
          isDense: true,
          filled: true,
          fillColor: context.vPanel,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: context.vRule),
          ),
        ),
      ),
    );
  }
}

class _CategoryButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Center(
              child: Container(
                constraints: const BoxConstraints(minHeight: 34),
                margin: const EdgeInsets.only(right: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: selected
                      ? IOH.teal500.withValues(alpha: 0.1)
                      : context.vPanel,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                    color: selected ? IOH.teal500 : context.vRule,
                  ),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: selected ? IOH.teal600 : context.vInk,
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CatalogMetricRow {
  final CatalogReportMetric metric;
  final String brand;

  const _CatalogMetricRow(this.metric, this.brand);
}

@immutable
class CatalogExecutiveProjection {
  final String llmtd;
  final String lmtd;
  final String mtd;
  final String growthMom;
  final String? varianceMom;
  final String lytd;
  final String ytd;
  final String growthYoy;
  final String? varianceYoy;

  const CatalogExecutiveProjection({
    required this.llmtd,
    required this.lmtd,
    required this.mtd,
    required this.growthMom,
    required this.varianceMom,
    required this.lytd,
    required this.ytd,
    required this.growthYoy,
    required this.varianceYoy,
  });

  static CatalogExecutiveProjection? fromColumns(List<String> columns) {
    String normalized(String value) => value
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');

    String? find(List<String> aliases) {
      final wanted = aliases.map(normalized).toSet();
      for (final column in columns) {
        if (wanted.contains(normalized(column))) return column;
      }
      return null;
    }

    final llmtd = find(const ['LLMTD']);
    final lmtd = find(const ['LMTD']);
    final mtd = find(const ['MTD']);
    final growthMom = find(const [
      'VAR_PCT',
      'GROWTH_MOM_PCT',
      'MOM_PCT',
      'GROWTH_MOM',
      'GROWTH',
    ]);
    final lytd = find(const ['LYTD']);
    final ytd = find(const ['YTD']);
    final growthYoy = find(const [
      'YOY_PCT',
      'GROWTH_YOY_PCT',
      'GROWTH_YOY',
    ]);
    if ([llmtd, lmtd, mtd, growthMom, lytd, ytd, growthYoy]
        .any((value) => value == null)) {
      return null;
    }
    return CatalogExecutiveProjection(
      llmtd: llmtd!,
      lmtd: lmtd!,
      mtd: mtd!,
      growthMom: growthMom!,
      varianceMom: find(const ['VAR', 'VAR_MOM', 'ABS_CHANGE_MOM']),
      lytd: lytd!,
      ytd: ytd!,
      growthYoy: growthYoy!,
      varianceYoy: find(const ['VAR_YOY', 'ABS_CHANGE_YOY']),
    );
  }
}

class _CatalogMetricTable extends StatelessWidget {
  final CatalogReportSection section;
  final List<String> columns;
  final String selectedBrand;
  final bool includeAllBrands;

  const _CatalogMetricTable({
    required this.section,
    required this.columns,
    required this.selectedBrand,
    required this.includeAllBrands,
  });

  @override
  Widget build(BuildContext context) {
    final rows = <_CatalogMetricRow>[];
    for (final metric in section.metrics) {
      if (metric.isHeader || metric.valuesByBrand.isEmpty) {
        rows.add(_CatalogMetricRow(metric, ''));
        continue;
      }
      if (includeAllBrands) {
        for (final brand in metric.brands) {
          rows.add(_CatalogMetricRow(metric, brand));
        }
      } else {
        var brand = selectedBrand.toUpperCase();
        if (!metric.brands.any((item) => item.toUpperCase() == brand)) {
          brand = metric.brands.first;
        }
        rows.add(_CatalogMetricRow(metric, brand));
      }
    }
    final showBrand = includeAllBrands ||
        rows
                .map((row) => row.brand)
                .where((brand) => brand.isNotEmpty)
                .toSet()
                .length >
            1;
    final executive = CatalogExecutiveProjection.fromColumns(columns);
    final metricWidth = showBrand ? 176.0 : 158.0;
    String metricIdentity(_CatalogMetricRow row) {
      if (row.brand.isEmpty || !showBrand) return row.metric.label;
      return '${row.metric.label}\n${row.brand}';
    }

    dynamic value(_CatalogMetricRow row, String? column) =>
        column == null ? null : row.metric.valueFor(row.brand, column);

    String formatted(_CatalogMetricRow row, String? column) => column == null
        ? kReportNotAvailable
        : row.metric.formatValue(value(row, column), column: column);

    // Growth polarity is per metric: churn rising is not the same news as
    // revenue rising, and the two sit in the same table.
    ReportPolarity polarityOf(_CatalogMetricRow row) =>
        reportPolarityFor('${row.metric.id} ${row.metric.label}');

    final dataColumns = executive == null
        ? <ReportTableColumn<_CatalogMetricRow>>[
            for (final column in columns)
              ReportTableColumn(
                label: column,
                width: column.toLowerCase().startsWith('rank ') ? 84 : 104,
                numeric: true,
                value: (row) => formatted(row, column),
              ),
          ]
        : <ReportTableColumn<_CatalogMetricRow>>[
            ReportTableColumn(
              label: 'LLMTD',
              width: 86,
              numeric: true,
              value: (row) => formatted(row, executive.llmtd),
            ),
            ReportTableColumn(
              label: 'LMTD',
              width: 86,
              numeric: true,
              value: (row) => formatted(row, executive.lmtd),
            ),
            ReportTableColumn(
              label: 'MTD',
              width: 86,
              numeric: true,
              emphasized: true,
              value: (row) => formatted(row, executive.mtd),
            ),
            ReportTableColumn(
              label: 'Growth',
              semanticLabel: 'Growth MTD terhadap LMTD',
              width: 106,
              numeric: true,
              comparison: true,
              value: (row) => formatted(row, executive.growthMom),
              secondaryValue: executive.varianceMom == null
                  ? null
                  : (row) => formatted(row, executive.varianceMom),
              signal: (row) => value(row, executive.growthMom),
              polarityOf: polarityOf,
            ),
            ReportTableColumn(
              label: 'LYTD',
              width: 86,
              numeric: true,
              value: (row) => formatted(row, executive.lytd),
            ),
            ReportTableColumn(
              label: 'YTD',
              width: 86,
              numeric: true,
              emphasized: true,
              value: (row) => formatted(row, executive.ytd),
            ),
            ReportTableColumn(
              label: 'Growth',
              semanticLabel: 'Growth YTD terhadap LYTD',
              width: 106,
              numeric: true,
              comparison: true,
              value: (row) => formatted(row, executive.growthYoy),
              secondaryValue: executive.varianceYoy == null
                  ? null
                  : (row) => formatted(row, executive.varianceYoy),
              signal: (row) => value(row, executive.growthYoy),
              polarityOf: polarityOf,
            ),
          ];
    return ReportAllDataTable<_CatalogMetricRow>(
      semanticLabel:
          '${section.title}, ${section.metrics.length} metrik, data lengkap',
      rows: rows,
      layoutPolicy: ReportTableLayoutPolicy.horizontal,
      freezeFirstColumn: true,
      onFirstColumnTap: (row) => _showMetricDetails(context, row),
      headerBackground: _catalogHeaderColor(selectedBrand),
      storageKey: 'catalog-${section.id}-$selectedBrand-${columns.join('|')}',
      columns: [
        ReportTableColumn(
          label: 'Metric',
          width: metricWidth,
          emphasized: true,
          value: metricIdentity,
        ),
        ...dataColumns,
      ],
    );
  }

  Color _catalogHeaderColor(String brand) =>
      brand.isEmpty ? IOH.teal500 : Brands.colorOf(brand);

  Future<void> _showMetricDetails(
    BuildContext context,
    _CatalogMetricRow row,
  ) {
    final metric = row.metric;
    final values = metric.valuesFor(row.brand);
    final details = <MapEntry<String, String>>[
      MapEntry('Metric ID', metric.id),
      if (row.brand.isNotEmpty) MapEntry('Brand', row.brand),
      MapEntry('Unit', metric.unit.isEmpty ? 'N/A' : metric.unit),
      MapEntry(
        'Type',
        metric.kind.isNotEmpty
            ? metric.kind
            : _directionLabel(metric.direction),
      ),
      MapEntry('Direction', _directionLabel(metric.direction)),
      MapEntry('Threshold', metric.threshold?.toString() ?? 'N/A'),
      MapEntry('Detail', metric.detail.isEmpty ? 'N/A' : metric.detail),
      for (final entry in values.entries)
        MapEntry(entry.key, metric.formatValue(entry.value, column: entry.key)),
    ];
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.56,
        minChildSize: 0.35,
        maxChildSize: 0.9,
        builder: (sheetContext, controller) => Container(
          decoration: BoxDecoration(
            color: context.vWhite,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              const SizedBox(height: 9),
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: context.vRule,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        metric.label,
                        style: TextStyle(
                          color: context.vInk,
                          fontFamily: 'Poppins',
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Tutup',
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: context.vRule),
              Expanded(
                child: ListView.builder(
                  controller: controller,
                  itemCount: details.length,
                  itemBuilder: (context, index) {
                    final entry = details[index];
                    return Container(
                      color: index.isOdd ? context.vZebra : context.vWhite,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 4,
                            child: Text(
                              entry.key,
                              style: TextStyle(
                                color: context.vMute,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 6,
                            child: SelectableText(
                              entry.value,
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                color: context.vInk,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _directionLabel(String direction) {
  return switch (direction.toLowerCase()) {
    'higher_is_better' => 'Higher is better',
    'lower_is_better' => 'Lower is better',
    _ => 'Neutral',
  };
}

Map<String, dynamic> _stringMap(dynamic value) {
  if (value is! Map) return {};
  return value.map((key, item) => MapEntry(key.toString(), item));
}

List<Map<String, dynamic>> _mapList(dynamic value) {
  if (value is! List) return [];
  return value.whereType<Map>().map(_stringMap).toList();
}

List<String> _strings(dynamic value) {
  if (value is! List) return [];
  return value.map((item) => item.toString()).toList();
}

String _firstText(
  Map<String, dynamic> source,
  List<String> keys,
  String fallback,
) {
  for (final key in keys) {
    final value = source[key]?.toString().trim();
    if (value != null && value.isNotEmpty) return value;
  }
  return fallback;
}

String? _optionalText(Map<String, dynamic> source, List<String> keys) {
  final value = _firstText(source, keys, '');
  return value.isEmpty ? null : value;
}

String _metricDetail(Map<String, dynamic> metric) {
  final parts = <String>[];
  void add(String label, dynamic value) {
    final text = value?.toString().trim();
    if (text != null && text.isNotEmpty && text != 'null') {
      parts.add('$label: $text');
    }
  }

  add('Definition', metric['definition']);
  add('Availability', metric['availability']);
  add('Source', metric['served_source']);
  add('Reason', metric['unavailable_reason']);
  add('Temporal', metric['temporal']);
  add('Grain', metric['source_grain']);
  final capabilities = _stringMap(metric['capabilities']);
  final enabled = capabilities.entries
      .where((entry) => entry.value == true)
      .map((entry) => entry.key)
      .toList();
  if (enabled.isNotEmpty) parts.add('Capabilities: ${enabled.join(', ')}');
  return parts.join(' | ');
}

List<String> _discoverBrands(List<CatalogReportSection> sections) {
  final result = <String>[];
  for (final section in sections) {
    for (final metric in section.metrics) {
      for (final brand in metric.brands) {
        if (!result.contains(brand)) result.add(brand);
      }
    }
  }
  return result;
}

List<String> _discoverColumns(List<CatalogReportSection> sections) {
  final result = <String>[];
  for (final section in sections) {
    for (final metric in section.metrics) {
      for (final values in metric.valuesByBrand.values) {
        for (final column in values.keys) {
          if (!result.contains(column)) result.add(column);
        }
      }
    }
  }
  return result;
}

String _slug(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-+|-+$'), '');

String _domainForSection(String page, String id, String title) {
  if (!page.toLowerCase().contains('internal')) return title;
  final match = RegExp(r'p2_s(\d+)').firstMatch(id);
  final number = int.tryParse(match?.group(1) ?? '');
  if (number == null) return title;
  if (number <= 2) return 'Infrastructure';
  if (number <= 5) return 'RAN Performance';
  if (number <= 7) return 'PRB & EUT';
  if (number <= 12) return 'User Experience';
  if (number <= 21) return 'Commercial Performance';
  return 'Subscriber Value Cohort';
}
