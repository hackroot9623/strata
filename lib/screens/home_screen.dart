import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models.dart';
import '../settings.dart';
import '../weather_theme.dart';
import '../widgets/mini_map.dart';
import '../widgets/sky_card.dart';
import '../widgets/sun_moon.dart';
import '../widgets/weather_background.dart';
import '../widgets/wx_icon.dart';
import '../util.dart';

class HomeScreen extends StatelessWidget {
  final Weather w;
  final VoidCallback onOpenMaps;
  final VoidCallback onOpenForecast;
  const HomeScreen(this.w,
      {super.key, required this.onOpenMaps, required this.onOpenForecast});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        LayoutBuilder(builder: (context, c) {
          if (c.maxWidth > 820) {
            // Right column is content-sized; IntrinsicHeight stretches the hero
            // to match its full height.
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 3, child: _Hero(w)),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                            height: 150,
                            child: MapMini(
                                key: ValueKey('${w.lat},${w.lon}'),
                                lat: w.lat,
                                lon: w.lon,
                                onTap: onOpenMaps)),
                        const SizedBox(height: 12),
                        _ForecastMini(w, onOpenForecast),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }
          return Column(
            children: [
              _Hero(w),
              const SizedBox(height: 16),
              SizedBox(
                  height: 180,
                  child: MapMini(
                      key: ValueKey('${w.lat},${w.lon}'),
                      lat: w.lat,
                      lon: w.lon,
                      onTap: onOpenMaps)),
              const SizedBox(height: 12),
              _ForecastMini(w, onOpenForecast),
            ],
          );
        }),
        const SizedBox(height: 28),
        _TodaySection(w),
        const SizedBox(height: 28),
        const _SectionTitle('Current Conditions'),
        const SizedBox(height: 12),
        _ConditionsGrid(w),
        const SizedBox(height: 28),
        const _SectionTitle('Sun & Moon'),
        const SizedBox(height: 12),
        LayoutBuilder(builder: (context, c) {
          final sun =
              SunCard(sunrise: w.sunrise, sunset: w.sunset, daily: w.daily);
          if (c.maxWidth > 560) {
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: sun),
                  const SizedBox(width: 16),
                  const Expanded(child: MoonCard()),
                ],
              ),
            );
          }
          return Column(
              children: [sun, const SizedBox(height: 16), const MoonCard()]);
        }),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 22));
}

class _Hero extends StatelessWidget {
  final Weather w;
  const _Hero(this.w);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tint = settings.tintHero;
    final g = WeatherVisuals.of(w.condition, w.isDay).gradient;

    final content =
        Padding(padding: const EdgeInsets.all(28), child: _row(context));

