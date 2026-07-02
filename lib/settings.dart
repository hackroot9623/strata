import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A saved location with its resolved coordinates, so it can be re-fetched
/// without geocoding a full "City, Region, Country" label (which often fails).
class SavedPlace {
  final double lat;
  final double lon;
  final String label;
  const SavedPlace(this.lat, this.lon, this.label);

  String encode() => '$lat|$lon|$label';
  static SavedPlace? decode(String s) {
    final p = s.split('|');
    if (p.length < 3) return null;
    final lat = double.tryParse(p[0]), lon = double.tryParse(p[1]);
    if (lat == null || lon == null) return null;
    return SavedPlace(lat, lon, p.sublist(2).join('|'));
  }
}

enum TempUnit { celsius, fahrenheit }

enum WindUnit { kmh, mph, ms, kn }

extension WindUnitX on WindUnit {
  String get api => switch (this) {
        WindUnit.kmh => 'kmh',
        WindUnit.mph => 'mph',
        WindUnit.ms => 'ms',
        WindUnit.kn => 'kn',
      };
  String get label => switch (this) {
        WindUnit.kmh => 'km/h',
        WindUnit.mph => 'mph',
        WindUnit.ms => 'm/s',
        WindUnit.kn => 'kn',
      };
}

/// App-wide settings. Single global instance (see [settings]); widgets rebuild
/// via AnimatedBuilder(animation: settings, ...). Persisted with
/// shared_preferences.
class AppSettings extends ChangeNotifier {
  TempUnit tempUnit = TempUnit.celsius;
  WindUnit windUnit = WindUnit.kmh;
  bool inchPrecip = false;
  bool tintHero = true; // hero card uses weather colors vs primary
  bool notifications = false; // desktop alerts for severe weather
  bool customTitleBar = false; // draw our own window controls
  bool minimizeToTray = false; // close button hides to tray instead of quitting
  ThemeMode themeMode = ThemeMode.system;
  String owmKey = ''; // OpenWeatherMap key for temp/wind map layers (optional)
  int providerIndex = 0; // index into providers[]
  String openMeteoModel = 'best_match'; // Open-Meteo 'models' param
  String pirateWeatherKey = ''; // api.pirateweather.net key (free tier)
  List<SavedPlace> savedPlaces = [];
  String lastPlace = 'Berlin';
  double? lastLat;
  double? lastLon;

  SharedPreferences? _prefs;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final p = _prefs!;
    tempUnit = TempUnit.values[p.getInt('tempUnit') ?? 0];
    windUnit = WindUnit.values[p.getInt('windUnit') ?? 0];
    inchPrecip = p.getBool('inchPrecip') ?? false;
    tintHero = p.getBool('tintHero') ?? true;
    notifications = p.getBool('notifications') ?? false;
    customTitleBar = p.getBool('customTitleBar') ?? false;
    minimizeToTray = p.getBool('minimizeToTray') ?? false;
    themeMode = ThemeMode.values[p.getInt('themeMode') ?? 0];
    owmKey = p.getString('owmKey') ?? '';
    providerIndex = p.getInt('providerIndex') ?? 0;
    openMeteoModel = p.getString('openMeteoModel') ?? 'best_match';
    pirateWeatherKey = p.getString('pirateWeatherKey') ?? '';
    savedPlaces = (p.getStringList('savedPlaces') ?? [])
        .map(SavedPlace.decode)
        .whereType<SavedPlace>()
        .toList();
    lastPlace = p.getString('lastPlace') ?? 'Berlin';
    lastLat = p.getDouble('lastLat');
    lastLon = p.getDouble('lastLon');
    notifyListeners();
  }

  void _save() {
    final p = _prefs;
    if (p == null) return;
    p.setInt('tempUnit', tempUnit.index);
    p.setInt('windUnit', windUnit.index);
    p.setBool('inchPrecip', inchPrecip);
    p.setBool('tintHero', tintHero);
    p.setBool('notifications', notifications);
    p.setBool('customTitleBar', customTitleBar);
    p.setBool('minimizeToTray', minimizeToTray);
    p.setInt('themeMode', themeMode.index);
    p.setString('owmKey', owmKey);
    p.setInt('providerIndex', providerIndex);
    p.setString('openMeteoModel', openMeteoModel);
    p.setString('pirateWeatherKey', pirateWeatherKey);
    p.setStringList('savedPlaces', savedPlaces.map((e) => e.encode()).toList());
    p.setString('lastPlace', lastPlace);
    if (lastLat != null) p.setDouble('lastLat', lastLat!);
    if (lastLon != null) p.setDouble('lastLon', lastLon!);
  }

  void update({
    TempUnit? temp,
    WindUnit? wind,
    bool? inch,
    bool? tint,
    bool? notify,
    bool? customBar,
    bool? minimizeTray,
    ThemeMode? mode,
    String? owm,
    int? provider,
    String? openMeteoModel,
    String? pirateWeatherKey,
    String? place,
    double? lat,
    double? lon,
  }) {
    if (temp != null) tempUnit = temp;
    if (wind != null) windUnit = wind;
    if (inch != null) inchPrecip = inch;
    if (tint != null) tintHero = tint;
    if (notify != null) notifications = notify;
    if (customBar != null) customTitleBar = customBar;
    if (minimizeTray != null) minimizeToTray = minimizeTray;
    if (mode != null) themeMode = mode;
    if (owm != null) owmKey = owm;
    if (provider != null) providerIndex = provider;
    if (openMeteoModel != null) this.openMeteoModel = openMeteoModel;
    if (pirateWeatherKey != null) this.pirateWeatherKey = pirateWeatherKey;
    if (place != null) lastPlace = place;
    if (lat != null) lastLat = lat;
    if (lon != null) lastLon = lon;
    _save();
    notifyListeners();
  }

  bool isSaved(String label) =>
      savedPlaces.any((p) => p.label.toLowerCase() == label.toLowerCase());

  void toggleSaved(double lat, double lon, String label) {
    if (label.trim().isEmpty) return;
    if (isSaved(label)) {
      removeSaved(label);
    } else {
      savedPlaces.add(SavedPlace(lat, lon, label));
      _save();
      notifyListeners();
    }
  }

  void removeSaved(String label) {
    savedPlaces
        .removeWhere((p) => p.label.toLowerCase() == label.toLowerCase());
    _save();
    notifyListeners();
  }

  String get tempUnitLabel => tempUnit == TempUnit.celsius ? '°C' : '°F';
  String get tempApi => tempUnit == TempUnit.celsius ? 'celsius' : 'fahrenheit';
  String get precipApi => inchPrecip ? 'inch' : 'mm';
  String get precipLabel => inchPrecip ? 'in' : 'mm';
}

final settings = AppSettings();
