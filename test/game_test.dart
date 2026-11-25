import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skyglide/flight_scene.dart';
import 'package:skyglide/main.dart';

void main() {
  testWidgets(
    'tilt calibration, gate pass, pause, touch resume, collision and retry',
    (tester) async {
      tester.view.physicalSize = const Size(390, 840);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final art = (await tester.runAsync(FlightArt.load))!;
      final motion = StreamController<dynamic>.broadcast(sync: true);
      final calls = <String>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(gameChannel, (call) async {
        calls.add('${call.method}=${call.arguments}');
        return null;
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Skyglide(
            art: art,
            samples: motion.stream,
            best: 0,
            sound: true,
          ),
        ),
      );
      expect(find.text('SKYGLIDE'), findsOneWidget);
      await tester.tap(find.text('উড়ান শুরু'));
      await tester.pump();
      expect(find.textContaining('এক মুহূর্ত'), findsOneWidget);
      for (var t = 0; t < 4400; t += 20) {
        motion.add([t, 7.0, 7.0]);
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(find.text('গেট  1'), findsOneWidget);
      expect(find.text('লেভেল 1'), findsOneWidget);
      expect(calls, contains('cue=feather'));
      await tester.tap(find.byTooltip('বিরতি'));
      await tester.pump();
      expect(find.text('উড়ানে বিরতি'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.text('টাচ দিয়ে চালিয়ে যান'));
      await tester.pump();
      final drag = await tester.startGesture(const Offset(170, 200));
      await drag.moveTo(const Offset(170, 72));
      await drag.up();
      for (var i = 0; i < 170; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }
      expect(find.text('নতুন রেকর্ড!'), findsOneWidget);
      expect(calls, contains('best=1'));
      expect(calls.where((c) => c.startsWith('featherBalance=')), [
        'featherBalance=1',
      ]);
      await tester.tap(find.text('আবার উড়ুন'));
      await tester.pump();
      expect(find.text('গেট  0'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('লেভেল 1'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      art.dispose();
      await motion.close();
      messenger.setMockMethodCallHandler(gameChannel, null);
    },
  );
  testWidgets(
    'Moon Valley appears during a played run and reports a shield save',
    (tester) async {
      tester.view.physicalSize = const Size(390, 840);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final art = (await tester.runAsync(FlightArt.load))!;
      final calls = <String>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(gameChannel, (call) async {
        calls.add('${call.method}=${call.arguments}');
        return null;
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Skyglide(
            art: art,
            samples: const Stream.empty(),
            best: 0,
            sound: true,
          ),
        ),
      );
      await tester.tap(find.text('টেনে খেলুন'));
      await tester.pump();
      final scene = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .whereType<FlightScene>()
          .single;
      final f = scene.flight;
      final drag = await tester.startGesture(const Offset(100, 420));
      for (var frame = 0; frame < 1600 && f.score < 70 && !f.crashed; frame++) {
        await drag.moveTo(
          Offset(100, 840 * f.gates.firstWhere((g) => !g.passed).center),
        );
        await tester.pump(const Duration(milliseconds: 80));
      }
      expect(calls.where((cue) => cue == 'cue=chapter'), hasLength(1));
      expect(f.score, 70);
      expect(find.text('চাঁদের উপত্যকা  ·  লেভেল 8'), findsOneWidget);
      expect(find.text('ঢাল 0/3'), findsOneWidget);
      for (var frame = 0; frame < 100 && !f.hasShield && !f.crashed; frame++) {
        await drag.moveTo(
          Offset(100, 840 * f.gates.firstWhere((g) => !g.passed).center),
        );
        await tester.pump(const Duration(milliseconds: 60));
      }
      expect(find.text('ঢাল প্রস্তুত'), findsOneWidget);
      expect(calls.where((cue) => cue == 'cue=shield'), hasLength(1));
      await drag.moveTo(const Offset(100, 80));
      for (var frame = 0; frame < 40 && f.hasShield; frame++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      expect(f.crashed, isFalse);
      expect(find.text('ঢাল 0/3'), findsOneWidget);
      expect(calls.where((cue) => cue == 'cue=shatter'), hasLength(1));
      await drag.up();
      await tester.pumpWidget(const SizedBox());
      art.dispose();
      messenger.setMockMethodCallHandler(gameChannel, null);
    },
  );
  testWidgets(
    'boost works with tilt, drag and a second finger; release, cancel and pause clear it',
    (tester) async {
      tester.view.physicalSize = const Size(390, 840);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final art = (await tester.runAsync(FlightArt.load))!;
      final motion = StreamController<dynamic>.broadcast(sync: true);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(gameChannel, (call) async => null);
      await tester.pumpWidget(
        MaterialApp(
          home: Skyglide(
            art: art,
            samples: motion.stream,
            best: 0,
            sound: true,
          ),
        ),
      );
      await tester.tap(find.text('উড়ান শুরু'));
      await tester.pump();
      for (var t = 0; t <= 400; t += 20) {
        motion.add([t, 7.0, 7.0]);
        await tester.pump(const Duration(milliseconds: 20));
      }
      final f = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .whereType<FlightScene>()
          .single
          .flight;
      await tester.tapAt(const Offset(225, 610));
      await tester.pump(const Duration(milliseconds: 220));
      expect(f.boostHeld, isFalse);
      final hold = await tester.startGesture(const Offset(225, 610));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 90));
      expect(find.text('বুস্ট'), findsOneWidget);
      expect(f.boost, greaterThan(0));
      expect(f.target, closeTo(.5, .001));
      await hold.up();
      await tester.pump();
      expect(find.text('বুস্ট'), findsNothing);
      final secondHold = await tester.startGesture(const Offset(225, 610));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.byTooltip('বিরতি'));
      await tester.pump();
      expect(f.boostHeld, isFalse);
      expect(f.boost, 0);
      await secondHold.up();
      await tester.tap(find.text('টাচ দিয়ে চালিয়ে যান'));
      await tester.pump();
      final drag = await tester.startGesture(const Offset(100, 420));
      await drag.moveTo(const Offset(100, 380));
      await tester.pump(const Duration(milliseconds: 210));
      expect(f.boostHeld, isFalse);
      final extra = await tester.startGesture(const Offset(270, 640));
      await tester.pump(const Duration(milliseconds: 220));
      expect(f.boostHeld, isTrue);
      expect(f.target, closeTo(380 / 840, .001));
      await drag.moveTo(const Offset(115, 410));
      expect(f.target, closeTo(410 / 840, .001));
      await extra.cancel();
      await tester.pump();
      expect(f.boostHeld, isFalse);
      await drag.up();
      final touchHold = await tester.startGesture(const Offset(160, 420));
      await tester.pump(const Duration(milliseconds: 220));
      await touchHold.moveTo(const Offset(160, 390));
      expect(f.boostHeld, isTrue);
      expect(f.target, closeTo(390 / 840, .001));
      await touchHold.up();
      await tester.pumpWidget(const SizedBox());
      art.dispose();
      await motion.close();
      messenger.setMockMethodCallHandler(gameChannel, null);
    },
  );
}
