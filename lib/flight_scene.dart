import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'courses.dart';
import 'flight.dart';

class FlightArt {
  FlightArt(this.valley, this.bird, this.column, this.moonValley, this.regions);
  final ui.Image valley, bird, column, moonValley, regions;
  static Future<FlightArt> load() async {
    Future<ui.Image> image(String name) async {
      final asset = await rootBundle.load('assets/flight/$name.webp');
      final codec = await ui.instantiateImageCodec(
        asset.buffer.asUint8List(asset.offsetInBytes, asset.lengthInBytes),
      );
      try {
        return (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
    }

    final items = await Future.wait(
      ['valley', 'bird', 'column', 'moon-valley', 'regions'].map(image),
    );
    return FlightArt(items[0], items[1], items[2], items[3], items[4]);
  }

  void dispose() {
    valley.dispose();
    bird.dispose();
    column.dispose();
    moonValley.dispose();
    regions.dispose();
  }
}

class FlightScene extends CustomPainter {
  FlightScene({
    required this.art,
    required this.flight,
    required this.lobby,
    required this.time,
    required Listenable frames,
  }) : super(repaint: frames);
  final FlightArt art;
  final Flight flight;
  final bool lobby;
  final double Function() time;
  final Paint imagePaint = Paint()..filterQuality = FilterQuality.medium;
  Rect full(ui.Image im) =>
      Rect.fromLTWH(0, 0, im.width.toDouble(), im.height.toDouble());

  void _column(
    Canvas c,
    double x,
    double edge,
    double width,
    double length,
    bool ceiling,
    Paint stone,
  ) {
    if (length <= 0) return;
    final img = art.column;
    final srcW = img.width.toDouble(), srcH = img.height.toDouble();
    c.save();
    c.translate(x, edge);
    if (ceiling) c.scale(1, -1);
    c.clipRect(Rect.fromLTWH(0, 0, width, length));
    final head = srcH * .16;
    final headH = width * head / srcW;
    c.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, srcW, head),
      Rect.fromLTWH(0, 0, width, headH + .4),
      stone,
    );
    final body = Rect.fromLTWH(0, head, srcW, srcH * .46);
    final tile = width * body.height / srcW;
    for (double y = headH; y < length; y += tile) {
      c.drawImageRect(img, body, Rect.fromLTWH(0, y, width, tile + .45), stone);
    }
    c.restore();
  }

  void _feather(Canvas c, Offset at, double unit, double seconds) {
    c.save();
    c.translate(at.dx, at.dy + math.sin(seconds * 3) * unit * .13);
    c.rotate(.4);
    final moon = flight.inMoonValley;
    c.drawCircle(
      Offset.zero,
      unit * 1.13,
      Paint()..color = moon ? const Color(0x5579efff) : const Color(0x30ffed9c),
    );
    final p = Path()
      ..moveTo(0, unit)
      ..quadraticBezierTo(-unit * 1.02, 0, unit * .1, -unit * 1.2)
      ..quadraticBezierTo(unit * .92, -unit * .22, unit * .36, unit * .14)
      ..lineTo(unit * .13, unit * .13)
      ..lineTo(unit * .21, unit * .38)
      ..close();
    c.drawPath(
      p,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = unit * .24
        ..strokeJoin = StrokeJoin.round
        ..color = moon ? const Color(0xff16465e) : const Color(0xff7d5226),
    );
    c.drawPath(
      p,
      Paint()..color = moon ? const Color(0xffb4ffff) : const Color(0xffffdc6a),
    );
    c.drawLine(
      Offset(-unit * .1, unit * 1.15),
      Offset(unit * .12, -unit * .67),
      Paint()
        ..strokeWidth = unit * .12
        ..strokeCap = StrokeCap.round
        ..color = moon ? const Color(0xff4597ac) : const Color(0xffae712c),
    );
    c.restore();
  }

  void _sky(Canvas c, Size size, Sky sky, Paint paint) {
    final bg = switch (sky) {
      Sky.valley => art.valley,
      Sky.moon => art.moonValley,
      _ => art.regions,
    };
    var src = full(bg);
    if (bg == art.regions) {
      final tile = sky.index - Sky.garden.index;
      final halfW = bg.width / 2, halfH = bg.height / 2;
      src = Rect.fromLTWH(
        tile % 2 * halfW,
        tile ~/ 2 * halfH,
        halfW,
        halfH,
      ).deflate(2);
    }
    final w = size.width, h = size.height;
    final bgW = math.max(w, h * src.width / src.height);
    final offset =
        (math.max(0.0, bgW * .82 - w * .75) + flight.distance * w * .12) %
        (bgW * 2);
    for (var i = 0; i < 3; i++) {
      final x = -offset + i * bgW;
      if (x + bgW < 0 || x > w) continue;
      c.save();
      c.translate(x, 0);
      if (i.isOdd) {
        c.translate(bgW, 0);
        c.scale(-1, 1);
      }
      c.drawImageRect(bg, src, Rect.fromLTWH(0, 0, bgW + .5, h), paint);
      c.restore();
    }
  }

