import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models.dart';
import '../weather_theme.dart';

/// Animated weather scene for the hero card: gradient base + procedural cloud
/// shader (fbm noise — the feTurbulence analogue) + particle layer (rain,
/// snow, sun rays, stars, lightning). No image assets.
class WeatherBackground extends StatefulWidget {
  final Condition condition;
  final bool isDay;
  final Widget child;
  const WeatherBackground({
    super.key,
    required this.condition,
    required this.isDay,
    required this.child,
  });

  @override
  State<WeatherBackground> createState() => _WeatherBackgroundState();
}

class _WeatherBackgroundState extends State<WeatherBackground>
    with TickerProviderStateMixin {
  // Fast loop for particles, slow continuous loop for cloud drift.
  late final AnimationController _particles =
      AnimationController(vsync: this, duration: const Duration(seconds: 8))
        ..repeat();
  // Long period so the procedural drift reads as endless (snaps ~hourly).
  late final AnimationController _clouds =
      AnimationController(vsync: this, duration: const Duration(seconds: 3600))
        ..repeat();

  ui.FragmentShader? _shader;

  @override
  void initState() {
    super.initState();
    _loadShader();
  }

  Future<void> _loadShader() async {
    try {
      final p =
          await ui.FragmentProgram.fromAsset('assets/shaders/clouds.frag');
      if (mounted) setState(() => _shader = p.fragmentShader());
    } catch (_) {/* clouds just won't render; gradient still shows */}
  }

  @override
  void dispose() {
    _particles.dispose();
    _clouds.dispose();
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final g = WeatherVisuals.of(widget.condition, widget.isDay).gradient;
    final lightScene = widget.condition == Condition.snow;
    // Strong left band keeps the (left-aligned) text readable over any clouds.
    final scrim = lightScene
        ? [
            Colors.white.withValues(alpha: 0.65),
            Colors.white.withValues(alpha: 0.30),
            Colors.white.withValues(alpha: 0.0),
          ]
        : [
            Colors.black.withValues(alpha: 0.50),
            Colors.black.withValues(alpha: 0.22),
            Colors.black.withValues(alpha: 0.0),
          ];
    final cloud = _CloudParams.of(widget.condition, widget.isDay);

    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: g,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          ),
          // Procedural clouds.
          if (cloud != null && _shader != null)
            Positioned.fill(
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _clouds,
                  builder: (_, __) => CustomPaint(
                    painter:
                        _CloudPainter(_shader!, _clouds.value * 3600, cloud),
                  ),
                ),
              ),
            ),
          // Particles (rain/snow/sun/stars/lightning).
          Positioned.fill(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _particles,
                builder: (_, __) => CustomPaint(
                  painter: _ScenePainter(
                      widget.condition, widget.isDay, _particles.value),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: scrim,
                  stops: const [0.0, 0.45, 0.9],
                ),
              ),
            ),
          ),
          widget.child,
        ],
      ),
    );
  }
}

class _CloudParams {
  final double coverage; // lower = more cloud
  final double opacity;
  final Color color;
  final double scale; // lower = bigger clouds
  const _CloudParams(this.coverage, this.opacity, this.color, this.scale);

  static _CloudParams? of(Condition c, bool isDay) {
    switch (c) {
      case Condition.clear:
        return null; // sun/stars only
      case Condition.cloudy:
        // Overcast: big, full, grey clouds (not bright white blobs).
        return isDay
            ? const _CloudParams(0.30, 0.60, Color(0xFF9AA6B2), 3.0)
            : const _CloudParams(0.34, 0.60, Color(0xFF8A95A2), 3.2);
      case Condition.fog:
        return const _CloudParams(0.40, 0.55, Color(0xFFDDE3E8), 5.0);
      case Condition.rain:
        return const _CloudParams(0.50, 0.70, Color(0xFF9AA4AE), 4.0);
      case Condition.snow:
        return const _CloudParams(0.52, 0.62, Color(0xFFF7FAFF), 4.0);
      case Condition.thunder:
        return const _CloudParams(0.50, 0.72, Color(0xFF8A86A0), 4.0);
    }
  }
}

class _CloudPainter extends CustomPainter {
  final ui.FragmentShader shader;
  final double time;
  final _CloudParams p;
  _CloudPainter(this.shader, this.time, this.p);

