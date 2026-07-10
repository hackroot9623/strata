import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'models.dart';
import 'settings.dart';

/// Implement to add a provider. Register impls in [providers]. Geocoding is
/// resolved by the caller (so the search picker can pass exact coordinates).
abstract class WeatherProvider {
  String get name;
  Future<Weather> fetch(Geo geo);
}

/// Append here to scale. Index persisted in settings.providerIndex.
final List<WeatherProvider> providers = [
  OpenMeteoProvider(),
  MetNoProvider(),
  PirateWeatherProvider(),
  ForecaProvider(),
];

/// Curated subset of Open-Meteo's `models` param — the full list has 20+
/// national-weather-service models, most of which only matter for regional
/// comparisons. (value, label) pairs for the settings picker.
const openMeteoModels = [
  ('best_match', 'Best match (auto)'),
  ('ecmwf_ifs025', 'ECMWF (Europe)'),
  ('gfs_seamless', 'GFS/HRRR (NOAA, US)'),
  ('icon_seamless', 'ICON (DWD, Germany)'),
  ('ukmo_seamless', 'UK Met Office'),
  ('meteofrance_seamless', 'Météo-France'),
  ('gem_seamless', 'GEM (Canada)'),
  ('knmi_seamless', 'KNMI (Netherlands/Europe)'),
];

// ── Shared helpers ──────────────────────────────────────────────────────────

class Geo {
  final double lat, lon;
  final String label;
  Geo(this.lat, this.lon, this.label);
}

/// Open-Meteo geocoder — free, no key. Shared by all providers.
Future<Geo> geocode(String place) async {
  final uri = Uri.https('geocoding-api.open-meteo.com', '/v1/search',
      {'name': place, 'count': '1', 'language': 'en', 'format': 'json'});
  final res = await http.get(uri);
  if (res.statusCode != 200) {
    throw Exception('Location search error ${res.statusCode}');
  }
  final j = jsonDecode(res.body) as Map<String, dynamic>;
  final results = j['results'] as List?;
  if (results == null || results.isEmpty) {
    throw Exception('No place found for "$place"');
  }
  final r = results.first as Map<String, dynamic>;
  final label = [r['name'], r['admin1'], r['country']]
      .where((e) => e != null && (e as String).isNotEmpty)
      .join(', ');
  return Geo((r['latitude'] as num).toDouble(),
      (r['longitude'] as num).toDouble(), label);
}

/// Autocomplete suggestions for the search box. Empty on short/failed queries.
Future<List<Geo>> geocodeSuggest(String q, {int count = 6}) async {
  if (q.trim().length < 2) return [];
  try {
    final uri = Uri.https('geocoding-api.open-meteo.com', '/v1/search',
        {'name': q, 'count': '$count', 'language': 'en', 'format': 'json'});
    final res = await http.get(uri);
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final results = j['results'] as List?;
    if (results == null) return [];
    return results.map((e) {
      final r = e as Map<String, dynamic>;
      final label = [r['name'], r['admin1'], r['country']]
          .where((x) => x != null && (x as String).isNotEmpty)
          .join(', ');
      return Geo((r['latitude'] as num).toDouble(),
          (r['longitude'] as num).toDouble(), label);
    }).toList();
  } catch (_) {
    return [];
  }
}

/// Free Open-Meteo air-quality endpoint (AQI + pollutants). Null on any
/// failure, so missing data never breaks a fetch. Shared by all providers.
Future<AirQuality?> airQuality(double lat, double lon) async {
  try {
    final uri = Uri.https('air-quality-api.open-meteo.com', '/v1/air-quality', {
      'latitude': '$lat',
      'longitude': '$lon',
      'current': 'european_aqi,pm2_5,pm10,ozone,nitrogen_dioxide',
      'timezone': 'auto',
    });
    final res = await http.get(uri);
    if (res.statusCode != 200) return null;
    final c = (jsonDecode(res.body) as Map<String, dynamic>)['current'] as Map?;
    if (c == null) return null;
    double? d(String k) => (c[k] as num?)?.toDouble();
    return AirQuality(
      aqi: (c['european_aqi'] as num?)?.toInt(),
      pm25: d('pm2_5'),
      pm10: d('pm10'),
      o3: d('ozone'),
      no2: d('nitrogen_dioxide'),
    );
  } catch (_) {
    return null;
  }
}