  void _gateDetails(Canvas c, Size size, Gate gate, Color accent, double t) {
    final w = size.width, h = size.height;
    final x = (gate.x + Flight.gateWidth / 2) * w;
    final paint = Paint()..color = accent;
    if (gate.style == GateStyle.fork) {
      final rect = Rect.fromLTRB(
        (gate.x + .012) * w,
        (gate.dividerY - Gate.dividerHalf) * h,
        (gate.x + Flight.gateWidth - .012) * w,
        (gate.dividerY + Gate.dividerHalf) * h,
      );
      final crystal = Path()
        ..moveTo(rect.left, rect.center.dy)
        ..lineTo(rect.left + rect.width * .16, rect.top)
        ..lineTo(rect.right - rect.width * .16, rect.top)
        ..lineTo(rect.right, rect.center.dy)
        ..lineTo(rect.right - rect.width * .16, rect.bottom)
        ..lineTo(rect.left + rect.width * .16, rect.bottom)
        ..close();
      c.drawPath(
        crystal,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [accent, const Color(0xff365969), const Color(0xff172b41)],
          ).createShader(rect),
      );
      c.drawLine(
        Offset(rect.left + rect.width * .16, rect.top + 1),
        Offset(rect.right - rect.width * .16, rect.top + 1),
        paint..strokeWidth = 2,
      );
    }
    if (gate.hasOrb) {
      final at = Offset(gate.orbX * w, gate.orbY * h);
      final radius = Gate.orbRadius * w;
      if (gate.style == GateStyle.orbit) {
        c.drawOval(
          Rect.fromCenter(
            center: Offset(x, gate.center * h),
            width: w * .136,
            height: h * .116,
          ),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.3
            ..color = accent.withValues(alpha: .56),
        );
      }
      c.drawCircle(
        at,
        radius * (1.36 + .1 * math.sin(t * 5)),
        paint..color = accent.withValues(alpha: .26),
      );
      c.drawCircle(
        at,
        radius,
        paint
          ..shader = RadialGradient(
            center: const Alignment(-.3, -.34),
            colors: [Colors.white, accent, const Color(0xff9d425c)],
            stops: const [0, .48, 1],
          ).createShader(Rect.fromCircle(center: at, radius: radius)),
      );
    }
    if (gate.style == GateStyle.boostLock || gate.style == GateStyle.iris) {
      final lock = gate.style == GateStyle.boostLock;
      paint
        ..color = lock ? const Color(0xffffda65) : accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      for (final sign in [-1.0, 1.0]) {
        final y = (gate.center + sign * gate.gap / 2) * h + sign * 6;
        final d = w * .014;
        if (lock) {
          c.drawPath(
            Path()
              ..moveTo(x - d * 2, y)
              ..lineTo(x - d / 2, y - d)
              ..lineTo(x - d / 2, y)
              ..lineTo(x + d * 2, y)
              ..lineTo(x + d / 2, y + d)
              ..lineTo(x + d / 2, y)
              ..close(),
            paint,
          );
        } else {
          c.drawPath(
            Path()
              ..moveTo(x - d * 2, y + sign * d)
              ..lineTo(x, y)
              ..lineTo(x + d * 2, y + sign * d),
            paint,
          );
        }
      }
    }
  }

  @override
  void paint(Canvas c, Size size) {
    final w = size.width, h = size.height, t = time();
    final sky = lobby ? Sky.valley : flight.sky;
    final fade = lobby ? 1.0 : flight.skyFade;
    if (fade < 1) _sky(c, size, flight.previousSky, imagePaint);
    if (fade > 0) {
      _sky(
        c,
        size,
        sky,
        fade == 1
            ? imagePaint
            : (Paint()
                ..filterQuality = FilterQuality.medium
                ..color = Colors.white.withValues(alpha: fade)),
      );
    }
    if (!lobby) {
      for (final gate in flight.gates) {
        final x = w * gate.x, width = w * Flight.gateWidth;
        final top = h * (gate.center - gate.gap / 2),
            bottom = h * (gate.center + gate.gap / 2);
        final stone = Paint()..filterQuality = FilterQuality.medium;
        final accent = Color(gate.course.accent);
        if (gate.course != Course.valley) {
          stone.colorFilter = ColorFilter.mode(
            Color.lerp(
              Colors.white,
              sky == Sky.moon ? const Color(0xff9eb5ff) : accent,
              sky == Sky.moon ? .68 * flight.moonlight : .68,
            )!,
            BlendMode.modulate,
          );
        }
        if (gate.deflected) stone.color = Colors.white.withValues(alpha: .32);
        _column(c, x, top, width, top, true, stone);
        _column(c, x, bottom, width, h - bottom, false, stone);
        if (gate.drift != 0 && !gate.deflected) {
          // Luminous rails on the lips distinguish moving and resting gates.
          final rail = Paint()
            ..color = const Color(0xffa9fff3)
            ..strokeWidth = 2.4
            ..strokeCap = StrokeCap.round;
          for (final edge in [top - 4, bottom + 4]) {
            c.drawLine(
              Offset(x + width * .16, edge),
              Offset(x + width * .84, edge),
              rail,
            );
          }
        }
        if (!gate.deflected) {
          _gateDetails(c, size, gate, accent, t);
          if (!gate.passed && !gate.feather) {
            final at = Offset(x + width / 2, gate.featherY * h);
            if (gate.style == GateStyle.comet) {
              final tail = Paint()..strokeCap = StrokeCap.round;
              for (var i = 1; i <= 4; i++) {
                tail.color = accent.withValues(alpha: .72 - i * .13);
                c.drawCircle(
                  at + Offset(-i * w * .014, math.sin(t * 4 - i * .5) * i),
                  4 - i * .55,
                  tail,
                );
              }
            }
            _feather(c, at, w * .028, t);
          }
        }
      }
    }
    for (var i = 0; i < 15; i++) {
      final x =
          ((i * .3177 - t * (.008 + (i % 3) * .003) - flight.distance * .05) %
              1) *
          w;
      final y = ((i * .1473 + .27 + .016 * math.sin(t * .72 + i)) % 1) * h;
      c.drawCircle(
        Offset(x, y),
        .7 + (i % 3) * .5,
        Paint()..color = const Color(0x94fff3b6),
      );
    }
    final x = lobby ? w * .49 : w * Flight.birdX;
    final y = lobby ? h * (.455 + .012 * math.sin(t * 2.0)) : h * flight.y;
    final birdW = lobby ? math.min(w * .54, h * .29) : w * .164;
    final frame = [
      0,
      1,
      2,
      1,
    ][(t * (lobby ? 5.4 : 8 + 4 * flight.boost)).floor() % 4];
    final atlas = art.bird;
    final cell = atlas.width / 3;
    final anchorX = [.52, .49, .51][frame];
    c.save();
    c.translate(x, y);
    if (!lobby && flight.boost > 0) {
      final power = flight.boost;
      final tail = Paint()..strokeCap = StrokeCap.round;
      for (var i = -2; i <= 2; i++) {
        final dy = birdW * i * .075;
        final length =
            birdW * power * (1.12 - .17 * i.abs() + .08 * math.sin(t * 21 + i));
        tail
          ..color =
              (i.isEven ? const Color(0xffacfffc) : const Color(0xffffdc78))
                  .withValues(alpha: .74 * power)
          ..strokeWidth = (3.6 - .6 * i.abs()) * power;
        c.drawLine(
          Offset(-birdW * .28 - length, dy + 2),
          Offset(-birdW * .28, dy),
          tail,
        );
      }
    }
    final breakAge = flight.age - flight.lastShieldBreak;
    if (!lobby && flight.hasShield) {
      final r = birdW * (.59 + .022 * math.sin(t * 4));
      c.drawCircle(Offset.zero, r, Paint()..color = const Color(0x337cefff));
      c.drawCircle(
        Offset.zero,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.1
          ..color = const Color(0xffc8ffff),
      );
    } else if (!lobby && breakAge < .45) {
      final progress = breakAge / .45;
      final radius = birdW * (.55 + progress * .7);
      final shard = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.3
        ..color = const Color(0xffafffff).withValues(alpha: 1 - progress);
      for (var i = 0; i < 7; i++) {
        c.drawArc(
          Rect.fromCircle(center: Offset.zero, radius: radius),
          i * math.pi * 2 / 7,
          .47 * (1 - progress),
          false,
          shard,
        );
      }
    }
    c.rotate(lobby ? -.075 : (flight.verticalSpeed * .25).clamp(-.32, .32));
    c.drawImageRect(
      atlas,
      Rect.fromLTWH(frame * cell, 0, cell, atlas.height.toDouble()),
      Rect.fromLTWH(-birdW * anchorX, -birdW * .565, birdW, birdW),
      imagePaint,
    );
    c.restore();
    final since = flight.age - flight.lastPass;
    if (!lobby && since >= 0 && since < .55) {
      for (var i = 0; i < 8; i++) {
        final a = i * math.pi / 4, r = w * (.04 + .16 * since);
        final pos = Offset(x + math.cos(a) * r, y + math.sin(a) * r);
        c.drawCircle(
          pos,
          2 * (1 - since / .55),
          Paint()..color = const Color(0xffffe587),
        );
      }
    }
  }

  @override
  bool shouldRepaint(FlightScene old) =>
      old.art != art ||
      old.flight != flight ||
      old.lobby != lobby ||
      old.time != time;
}
