import 'dart:math' as math;

import 'courses.dart';

class Gate {
  Gate(
    this.x,
    this.restCenter,
    this.baseGap, {
    this.drift = 0,
    this.style = GateStyle.arch,
    this.course = Course.valley,
    this.beat = 0,
    this.side = 1,
    this.phase = 0,
    this.dividerOffset = 0,
  }) : center = restCenter,
       gap = baseGap;
  double x, center, gap;
  final double restCenter, baseGap, drift, side, phase, dividerOffset;
  final GateStyle style;
  final Course course;
  final int beat;
  double _age = 0;
  bool passed = false, feather = false, deflected = false;
  bool get hasOrb => style == GateStyle.sentry || style == GateStyle.orbit;
  double get dividerY => center + dividerOffset;
  static const dividerHalf = .023, orbRadius = .041;
  double get orbX =>
      x +
      Flight.gateWidth / 2 +
      (style == GateStyle.orbit ? .068 * math.cos(_age * 2.6 + phase) : 0);
  double get orbY =>
      center +
      (style == GateStyle.orbit ? .058 : .073) * math.sin(_age * 2.6 + phase);
  double get featherY => switch (style) {
    GateStyle.fork =>
      (dividerY + side * dividerHalf + center + side * gap / 2) / 2,
    GateStyle.comet => center + .085 * math.sin(_age * 3 + phase),
    GateStyle.sentry || GateStyle.orbit => center + side * .135,
    _ => center,
  };

  void advance(double dx, double dt, {double boost = 0}) {
    x -= dx;
    _age += dt;
    if (drift != 0) center = restCenter + drift * math.sin(_age * 1.9 + phase);
    if (style == GateStyle.iris) {
      gap = baseGap + .043 * math.sin(_age * 2.8 + phase);
    }
    if (style == GateStyle.boostLock) gap = baseGap + .13 * boost;
  }

  bool touchesBird(double y, double aspect) {
    if (hasOrb) {
      final dx = (Flight.birdX - orbX) / (Flight.birdRadiusX + orbRadius);
      final dy = (y - orbY) / (Flight.birdRadiusY + orbRadius * aspect);
      if (dx * dx + dy * dy < 1) return true;
    }
    final top = center - gap / 2, bottom = center + gap / 2;
    final high = y - Flight.birdRadiusY, low = y + Flight.birdRadiusY;
    if (style == GateStyle.fork &&
        low > dividerY - dividerHalf &&
        high < dividerY + dividerHalf &&
        Flight.birdX + Flight.birdRadiusX > x + .012 &&
        Flight.birdX - Flight.birdRadiusX < x + Flight.gateWidth - .012) {
      return true;
    }
    if (high >= top && low <= bottom) return false;
    // The generated stone capital is wider than the shaft. Empty air beside
    // the shaft stays flyable even when the bird is far above or below a gap.
    final capHeight = Flight.gateWidth * aspect * .69;
    final besideShaft = low < top - capHeight || high > bottom + capHeight;
    final inset = Flight.gateWidth * (besideShaft ? .18 : .014);
    return Flight.birdX + Flight.birdRadiusX > x + inset &&
        Flight.birdX - Flight.birdRadiusX < x + Flight.gateWidth - inset;
  }
}

class Flight {
  Flight({math.Random? random, this.featherBalance = 0})
    : random = random ?? math.Random() {
    gates.add(Gate(.98, .5, opening));
  }
  final math.Random random;
  static const birdX = .27, birdRadiusX = .032, birdRadiusY = .017;
  static const gateWidth = .18;
  static const pointsPerLevel = 10;
  static const moonLevel = 8;
  static const shieldCost = 3;
  static const reviveCost = 50;
  final List<Gate> gates = [];
  int score = 0, feathers = 0;
  int featherBalance;
  double y = .5, target = .5, verticalSpeed = 0, distance = 0, age = 0;
  Gate? _crashGate;
  bool get crashed => _crashGate != null;
  bool get canRevive => crashed && featherBalance >= reviveCost;