/// Approximate current location by IP (free, no key). Throws on failure.
Future<Geo> ipLocation() async {
  final res = await http.get(Uri.parse('https://ipapi.co/json/'));
  if (res.statusCode != 200) throw Exception('Location lookup failed');
  final j = jsonDecode(res.body) as Map<String, dynamic>;
  final lat = (j['latitude'] as num?)?.toDouble();
  final lon = (j['longitude'] as num?)?.toDouble();
  if (lat == null || lon == null) throw Exception('Location unavailable');
  final label = [j['city'], j['region'], j['country_name']]
      .where((e) => e != null && (e as String).isNotEmpty)
      .join(', ');
  return Geo(lat, lon, label.isEmpty ? 'My location' : label);
}

// Client-side unit conversions (used by providers that only return metric).
double _msToWind(double ms) => switch (settings.windUnit) {
      WindUnit.kmh => ms * 3.6,
      WindUnit.mph => ms * 2.236936,
      WindUnit.ms => ms,
      WindUnit.kn => ms * 1.943844,
    };
double _cToTemp(double c) =>
    settings.tempUnit == TempUnit.celsius ? c : c * 9 / 5 + 32;
double _mmToPrecip(double mm) => settings.inchPrecip ? mm / 25.4 : mm;

double _dewPoint(double tC, double rh) {
  const a = 17.27, b = 237.7;
  final g = (a * tC) / (b + tC) + math.log((rh.clamp(1, 100)) / 100);
  return (b * g) / (a - g);
}

// Short-range rain nowcast from 15-min precipitation over the next ~2h.
String? _nowcast(Map<String, dynamic>? m, DateTime now) {
  final times = (m?['time'] as List?)?.cast<String>();
  final prec = (m?['precipitation'] as List?)?.cast<num?>();
  if (times == null || prec == null || times.isEmpty) return null;
  const thr = 0.1; // mm per 15 min
  var start = 0;
  for (var i = 0; i < times.length; i++) {
    if (!DateTime.parse(times[i]).isAfter(now)) start = i;
  }
  final end = math.min(start + 8, times.length);
  final rainingNow = (prec[start] ?? 0) >= thr;
  for (var i = start; i < end; i++) {
    final wet = (prec[i] ?? 0) >= thr;
    if (wet == rainingNow) continue;
    final mins =
        math.max(0, DateTime.parse(times[i]).difference(now).inMinutes);
    final verb = rainingNow ? 'stopping' : 'starting';
    return mins <= 5 ? 'Rain $verb soon' : 'Rain $verb in ~$mins min';
  }
  return null; // no change in the window
}

// ── Open-Meteo ───────────────────────────────────────────────────────────────

class OpenMeteoProvider implements WeatherProvider {
  @override
  String get name => 'Open-Meteo';