    final card = tint
        ? WeatherBackground(
            condition: w.condition, isDay: w.isDay, child: content)
        : Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              color: cs.brightness == Brightness.light
                  ? Colors.white
                  : const Color(0xFF131C22),
              border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
            ),
            child: content,
          );

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: (tint ? g.last : Colors.black).withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: card,
    );
  }

  Widget _row(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tint = settings.tintHero;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.location_on,
                    size: 18, color: _fg(tint, cs).withValues(alpha: 0.9)),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(w.place,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: _fg(tint, cs).withValues(alpha: 0.9),
                          fontWeight: FontWeight.w600)),
                ),
              ]),
              if (w.nowcast != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: _fg(tint, cs).withValues(alpha: 0.20),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.umbrella, size: 16, color: _fg(tint, cs)),
                      const SizedBox(width: 6),
                      Text(w.nowcast!,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _fg(tint, cs))),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${w.temp.round()}',
                      style: TextStyle(
                          fontFamily: 'PlusJakartaSans',
                          fontSize: 72,
                          height: 1,
                          fontWeight: FontWeight.w800,
                          color: _fg(tint, cs))),
                  const SizedBox(width: 4),
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(w.tempUnit,
                        style: TextStyle(fontSize: 22, color: _fg(tint, cs))),
                  ),
                ],
              ),
              Text(w.description,
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: _fg(tint, cs))),
              const SizedBox(height: 10),
              Row(children: [
                Icon(Icons.arrow_upward,
                    size: 16, color: _fg(tint, cs).withValues(alpha: 0.85)),
                Text(' ${w.daily.first.max.round()}°   ',
                    style: TextStyle(
                        color: _fg(tint, cs).withValues(alpha: 0.85))),
                Icon(Icons.arrow_downward,
                    size: 16, color: _fg(tint, cs).withValues(alpha: 0.85)),
                Text(' ${w.daily.first.min.round()}°',
                    style: TextStyle(
                        color: _fg(tint, cs).withValues(alpha: 0.85))),
              ]),
              const Spacer(),
              _chips(context),
            ],
          ),
        ),
        WxLottie(w.condition, isDay: w.isDay, size: 140),
      ],
    );
  }

  Widget _chips(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = _fg(settings.tintHero, cs);
    final rain = w.hourly.isNotEmpty ? w.hourly.first.precipProb : null;
    final uv = w.uvIndex;
    final items = <(IconData, String)>[
      (Icons.thermostat, 'Feels ${w.feelsLike.round()}°'),
      (Icons.water_drop_outlined, '${w.humidity}%'),
      (Icons.air, '${w.wind.round()} ${w.windUnit}'),
      if (rain != null) (Icons.umbrella_outlined, 'Rain $rain%'),
      if (uv != null) (Icons.wb_sunny_outlined, 'UV ${uv.round()}'),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (icon, text) in items)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: fg.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: fg),
                const SizedBox(width: 5),
                Text(text,
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
              ],
            ),
          ),
      ],
    );
  }

  // On the animated scene, white reads everywhere except the light snow scene
  // (dark text); with tint off, follow the theme's onSurface.
  Color _fg(bool tint, ColorScheme cs) => !tint
      ? cs.onSurface
      : (w.condition == Condition.snow ? Colors.black87 : Colors.white);
}

class _TodaySection extends StatefulWidget {
  final Weather w;
  const _TodaySection(this.w);
  @override
  State<_TodaySection> createState() => _TodaySectionState();
}

class _TodaySectionState extends State<_TodaySection> {
  static const _step = 90.0; // chip width 78 + gap 12
  final _ctrl = ScrollController();
  String _label = 'Today';
  bool _atStart = true;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
  }

  void _onScroll() {
    final pts = widget.w.hourly;
    if (pts.isEmpty || !_ctrl.hasClients) return;
    final center = _ctrl.offset + _ctrl.position.viewportDimension / 2;
    final i = (center / _step).floor().clamp(0, pts.length - 1);
    final label = dayLabel(pts[i].time, pts.first.time);
    final atStart = _ctrl.offset <= 0;
    if (label != _label || atStart != _atStart) {
      setState(() {
        _label = label;
        _atStart = atStart;
      });
    }
  }

  void _scrollBy(double delta) {
    final target =
        (_ctrl.offset + delta).clamp(0.0, _ctrl.position.maxScrollExtent);
    _ctrl.animateTo(target,
        duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pts = widget.w.hourly;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(_label),
        const SizedBox(height: 12),
        SizedBox(
          height: 132,
          child: Stack(
            alignment: Alignment.center,
            children: [
              ListView.separated(
                controller: _ctrl,
                scrollDirection: Axis.horizontal,
                itemCount: pts.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, i) {
                  final p = pts[i];
                  final selected = i == 0;
                  return Container(
                    width: 78,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: selected
                          ? cs.primary
                          : (cs.brightness == Brightness.light
                              ? Colors.white
                              : const Color(0xFF131C22)),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: cs.brightness == Brightness.light
                            ? Colors.black.withValues(alpha: 0.05)
                            : Colors.white.withValues(alpha: 0.06),
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(i == 0 ? 'Now' : hourLabel(p.time),
                            style: TextStyle(
                                fontSize: 12,
                                color: selected ? cs.onPrimary : cs.onSurface)),
                        WxTile(p.condition, size: 34),
                        Text('${p.temp.round()}°',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: selected ? cs.onPrimary : cs.onSurface)),
                      ],
                    ),
                  );
                },
              ),
              if (!_atStart)
                Positioned(
                    left: 0,
                    child: _ScrollArrow(
                      icon: Icons.chevron_left,
                      onTap: () => _scrollBy(-_step * 3),
                    )),
              Positioned(
                  right: 0,
                  child: _ScrollArrow(
                    icon: Icons.chevron_right,
                    onTap: () => _scrollBy(_step * 3),
                  )),
            ],
          ),
        ),
      ],
    );
  }
}

