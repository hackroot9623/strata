/// Coarse weather buckets every provider maps its codes into. UI/theme/icons
/// only react to these, so a new provider = new fetcher + code mapping, no UI
/// changes.
enum Condition { clear, cloudy, fog, rain, snow, thunder }

class AirQuality {
  final int? aqi; // European AQI
  final double? pm25;
  final double? pm10;
  final double? o3;
  final double? no2;
  const AirQuality({this.aqi, this.pm25, this.pm10, this.o3, this.no2});
}

class Weather {
  final String place;
  final double lat;
  final double lon;
  final String provider; // e.g. "Open-Meteo", "MET Norway" — for gap notices

  final double temp;
  final double feelsLike;
  final int humidity;
  final double wind;
  final double windGust;
  final int windDir; // degrees
  final double pressure; // hPa
  final double precip; // mm or inch
  final int cloudCover; // %
  final double? uvIndex; // null: not supported by this provider/model
  final double? visibilityKm; // null: not supported by this provider/model
  final double? dewPoint; // null: not supported by this provider/model
  final AirQuality? air;
  final String? nowcast; // e.g. "Rain starting in ~20 min"
  final Condition condition;
  final String description;
  final bool isDay;
  final DateTime? sunrise;
  final DateTime? sunset;

  final List<HourlyPoint> hourly;
  final List<DailyForecast> daily;

  // Unit labels for display, derived from settings at fetch time.
  final String tempUnit;
  final String windUnit;
  final String precipUnit;

  Weather({
    required this.place,
    required this.lat,
    required this.lon,
    required this.provider,
    required this.temp,
    required this.feelsLike,
    required this.humidity,
    required this.wind,
    required this.windGust,
    required this.windDir,
    required this.pressure,
    required this.precip,
    required this.cloudCover,
    required this.uvIndex,
    required this.visibilityKm,
    required this.dewPoint,
    required this.air,
    required this.nowcast,
    required this.condition,
    required this.description,
    required this.isDay,
    required this.sunrise,
    required this.sunset,
    required this.hourly,
    required this.daily,
    required this.tempUnit,
    required this.windUnit,
    required this.precipUnit,
  });
}

class HourlyPoint {
  final DateTime time;
  final double temp;
  final double feelsLike;
  final int? precipProb; // %; null: not supported by this provider/model
  final double wind;
  final Condition condition;
  HourlyPoint(this.time, this.temp, this.feelsLike, this.precipProb, this.wind,
      this.condition);
}

class DailyForecast {
  final DateTime date;
  final double max;
  final double min;
  final Condition condition;
  final int? precipProbMax; // %; null: not supported by this provider/model
  final double precipSum;
  final double? uvMax; // null: not supported by this provider/model
  final double windMax;
  final DateTime? sunrise;
  final DateTime? sunset;
  DailyForecast({
    required this.date,
    required this.max,
    required this.min,
    required this.condition,
    required this.precipProbMax,
    required this.precipSum,
    required this.uvMax,
    required this.windMax,
    required this.sunrise,
    required this.sunset,
  });
}