  @override
  Future<Weather> fetch(Geo geo) async {
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': '${geo.lat}',
      'longitude': '${geo.lon}',
      'current':
          'temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,'
              'wind_speed_10m,wind_gusts_10m,wind_direction_10m,is_day,'
              'surface_pressure,precipitation,cloud_cover',
      'hourly': 'temperature_2m,apparent_temperature,precipitation_probability,'
          'weather_code,wind_speed_10m,visibility,dew_point_2m',
      'minutely_15': 'precipitation',
      'daily': 'weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,'
          'uv_index_max,precipitation_probability_max,precipitation_sum,wind_speed_10m_max',
      'temperature_unit': settings.tempApi,
      'wind_speed_unit': settings.windUnit.api,
      'precipitation_unit': settings.precipApi,
      'timezone': 'auto',
      'forecast_days': '7',
      'models': settings.openMeteoModel,
    });
    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('Open-Meteo error ${res.statusCode}');
    }
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final cur = j['current'] as Map<String, dynamic>;
    final h = j['hourly'] as Map<String, dynamic>;
    final d = j['daily'] as Map<String, dynamic>;

    final hTimes = (h['time'] as List).cast<String>();
    final hTemp = (h['temperature_2m'] as List).cast<num>();
    // Regional models (via settings.openMeteoModel) don't all compute every
    // derived variable — the whole key can be missing, not just individual
    // entries, so guard the list cast itself, not just its elements.
    final hFeels = (h['apparent_temperature'] as List?)?.cast<num?>();
    final hProb = (h['precipitation_probability'] as List?)?.cast<num?>();
    final hCode = (h['weather_code'] as List?)?.cast<num?>();
    final hWind = (h['wind_speed_10m'] as List).cast<num>();
    final hVis = (h['visibility'] as List?)?.cast<num?>();
    final hDew = (h['dew_point_2m'] as List?)?.cast<num?>();
    final now = DateTime.parse(cur['time'] as String);

    var nowIdx = 0;
    for (var i = 0; i < hTimes.length; i++) {
      if (!DateTime.parse(hTimes[i]).isAfter(now)) nowIdx = i;
    }

    final hourly = <HourlyPoint>[];
    for (var i = 0; i < hTimes.length; i++) {
      final t = DateTime.parse(hTimes[i]);
      if (t.isBefore(now.subtract(const Duration(hours: 1)))) continue;
      final feels = (hFeels != null && i < hFeels.length) ? hFeels[i] : null;
      final prob = (hProb != null && i < hProb.length) ? hProb[i] : null;
      final code = (hCode != null && i < hCode.length) ? hCode[i] : null;
      hourly.add(HourlyPoint(
          t,
          hTemp[i].toDouble(),
          (feels ?? hTemp[i]).toDouble(),
          prob?.toInt(),
          hWind[i].toDouble(),
          conditionFromCode((code ?? 0).toInt())));
      if (hourly.length >= 24) break;
    }

    final dTimes = (d['time'] as List).cast<String>();
    final dProbMax =
        (d['precipitation_probability_max'] as List?)?.cast<num?>();
    final dUvMax = (d['uv_index_max'] as List?)?.cast<num?>();
    final dCode = (d['weather_code'] as List?)?.cast<num?>();
    final daily = <DailyForecast>[];
    for (var i = 0; i < dTimes.length; i++) {
      daily.add(DailyForecast(
        date: DateTime.parse(dTimes[i]),
        max: (d['temperature_2m_max'] as List)[i].toDouble(),
        min: (d['temperature_2m_min'] as List)[i].toDouble(),
        condition: conditionFromCode(
            (dCode != null && i < dCode.length ? dCode[i] : null)?.toInt() ??
                0),
        precipProbMax: (dProbMax != null && i < dProbMax.length)
            ? dProbMax[i]?.toInt()
            : null,
        precipSum: ((d['precipitation_sum'] as List)[i] ?? 0).toDouble(),
        uvMax: (dUvMax != null && i < dUvMax.length)
            ? dUvMax[i]?.toDouble()
            : null,
        windMax: ((d['wind_speed_10m_max'] as List)[i] ?? 0).toDouble(),
        sunrise: _dt((d['sunrise'] as List)[i]),
        sunset: _dt((d['sunset'] as List)[i]),
      ));
    }

    final air = await airQuality(geo.lat, geo.lon);
    final visM = (hVis != null && nowIdx < hVis.length) ? hVis[nowIdx] : null;
    final dew = (hDew != null && nowIdx < hDew.length) ? hDew[nowIdx] : null;
    final nowcast = _nowcast(j['minutely_15'] as Map<String, dynamic>?, now);

    final curTemp = (cur['temperature_2m'] as num).toDouble();
    final code = (cur['weather_code'] as num?)?.toInt() ?? 0;
    return Weather(
      place: geo.label,
      lat: geo.lat,
      lon: geo.lon,
      provider: name,
      temp: curTemp,
      feelsLike: (cur['apparent_temperature'] as num?)?.toDouble() ?? curTemp,
      humidity: (cur['relative_humidity_2m'] as num).toInt(),
      wind: (cur['wind_speed_10m'] as num).toDouble(),
      windGust: (cur['wind_gusts_10m'] as num?)?.toDouble() ?? 0,
      windDir: (cur['wind_direction_10m'] as num).toInt(),
      pressure: (cur['surface_pressure'] as num).toDouble(),
      precip: (cur['precipitation'] as num).toDouble(),
      cloudCover: (cur['cloud_cover'] as num).toInt(),
      uvIndex: daily.isNotEmpty ? daily.first.uvMax : null,
      visibilityKm: visM != null ? visM.toDouble() / 1000 : null,
      dewPoint: dew?.toDouble(),
      air: air,
      nowcast: nowcast,
      condition: conditionFromCode(code),
      description: describeCode(code),
      isDay: (cur['is_day'] as num).toInt() == 1,
      sunrise: daily.isNotEmpty ? daily.first.sunrise : null,
      sunset: daily.isNotEmpty ? daily.first.sunset : null,
      hourly: hourly,
      daily: daily,
      tempUnit: settings.tempUnitLabel,
      windUnit: settings.windUnit.label,
      precipUnit: settings.precipLabel,
    );
  }
}

