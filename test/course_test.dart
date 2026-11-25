import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:skyglide/courses.dart';
import 'package:skyglide/flight.dart';

void main() {
  test('fifteen course entrances are spaced five levels apart; the crown continues', () {
    expect(Course.values.skip(1), hasLength(15));
    for (final course in Course.values.skip(1)) {
      final f = Flight()
        ..score = (course.level - 1) * Flight.pointsPerLevel - 1;
      expect(f.course.index, course.index - 1);
      f.score++;
      expect(f.course, course);
      expect(f.level, course.index * 5);
    }
    expect(Course.at(500), Course.crown);
  });

  test('pressing accelerates smoothly, releasing restores cruise speed', () {
    final f = Flight();
    final cruise = f.speed;
    f.boostHeld = true;
    f.step(.05);
    expect(f.speed, inExclusiveRange(cruise, 1.5 * cruise));
    for (var i = 0; i < 5; i++) {
      f.step(.1);
    }
    expect(f.speed, closeTo(1.5 * cruise, 1e-8));
    f.boostHeld = false;
    for (var i = 0; i < 3; i++) {
      f.step(.1);
    }
    expect(f.speed, cruise);
    expect(f.distance, greaterThan(cruise * .85));
  });

  test(
    'fork, fireball, orbit, iris and boost gates use their visible openings',
    () {
      final x = Flight.birdX - Flight.gateWidth / 2;
      final fork = Gate(x, .5, .41, style: GateStyle.fork);
      expect(fork.touchesBird(.5, .5), isTrue);
      for (final y in [.39, .61]) {
        expect(fork.touchesBird(y, .5), isFalse);
      }
      for (final style in [GateStyle.sentry, GateStyle.orbit]) {
        final g = Gate(x, .5, .43, style: style)..advance(0, .5);
        g.x += Flight.birdX - g.orbX;
        expect(g.touchesBird(g.orbY, .5), isTrue);
        expect(g.touchesBird(g.featherY, .5), isFalse);
      }
      final lock = Gate(x, .5, .14, style: GateStyle.boostLock);
      expect(lock.touchesBird(.4, .5), isTrue);
      lock.advance(0, .1, boost: 1);
      expect(lock.touchesBird(.4, .5), isFalse);
      final iris = Gate(x, .5, .24, style: GateStyle.iris);
      iris.advance(0, math.pi / 5.6);
      final wide = iris.gap;
      iris.advance(0, math.pi / 2.8);
      expect(iris.gap, lessThan(wide));
    },
  );

  test('a continuous flight can follow all fifteen courses at cruise and full boost', () {
    for (final held in [false, true]) {
      for (var seed = 0; seed < 4; seed++) {
        final f = Flight(random: math.Random(seed))..boostHeld = held;
        final visited = <Course>{}, finaleStyles = <GateStyle>{};
        for (
          var frame = 0;
          frame < 90000 && f.score < 790 && !f.crashed;
          frame++
        ) {
          final next = f.gates.firstWhere((g) => !g.passed);
          if (frame % 4 == 0) f.steer(next.featherY);
          visited.add(next.course);
          if (next.course == Course.crown) finaleStyles.add(next.style);
          f.step(1 / 60, aspect: 390 / 840);
        }
        expect(
          f.score,
          790,
          reason: 'seed $seed, boost $held, course ${f.course}',
        );
        expect(visited, Course.values.toSet());
        expect(finaleStyles.length, greaterThanOrEqualTo(6));
        expect(
          f.lastShieldBreak,
          lessThan(0),
          reason: 'forced hit at seed $seed, boost $held in ${f.course}',
        );
      }
    }
  });
}