  @override
  void paint(Canvas canvas, Size size) {
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, time)
      ..setFloat(3, p.coverage)
      ..setFloat(4, p.opacity)
      ..setFloat(5, p.color.r)
      ..setFloat(6, p.color.g)
      ..setFloat(7, p.color.b)
      ..setFloat(8, p.scale);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_CloudPainter old) => old.time != time || old.p != p;
}

class _ScenePainter extends CustomPainter {
  final Condition condition;
  final bool isDay;
  final double t; // 0..1 loop
  _ScenePainter(this.condition, this.isDay, this.t);

  static final _rng = math.Random(42);
  static final List<Offset> _field =
      List.generate(120, (_) => Offset(_rng.nextDouble(), _rng.nextDouble()));
  static final List<double> _phase =
      List.generate(120, (_) => _rng.nextDouble());

  @override
  void paint(Canvas canvas, Size size) {
    switch (condition) {
      case Condition.clear:
        isDay ? _sun(canvas, size) : _stars(canvas, size);
      case Condition.cloudy:
        if (!isDay) _stars(canvas, size, count: 24, dim: true);
      case Condition.fog:
        break; // shader handles fog haze
      case Condition.rain:
        _rain(canvas, size);
      case Condition.snow:
        _snow(canvas, size);
      case Condition.thunder:
        _rain(canvas, size, count: 50);
        _lightning(canvas, size);
    }
  }

  void _sun(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.82, size.height * 0.28);
    final pulse = 0.5 + 0.5 * math.sin(t * 2 * math.pi); // breathing 0..1

    // Wide pulsing halo (the "looking into the sun" glare) — strong pulse.
    final haloR = size.height * (0.7 + 0.5 * pulse);
    canvas.drawCircle(
      center,
      haloR,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: 0.22 + 0.30 * pulse),
            Colors.white.withValues(alpha: 0.08),
            Colors.white.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.4, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: haloR)),
    );

    // Tight bright core bloom that flares with the pulse.
    final coreR = size.height * (0.30 + 0.16 * pulse);
    canvas.drawCircle(
      center,
      coreR,
      Paint()
        ..shader = RadialGradient(colors: [
          Colors.white.withValues(alpha: 0.20 + 0.45 * pulse),
          Colors.white.withValues(alpha: 0.0),
        ]).createShader(Rect.fromCircle(center: center, radius: coreR)),
    );
  }

  void _stars(Canvas canvas, Size size, {int count = 50, bool dim = false}) {
    for (var i = 0; i < count; i++) {
      final p = _field[i];
      final pos = Offset(p.dx * size.width, p.dy * size.height * 0.7);
      final tw =
          0.4 + 0.6 * (0.5 + 0.5 * math.sin(t * 2 * math.pi + _phase[i] * 6));
      canvas.drawCircle(
        pos,
        1.4 * (dim ? 0.7 : 1),
        Paint()..color = Colors.white.withValues(alpha: (dim ? 0.4 : 0.9) * tw),
      );
    }
  }

  void _rain(Canvas canvas, Size size, {int count = 80}) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    const len = 16.0;
    for (var i = 0; i < count; i++) {
      final p = _field[i];
      final speed = 1.4 + _phase[i];
      final y = (p.dy + t * speed) % 1.0;
      final x = (p.dx + y * 0.08) % 1.0;
      final o = Offset(x * size.width, y * size.height);
      canvas.drawLine(o, o + const Offset(-4, len), paint);
    }
  }

  void _snow(Canvas canvas, Size size, {int count = 70}) {
    for (var i = 0; i < count; i++) {
      final p = _field[i];
      final speed = 0.25 + _phase[i] * 0.4;
      final y = (p.dy + t * speed) % 1.0;
      final drift = 0.03 * math.sin(t * 2 * math.pi + _phase[i] * 8);
      final x = (p.dx + drift) % 1.0;
      canvas.drawCircle(
        Offset(x * size.width, y * size.height),
        1.5 + _phase[i] * 1.8,
        Paint()..color = Colors.white.withValues(alpha: 0.8),
      );
    }
  }

  void _lightning(Canvas canvas, Size size) {
    final f = (t * 2) % 1.0;
    if (f > 0.06) return;
    final intensity = (1 - f / 0.06);
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Colors.white.withValues(alpha: 0.45 * intensity),
    );
  }

  @override
  bool shouldRepaint(_ScenePainter old) =>
      old.t != t || old.condition != condition || old.isDay != isDay;
}