// ── MET Norway (api.met.no) ───────────────────────────────────────────────────

class MetNoProvider implements WeatherProvider {
  @override
  String get name => 'MET Norway';

  // MET requires an identifying User-Agent or returns 403.
  static const _ua = {
    'User-Agent': 'gnome_weather/0.1 github.com/example/gnome_weather'
  };

  @override
  Future<Weather> fetch(Geo geo) async {
    final uri = Uri.https(
        'api.met.no',
        '/weatherapi/locationforecast/2.0/compact',
        {'lat': geo.lat.toStringAsFixed(4), 'lon': geo.lon.toStringAsFixed(4)});
    final res = await http.get(uri, headers: _ua);
    if (res.statusCode != 200) {
      throw Exception('MET Norway error ${res.statusCode}');
    }
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final series = ((j['properties'] as Map)['timeseries'] as List)
        .cast<Map<String, dynamic>>();
    if (series.isEmpty) throw Exception('MET Norway: empty forecast');

    final first = series.first;
    final inst =
        (first['data']['instant']['details'] as Map).cast<String, dynamic>();
    final tC = (inst['air_temperature'] as num).toDouble();
    final rh = (inst['relative_humidity'] as num?)?.toDouble() ?? 50;
    final symbol = _symbol(first);
    final isDay = symbol.endsWith('_day');

    // Hourly (next 24 entries that carry a 1-hour block).
    final hourly = <HourlyPoint>[];
    for (final s in series) {
      final det = s['data']['instant']['details'] as Map?;
      final next1 = s['data']['next_1_hours'];
      if (det == null || next1 == null) continue;
      final hTemp = _cToTemp((det['air_temperature'] as num).toDouble());
      hourly.add(HourlyPoint(
        DateTime.parse(s['time'] as String).toLocal(),
        hTemp,
        hTemp, // MET compact has no apparent temperature
        null, // MET compact has no precipitation probability
        _msToWind((det['wind_speed'] as num?)?.toDouble() ?? 0),
        _condFromSymbol(_symbol(s)),
      ));
      if (hourly.length >= 24) break;
    }

    // Daily aggregation by local date.
    final byDay = <DateTime, List<Map<String, dynamic>>>{};
    for (final s in series) {
      final dt = DateTime.parse(s['time'] as String).toLocal();
      final key = DateTime(dt.year, dt.month, dt.day);
      (byDay[key] ??= []).add(s);
    }
    final daily = <DailyForecast>[];
    final keys = byDay.keys.toList()..sort();
    for (final k in keys.take(7)) {
      final entries = byDay[k]!;
      double? hi, lo, windMax = 0, precipSum = 0;
      for (final s in entries) {
        final det = s['data']['instant']['details'] as Map?;
        if (det != null) {
          final t = (det['air_temperature'] as num?)?.toDouble();
          if (t != null) {
            hi = hi == null ? t : math.max(hi, t);
            lo = lo == null ? t : math.min(lo, t);
          }
          final ws = (det['wind_speed'] as num?)?.toDouble() ?? 0;
          windMax = math.max(windMax!, ws);
        }
        final p =
            s['data']['next_1_hours']?['details']?['precipitation_amount'];
        if (p != null) precipSum = precipSum! + (p as num).toDouble();
      }
      // Representative symbol: entry nearest local noon.
      final noon = entries.reduce((a, b) {
        final ah = (DateTime.parse(a['time']).toLocal().hour - 12).abs();
        final bh = (DateTime.parse(b['time']).toLocal().hour - 12).abs();
        return ah <= bh ? a : b;
      });
      daily.add(DailyForecast(
        date: k,
        max: _cToTemp(hi ?? tC),
        min: _cToTemp(lo ?? tC),
        condition: _condFromSymbol(_symbol(noon)),
        precipProbMax: null, // MET compact has no precipitation probability
        precipSum: _mmToPrecip(precipSum ?? 0),
        uvMax: null, // not in compact endpoint
        windMax: _msToWind(windMax ?? 0),
        sunrise: null,
        sunset: null,
      ));
    }

    final air = await airQuality(geo.lat, geo.lon);
    final precip1h = (first['data']['next_1_hours']?['details']
                ?['precipitation_amount'] as num?)
            ?.toDouble() ??
        0;

    return Weather(
      place: geo.label,
      lat: geo.lat,
      lon: geo.lon,
      provider: name,
      temp: _cToTemp(tC),
      feelsLike: _cToTemp(tC), // MET compact has no apparent temperature
      humidity: rh.round(),
      wind: _msToWind((inst['wind_speed'] as num?)?.toDouble() ?? 0),
      windGust:
          _msToWind((inst['wind_speed_of_gust'] as num?)?.toDouble() ?? 0),
      windDir: (inst['wind_from_direction'] as num?)?.round() ?? 0,
      pressure: (inst['air_pressure_at_sea_level'] as num?)?.toDouble() ?? 0,
      precip: _mmToPrecip(precip1h),
      cloudCover: (inst['cloud_area_fraction'] as num?)?.round() ?? 0,
      uvIndex: null, // not in compact endpoint
      visibilityKm: null, // not provided
      dewPoint: _cToTemp(_dewPoint(tC, rh)),
      air: air,
      nowcast: null, // MET compact has no minutely data
      condition: _condFromSymbol(symbol),
      description: _describeSymbol(symbol),
      isDay: isDay,
      sunrise: null,
      sunset: null,
      hourly: hourly,
      daily: daily,
      tempUnit: settings.tempUnitLabel,
      windUnit: settings.windUnit.label,
      precipUnit: settings.precipLabel,
    );
  }

