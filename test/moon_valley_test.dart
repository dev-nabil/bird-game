import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:skyglide/flight.dart';

void main() {
  test('the night chapter starts at gate 70 and alternates new moving and resting gates', () {
    final f = Flight(random: math.Random(37));
    Gate? previousSpawn;
    var moving = 0, staticAfterMoving = 0;
    for (var i = 0; i < 18000 && f.score < 120; i++) {
      f.steer(f.gates.firstWhere((g) => !g.passed).center);
      f.step(1 / 60);
      expect(f.crashed, isFalse);
      expect(f.lastShieldBreak, lessThan(0));
      if (f.score < 70) {
        expect(f.inMoonValley, isFalse);
        expect(f.moonlight, 0);
        expect(f.moonCharge, 0);
        expect(f.gates.every((g) => g.drift == 0), isTrue);
      } else {
        expect(f.inMoonValley, isTrue);
        final last = f.gates.last;
        if (last != previousSpawn) {
          if (previousSpawn != null) {
            if (last.drift != 0) {
              moving++;
              expect(previousSpawn.drift, 0);
            }
            if (previousSpawn.drift != 0) {
              staticAfterMoving++;
              expect(last.drift, 0);
            }
          }
          previousSpawn = last;
        }
      }
    }
    expect(f.score, 120);
    expect(f.level, 13);
    expect(f.moonlight, 1);
    expect(moving, greaterThan(20));
    expect(staticAfterMoving, greaterThan(20));
    expect(f.hasShield, isTrue);
  });

  test('feathers charge one shield, protect the whole struck gate, and reset on retry', () {
    final f = Flight()..score = 69;
    Gate present(double x, double center) {
      final gate = Gate(x, center, .22);
      f.gates
        ..clear()
        ..add(gate);
      f.step(1 / 60);
      return gate;
    }

    final pickupX = Flight.birdX - Flight.gateWidth / 2;
    final day = present(pickupX, .5);
    expect(day.feather, isTrue);
    expect(f.moonCharge, 0);
    day.x = 0;
    f.step(1 / 60);
    expect(f.score, 70);
    for (var i = 1; i <= 3; i++) {
      final g = present(pickupX, .5);
      expect(g.feather, isTrue);
      expect(f.moonCharge, i);
      f.step(1 / 60);
      expect(f.moonCharge, i);
    }
    expect(f.hasShield, isTrue);
    present(pickupX, .5);
    expect(f.moonCharge, 3);
    final wall = present(Flight.birdX - .02, .77);
    expect(wall.deflected, isTrue);
    expect(f.hasShield, isFalse);
    expect(f.moonCharge, 0);
    for (var i = 0; i < 22; i++) {
      f.step(1 / 60);
      expect(f.crashed, isFalse);
    }
    expect(wall.feather, isFalse);
    present(Flight.birdX - .02, .77);
    expect(f.crashed, isTrue);
    final replay = Flight();
    expect(
      (replay.inMoonValley, replay.hasShield, replay.moonCharge),
      (false, false, 0),
    );
  });

  test('the collision opening follows the painted moving gate', () {
    final g = Gate(.20, .5, .22, drift: .076);
    expect(g.touchesBird(.42, .5), isFalse);
    g.advance(0, math.pi / (2 * 1.9));
    expect(g.center, closeTo(.576, .0001));
    expect(g.touchesBird(.42, .5), isTrue);
    expect(g.touchesBird(g.center, .5), isFalse);
  });
}
