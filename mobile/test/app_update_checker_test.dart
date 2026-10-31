import 'dart:async';

import 'package:bizplan_java_agent/src/services/update_service.dart';
import 'package:bizplan_java_agent/src/widgets/app_update_checker.dart';
import 'package:bizplan_java_agent/src/widgets/update_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final release = UpdateInfo(
      versionName: '1.48.1',
      versionCode: 64,
      notes: 'Update',
      mandatory: false,
      downloadUrl: 'https://example.test/apk',
      sizeBytes: 100);

  Widget app(Future<UpdateInfo?> Function() check,
      Future<void> Function(BuildContext, UpdateInfo) prompt) {
    final navigator = GlobalKey<NavigatorState>();
    return MaterialApp(
      navigatorKey: navigator,
      home: const Scaffold(body: Text('Login')),
      builder: (_, child) => AppUpdateChecker(
          navigatorKey: navigator,
          checkForUpdate: check,
          prompt: prompt,
          child: child!),
    );
  }

  testWidgets('startup and resume check independently of the Chat route',
      (tester) async {
    var checks = 0, prompts = 0;
    await tester.pumpWidget(app(() async {
      checks++;
      return release;
    }, (_, info) async {
      prompts++;
      expect(info.versionCode, 64);
    }));
    await tester.pump();
    expect(checks, 1);
    expect(prompts, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(checks, 2);
    expect(prompts, 2);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('resume cannot stack a pending update prompt', (tester) async {
    var checks = 0;
    final dialog = Completer<void>();
    await tester.pumpWidget(app(() async {
      checks++;
      return release;
    }, (_, __) => dialog.future));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(checks, 1);
    dialog.complete();
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('failed checks retry in foreground and stop after disposal',
      (tester) async {
    var checks = 0;
    await tester.pumpWidget(app(() async {
      checks++;
      if (checks == 1) throw const UpdateCheckException('offline');
      return null;
    }, (_, __) async {}));
    await tester.pump();
    await tester.pump(const Duration(seconds: 29));
    expect(checks, 1);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(checks, 2);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(minutes: 5));
    expect(checks, 2);
  });
  testWidgets('manual and automatic checks share one scrollable dialog',
      (tester) async {
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) {
      context = c;
      return const Scaffold(body: Text('Profile'));
    })));
    final first = showUpdateDialog(context, release);
    final second = showUpdateDialog(context, release);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(tester.widget<AlertDialog>(find.byType(AlertDialog)).scrollable,
        isTrue);
    await tester.tap(find.text('Nanti'));
    await tester.pumpAndSettle();
    await Future.wait([first, second]);
  });

  testWidgets('a response in background waits for resume before prompting',
      (tester) async {
    var checks = 0, prompts = 0;
    final request = Completer<UpdateInfo?>();
    await tester.pumpWidget(app(() {
      checks++;
      return checks == 1 ? request.future : Future.value(release);
    }, (_, __) async {
      prompts++;
    }));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    request.complete(release);
    await tester.pump();
    await tester.pump(const Duration(seconds: 30));
    expect(prompts, 0);
    expect(checks, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(prompts, 1);
    expect(checks, 2);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('successful checks refresh periodically while foregrounded',
      (tester) async {
    var checks = 0;
    await tester.pumpWidget(app(() async {
      checks++;
      return null;
    }, (_, __) async {}));
    await tester.pump();
    await tester.pump(const Duration(minutes: 5));
    await tester.pump();
    expect(checks, 2);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