  String _symbol(Map<String, dynamic> s) {
    final data = s['data'] as Map;
    for (final k in ['next_1_hours', 'next_6_hours', 'next_12_hours']) {
      final code = data[k]?['summary']?['symbol_code'];
      if (code != null) return code as String;
    }
    return 'cloudy';
  }
}

// ── Pirate Weather (api.pirateweather.net) ──────────────────────────────────

class PirateWeatherProvider implements WeatherProvider {
  @override
  String get name => 'Pirate Weather';

  @override
  Future<Weather> fetch(Geo geo) async {
    final key = settings.pirateWeatherKey.trim();
    if (key.isEmpty) {
      throw Exception('Add a Pirate Weather API key in Settings');
    }
    // Always request SI units and convert client-side, like MET Norway does
    // — one conversion path instead of juggling Dark-Sky-style unit bundles
    // (us/si/ca/uk2) against our independently-configurable unit settings.
    final uri = Uri.https(
        'api.pirateweather.net',
        '/forecast/$key/${geo.lat},${geo.lon}',
        {'units': 'si', 'exclude': 'minutely,alerts,flags'});
    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('Pirate Weather error ${res.statusCode}');
    }
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final cur = j['currently'] as Map<String, dynamic>;
    final hourlyData = ((j['hourly'] as Map?)?['data'] as List?) ?? [];
    final dailyData = ((j['daily'] as Map?)?['data'] as List?) ?? [];

    double numOf(Map m, String k) => (m[k] as num?)?.toDouble() ?? 0;
    int pct(Map m, String k) => (((m[k] as num?) ?? 0) * 100).round();
    DateTime unix(num secs) =>
        DateTime.fromMillisecondsSinceEpoch((secs * 1000).toInt());
    DateTime? unixOrNull(Map m, String k) {
      final v = m[k] as num?;
      return v == null ? null : unix(v);
    }

