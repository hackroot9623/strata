import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'sky_card.dart';
import '../models.dart';
import '../util.dart';

// ── Sun: sunrise/sunset arc with current position ────────────────────────────

class SunCard extends StatelessWidget {
  final DateTime? sunrise;
  final DateTime? sunset;
  final List<DailyForecast> daily;
  const SunCard(
      {super.key,
      required this.sunrise,
      required this.sunset,
      this.daily = const []});

  void _showDialog(BuildContext context) {
    final days =
        daily.where((d) => d.sunrise != null && d.sunset != null).toList();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.wb_twilight),
          SizedBox(width: 8),
          Text('Sun · next days'),
        ]),
        content: days.isEmpty
            ? const Text('Sunrise/sunset not available for this provider.')
            : SizedBox(
                width: 320,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < days.length; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            SizedBox(
                                width: 56,
                                child: Text(
                                    i == 0 ? 'Today' : weekday(days[i].date),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600))),
                            const Spacer(),
                            const Icon(Icons.wb_sunny_outlined, size: 16),
                            const SizedBox(width: 4),
                            Text(fmtTime(days[i].sunrise)),
                            const SizedBox(width: 16),
                            const Icon(Icons.nightlight_outlined, size: 16),
                            const SizedBox(width: 4),
                            Text(fmtTime(days[i].sunset)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurface.withValues(alpha: 0.55);
    final has = sunrise != null && sunset != null;

    double progress = 0;
    String daylight = '—';
    if (has) {
      final now = DateTime.now();
      final span = sunset!.difference(sunrise!).inSeconds;
      if (span > 0) {
        progress =
            (now.difference(sunrise!).inSeconds / span).clamp(0, 1).toDouble();
        final h = span ~/ 3600, m = (span % 3600) ~/ 60;
        daylight = '${h}h ${m}m';
      }
    }

    return SkyCard(
      onTap: () => _showDialog(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('SUN',
                style: TextStyle(
                    fontSize: 12,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w600,
                    color: muted)),
            const Spacer(),
            Icon(Icons.wb_twilight, size: 18, color: muted),
          ]),
          const SizedBox(height: 8),
          SizedBox(
            height: 96,
            width: double.infinity,
            child: CustomPaint(
              painter: _SunArcPainter(has ? progress : -1, cs.primary,
                  cs.onSurface.withValues(alpha: 0.15)),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _stat(context, 'Sunrise', fmtTime(sunrise)),
              Column(children: [
                Text('Daylight', style: TextStyle(fontSize: 12, color: muted)),
                Text(daylight,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ]),
              _stat(context, 'Sunset', fmtTime(sunset)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(BuildContext context, String k, String v) {
    final muted =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(k, style: TextStyle(fontSize: 12, color: muted)),
        Text(v, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _SunArcPainter extends CustomPainter {
  final double progress; // 0..1, or <0 for "no data"
  final Color sun;
  final Color track;
  _SunArcPainter(this.progress, this.sun, this.track);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final baseY = size.height - 6;
    final rx = (size.width - 36) / 2;
    final ry = size.height - 18;

    Offset at(double t) {
      final a = math.pi * (1 - t);
      return Offset(cx + rx * math.cos(a), baseY - ry * math.sin(a));
    }

    // Dashed track.
    final track1 = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = track;
    const steps = 48;
    for (var i = 0; i < steps; i++) {
      if (i.isOdd) continue; // dashes
      canvas.drawLine(at(i / steps), at((i + 1) / steps), track1);
    }

    // Baseline.
    canvas.drawLine(
        Offset(cx - rx, baseY),
        Offset(cx + rx, baseY),
        Paint()
          ..color = track
          ..strokeWidth = 1);

    if (progress < 0) return;

    // Lit arc up to current position.
    final lit = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = sun;
    final litPath = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i <= steps; i++) {
      final t = i / steps;
      if (t > progress) break;
      final p = at(t);
      litPath.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(litPath, lit);

    // Sun dot + glow.
    final pos = at(progress);
    canvas.drawCircle(
        pos,
        16,
        Paint()
          ..shader = RadialGradient(colors: [
            sun.withValues(alpha: 0.45),
            sun.withValues(alpha: 0.0),
          ]).createShader(Rect.fromCircle(center: pos, radius: 16)));
    canvas.drawCircle(pos, 6, Paint()..color = sun);
  }

  @override
  bool shouldRepaint(_SunArcPainter old) => old.progress != progress;
}

// ── Moon: computed phase, drawn as a moon graphic ────────────────────────────

/// Moon phase 0..1 (0=new, .25=first quarter, .5=full, .75=last quarter).
double moonPhase(DateTime date) {
  final ref = DateTime.utc(2000, 1, 6, 18, 14); // a known new moon
  const synodic = 29.53058867;
  final days = date.toUtc().difference(ref).inSeconds / 86400.0;
  var p = (days % synodic) / synodic;
  if (p < 0) p += 1;
  return p;
}

String moonName(double p) {
  if (p < 0.03 || p > 0.97) return 'New Moon';
  if (p < 0.22) return 'Waxing Crescent';
  if (p < 0.28) return 'First Quarter';
  if (p < 0.47) return 'Waxing Gibbous';
  if (p < 0.53) return 'Full Moon';
  if (p < 0.72) return 'Waning Gibbous';
  if (p < 0.78) return 'Last Quarter';
  return 'Waning Crescent';
}

class MoonCard extends StatelessWidget {
  const MoonCard({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurface.withValues(alpha: 0.55);
    final p = moonPhase(DateTime.now());
    final illum = ((1 - math.cos(2 * math.pi * p)) / 2 * 100).round();
    final age = (p * 29.53).round();

    return SkyCard(
      onTap: () => _showDialog(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(children: [
            Text('MOON',
                style: TextStyle(
                    fontSize: 12,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w600,
                    color: muted)),
            const Spacer(),
            Icon(Icons.nightlight_round, size: 18, color: muted),
          ]),
          const SizedBox(height: 12),
          Row(
            children: [
              _MoonGlyph(phase: p, size: 104),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(moonName(p),
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontSize: 18)),
                    const SizedBox(height: 6),
                    _line(Icons.brightness_2_outlined, '$illum% illuminated',
                        muted),
                    const SizedBox(height: 4),
                    _line(Icons.schedule, '$age days into cycle', muted),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _line(IconData icon, String text, Color c) => Row(
        children: [
          Icon(icon, size: 14, color: c),
          const SizedBox(width: 6),
          Text(text, style: TextStyle(color: c, fontSize: 13)),
        ],
      );

  void _showDialog(BuildContext context) {
    showDialog(context: context, builder: (_) => const _MoonDialog());
  }
}

/// Moon phases dialog: a realistic moon graphic plus a day slider (today .. +29
/// days) that scrubs through the synodic cycle, animating the phase/terminator
/// and illumination% as it moves.
class _MoonDialog extends StatefulWidget {
  const _MoonDialog();
  @override
  State<_MoonDialog> createState() => _MoonDialogState();
}

class _MoonDialogState extends State<_MoonDialog>
    with SingleTickerProviderStateMixin {
  static const _synodic = 29.53058867;
  late final DateTime _today = DateTime.now();
  late final List<(String, double, DateTime)> _events = _upcomingEvents();

  late final AnimationController _ctrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 260));
  late Animation<double> _phaseAnim = AlwaysStoppedAnimation(moonPhase(_today));
  double _displayedPhase = 0;
  double _days = 0; // slider position: days from today

  @override
  void initState() {
    super.initState();
    _displayedPhase = moonPhase(_today);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  List<(String, double, DateTime)> _upcomingEvents() {
    final p = moonPhase(_today);
    DateTime nextAt(double target) {
      var d = (target - p) % 1.0;
      if (d <= 0) d += 1;
      return _today.add(Duration(seconds: (d * _synodic * 86400).round()));
    }

    return <(String, double, DateTime)>[
      ('New Moon', 0.0, nextAt(0.0)),
      ('First Quarter', 0.25, nextAt(0.25)),
      ('Full Moon', 0.5, nextAt(0.5)),
      ('Last Quarter', 0.75, nextAt(0.75)),
    ]..sort((a, b) => a.$3.compareTo(b.$3));
  }

  void _seek(double days) {
    final target =
        moonPhase(_today.add(Duration(minutes: (days * 1440).round())));
    // Interpolate the short way around the 0..1 cycle instead of always
    // forward, so the terminator doesn't visibly "rewind" the long way.
    var begin = _displayedPhase;
    final delta = target - begin;
    if (delta > 0.5) {
      begin += 1;
    } else if (delta < -0.5) {
      begin -= 1;
    }
    _phaseAnim = Tween(begin: begin, end: target)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic))
      ..addListener(() {
        setState(() => _displayedPhase = _phaseAnim.value % 1.0);
      });
    _ctrl
      ..reset()
      ..forward();
    setState(() => _days = days);
  }

  @override
  Widget build(BuildContext context) {
    final date = _today.add(Duration(minutes: (_days * 1440).round()));
    final illum =
        ((1 - math.cos(2 * math.pi * _displayedPhase)) / 2 * 100).round();
    final dayLabel =
        _days == 0 ? 'Today' : '${weekday(date)} ${date.day}/${date.month}';

    return AlertDialog(
      title: const Row(children: [
        Icon(Icons.nightlight_round),
        SizedBox(width: 8),
        Text('Moon phases'),
      ]),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _MoonGlyph(phase: _displayedPhase, size: 148),
            const SizedBox(height: 10),
            Text(moonName(_displayedPhase),
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
            const SizedBox(height: 2),
            Text('$illum% illuminated · $dayLabel',
                style: TextStyle(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.6))),
            Slider(
              value: _days,
              min: 0,
              max: 29,
              divisions: 29,
              label: dayLabel,
              onChanged: _seek,
            ),
            const Divider(height: 16),
            for (final (name, phase, evDate) in _events)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    _MoonGlyph(phase: phase, size: 34),
                    const SizedBox(width: 12),
                    Expanded(child: Text(name)),
                    Text('${weekday(evDate)} ${evDate.day}/${evDate.month}',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close')),
      ],
    );
  }
}

/// Real moon photo + a phase-shadow overlay, instead of a procedural texture.
class _MoonGlyph extends StatelessWidget {
  final double phase; // 0..1
  final double size;
  const _MoonGlyph({required this.phase, required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          ClipOval(
            child: Image.asset('assets/moon/full-moon.png',
                width: size, height: size, fit: BoxFit.cover),
          ),
          CustomPaint(
              size: Size(size, size), painter: _MoonShadowPainter(phase)),
        ],
      ),
    );
  }
}

class _MoonShadowPainter extends CustomPainter {
  final double phase; // 0..1
  _MoonShadowPainter(this.phase);

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final c = Offset(r, r);
    final rect = Rect.fromCircle(center: c, radius: r);

    // Same terminator math as before, just masking the real photo instead of
    // a painted texture.
    final waxing = phase < 0.5;
    final half = Path()
      ..addArc(rect, waxing ? -math.pi / 2 : math.pi / 2, math.pi);
    final ellW = (r * math.cos(2 * math.pi * phase)).abs();
    final ell = Path()
      ..addOval(Rect.fromCenter(center: c, width: ellW * 2, height: r * 2));
    final illum = (1 - math.cos(2 * math.pi * phase)) / 2; // 0..1
    final litPath = illum <= 0.5
        ? Path.combine(PathOperation.difference, half, ell)
        : Path.combine(PathOperation.union, half, ell);
    final unlitPath =
        Path.combine(PathOperation.difference, Path()..addOval(rect), litPath);

    canvas.drawPath(
        unlitPath,
        Paint()
          ..color = const Color(0xFF0B0E14).withValues(alpha: 0.94)
          ..isAntiAlias = true);
  }

  @override
  bool shouldRepaint(_MoonShadowPainter old) => old.phase != phase;
}
