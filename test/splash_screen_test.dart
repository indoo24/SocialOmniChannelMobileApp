import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/features/splash/splash_motion.dart';
import 'package:scenario_mobile/features/splash/splash_screen.dart';

/// Hosts the splash with a mutable `initDone`, counting `onFinished` calls.
class _Host extends StatefulWidget {
  const _Host({required this.reduceMotion, required this.onFinished});

  final bool reduceMotion;
  final VoidCallback onFinished;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  bool initDone = false;

  void markInitDone() => setState(() => initDone = true);

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQueryData(
        size: const Size(390, 844),
        disableAnimations: widget.reduceMotion,
      ),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: SplashScreen(initDone: initDone, onFinished: widget.onFinished),
      ),
    );
  }
}

/// Animations only report completion strictly after their duration.
final _pastFade = SplashMotion.exitFade + const Duration(milliseconds: 1);

void main() {
  Future<void> startIntro(WidgetTester tester, Widget host) async {
    // Precaching decodes real images, which needs real async time.
    await tester.runAsync(() async {
      await tester.pumpWidget(host);
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pump();
  }

  testWidgets('waits for init after the intro, then fades and finishes once', (
    tester,
  ) async {
    var finished = 0;
    await startIntro(
      tester,
      _Host(reduceMotion: false, onFinished: () => finished++),
    );

    await tester.pump(SplashMotion.introDuration);
    await tester.pump(const Duration(seconds: 3));
    expect(finished, 0, reason: 'init is not done yet');

    tester.state<_HostState>(find.byType(_Host)).markInitDone();
    await tester.pump(); // starts the exit fade
    await tester.pump(); // the fade's first tick
    expect(finished, 0, reason: 'the exit fade has not run yet');

    await tester.pump(_pastFade);
    expect(finished, 1);

    await tester.pump(const Duration(seconds: 2));
    expect(finished, 1);
  });

  testWidgets('init done early still waits for the whole intro', (
    tester,
  ) async {
    var finished = 0;
    await startIntro(
      tester,
      _Host(reduceMotion: false, onFinished: () => finished++),
    );
    tester.state<_HostState>(find.byType(_Host)).markInitDone();

    await tester.pump(const Duration(milliseconds: 4000));
    expect(finished, 0);

    await tester.pump(SplashMotion.introDuration);
    await tester.pump(); // starts the exit fade
    await tester.pump(); // the fade's first tick
    expect(finished, 0);
    await tester.pump(_pastFade);
    expect(finished, 1);
  });

  testWidgets('reduced motion skips the intro and leaves as soon as init is '
      'done', (tester) async {
    var finished = 0;
    await tester.pumpWidget(
      _Host(reduceMotion: true, onFinished: () => finished++),
    );
    await tester.pump();
    expect(finished, 0);

    tester.state<_HostState>(find.byType(_Host)).markInitDone();
    await tester.pump();
    await tester.pump();
    expect(finished, 1);
  });
}
