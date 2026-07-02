import 'package:flutter/material.dart';
import 'models.dart';

/// Maps a [Condition] (+ day/night) to a hero gradient and the animated Lottie
/// asset. Only the hero card + icons react to weather; the app chrome stays on
/// the Strata light/dark palette (see [SkyTheme]).
class WeatherVisuals {
  final List<Color> gradient;
  final String lottie; // asset basename
  const WeatherVisuals(this.gradient, this.lottie);

  String get lottieAsset => 'assets/icons/$lottie.json';

  static WeatherVisuals of(Condition c, bool isDay) {
    switch (c) {
      case Condition.clear:
        return isDay
            ? const WeatherVisuals(
                [Color(0xFF4FACFE), Color(0xFF0077C2)], 'clear-day')
            : const WeatherVisuals(
                [Color(0xFF30446E), Color(0xFF141E30)], 'clear-night');
      case Condition.cloudy:
        return isDay
            ? const WeatherVisuals(
                [Color(0xFF7B92A8), Color(0xFF4A5A6A)], 'partly-cloudy-day')
            : const WeatherVisuals(
                [Color(0xFF3A4855), Color(0xFF222B33)], 'partly-cloudy-night');
      case Condition.fog:
        return const WeatherVisuals(
            [Color(0xFF9AA9B5), Color(0xFF6B7C88)], 'fog');
      case Condition.rain:
        return const WeatherVisuals(
            [Color(0xFF4E6E81), Color(0xFF2C3E4C)], 'rain');
      case Condition.snow:
        return const WeatherVisuals(
            [Color(0xFF8FC6F0), Color(0xFF5A9BD4)], 'snow');
      case Condition.thunder:
        return const WeatherVisuals(
            [Color(0xFF5C4B8A), Color(0xFF2A1E47)], 'thunderstorms');
    }
  }
}

String tileLottie(Condition c) => WeatherVisuals.of(c, true).lottieAsset;
