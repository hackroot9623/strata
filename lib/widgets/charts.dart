import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../models.dart';

/// Hourly temperature line with gradient fill.
class HourlyTempChart extends StatelessWidget {
  final List<HourlyPoint> points;
  final String unit;
  const HourlyTempChart(this.points, this.unit, {super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pts = points.take(24).toList();
    if (pts.length < 2) return const SizedBox.shrink();
    final spots = <FlSpot>[
      for (var i = 0; i < pts.length; i++) FlSpot(i.toDouble(), pts[i].temp)
    ];
    // Only draw a separate line when it actually differs (MET Norway has no
    // apparent temperature and just mirrors temp — a second identical line
    // is visual noise).
    final showFeels = pts.any((p) => (p.feelsLike - p.temp).abs() > 0.5);
    final feelsSpots = <FlSpot>[
      for (var i = 0; i < pts.length; i++)
        FlSpot(i.toDouble(), pts[i].feelsLike)
    ];
    final temps = pts.expand((p) => [p.temp, if (showFeels) p.feelsLike]);
    final minY = temps.reduce((a, b) => a < b ? a : b);
    final maxY = temps.reduce((a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showFeels)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 14, height: 3, color: cs.primary),
                const SizedBox(width: 6),
                Text('Temp',
                    style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withValues(alpha: 0.7))),
                const SizedBox(width: 16),
                Container(width: 14, height: 2, color: cs.secondary),
                const SizedBox(width: 6),
                Text('Feels like',
                    style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withValues(alpha: 0.7))),
              ],
            ),
          ),
        SizedBox(
          height: 160,
          child: LineChart(
            LineChartData(
              minY: minY - 2,
              maxY: maxY + 2,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) => FlLine(
                    color: cs.onSurface.withValues(alpha: 0.08),
                    strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: 4,
                    getTitlesWidget: (v, _) {
                      final i = v.toInt();
                      if (i < 0 || i >= pts.length) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text('${pts[i].time.hour}h',
                            style: TextStyle(
                                fontSize: 11,
                                color: cs.onSurface.withValues(alpha: 0.6))),
                      );
                    },
                  ),
                ),
              ),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipItems: (spots) => spots
                      .map((s) => LineTooltipItem(
                          s.barIndex == 0
                              ? '${s.y.round()}$unit'
                              : 'Feels ${s.y.round()}$unit',
                          TextStyle(
                              color:
                                  s.barIndex == 0 ? cs.onSurface : cs.secondary,
                              fontWeight: FontWeight.w600)))
                      .toList(),
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  barWidth: 3,
                  color: cs.primary,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        cs.primary.withValues(alpha: 0.35),
                        cs.primary.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
                if (showFeels)
                  LineChartBarData(
                    spots: feelsSpots,
                    isCurved: true,
                    barWidth: 2,
                    color: cs.secondary,
                    dashArray: const [6, 4],
                    dotData: const FlDotData(show: false),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Precipitation probability bars (per hour or per day).
class PrecipBars extends StatelessWidget {
  final List<double> values; // 0..100
  final List<String> labels;
  const PrecipBars(this.values, this.labels, {super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (values.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 150,
      child: BarChart(
        BarChartData(
          maxY: 100,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(
                color: cs.onSurface.withValues(alpha: 0.08), strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (v, _) {
                  final i = v.toInt();
                  if (i < 0 || i >= labels.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(labels[i],
                        style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurface.withValues(alpha: 0.6))),
                  );
                },
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < values.length; i++)
              BarChartGroupData(x: i, barRods: [
                BarChartRodData(
                  toY: values[i],
                  width: 14,
                  borderRadius: BorderRadius.circular(4),
                  color: cs.primary,
                )
              ]),
          ],
        ),
      ),
    );
  }
}