    final hourly = <HourlyPoint>[];
    for (final raw in hourlyData) {
      final e = raw as Map<String, dynamic>;
      hourly.add(HourlyPoint(
        unix(e['time'] as num),
        _cToTemp(numOf(e, 'temperature')),
        _cToTemp(numOf(e, 'apparentTemperature')),
        pct(e, 'precipProbability'),
        _msToWind(numOf(e, 'windSpeed')),
        _condFromPirateIcon(e['icon'] as String? ?? 'cloudy'),
      ));
      if (hourly.length >= 24) break;
    }

    final daily = <DailyForecast>[];
    for (final raw in dailyData) {
      final e = raw as Map<String, dynamic>;
      daily.add(DailyForecast(
        date: unixOrNull(e, 'time') ?? DateTime.now(),
        max: _cToTemp(numOf(e, 'temperatureHigh')),
        min: _cToTemp(numOf(e, 'temperatureLow')),
        condition: _condFromPirateIcon(e['icon'] as String? ?? 'cloudy'),
        precipProbMax: pct(e, 'precipProbability'),
        precipSum: _mmToPrecip(numOf(e, 'precipAccumulation')),
        uvMax: numOf(e, 'uvIndex'),
        windMax: _msToWind(numOf(e, 'windSpeed')),
        sunrise: unixOrNull(e, 'sunriseTime'),
        sunset: unixOrNull(e, 'sunsetTime'),
      ));
      if (daily.length >= 7) break;
    }

    final air = await airQuality(geo.lat, geo.lon);
    final icon = cur['icon'] as String? ?? 'cloudy';

    return Weather(
      place: geo.label,
      lat: geo.lat,
      lon: geo.lon,
      provider: name,
      temp: _cToTemp(numOf(cur, 'temperature')),
      feelsLike: _cToTemp(numOf(cur, 'apparentTemperature')),
      humidity: pct(cur, 'humidity'),
      wind: _msToWind(numOf(cur, 'windSpeed')),
      windGust: _msToWind(numOf(cur, 'windGust')),
      windDir: (cur['windBearing'] as num?)?.round() ?? 0,
      pressure: numOf(cur, 'pressure'),
      precip: _mmToPrecip(numOf(cur, 'precipIntensity')),
      cloudCover: pct(cur, 'cloudCover'),
      uvIndex: numOf(cur, 'uvIndex'),
      visibilityKm: numOf(cur, 'visibility'),
      dewPoint: _cToTemp(numOf(cur, 'dewPoint')),
      air: air,
      // The `minutely` block has real nowcast data, but exclude=minutely
      // above skips it for now — parsing it is a separate feature.
      nowcast: null,
      condition: _condFromPirateIcon(icon),
      description: (cur['summary'] as String?) ?? 'Unknown',
      isDay: !icon.contains('night'),
      sunrise: daily.isNotEmpty ? daily.first.sunrise : null,
      sunset: daily.isNotEmpty ? daily.first.sunset : null,
      hourly: hourly,
      daily: daily,
      tempUnit: settings.tempUnitLabel,
      windUnit: settings.windUnit.label,
      precipUnit: settings.precipLabel,
    );
  }
}

// ── Foreca (pfa.foreca.com) ─────────────────────────────────────────────────

class ForecaProvider implements WeatherProvider {
  @override
  String get name => 'Foreca';

  String get _windUnit => switch (settings.windUnit) {
        WindUnit.kmh => 'KMH',
        WindUnit.mph => 'MPH',
        WindUnit.ms => 'MS',
        WindUnit.kn => 'KTS',
      };
  String get _tempUnit => settings.tempUnit == TempUnit.celsius ? 'C' : 'F';

