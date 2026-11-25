import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skyglide/flight.dart';
import 'package:skyglide/flight_scene.dart';
import 'package:skyglide/main.dart';

void main() {
  Gate crashIntoGate(Flight f) {
    final gate = Gate(Flight.birdX, .78, .22);
    f.gates
      ..clear()
      ..add(gate);
    f.step(1 / 60);
    expect(f.crashed, isTrue);
    return gate;
  }

  test('each 50 feathers buys exactly one continue at impact', () {
    final short = Flight(featherBalance: 49);
    crashIntoGate(short);
    expect(short.canRevive, isFalse);
    expect(short.revive(), isFalse);
    expect(short.featherBalance, 49);

    final f = Flight(featherBalance: 100)..score = 157;
    expect(f.revive(), isFalse);
    for (final remaining in [50, 0]) {
      final gate = crashIntoGate(f);
      final snapshot = (
        f.y,
        f.distance,
        f.age,
        gate.x,
        f.score,
        f.level,
        f.course,
      );
      expect(f.canRevive, isTrue);
      expect(f.revive(), isTrue);
      expect((
        f.y,
        f.distance,
        f.age,
        gate.x,
        f.score,
        f.level,
        f.course,
      ), snapshot);
      expect(f.gates.first, same(gate));
      expect(f.revive(), isFalse);
      expect(f.featherBalance, remaining);
      expect(gate.deflected, isTrue);
      while (!gate.passed && !f.crashed) {
        f.step(1 / 60);
      }
      expect(f.crashed, isFalse);
      expect(f.score, snapshot.$5 + 1);
      expect(f.featherBalance, remaining);
    }
    crashIntoGate(f);
    expect(f.revive(), isFalse);
  });

  for (final useTilt in [false, true]) {
    testWidgets(
      'earn the 50th feather then continue in ${useTilt ? "tilt" : "touch"} mode',
      (tester) async {
        tester.view.physicalSize = const Size(390, 840);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final art = (await tester.runAsync(FlightArt.load))!;
        final motion = StreamController<dynamic>.broadcast(sync: true);
        final writes = <int>[];
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(gameChannel, (call) async {
          if (call.method == 'featherBalance') {
            writes.add(call.arguments as int);
          }
          return null;
        });
        await tester.pumpWidget(
          MaterialApp(
            home: Skyglide(
              art: art,
              samples: motion.stream,
              best: 0,
              sound: false,
              featherBalance: 49,
            ),
          ),
        );
        await tester.tap(find.text(useTilt ? 'উড়ান শুরু' : 'টেনে খেলুন'));
        await tester.pump();
        var timestamp = 0;
        Future<void> frame() async {
          if (useTilt) motion.add([timestamp += 40, 7.0, 7.0]);
          await tester.pump(const Duration(milliseconds: 40));
        }

        Flight current() => tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((w) => w.painter)
            .whereType<FlightScene>()
            .single
            .flight;
        final f = current();
        for (var i = 0; i < 160 && f.score == 0; i++) {
          await frame();
        }
        expect(f.score, 1);
        expect(writes, [50]);
        final wall = Gate(Flight.birdX, .8, .22);
        f.gates
          ..clear()
          ..add(wall);
        await frame();
        expect(f.crashed, isTrue);
        final at = (f.y, f.distance, f.score);
        await tester.tap(find.text('এখান থেকে উড়ুন · 50 পালক'));
        await tester.pump();
        expect(current(), same(f));
        expect((f.y, f.distance, f.score), at);
        expect(writes, [50, 0]);
        if (useTilt) expect(find.textContaining('এক মুহূর্ত'), findsOneWidget);
        for (var i = 0; i < 35 && !wall.passed; i++) {
          await frame();
        }
        expect(wall.passed, isTrue);
        expect(f.score, 2);
        f.gates
          ..clear()
          ..add(Gate(Flight.birdX, .8, .22));
        await frame();
        expect(find.textContaining('আরও 50টি পালক'), findsOneWidget);
        await tester.tap(find.text('আবার উড়ুন'));
        await tester.pump();
        expect(current().score, 0);
        expect(current().featherBalance, 0);
        await tester.pumpWidget(const SizedBox());
        await motion.close();
        art.dispose();
        messenger.setMockMethodCallHandler(gameChannel, null);
      },
    );
  }
}
