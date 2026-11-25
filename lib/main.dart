import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'courses.dart';
import 'flight.dart';
import 'flight_scene.dart';

const gameChannel = MethodChannel('skyglide/game');
const tiltChannel = EventChannel('skyglide/tilt');
const navy = Color(0xff123b49),
    deep = Color(0xff092e3b),
    ivory = Color(0xfffff7df),
    gold = Color(0xffffcd68);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final saved =
      await gameChannel.invokeMapMethod<String, dynamic>('read') ?? {};
  final art = await FlightArt.load();
  runApp(
    MaterialApp(
      title: 'Skyglide',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Hind',
        colorScheme: ColorScheme.fromSeed(seedColor: navy),
      ),
      home: Skyglide(
        art: art,
        samples: tiltChannel.receiveBroadcastStream(),
        best: saved['best'] as int? ?? 0,
        featherBalance: saved['featherBalance'] as int? ?? 0,
        sound: saved['sound'] as bool? ?? true,
      ),
    ),
  );
}

enum Stage { title, calibrating, flying, paused, ended }

TextStyle lettering(double size, {Color color = ivory, bool italic = true}) =>
    TextStyle(
      fontFamily: 'Barlow',
      fontSize: size,
      height: 1,
      color: color,
      fontWeight: FontWeight.w800,
      fontStyle: italic ? FontStyle.italic : FontStyle.normal,
    );

class Skyglide extends StatefulWidget {
  const Skyglide({
    super.key,
    required this.art,
    required this.samples,
    required this.best,
    required this.sound,
    this.featherBalance = 0,
  });
  final FlightArt art;
  final Stream<dynamic> samples;
  final int best, featherBalance;
  final bool sound;
  @override
  State<Skyglide> createState() => _SkyglideState();
}