  @override
  Future<Weather> fetch(Geo geo) async {
    final key = settings.forecaKey.trim();
    if (key.isEmpty) throw Exception('Add a Foreca access token in Settings');
    final headers = {'Authorization': 'Bearer $key'};
    final loc = '${geo.lon},${geo.lat}';
    final common = {
      'tempunit': _tempUnit,
      'windunit': _windUnit,
      'rounding': '0',
      'dataset': 'full',
    };

    Future<Map<String, dynamic>> get(String path,
        [Map<String, String> extra = const {}]) async {
      final uri = Uri.https('pfa.foreca.com', path, {...common, ...extra});
      final res = await http.get(uri, headers: headers);
      if (res.statusCode != 200) {
        throw Exception('Foreca error ${res.statusCode}');
      }
      return jsonDecode(res.body) as Map<String, dynamic>;
    }

    final results = await Future.wait([
      get('/api/v1/current/$loc'),
      get('/api/v1/forecast/hourly/$loc', {'periods': '24'}),
      get('/api/v1/forecast/daily/$loc', {'periods': '7'}),
    ]);
    final cur = results[0]['current'] as Map<String, dynamic>;
    final hourlyData =
        (results[1]['forecast'] as List).cast<Map<String, dynamic>>();
    final dailyData =
        (results[2]['forecast'] as List).cast<Map<String, dynamic>>();

    double? d(Map m, String k) => (m[k] as num?)?.toDouble();

    final hourly = <HourlyPoint>[];
    for (final e in hourlyData) {
      final temp = (e['temperature'] as num).toDouble();
      hourly.add(HourlyPoint(
        DateTime.parse(e['time'] as String),
        temp,
        d(e, 'feelsLikeTemp') ?? temp,
        (e['precipProb'] as num?)?.toInt(),
        (e['windSpeed'] as num).toDouble(),
        _condFromForecaSymbol(e['symbolPhrase'] as String? ?? ''),
      ));
      if (hourly.length >= 24) break;
    }

    DateTime? epoch(Map m, String k) {
      final v = m[k] as num?;
      return v == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(v.toInt() * 1000);
    }

    final daily = <DailyForecast>[];
    for (final e in dailyData) {
      daily.add(DailyForecast(
        date: DateTime.parse(e['date'] as String),
        max: (e['maxTemp'] as num).toDouble(),
        min: (e['minTemp'] as num).toDouble(),
        condition: _condFromForecaSymbol(e['symbolPhrase'] as String? ?? ''),
        precipProbMax: (e['precipProb'] as num?)?.toInt(),
        precipSum: _mmToPrecip(d(e, 'precipAccum') ?? 0),
        uvMax: d(e, 'uvIndex'),
        windMax: (e['maxWindSpeed'] as num?)?.toDouble() ?? 0,
        sunrise: epoch(e, 'sunriseEpoch'),
        sunset: epoch(e, 'sunsetEpoch'),
      ));
      if (daily.length >= 7) break;
    }

    final air = await airQuality(geo.lat, geo.lon);
    final phrase = cur['symbolPhrase'] as String? ?? '';
    final symbol = cur['symbol'] as String? ?? 'd000';
    final curTemp = (cur['temperature'] as num).toDouble();

    return Weather(
      place: geo.label,
      lat: geo.lat,
      lon: geo.lon,
      provider: name,
      temp: curTemp,
      feelsLike: d(cur, 'feelsLikeTemp') ?? curTemp,
      humidity: (cur['relHumidity'] as num?)?.round() ?? 0,
      wind: (cur['windSpeed'] as num).toDouble(),
      windGust: (cur['windGust'] as num?)?.toDouble() ?? 0,
      windDir: (cur['windDir'] as num?)?.round() ?? 0,
      pressure: (cur['pressure'] as num?)?.toDouble() ?? 0,
      precip: _mmToPrecip((cur['precipRate'] as num?)?.toDouble() ?? 0),
      cloudCover: (cur['cloudiness'] as num?)?.round() ?? 0,
      uvIndex: d(cur, 'uvIndex'),
      visibilityKm: (cur['visibility'] as num?) == null
          ? null
          : (cur['visibility'] as num).toDouble() / 1000,
      dewPoint: d(cur, 'dewPoint'),
      air: air,
      // Foreca's minutely nowcast is a separate endpoint — not wired up yet.
      nowcast: null,
      condition: _condFromForecaSymbol(phrase),
      description: phrase.isEmpty
          ? 'Unknown'
          : '${phrase[0].toUpperCase()}${phrase.substring(1)}',
      isDay: symbol.startsWith('d'),
      sunrise: daily.isNotEmpty ? daily.first.sunrise : null,
      sunset: daily.isNotEmpty ? daily.first.sunset : null,
      hourly: hourly,
      daily: daily,
      tempUnit: settings.tempUnitLabel,
      windUnit: settings.windUnit.label,
      precipUnit: settings.precipLabel,
    );
  }
}

