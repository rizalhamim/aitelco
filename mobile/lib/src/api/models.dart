class ResultTable {
  final List<String> columns;
  final List<Map<String, dynamic>> rows;
  final int rowCount;
  ResultTable(this.columns, this.rows, this.rowCount);
}

class ProfileSection {
  final String title;
  final String domain;
  final String status;
  final int rowCount;
  final List<String> columns;
  final List<Map<String, dynamic>> rows;
  final String? error;
  ProfileSection({
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
  List<ProfileSection> profileResults;
  Map<String, dynamic>? locationResult;

  ChatMessage({
    required this.isUser,
    this.content = '',
    this.domain,
    this.domainLabel,
    this.sql,
    this.status,
    this.error,
    this.result,
    List<ProfileSection>? profileResults,
    this.locationResult,
  }) : profileResults = profileResults ?? [];
}
