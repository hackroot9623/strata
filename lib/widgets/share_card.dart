import 'package:flutter/material.dart';
import '../models.dart';
import '../util.dart';
import '../weather_theme.dart';
import 'wx_icon.dart';

/// Fixed-size "story" summary for exporting — condenses every section (now,
/// stats, hourly, 7-day) onto one compact card instead of screenshotting
/// whatever page happens to be on screen. Uses the same weather gradient as
/// the home hero card, so it reads as the same app.
class ShareCard extends StatelessWidget {
  final Weather w;
  const ShareCard(this.w, {super.key});

  static const width = 480.0;
  // Fixed rather than content-driven: an unbounded/OverflowBox height crashes
  // the Linux embedder's hit-testing (RenderShiftedBox assertion) once the
  // off-screen card overflows its Positioned bounds. 940 comfortably covers
  // header + stats + hourly + 5 daily rows + footer with room to spare.
  static const height = 940.0;
  static const _fg = Colors.white;

  @override
  Widget build(BuildContext context) {
    final g = WeatherVisuals.of(w.condition, w.isDay).gradient;
    final today = w.daily.isNotEmpty ? w.daily.first : null;

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
            colors: g, begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      padding: const EdgeInsets.fromLTRB(26, 24, 26, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.location_on, size: 16, color: Colors.white),
              const SizedBox(width: 4),
              Expanded(
                child: Text(w.place,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: _fg, fontWeight: FontWeight.w600, fontSize: 15)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text('${w.temp.round()}',
                  style: const TextStyle(
                      fontFamily: 'PlusJakartaSans',
                      fontSize: 56,
                      height: 1,
                      fontWeight: FontWeight.w800,
                      color: _fg)),
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 2),
                child: Text(w.tempUnit,
                    style: const TextStyle(fontSize: 18, color: _fg)),
              ),
              const Spacer(),
              WxTile(w.condition, size: 56, isDay: w.isDay),
            ],
          ),
          Text(w.description,
              style: const TextStyle(fontSize: 14, color: Color(0xE6FFFFFF))),
          if (today != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('H:${today.max.round()}°  L:${today.min.round()}°',
                  style:
                      const TextStyle(fontSize: 13, color: Color(0xCCFFFFFF))),
            ),
          const SizedBox(height: 16),
          _stats(),
          const SizedBox(height: 18),
          _label('HOURLY'),
          const SizedBox(height: 8),
          _hourly(),
          const SizedBox(height: 18),
          _label('7-DAY'),
          const SizedBox(height: 6),
          Expanded(child: _daily()),
          _footer(),
        ],
      ),
    );
  }

  Widget _label(String t) => Text(t,
      style: const TextStyle(
          fontSize: 11,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w700,
          color: Color(0xB3FFFFFF)));

  Widget _chip(String svg, String value) => Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              WxSvg(svg, size: 18),
              const SizedBox(height: 4),
              Text(value,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600, color: _fg)),
            ],
          ),
        ),
      );

  Widget _stats() => Row(
        children: [
          _chip('thermometer', 'Feels ${w.feelsLike.round()}°'),
          _chip('humidity', '${w.humidity}%'),
          _chip('wind', '${w.wind.round()} ${w.windUnit}'),
          _chip('uv-index',
              w.uvIndex != null ? 'UV ${w.uvIndex!.round()}' : 'UV —'),
        ],
      );

  Widget _hourly() {
    final pts = w.hourly.take(6).toList();
    return Row(
      children: [
        for (var i = 0; i < pts.length; i++)
          Expanded(
            child: Container(
              margin: EdgeInsets.only(right: i == pts.length - 1 ? 0 : 6),
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  Text(
                      i == 0
                          ? 'Now'
                          : hourLabel(pts[i].time).replaceAll(' ', ''),
                      style: const TextStyle(
                          fontSize: 10, color: Color(0xCCFFFFFF))),
                  const SizedBox(height: 2),
                  WxTile(pts[i].condition, size: 22, isDay: w.isDay),
                  const SizedBox(height: 2),
                  Text('${pts[i].temp.round()}°',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _fg)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _daily() {
    final days = w.daily.take(5).toList();
    return Column(
      children: [
        for (var i = 0; i < days.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                SizedBox(
                  width: 54,
                  child: Text(i == 0 ? 'Today' : weekday(days[i].date),
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _fg)),
                ),
                WxTile(days[i].condition, size: 24, isDay: true),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                      days[i].precipProbMax != null
                          ? '${days[i].precipProbMax}%'
                          : '—',
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xB3FFFFFF))),
                ),
                Text('${days[i].max.round()}°',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, color: _fg)),
                const SizedBox(width: 6),
                Text('${days[i].min.round()}°',
                    style: const TextStyle(color: Color(0xB3FFFFFF))),
              ],
            ),
          ),
      ],
    );
  }

  Widget _footer() => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          children: [
            Image.asset('assets/icons/strata-icon.png', width: 16, height: 16),
            const SizedBox(width: 6),
            const Text('Strata',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xCCFFFFFF))),
          ],
        ),
      );
}