  bool revive() {
    if (!canRevive) return false;
    featherBalance -= reviveCost;
    // Keep the world at impact. Only the obstacle already touching the bird is safe.
    _crashGate!.deflected = true;
    _crashGate = null;
    target = y;
    verticalSpeed = 0;
    clearBoost();
    return true;
  }

  double lastPass = -10;
  int moonCharge = 0;
  double moonlight = 0, lastShieldBreak = -10;
  bool get inMoonValley => level >= moonLevel;
  bool get hasShield => moonCharge == shieldCost;
  int get level => 1 + score ~/ pointsPerLevel;
  bool get justLeveledUp => score > 0 && score % pointsPerLevel == 0;
  Course get course => Course.at(level);
  Sky get sky =>
      inMoonValley && course == Course.gardens ? Sky.moon : course.sky;
  Sky previousSky = Sky.valley;
  double skyFade = 1;
  bool boostHeld = false;
  double boost = 0;
  void clearBoost() {
    boostHeld = false;
    boost = 0;
  }

  double get speed => (.245 + .025 * math.min(score, 16)) * (1 + .5 * boost);
  int get _gateDifficulty => math.min(score ~/ 4, 10);
  double get opening => .39 - .017 * _gateDifficulty;
  double get spacing => .72 - .008 * _gateDifficulty;

  void steer(double position) => target = position.clamp(.075, .925);

  void step(double elapsed, {double aspect = .5}) {
    if (crashed || !elapsed.isFinite || elapsed <= 0) return;
    // Substeps keep collision checks continuous through a missed display frame.
    var remaining = elapsed.clamp(0.0, .12);
    while (remaining > .000001 && !crashed) {
      final dt = math.min(remaining, 1 / 90);
      remaining -= dt;
      age += dt;
      boost = boostHeld
          ? math.min(1, boost + dt * 3)
          : math.max(0, boost - dt * 4);
      skyFade = math.min(1, skyFade + dt / 1.3);
      if (inMoonValley) moonlight = math.min(1, moonlight + dt / 1.6);
      final change = (target - y) * (1 - math.exp(-dt * 8));
      verticalSpeed = change / dt;
      y += change;
      final dx = speed * dt;
      distance += dx;
      for (final gate in gates) {
        gate.advance(dx, dt, boost: boost);
        if (!gate.deflected && gate.touchesBird(y, aspect)) {
          if (!hasShield) {
            _crashGate = gate;
            return;
          }
          moonCharge = 0;
          gate.deflected = true;
          lastShieldBreak = age;
        }
        if (!gate.deflected &&
            !gate.feather &&
            !gate.passed &&
            (gate.x + gateWidth / 2 - birdX).abs() < birdRadiusX &&
            (y - gate.featherY).abs() < .04) {
          gate.feather = true;
          feathers++;
          featherBalance++;
          if (inMoonValley && !hasShield) moonCharge++;
        }
        if (!gate.passed && gate.x + gateWidth < birdX - birdRadiusX) {
          gate.passed = true;
          final oldSky = sky;
          score++;
          if (sky != oldSky) {
            previousSky = oldSky;
            skyFade = 0;
          }
          lastPass = age;
        }
      }
      final last = gates.last;
      final chapter = course;
      final beat = chapter == last.course ? last.beat + 1 : 0;
      final interval = switch (chapter) {
        Course.echo => beat.isOdd ? .45 : .80,
        Course.ribbon => beat % 3 == 0 ? .89 : .47,
        _ => spacing,
      };
      if (last.x < 1.08 - interval) _spawn(last, chapter, beat, interval);
      if (gates.first.x + gateWidth < -.04) gates.removeAt(0);
    }
  }

