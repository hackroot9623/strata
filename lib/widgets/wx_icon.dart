import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:lottie/lottie.dart';
import '../models.dart';
import '../weather_theme.dart';

/// Animated condition icon (Lottie).
class WxLottie extends StatelessWidget {
  final Condition condition;
  final bool isDay;
  final double size;
  const WxLottie(this.condition,
      {super.key, this.isDay = true, this.size = 120});

  @override
  Widget build(BuildContext context) {
    return Lottie.asset(
      WeatherVisuals.of(condition, isDay).lottieAsset,
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }
}

/// Small condition icon (Lottie). Pass isDay=false for the night variant.
class WxTile extends StatelessWidget {
  final Condition condition;
  final double size;
  final bool isDay;
  const WxTile(this.condition, {super.key, this.size = 32, this.isDay = true});

  @override
  Widget build(BuildContext context) {
    return Lottie.asset(WeatherVisuals.of(condition, isDay).lottieAsset,
        width: size, height: size, fit: BoxFit.contain);
  }
}

/// Colorful static SVG glyph (humidity, wind, uv, sunrise…).
class WxSvg extends StatelessWidget {
  final String name; // asset basename
  final double size;
  const WxSvg(this.name, {super.key, this.size = 28});

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset('assets/icons/$name.svg',
        width: size, height: size);
  }
}
