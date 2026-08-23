import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'src/theme.dart';
import 'src/api/api_client.dart';
import 'src/app_state.dart';
import 'src/services/keep_alive_service.dart';
import 'src/screens/login_screen.dart';
import 'src/screens/chat_screen.dart';
import 'src/screens/profile_screen.dart';
import 'src/screens/map_query_screen.dart';
import 'src/screens/reports_screen.dart';
import 'src/screens/site_performance_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  KeepAliveService.init();
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
  @override
  void initState() {
    super.initState();
    AppState.I.addListener(() => setState(() {}));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bizplan Java Agent',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: AppState.I.themeMode,
      // WithForegroundTask lets the keep-alive foreground service coordinate
      // with the app lifecycle so in-flight requests survive backgrounding.
      // Keep the platform MediaQuery unchanged so OS text scaling is respected.
      builder: (context, child) =>
          WithForegroundTask(child: child ?? const SizedBox.shrink()),
      initialRoute: AuthState.isLoggedIn ? '/chat' : '/login',
      routes: {
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
