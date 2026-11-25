import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:skyglide/flight.dart';

void main() {
  test('speed builds at each gate while openings narrow every fourth gate', () {
    final flight = Flight();
    final start = flight.speed, firstOpening = flight.opening;
    for (var gate = 1; gate <= 16; gate++) {
      final before = flight.speed;
      flight.score = gate;
      expect(flight.speed, greaterThan(before));
      if (gate < 4) expect(flight.opening, firstOpening);
      if (gate == 4) expect(flight.opening, lessThan(firstOpening));
      if (gate == 10) expect(flight.speed, greaterThan(2 * start));
    }
    final topSpeed = flight.speed;
    flight.score = 40;
    expect(flight.speed, topSpeed);
  });

  test(
    'stone caps and narrow shafts collide only inside their silhouettes',
    () {
      final gate = Gate(.289, .5, .30);
      expect(gate.touchesBird(.5, .5), isFalse);
      expect(gate.touchesBird(.341, .5), isTrue);
      expect(gate.touchesBird(.12, .5), isFalse);
      gate.x = .22;
      expect(gate.touchesBird(.12, .5), isTrue);
    },
  );

  test(
    'central first gate gives one point and a feather, never double counts',
    () {
      final f = Flight(random: math.Random(17));
      for (var i = 0; i < 230; i++) {
        f.step(1 / 60);
      }
      expect(f.crashed, isFalse);
      expect(f.score, 1);
      expect(f.feathers, 1);
      for (var i = 0; i < 8; i++) {
        f.step(1 / 60);
      }
      expect(f.score, 1);
    },
  );
  test('passing off-centre earns gate without feather; rock contact freezes the run', () {
    final f = Flight(random: math.Random(2));
    f.steer(.61);
    while (f.score == 0 && !f.crashed) {
      f.step(1 / 60);
    }
    expect(f.crashed, isFalse);
    expect(f.feathers, 0);
    f.steer(.08);
    for (var i = 0; i < 350; i++) {
      f.step(1 / 60);
    }
    expect(f.crashed, isTrue);
    final snapshot = (f.y, f.distance, f.score);
    f.step(.12);
    expect((f.y, f.distance, f.score), snapshot);
  });
  test(
    'all levels remain reachable, shrink gaps and increase speed within limits',
    () {
      final f = Flight(random: math.Random(23));
      final firstSpeed = f.speed, firstGap = f.opening;
      final promotions = <(int, int)>[];
      for (var i = 0; i < 14000 && f.score < 55; i++) {
        final previousScore = f.score, previousLevel = f.level;
        f.steer(f.gates.firstWhere((gate) => !gate.passed).center);
        f.step(1 / 60);
        expect(f.crashed, isFalse);
        if (f.score != previousScore) {
          expect(f.justLeveledUp, f.level != previousLevel);
          if (f.justLeveledUp) promotions.add((f.score, f.level));
        }
      }
      expect(promotions, [(10, 2), (20, 3), (30, 4), (40, 5), (50, 6)]);
      expect(f.score, 55);
      expect(f.feathers, 55);
      expect(f.level, 6);
      expect(f.speed, greaterThan(firstSpeed));
      expect(f.opening, lessThan(firstGap));
      expect(f.opening, greaterThan(.21));
      expect(f.gates.length, lessThan(5));
      final fresh = Flight();
      expect(
        (fresh.score, fresh.feathers, fresh.level, fresh.y),
        (0, 0, 1, .5),
      );
    },
  );
  test(
    'upper and lower blocks both collide, even with a long render frame',
    () {
      for (final y in [.08, .92]) {
        final f = Flight()..steer(y);
        for (var i = 0; i < 50; i++) {
          f.step(.1);
        }
        expect(f.crashed, isTrue);
        expect(f.score, 0);
      }
    },
  );
  test('tilt is relative to the starting grip, raising top edge climbs', () {
    for (final base in [.1, .8, 1.55]) {
      final steering = TiltSteering();
      double? reading(int t, double angle) =>
          steering.sample(t, 9.81 * math.sin(angle), 9.81 * math.cos(angle));
      expect(steering.sample(0, double.nan, 1), isNull);
      expect(steering.sample(0, .1, .3), isNull);
      expect(reading(0, base), isNull);
      for (var t = 20; t <= 340; t += 20) {
        reading(t, base);
      }
      expect(reading(360, base), closeTo(.5, .001));
      double? output;
      for (var t = 380; t < 1000; t += 20) {
        output = reading(t, base + .32);
      }
      expect(output, lessThan(.25));
      for (var t = 1000; t < 1800; t += 20) {
        output = reading(t, base - .32);
      }
      expect(output, greaterThan(.75));
    }
  });
}
