/// App configuration. The backend base URL is compile-time configurable via
/// --dart-define=API_BASE=... so the app always points at the SAME backend &
/// AI agent as the web app. Default points to the deployed server.
class AppConfig {
  static const String apiBase = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'https://agent.bizplan-java.com',
  );

  static const String appName = 'Bizplan Java Agent';
  static const String appSub = 'Business Planning Circle Java';
}