class _ScrollArrow extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _ScrollArrow({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.brightness == Brightness.light
          ? Colors.white.withValues(alpha: 0.9)
          : const Color(0xFF131C22).withValues(alpha: 0.9),
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 20, color: cs.onSurface),
        ),
      ),
    );
  }
}

class _ConditionsGrid extends StatelessWidget {
  final Weather w;
  const _ConditionsGrid(this.w);

  @override
  Widget build(BuildContext context) {
    final aqi = w.air?.aqi;
    final band = aqi != null ? aqiBand(aqi) : null;
    final uv = w.uvIndex;
    final uvGap = uv == null ? 'Not supported by ${w.provider}' : null;
    final cards = <Widget>[
      StatCard(
        label: 'UV INDEX',
        icon: Icons.wb_sunny_outlined,
        value: uv != null ? uv.round().toString() : '—',
        sub: uv != null ? uvLabel(uv) : 'Unavailable',
        progress: uv != null ? (uv / 11).clamp(0, 1).toDouble() : null,
        barColor: const Color(0xFFFDD835),
        unsupportedNote: uvGap,
        onTap: uv == null
            ? null
            : () => _detail(context,
                icon: Icons.wb_sunny_outlined,
                title: 'UV Index',
                rows: [
                  ('Today\'s max', '${uv.round()}'),
                  ('Level', uvLabel(uv)),
                ],
                note: _uvAdvice(uv)),
      ),
      StatCard(
        label: 'WIND',
        icon: Icons.air,
        value: '${w.wind.round()} ${w.windUnit}',
        sub: windCardinal(w.windDir),
        trailing: Transform.rotate(
          angle: (w.windDir + 180) * math.pi / 180,
          child: const Icon(Icons.navigation, size: 22),
        ),
        onTap: () => _detail(context,
            icon: Icons.air,
            title: 'Wind',
            rows: [
              ('Speed', '${w.wind.round()} ${w.windUnit}'),
              ('Gusts', '${w.windGust.round()} ${w.windUnit}'),
              ('Direction', '${w.windDir}° ${windCardinal(w.windDir)}'),
              ('Max today', '${w.daily.first.windMax.round()} ${w.windUnit}'),
            ],
            note: 'Wind blowing from the ${windCardinal(w.windDir)}. '
                'Gusts are brief peaks above the steady speed.'),
      ),
      StatCard(
        label: 'HUMIDITY',
        icon: Icons.water_drop_outlined,
        value: '${w.humidity}%',
        sub: w.dewPoint != null
            ? 'Dew point ${w.dewPoint!.round()}°'
            : 'Dew point unavailable',
        unsupportedNote: w.dewPoint == null
            ? 'Dew point not supported by ${w.provider}'
            : null,
        onTap: () => _detail(context,
            icon: Icons.water_drop_outlined,
            title: 'Humidity',
            rows: [
              ('Relative humidity', '${w.humidity}%'),
              if (w.dewPoint != null)
                ('Dew point', '${w.dewPoint!.round()}${w.tempUnit}'),
            ],
            note: w.dewPoint != null
                ? _humidityNote(w.humidity)
                : '${_humidityNote(w.humidity)}\n\nDew point isn\'t provided by '
                    '${w.provider}.'),
      ),
      StatCard(
        label: 'FEELS LIKE',
        icon: Icons.thermostat,
        value: '${w.feelsLike.round()}°',
        sub: _feelsNote(w),
        onTap: () => _detail(context,
            icon: Icons.thermostat,
            title: 'Feels like',
            rows: [
              ('Actual', '${w.temp.round()}${w.tempUnit}'),
              ('Feels like', '${w.feelsLike.round()}${w.tempUnit}'),
              (
                'Difference',
                '${(w.feelsLike - w.temp).round().abs()}° ${w.feelsLike >= w.temp ? 'warmer' : 'cooler'}'
              ),
            ],
            note: 'Apparent temperature blends humidity, wind and sun into how '
                'the air actually feels on your skin.'),
      ),
      StatCard(
        label: 'VISIBILITY',
        icon: Icons.visibility_outlined,
        value: w.visibilityKm != null ? '${w.visibilityKm!.round()} km' : '—',
        sub: w.visibilityKm != null ? _visNote(w.visibilityKm!) : 'Unavailable',
        unsupportedNote:
            w.visibilityKm == null ? 'Not supported by ${w.provider}' : null,
        onTap: w.visibilityKm == null
            ? null
            : () => _detail(context,
                icon: Icons.visibility_outlined,
                title: 'Visibility',
                rows: [
                  ('Distance', '${w.visibilityKm!.round()} km'),
                  ('Condition', _visNote(w.visibilityKm!)),
                ],
                note: 'How far you can clearly see. Fog, haze and heavy rain '
                    'reduce it.'),
      ),
      StatCard(
        label: 'AIR QUALITY',
        icon: Icons.eco_outlined,
        value: aqi?.toString() ?? '—',
        sub: band?.$1 ?? 'Unavailable',
        progress: aqi != null ? (aqi / 100).clamp(0, 1).toDouble() : null,
        barColor: band != null ? Color(band.$2) : null,
        onTap: w.air == null ? null : () => _showAir(context, w.air!),
      ),
    ];

    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth > 900 ? 3 : (c.maxWidth > 560 ? 2 : 1);
      const gap = 16.0;
      final width = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final card in cards) SizedBox(width: width, child: card)
        ],
      );
    });
  }

  String _feelsNote(Weather w) {
    final d = (w.feelsLike - w.temp).abs();
    if (d < 1) return 'Similar to actual';
    return w.feelsLike > w.temp ? 'Warmer than actual' : 'Cooler than actual';
  }

  String _visNote(double km) {
    if (km >= 20) return 'Perfectly clear';
    if (km >= 10) return 'Clear view';
    if (km >= 4) return 'Hazy';
    return 'Low visibility';
  }

  String _uvAdvice(double uv) {
    if (uv < 3) return 'Low risk. No protection needed for most people.';
    if (uv < 6) return 'Moderate. Wear sunscreen and sunglasses midday.';
    if (uv < 8) return 'High. Seek shade around noon; SPF 30+ recommended.';
    if (uv < 11) {
      return 'Very high. Minimize sun 10am–4pm; reapply sunscreen often.';
    }
    return 'Extreme. Avoid the sun midday; full protection essential.';
  }

  String _humidityNote(int h) {
    if (h < 30) return 'Dry — skin and airways may feel parched.';
    if (h <= 60) return 'Comfortable humidity range.';
    if (h <= 75) return 'Humid — the air feels sticky.';
    return 'Very humid — muggy and oppressive.';
  }

  void _detail(
    BuildContext context, {
    required IconData icon,
    required String title,
    required List<(String, String)> rows,
    required String note,
  }) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title:
            Row(children: [Icon(icon), const SizedBox(width: 8), Text(title)]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (k, v) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(k),
                    Text(v,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            Text(note,
                style: TextStyle(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.7),
                    fontSize: 13)),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close')),
        ],
      ),
    );
  }

  void _showAir(BuildContext context, AirQuality air) {
    final band = air.aqi != null ? aqiBand(air.aqi!) : null;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.eco_outlined),
            const SizedBox(width: 8),
            const Text('Air quality'),
            const Spacer(),
            if (band != null)
              Text('${air.aqi}  ${band.$1}',
                  style: TextStyle(
                      color: Color(band.$2), fontWeight: FontWeight.w700)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _pollutant('PM2.5', air.pm25, 'µg/m³', 25),
            _pollutant('PM10', air.pm10, 'µg/m³', 50),
            _pollutant('Ozone (O₃)', air.o3, 'µg/m³', 120),
            _pollutant('NO₂', air.no2, 'µg/m³', 40),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close')),
        ],
      ),
    );
  }

  Widget _pollutant(String name, double? v, String unit, double ref) {
    // ref = rough guideline value; bar fills relative to it.
    final frac = v == null ? 0.0 : (v / ref).clamp(0.0, 1.0).toDouble();
    final color = frac < 0.5
        ? const Color(0xFF43A047)
        : frac < 0.85
            ? const Color(0xFFFB8C00)
            : const Color(0xFFE53935);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(name),
              Text(v == null ? '—' : '${v.round()} $unit',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
                value: frac, minHeight: 6, color: color),
          ),
        ],
      ),
    );
  }
}

