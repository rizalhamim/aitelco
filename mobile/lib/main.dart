import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'src/theme.dart';
import 'src/api/api_client.dart';
import 'src/app_state.dart';
import 'src/services/keep_alive_service.dart';
import 'src/screens/login_screen.dart';
import 'src/screens/chat_screen.dart';
import 'src/screens/download_screen.dart';
import 'src/screens/home_shell.dart';
import 'src/screens/profile_screen.dart';
import 'src/screens/map_query_screen.dart';
import 'src/screens/reports_screen.dart';
import 'src/screens/site_performance_screen.dart';
import 'src/screens/splash_screen.dart';
import 'src/screens/stats_screen.dart';
import 'src/widgets/app_update_checker.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  KeepAliveService.init();
  await ClientInfo.init();
  await AuthState.load();
  await AppState.I.load();
  runApp(const BizplanApp());
}

class BizplanApp extends StatefulWidget {
  const BizplanApp({super.key});
  @override
  State<BizplanApp> createState() => _BizplanAppState();
}

class _BizplanAppState extends State<BizplanApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  @override
  void initState() {
    super.initState();
    AppState.I.addListener(() => setState(() {}));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'Bizplan Java Agent',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: AppState.I.themeMode,
      // WithForegroundTask lets the keep-alive foreground service coordinate
      // with the app lifecycle so in-flight requests survive backgrounding.
      // Text sizes follow the mockups 1:1; the OS font scale is respected but
      // capped so cards keep their layout. AppUpdateChecker checks for a new
      // APK on every route, including splash and login.
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        final base = mq.textScaler.scale(1.0).clamp(1.0, 1.3);
        return MediaQuery(
          data: mq.copyWith(textScaler: TextScaler.linear(base)),
          child: AppUpdateChecker(
            navigatorKey: _navigatorKey,
            child: WithForegroundTask(child: child ?? const SizedBox.shrink()),
          ),
        );
      },
      initialRoute: '/splash',
      routes: {
        '/splash': (_) => const SplashScreen(),
        '/home': (_) => const HomeShell(),
        '/stats': (_) => const StatsScreen(),
        '/download': (_) => const DownloadScreen(),
        '/login': (_) => const LoginScreen(),
        '/chat': (_) => const ChatScreen(),
        '/profile': (_) => const ProfileScreen(),
        '/map': (_) => const MapQueryScreen(),
        '/reports': (_) => const ReportsScreen(),
        '/site': (_) => const SitePerformanceScreen(),
      },
    );
  }
}
