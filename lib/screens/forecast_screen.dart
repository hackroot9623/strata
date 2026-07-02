import 'package:flutter/material.dart';
import '../models.dart';
import '../widgets/charts.dart';
import '../widgets/sky_card.dart';
import '../widgets/wx_icon.dart';
import '../util.dart';

class ForecastScreen extends StatelessWidget {
  final Weather w;
  const ForecastScreen(this.w, {super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('7-Day Forecast', style: Theme.of(context).textTheme.displaySmall),
        const SizedBox(height: 6),
        Text('${w.place} · Updated just now',
            style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6))),
        const SizedBox(height: 20),
        for (var i = 0; i < w.daily.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _DayCard(w.daily[i], w.tempUnit, w.windUnit, w.provider,
                isToday: i == 0),
          ),
        const SizedBox(height: 16),
        SkyCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Hourly temperature',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontSize: 18)),
              const SizedBox(height: 12),
              HourlyTempChart(w.hourly, w.tempUnit),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SkyCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Rain chance · next 12h',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontSize: 18)),
              const SizedBox(height: 12),
              if (w.hourly.isNotEmpty && w.hourly.first.precipProb != null)
                PrecipBars(
                  w.hourly
                      .take(12)
                      .map((h) => (h.precipProb ?? 0).toDouble())
                      .toList(),
                  w.hourly.take(12).map((h) => '${h.time.hour}').toList(),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Text('Not supported by ${w.provider}',
                      style: TextStyle(
                          color: cs.onSurface.withValues(alpha: 0.5))),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DayCard extends StatefulWidget {
  final DailyForecast d;
  final String tempUnit;
  final String windUnit;
  final String provider;
  final bool isToday;
  const _DayCard(this.d, this.tempUnit, this.windUnit, this.provider,
      {required this.isToday});
  @override
  State<_DayCard> createState() => _DayCardState();
}

class _DayCardState extends State<_DayCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final d = widget.d;
    final muted = cs.onSurface.withValues(alpha: 0.6);
    return SkyCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      onTap: () => setState(() => _open = !_open),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 70,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.isToday ? 'Today' : weekday(d.date),
                        style: const TextStyle(
                            fontFamily: 'PlusJakartaSans',
                            fontWeight: FontWeight.w700,
                            fontSize: 17)),
                    Text('${d.date.month}/${d.date.day}',
                        style: TextStyle(color: muted, fontSize: 12)),
                  ],
                ),
              ),
              WxTile(d.condition, size: 42),
              const Spacer(),
              d.precipProbMax != null
                  ? _chip(
                      Icons.water_drop_outlined, '${d.precipProbMax}%', muted)
                  : Tooltip(
                      message:
                          'Rain chance not supported by ${widget.provider}',
                      child: _chip(Icons.water_drop_outlined, '—', muted),
                    ),
              const SizedBox(width: 16),
              _chip(
                  Icons.air, '${d.windMax.round()} ${widget.windUnit}', muted),
              const SizedBox(width: 20),
              Text('${d.max.round()}${widget.tempUnit}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 17)),
              const SizedBox(width: 8),
              Text('${d.min.round()}°', style: TextStyle(color: muted)),
              const SizedBox(width: 8),
              AnimatedRotation(
                turns: _open ? 0.5 : 0,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOutCubicEmphasized,
                child: Icon(Icons.keyboard_arrow_down, color: muted),
              ),
            ],
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 300),
            sizeCurve: Curves.easeInOutCubicEmphasized,
            firstCurve: Curves.easeInOutCubicEmphasized,
            secondCurve: Curves.easeInOutCubicEmphasized,
            crossFadeState:
                _open ? CrossFadeState.showFirst : CrossFadeState.showSecond,
            firstChild: Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Column(
                children: [
                  Divider(color: cs.onSurface.withValues(alpha: 0.08)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 28,
                    runSpacing: 12,
                    children: [
                      _detail('Rain', '${d.precipSum.toStringAsFixed(1)} mm'),
                      _detail(
                          'Max UV',
                          d.uvMax != null
                              ? '${d.uvMax!.round()} · ${uvLabel(d.uvMax!)}'
                              : 'Not supported by ${widget.provider}'),
                      _detail('Sunrise', fmtTime(d.sunrise)),
                      _detail('Sunset', fmtTime(d.sunset)),
                    ],
                  ),
                ],
              ),
            ),
            secondChild: const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  Widget _chip(IconData i, String t, Color c) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(i, size: 16, color: c),
          const SizedBox(width: 4),
          Text(t, style: TextStyle(color: c, fontSize: 13)),
        ],
      );

  Widget _detail(String k, String v) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(k,
              style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.55))),
          Text(v, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      );
}