/// One tile in the Current Conditions grid.
class StatCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final String value;
  final String sub;
  final double? progress; // 0..1, optional bar
  final Color? barColor;
  final Widget? trailing;
  final VoidCallback? onTap;
  // Non-null when this card's data isn't provided by the current
  // provider/model — shown as a small badge + tooltip instead of pretending
  // the value is real.
  final String? unsupportedNote;
  const StatCard({
    super.key,
    required this.label,
    required this.icon,
    required this.value,
    required this.sub,
    this.progress,
    this.barColor,
    this.trailing,
    this.onTap,
    this.unsupportedNote,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurface.withValues(alpha: 0.55);
    final gap = unsupportedNote != null;
    return SkyCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label,
                    style: TextStyle(
                        fontSize: 12,
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w600,
                        color: muted)),
              ),
              if (unsupportedNote != null) ...[
                Tooltip(
                  message: unsupportedNote,
                  child: Icon(Icons.info_outline,
                      size: 15, color: cs.error.withValues(alpha: 0.7)),
                ),
                const SizedBox(width: 6),
              ],
              Icon(icon, size: 18, color: muted),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(value,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        color: gap ? muted : null)),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 4),
          Text(sub, style: TextStyle(color: muted, fontSize: 13)),
          // Always reserve the bar row so every card is the same height.
          const SizedBox(height: 12),
          SizedBox(
            height: 6,
            child: progress == null
                ? null
                : ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 6,
                      backgroundColor: cs.onSurface.withValues(alpha: 0.10),
                      color: barColor ?? cs.primary,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Compact next-days preview on Home; tap opens the Forecast page.
class _ForecastMini extends StatelessWidget {
  final Weather w;
  final VoidCallback onTap;
  const _ForecastMini(this.w, this.onTap);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final days = w.daily.take(4).toList();
    return SkyCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text('Forecast',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontSize: 16)),
              const Spacer(),
              Icon(Icons.chevron_right,
                  color: cs.onSurface.withValues(alpha: 0.5)),
            ],
          ),
          const SizedBox(height: 4),
          for (var i = 0; i < days.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                      width: 44,
                      child: Text(i == 0 ? 'Today' : weekday(days[i].date),
                          style: const TextStyle(fontSize: 13))),
                  WxTile(days[i].condition, size: 26),
                  const Spacer(),
                  Text('${days[i].max.round()}°',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  Text('${days[i].min.round()}°',
                      style: TextStyle(
                          color: cs.onSurface.withValues(alpha: 0.55))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