  void _spawn(Gate last, Course chapter, int beat, double interval) {
    final shift = .09 + random.nextDouble() * (.075 + _gateDifficulty * .005);
    final sign = last.restCenter < .31
        ? 1.0
        : last.restCenter > .69
        ? -1.0
        : random.nextBool()
        ? 1.0
        : -1.0;
    var center = last.restCenter + sign * shift;
    var gap = opening, drift = 0.0, phase = 0.0, divider = 0.0;
    final side = beat.isEven ? -1.0 : 1.0;
    var style = GateStyle.arch;
    final pattern = chapter == Course.crown
        ? const [
            Course.twins,
            Course.forge,
            Course.lantern,
            Course.bells,
            Course.comet,
            Course.orbit,
          ][(beat ~/ 4) % 6]
        : chapter;
    switch (pattern) {
      case Course.valley:
        break;
      case Course.gardens:
        center = const [.34, .47, .60, .69, .56, .43][beat % 6];
        if (inMoonValley && last.drift == 0) drift = sign * .052;
      case Course.bells:
        style = GateStyle.iris;
        gap = .252;
        if (last.drift == 0) drift = sign * .060;
      case Course.twins:
        style = GateStyle.fork;
        gap = .41;
      case Course.forge:
        style = GateStyle.boostLock;
        gap = .145;
      case Course.slalom:
        center = const [.37, .58, .39, .64, .42, .62][beat % 6];
      case Course.comet:
        style = GateStyle.comet;
        gap = .285;
        phase = beat % 6 * .9;
      case Course.tide:
        center = .5 + .145 * math.sin(beat * .76);
        drift = .082;
        phase = beat % 8 * math.pi / 4;
      case Course.echo:
        if (beat.isOdd) center = last.restCenter;
      case Course.lantern:
        style = GateStyle.sentry;
        gap = .41;
        phase = side * 1.2;
      case Course.pistons:
        style = GateStyle.iris;
        gap = .234;
        drift = side * .08;
        phase = side * math.pi / 2;
      case Course.weave:
        style = GateStyle.fork;
        gap = .44;
        divider = side * .045;
      case Course.ribbon:
        if (beat % 3 != 0) {
          center = last.restCenter + ((beat ~/ 3).isEven ? -.048 : .048);
        }
      case Course.orbit:
        style = GateStyle.orbit;
        gap = .43;
        phase = beat % 5 * 1.2;
      case Course.relay:
        style = beat % 3 == 2 ? GateStyle.fork : GateStyle.boostLock;
        gap = style == GateStyle.fork ? .41 : .14;
      case Course.crown:
        break; // The crown cycles through the patterns above.
    }
    center = chapter == Course.valley
        ? center.clamp(.25, .75)
        : center
              .clamp(last.restCenter - .20, last.restCenter + .20)
              .clamp(.28, .72);
    gates.add(
      Gate(
        last.x + interval,
        center,
        gap,
        drift: drift,
        side: side,
        phase: phase,
        course: chapter,
        beat: beat,
        style: style,
        dividerOffset: divider,
      ),
    );
  }
}

class TiltSteering {
  double? _angle, _neutral;
  int? _first, _last;
  bool get calibrated => _neutral != null;
  static double _wrapped(double r) => math.atan2(math.sin(r), math.cos(r));

  // Android +Y points towards the phone's top edge and +Z out of its screen.
  // Calibrating the Y/Z angle allows a comfortable flat or upright grip.
  double? sample(int time, double y, double z) {
    if (!y.isFinite || !z.isFinite || math.sqrt(y * y + z * z) < 2) return null;
    final angle = math.atan2(y, z);
    _first ??= time;
    final dt = time - (_last ?? time);
    _last = time;
    final old = _angle;
    _angle = old == null || dt < 0 || dt > 500
        ? angle
        : old + _wrapped(angle - old) * (1 - math.exp(-dt / 85));
    if (_neutral == null) {
      if (time - _first! < 320) return null;
      _neutral = _angle;
    }
    final delta = _wrapped(_angle! - _neutral!);
    final tilt = (delta.abs() - .022).clamp(0.0, .46) * delta.sign;
    return (.5 - tilt * .95).clamp(.075, .925);
  }
}