class _SkyglideState extends State<Skyglide>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  var stage = Stage.title, steering = TiltSteering();
  late Flight flight = Flight(featherBalance: widget.featherBalance);
  late int best = widget.best;
  late bool sound = widget.sound;
  bool touch = false, newBest = false;
  String? sensorIssue;
  late final Ticker ticker;
  final sceneTime = ValueNotifier<double>(0);
  Duration? previous;
  final holdTimers = <int, Timer>{};
  final boostPointers = <int>{};
  int? steeringPointer;
  Offset steeringOrigin = Offset.zero;
  StreamSubscription<dynamic>? stream;
  Timer? watchdog;
  final lastSample = Stopwatch(), calibratingFor = Stopwatch();
  int generation = 0;
  double neutralY = .5;
  bool get live => stage == Stage.flying || stage == Stage.calibrating;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ticker = createTicker(update)..start();
  }

  void send(String command, Object value) =>
      unawaited(gameChannel.invokeMethod<void>(command, value));
  void cue(String name) {
    if (sound) send('cue', name);
  }

  void update(Duration elapsed) {
    final dt = (elapsed - (previous ?? elapsed)).inMicroseconds / 1e6;
    previous = elapsed;
    if (stage != Stage.title &&
        stage != Stage.flying &&
        stage != Stage.calibrating) {
      return;
    }
    if (stage == Stage.flying) {
      final oldScore = flight.score, oldFeathers = flight.feathers;
      final oldShield = flight.hasShield, oldCourse = flight.course;
      flight.step(dt, aspect: MediaQuery.sizeOf(context).aspectRatio);
      if (oldFeathers != flight.feathers) {
        send('featherBalance', flight.featherBalance);
      }
      if (flight.crashed) {
        disconnect();
        cue('stop');
        setState(() {
          stage = Stage.ended;
          newBest = flight.score > best;
          if (newBest) {
            best = flight.score;
            send('best', best);
          }
        });
      } else if (oldScore != flight.score ||
          oldFeathers != flight.feathers ||
          oldShield != flight.hasShield) {
        if (oldShield != flight.hasShield) {
          cue(flight.hasShield ? 'shield' : 'shatter');
        } else if (oldFeathers != flight.feathers) {
          cue('feather');
        }
        if (oldScore != flight.score) {
          cue(oldCourse != flight.course ? 'chapter' : 'pass');
        }
        setState(() {});
      }
    }
    sceneTime.value += dt.clamp(0, .12);
  }

  void press(PointerDownEvent event, double height) {
    if (touch && steeringPointer == null) {
      steeringPointer = event.pointer;
      steeringOrigin = event.localPosition;
      flight.steer(event.localPosition.dy / height);
    }
    holdTimers[event.pointer] = Timer(const Duration(milliseconds: 180), () {
      holdTimers.remove(event.pointer);
      if (stage != Stage.flying) return;
      boostPointers.add(event.pointer);
      if (!flight.boostHeld) setState(() => flight.boostHeld = true);
    });
  }

  void drag(PointerMoveEvent event, double height) {
    if (!touch || steeringPointer != event.pointer) return;
    if ((event.localPosition - steeringOrigin).distance > 12) {
      // An immediate drag steers at cruise speed. A second finger can boost independently.
      holdTimers.remove(event.pointer)?.cancel();
    }
    flight.steer(event.localPosition.dy / height);
  }

  void release(PointerEvent event) {
    holdTimers.remove(event.pointer)?.cancel();
    if (steeringPointer == event.pointer) steeringPointer = null;
    if (boostPointers.remove(event.pointer) &&
        boostPointers.isEmpty &&
        flight.boostHeld) {
      setState(() => flight.boostHeld = false);
    }
  }

  void disconnect() {
    for (final timer in holdTimers.values) {
      timer.cancel();
    }
    holdTimers.clear();
    boostPointers.clear();
    steeringPointer = null;
    flight.clearBoost();
    generation++;
    watchdog?.cancel();
    watchdog = null;
    unawaited(stream?.cancel());
    stream = null;
    lastSample.stop();
    calibratingFor.stop();
    send('awake', false);
  }

  void start({required bool useTouch, bool resume = false}) {
    disconnect();
    if (!resume) flight = Flight(featherBalance: flight.featherBalance);
    neutralY = flight.y;
    flight.steer(neutralY);
    previous = null;
    setState(() {
      touch = useTouch;
      stage = touch ? Stage.flying : Stage.calibrating;
      newBest = false;
      sensorIssue = null;
    });
    send('awake', true);
    if (touch) return;
    final token = generation;
    steering = TiltSteering();
    lastSample
      ..reset()
      ..start();
    calibratingFor
      ..reset()
      ..start();
    stream = widget.samples.listen(
      (dynamic event) {
        if (token != generation || !live) return;
        final reading = event as List;
        final target = steering.sample(
          reading[0] as int,
          reading[1] as double,
          reading[2] as double,
        );
        lastSample.reset();
        if (target == null) return;
        if (stage == Stage.calibrating) {
          previous = null;
          setState(() => stage = Stage.flying);
        }
        // A continue can begin at either edge. The full tilt range must still
        // reach both ends of the screen from the new neutral height.
        final range = target < .5 ? neutralY - .075 : .925 - neutralY;
        flight.steer(neutralY + (target - .5) * range / .425);
      },
      onError: (Object err) {
        if (token == generation) {
          pause('কাত করার সেন্সর পাওয়া যায়নি। টাচেও উড়তে পারবেন।');
        }
      },
      onDone: () {
        if (token == generation) pause('সেন্সরের সংযোগ থেমেছে।');
      },
    );
    watchdog = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (lastSample.elapsedMilliseconds > 2400) {
        pause('সেন্সরের সাড়া পাওয়া যায়নি।');
      } else if (stage == Stage.calibrating &&
          calibratingFor.elapsedMilliseconds > 4000) {
        pause('ফোনটা সোজা হাতে ধরে আবার চেষ্টা করুন।');
      }
    });
  }

  void pause([String? issue]) {
    if (!live) return;
    disconnect();
    setState(() {
      stage = Stage.paused;
      sensorIssue = issue;
    });
  }

  void home() {
    disconnect();
    setState(() {
      stage = Stage.title;
      flight = Flight(featherBalance: flight.featherBalance);
      sensorIssue = null;
    });
  }

  void continueFromCrash() {
    if (stage != Stage.ended || !flight.revive()) return;
    send('featherBalance', flight.featherBalance);
    start(useTouch: touch, resume: true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    disconnect();
    ticker.dispose();
    sceneTime.dispose();
    super.dispose();
  }

  void toggleSound() {
    setState(() => sound = !sound);
    send('sound', sound);
  }

  Widget circleButton(IconData icon, String label, VoidCallback action) =>
      IconButton(
        onPressed: action,
        tooltip: label,
        style: IconButton.styleFrom(
          backgroundColor: deep.withValues(alpha: .83),
          foregroundColor: ivory,
          minimumSize: const Size(46, 46),
          side: const BorderSide(color: Color(0x55fff7df)),
        ),
        icon: Icon(icon, size: 21),
      );

  Widget action(String label, IconData icon, VoidCallback press) =>
      FilledButton.icon(
        onPressed: press,
        style: FilledButton.styleFrom(
          backgroundColor: gold,
          foregroundColor: deep,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        icon: Icon(icon, size: 22),
        label: Text(
          label,
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
        ),
      );

  Widget secondary(String text, VoidCallback press) => TextButton(
    onPressed: press,
    style: TextButton.styleFrom(
      foregroundColor: ivory,
      minimumSize: const Size(60, 44),
    ),
    child: Text(
      text,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
    ),
  );

  Widget menuPanel() {
    final paused = stage == Stage.paused;
    final nextCourse = flight.course == Course.crown
        ? null
        : Course.values[flight.course.index + 1];
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(22),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 350),
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
          decoration: BoxDecoration(
            color: deep.withValues(alpha: .96),
            borderRadius: BorderRadius.circular(23),
            border: Border.all(color: const Color(0xffb8a774), width: 1.5),
            boxShadow: const [BoxShadow(blurRadius: 25, color: Colors.black26)],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                paused
                    ? Icons.pause_circle_outline
                    : newBest
                    ? Icons.emoji_events_rounded
                    : Icons.air_rounded,
                color: gold,
                size: 34,
              ),
              const SizedBox(height: 8),
              Text(
                paused
                    ? 'উড়ানে বিরতি'
                    : newBest
                    ? 'নতুন রেকর্ড!'
                    : 'উড়ান শেষ',
                style: const TextStyle(
                  color: ivory,
                  fontSize: 27,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              if (sensorIssue != null)
                Text(
                  sensorIssue!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: gold, fontSize: 16),
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final item in [
                    ('গেট', flight.score),
                    ('লেভেল', flight.level),
                    ('জমা পালক', flight.featherBalance),
                    ('সেরা', best),
                  ])
                    Expanded(
                      child: Column(
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              '${item.$2}',
                              style: lettering(40, color: gold, italic: false),
                            ),
                          ),
                          Text(
                            item.$1,
                            style: const TextStyle(color: ivory, fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              if (nextCourse != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    'পরের অঞ্চল · ${nextCourse.title} · লেভেল ${nextCourse.level}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: ivory, fontSize: 15),
                  ),
                ),
              const SizedBox(height: 16),
              if (!paused && flight.canRevive) ...[
                action(
                  'এখান থেকে উড়ুন · ${Flight.reviveCost} পালক',
                  Icons.restore_rounded,
                  continueFromCrash,
                ),
                secondary('শুরু থেকে খেলুন', () => start(useTouch: touch)),
              ] else ...[
                if (!paused)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      'এখান থেকে ফিরতে আরও ${Flight.reviveCost - flight.featherBalance}টি পালক লাগবে।',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: gold, fontSize: 15),
                    ),
                  ),
                action(
                  paused ? 'চালিয়ে যান' : 'আবার উড়ুন',
                  Icons.play_arrow_rounded,
                  () => start(useTouch: touch, resume: paused),
                ),
              ],
              if (paused && !touch)
                secondary(
                  'টাচ দিয়ে চালিয়ে যান',
                  () => start(useTouch: true, resume: true),
                ),
              secondary('শুরুতে ফিরুন', home),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = stage == Stage.title;
    final course = flight.course;
    final gatesIntoCourse =
        flight.score - (course.level - 1) * Flight.pointsPerLevel;
    final moonEntry =
        flight.level == Flight.moonLevel &&
        flight.score % Flight.pointsPerLevel < 4;
    final levelLabel = course == Course.gardens && flight.inMoonValley
        ? 'চাঁদের উপত্যকা  ·  লেভেল ${flight.level}'
        : course != Course.valley
        ? '${course.title}  ·  লেভেল ${flight.level}'
        : flight.justLeveledUp
        ? 'লেভেল আপ!  ·  লেভেল ${flight.level}'
        : 'লেভেল ${flight.level}';
    return PopScope(
      canPop: title,
      onPopInvokedWithResult: (popped, result) {
        if (popped) return;
        if (live) {
          pause();
        } else {
          home();
        }
      },
      child: Scaffold(
        backgroundColor: deep,
        body: LayoutBuilder(
          builder: (context, box) {
            final h = box.maxHeight, w = box.maxWidth;
            return Stack(
              fit: StackFit.expand,
              children: [
                RepaintBoundary(
                  child: CustomPaint(
                    painter: FlightScene(
                      art: widget.art,
                      flight: flight,
                      lobby: title,
                      time: () => sceneTime.value,
                      frames: sceneTime,
                    ),
                  ),
                ),
                if (title)
                  const IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: [0, .25, .51, .76, 1],
                          colors: [
                            Color(0x17193e43),
                            Colors.transparent,
                            Colors.transparent,
                            Color(0x48123440),
                            Color(0xf2092b38),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (stage == Stage.flying)
                  Positioned.fill(
                    child: Semantics(
                      label: touch
                          ? 'টেনে চালান, চেপে ধরে বুস্ট দিন'
                          : 'চেপে ধরে বুস্ট দিন',
                      child: Listener(
                        behavior: HitTestBehavior.opaque,
                        onPointerDown: (e) => press(e, h),
                        onPointerMove: (e) => drag(e, h),
                        onPointerUp: release,
                        onPointerCancel: release,
                      ),
                    ),
                  ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: IgnorePointer(
                              child: Wrap(
                                spacing: 7,
                                runSpacing: 4,
                                children: [
                                  if (title)
                                    _Pill(
                                      Icons.emoji_events_outlined,
                                      'সেরা  $best',
                                    )
                                  else ...[
                                    _Pill(
                                      Icons.flag_outlined,
                                      'গেট  ${flight.score}',
                                    ),
                                    if (flight.inMoonValley)
                                      _Pill(
                                        flight.hasShield
                                            ? Icons.shield
                                            : Icons.nightlight_outlined,
                                        flight.hasShield
                                            ? 'ঢাল প্রস্তুত'
                                            : 'ঢাল ${flight.moonCharge}/${Flight.shieldCost}',
                                      ),
                                  ],
                                  _Pill(
                                    Icons.eco_outlined,
                                    '${flight.featherBalance}',
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          if (live)
                            circleButton(Icons.pause_rounded, 'বিরতি', pause)
                          else
                            circleButton(
                              sound
                                  ? Icons.volume_up_outlined
                                  : Icons.volume_off_outlined,
                              sound ? 'শব্দ বন্ধ করুন' : 'শব্দ চালু করুন',
                              toggleSound,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (title) ...[
                  Positioned(
                    top: h * .185,
                    left: 12,
                    right: 12,
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Semantics(
                          header: true,
                          child: Text(
                            'SKYGLIDE',
                            style:
                                lettering(
                                  math.min(96, w * .245),
                                  color: ivory,
                                ).copyWith(
                                  letterSpacing: -1.8,
                                  shadows: const [
                                    Shadow(color: navy, offset: Offset(2, 4)),
                                    Shadow(color: navy, blurRadius: 7),
                                  ],
                                ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: SafeArea(
                      top: false,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 430),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(25, 8, 25, 12),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'ফোন কাত করে উড়ুন। গতি বাড়াতে স্ক্রিন চেপে ধরুন।',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: ivory,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 18,
                                  shadows: [Shadow(color: deep, blurRadius: 5)],
                                ),
                              ),
                              const SizedBox(height: 12),
                              action(
                                'উড়ান শুরু',
                                Icons.flight_takeoff_rounded,
                                () => start(useTouch: false),
                              ),
                              secondary(
                                'টেনে খেলুন',
                                () => start(useTouch: true),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
                if (stage == Stage.calibrating)
                  Center(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 18),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 13,
                      ),
                      decoration: BoxDecoration(
                        color: deep.withValues(alpha: .93),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Text(
                        'যেভাবে খেলবেন, সেভাবে এক মুহূর্ত ফোনটি ধরুন।',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: ivory, fontSize: 17),
                      ),
                    ),
                  ),
                if (stage == Stage.flying)
                  SafeArea(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: IgnorePointer(
                        child: Padding(
                          padding: const EdgeInsets.all(13),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (flight.score == 0) ...[
                                _Pill(
                                  touch
                                      ? Icons.touch_app
                                      : Icons.screen_rotation_alt,
                                  touch
                                      ? 'টেনে চালান। বুস্ট দিতে ধরে রেখে টানুন।'
                                      : 'ফোনের ওপরের দিক তুললে পাখি ওপরে উঠবে',
                                ),
                                const SizedBox(height: 5),
                              ],
                              if (moonEntry ||
                                  (course != Course.valley &&
                                      gatesIntoCourse < 4)) ...[
                                _Pill(
                                  moonEntry
                                      ? Icons.nightlight_round
                                      : Icons.explore_outlined,
                                  moonEntry
                                      ? 'ফাঁক দুলবে। ৩টি চাঁদপালক তুললে ঢাল পাবেন।'
                                      : course.hint,
                                ),
                                const SizedBox(height: 5),
                              ],
                              if (flight.boostHeld)
                                const Align(
                                  alignment: Alignment.centerRight,
                                  child: _Pill(Icons.bolt_rounded, 'বুস্ট'),
                                ),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Semantics(
                                  liveRegion: true,
                                  child: _Pill(
                                    flight.justLeveledUp
                                        ? Icons.celebration_outlined
                                        : flight.inMoonValley
                                        ? Icons.nightlight_round
                                        : Icons.layers_outlined,
                                    levelLabel,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                if (stage == Stage.paused || stage == Stage.ended) ...[
                  const ColoredBox(color: Color(0x4d103a49)),
                  SafeArea(child: menuPanel()),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.icon, this.label);
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: deep.withValues(alpha: .83),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: const Color(0x55fff7df)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: gold),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            style: const TextStyle(
              color: ivory,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}