Condition _condFromForecaSymbol(String phrase) {
  final s = phrase.toLowerCase();
  if (s.contains('thunder')) return Condition.thunder;
  if (s.contains('snow') || s.contains('sleet') || s.contains('ice')) {
    return Condition.snow;
  }
  if (s.contains('rain') || s.contains('drizzle') || s.contains('shower')) {
    return Condition.rain;
  }
  if (s.contains('fog') || s.contains('mist') || s.contains('haze')) {
    return Condition.fog;
  }
  if (s.contains('clear') || s.contains('sunny')) return Condition.clear;
  return Condition.cloudy;
}

Condition _condFromPirateIcon(String icon) {
  if (icon.contains('thunderstorm')) return Condition.thunder;
  if (icon.contains('snow') || icon.contains('sleet')) return Condition.snow;
  if (icon.contains('rain') || icon.contains('drizzle')) return Condition.rain;
  if (icon.contains('fog')) return Condition.fog;
  if (icon.contains('cloudy') || icon.contains('wind')) return Condition.cloudy;
  return Condition.clear;
}

Condition _condFromSymbol(String sym) {
  final s = sym.toLowerCase();
  if (s.contains('thunder')) return Condition.thunder;
  if (s.contains('snow') || s.contains('sleet')) return Condition.snow;
  if (s.contains('rain') || s.contains('drizzle')) return Condition.rain;
  if (s.contains('fog')) return Condition.fog;
  if (s.contains('cloud')) return Condition.cloudy;
  if (s.startsWith('clearsky') || s.startsWith('fair')) return Condition.clear;
  return Condition.cloudy;
}

String _describeSymbol(String sym) {
  final base = sym.replaceAll(RegExp(r'_(day|night|polartwilight)$'), '');
  // "lightrainshowers" -> "Light rain showers"
  final words = base
      .replaceAllMapped(RegExp(r'(light|heavy|partly)'), (m) => '${m[0]} ')
      .replaceAll('showers', ' showers')
      .replaceAll('clearsky', 'clear sky')
      .trim();
  return words.isEmpty
      ? 'Unknown'
      : '${words[0].toUpperCase()}${words.substring(1)}';
}

DateTime? _dt(dynamic s) => s == null ? null : DateTime.tryParse(s as String);

// WMO weather interpretation codes -> our buckets (Open-Meteo).
// https://open-meteo.com/en/docs
Condition conditionFromCode(int code) {
  if (code == 0 || code == 1) return Condition.clear;
  if (code == 2 || code == 3) return Condition.cloudy;
  if (code == 45 || code == 48) return Condition.fog;
  if (code >= 51 && code <= 67) return Condition.rain;
  if (code >= 71 && code <= 77) return Condition.snow;
  if (code >= 80 && code <= 82) return Condition.rain;
  if (code == 85 || code == 86) return Condition.snow;
  if (code >= 95) return Condition.thunder;
  return Condition.cloudy;
}

String describeCode(int code) {
  const m = {
    0: 'Clear sky',
    1: 'Mainly clear',
    2: 'Partly cloudy',
    3: 'Overcast',
    45: 'Fog',
    48: 'Rime fog',
    51: 'Light drizzle',
    53: 'Drizzle',
    55: 'Dense drizzle',
    56: 'Freezing drizzle',
    57: 'Freezing drizzle',
    61: 'Slight rain',
    63: 'Rain',
    65: 'Heavy rain',
    66: 'Freezing rain',
    67: 'Freezing rain',
    71: 'Slight snow',
    73: 'Snow',
    75: 'Heavy snow',
    77: 'Snow grains',
    80: 'Rain showers',
    81: 'Rain showers',
    82: 'Violent showers',
    85: 'Snow showers',
    86: 'Snow showers',
    95: 'Thunderstorm',
    96: 'Thunderstorm, hail',
    99: 'Thunderstorm, hail',
  };
  return m[code] ?? 'Unknown';
}
