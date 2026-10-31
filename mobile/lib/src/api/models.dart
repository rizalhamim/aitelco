class ResultTable {
  final List<String> columns;
  final List<Map<String, dynamic>> rows;
  final int rowCount;

  /// Render-ready chart spec from the backend (backend/app/chart_spec.py).
  final Map<String, dynamic>? chart;
  ResultTable(this.columns, this.rows, this.rowCount, {this.chart});
}

class ProfileSection {
  final String title;
  final String domain;
  final String status;
  final int rowCount;
  final List<String> columns;
  final List<Map<String, dynamic>> rows;
  final String? error;
  final Map<String, dynamic>? chart;
  ProfileSection({
    this.chart,
    required this.title,
    required this.domain,
    required this.status,
    required this.rowCount,
    required this.columns,
    required this.rows,
    this.error,
  });
}

class FlowStep {
  final String kind;
  final String label;
  String? feedback;
  bool done;
  FlowStep(this.kind, this.label, {this.feedback, this.done = false});
}

class ChatMessage {
  final bool isUser;
  String content;
  String? domain;
  String? domainLabel;
  String? sql;
  String? status;
  String? error;
  ResultTable? result;
  /// Chart render decision from the backend (see backend/app/chart_spec.py). The
  /// client draws what this says instead of guessing from column types, which used
  /// to plot whichever numeric column came first.
  Map<String, dynamic>? chartSpec;
  List<ProfileSection> profileResults;
  Map<String, dynamic>? locationResult;

  /// Pipeline steps the agent ran and how long the answer took.
  int steps = 0;
  DateTime? startedAt;
  Duration? elapsed;

  /// The quality check passed (reflect verdict "ok") or the answer finished cleanly.
  bool validated = false;

  ChatMessage({
    required this.isUser,
    this.content = '',
    this.domain,
    this.domainLabel,
    this.sql,
    this.status,
    this.error,
    this.result,
    this.chartSpec,
    List<ProfileSection>? profileResults,
    this.locationResult,
  }) : profileResults = profileResults ?? [];
}
