import 'package:flutter/material.dart';
import '../main.dart' show applyTitleBar;
import '../settings.dart';
import '../weather_service.dart';
import '../widgets/sky_card.dart';

class SettingsScreen extends StatelessWidget {
  final VoidCallback onChanged; // re-fetch when units change
  const SettingsScreen({super.key, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) {
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text('Settings', style: Theme.of(context).textTheme.displaySmall),
            const SizedBox(height: 20),
            SkyCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _Header('Weather provider'),
                  RadioGroup<int>(
                    groupValue: settings.providerIndex,
                    onChanged: (v) {
                      if (v == null) return;
                      settings.update(provider: v);
                      onChanged();
                    },
                    child: Column(
                      children: [
                        for (var i = 0; i < providers.length; i++)
                          RadioListTile<int>(
                            contentPadding: EdgeInsets.zero,
                            title: Text(providers[i].name),
                            value: i,
                          ),
                      ],
                    ),
                  ),
                  if (settings.providerIndex == 0) ...[
                    const Divider(height: 24),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Forecast model'),
                          DropdownButton<String>(
                            value: settings.openMeteoModel,
                            onChanged: (v) {
                              if (v == null) return;
                              settings.update(openMeteoModel: v);
                              onChanged();
                            },
                            items: [
                              for (final (value, label) in openMeteoModels)
                                DropdownMenuItem(
                                    value: value, child: Text(label)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Text(
                        'Picks the underlying national-weather-service model instead '
                        'of Open-Meteo\'s auto blend. A specific model can be more '
                        'accurate for its home region; some omit UV or visibility.',
                        style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.55))),
                  ],
                  if (settings.providerIndex == 2) ...[
                    const Divider(height: 24),
                    TextFormField(
                      initialValue: settings.pirateWeatherKey,
                      decoration: const InputDecoration(
                        labelText: 'Pirate Weather API key',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (v) {
                        settings.update(pirateWeatherKey: v.trim());
                        onChanged();
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                        'Free tier: 20,000 calls/month, no card required. Built on '
                        'NOAA models (HRRR/GFS) — most accurate for the US, weaker '
                        'elsewhere. Get a key at pirateweather.net.',
                        style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.55))),
                  ],
                  Text(
                      'MET Norway omits UV, visibility and rain probability — '
                      'those show as 0/—.',
                      style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.55))),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SkyCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _Header('Saved locations'),
                  if (settings.savedPlaces.isEmpty)
                    Text('Star a location from the top bar to save it.',
                        style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.55)))
                  else
                    for (final p in settings.savedPlaces)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.place_outlined),
                        title: Text(p.label),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => settings.removeSaved(p.label),
                        ),
                      ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SkyCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _Header('Units'),
                  _seg<TempUnit>(
                    label: 'Temperature',
                    value: settings.tempUnit,
                    options: const {
                      TempUnit.celsius: '°C',
                      TempUnit.fahrenheit: '°F'
                    },
                    onChange: (v) {
                      settings.update(temp: v);
                      onChanged();
                    },
                  ),
                  _seg<WindUnit>(
                    label: 'Wind',
                    value: settings.windUnit,
                    options: const {
                      WindUnit.kmh: 'km/h',
                      WindUnit.mph: 'mph',
                      WindUnit.ms: 'm/s',
                      WindUnit.kn: 'kn',
                    },
                    onChange: (v) {
                      settings.update(wind: v);
                      onChanged();
                    },
                  ),
                  _seg<bool>(
                    label: 'Precipitation',
                    value: settings.inchPrecip,
                    options: const {false: 'mm', true: 'inch'},
                    onChange: (v) {
                      settings.update(inch: v);
                      onChanged();
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SkyCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _Header('Appearance'),
                  _seg<ThemeMode>(
                    label: 'Theme',
                    value: settings.themeMode,
                    options: const {
                      ThemeMode.system: 'System',
                      ThemeMode.light: 'Light',
                      ThemeMode.dark: 'Dark',
                    },
                    onChange: (v) => settings.update(mode: v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Tint hero card from weather'),
                    subtitle:
                        const Text('Color the main card to match conditions'),
                    value: settings.tintHero,
                    onChanged: (v) => settings.update(tint: v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Severe weather notifications'),
                    subtitle: const Text(
                        'Desktop alert on thunderstorms (while open)'),
                    value: settings.notifications,
                    onChanged: (v) => settings.update(notify: v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Custom window controls'),
                    subtitle: const Text(
                        'Use in-app title bar instead of the system one'),
                    value: settings.customTitleBar,
                    onChanged: (v) {
                      settings.update(customBar: v);
                      applyTitleBar(v);
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Minimize to tray'),
                    subtitle: const Text(
                        'Closing the window hides it to the system tray instead of quitting'),
                    value: settings.minimizeToTray,
                    onChanged: (v) => settings.update(minimizeTray: v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SkyCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _Header('Map layers'),
                  const Text(
                      'Precipitation radar is free (RainViewer), as is the '
                      'higher-resolution US Radar layer (NOAA/NWS, US only). '
                      'Temperature and Wind layers use OpenWeatherMap — paste '
                      'a free API key:'),
                  const SizedBox(height: 12),
                  TextFormField(
                    initialValue: settings.owmKey,
                    decoration: const InputDecoration(
                      labelText: 'OpenWeatherMap API key',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) => settings.update(owm: v.trim()),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const SkyCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Header('About'),
                  Text('Data: Open-Meteo, MET Norway · Radar: RainViewer'),
                  Text('Icons: Meteocons by Bas Milius (MIT)'),
                  Text('Fonts: Plus Jakarta Sans, Inter'),
                  SizedBox(height: 4),
                  Text('Material 3 · Flutter · GNOME Wayland'),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _seg<T>({
    required String label,
    required T value,
    required Map<T, String> options,
    required ValueChanged<T> onChange,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          SegmentedButton<T>(
            showSelectedIcon: false,
            segments: options.entries
                .map((e) => ButtonSegment(value: e.key, label: Text(e.value)))
                .toList(),
            selected: {value},
            onSelectionChanged: (s) => onChange(s.first),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String text;
  const _Header(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: const TextStyle(
                fontFamily: 'PlusJakartaSans',
                fontSize: 17,
                fontWeight: FontWeight.w700)),
      );
}
