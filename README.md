


<p align="center">
  <img src="packaging/io.github.strata.Strata.png" width="96" alt="Strata icon">
</p>

<h1 align="center">Strata</h1>

<p align="center">A Material 3 desktop weather app for GNOME / Wayland, built with Flutter.</p>

## Features

<p align="center">
https://github.com/user-attachments/assets/57cff696-ccc7-408b-9da0-14ee2c85d7ae
</p>

- **Live conditions & 7-day / hourly forecast** — current temp, feels-like trend, hourly cards with a today/tomorrow scroller, expandable daily rows.
- **Weather-reactive UI** — the hero card's background and icon animate to match current conditions (clear, rain, snow, thunder, fog…), day or night.
- **Radar & satellite map** — animated precipitation radar and infrared satellite (RainViewer), with a timeline scrubber, plus optional temperature/wind overlays via an OpenWeatherMap key.
- **Air quality, UV, sun & moon** — AQI band, UV index with advice, sunrise/sunset, moon phase.
- **Multiple weather providers**, switchable in Settings:
  - **Open-Meteo** — free, no key; pick a specific national-weather-service model (ECMWF, GFS/HRRR, ICON, UK Met Office, Météo-France, GEM, KNMI) instead of the auto blend.
  - **MET Norway** — free, no key.
  - **Pirate Weather** — free tier (20k calls/month), NOAA-based; needs an API key from [pirateweather.net](https://pirateweather.net).
  - Stat cards clearly flag any value a provider/model doesn't supply (e.g. dew point, UV) instead of showing a fake zero.
- **Saved locations** with live mini-cards in the side rail, search with autocomplete, IP-based auto-locate.
- **System tray integration** — live temperature in the tray title, a native menu reproducing the current-conditions summary, optional "minimize to tray" instead of quitting.
- **Desktop niceties** — custom in-app title bar (optional), keyboard shortcuts (`Ctrl+F` search, `Ctrl+R` refresh, `Ctrl+1..4` switch pages, `Esc` back), desktop notifications for severe weather.
- °C/°F, km/h · mph · m/s · kn, mm/inch — independently configurable.

## Install

Prebuilt Linux bundles are published on [Releases](https://github.com/hackroot9623/strata/releases) — grab `strata-linux-x64.tar.gz` from the `latest` release (rebuilt on every push to `main`) or a tagged version.

```bash
tar -xzf strata-linux-x64.tar.gz
cd strata
./install.sh      # installs to ~/.local/share/strata, adds a desktop entry + icon
```

This installs for the current user only (no `sudo`). Launch it as **Strata** from your app grid, or run `strata` directly if `~/.local/bin` is on your `PATH`.

To remove it: `./uninstall.sh` (from the same extracted folder, or from `packaging/` in a repo checkout).

### Requirements

Runtime needs GTK 3 and an AppIndicator implementation for the tray icon (present by default on GNOME/most distros):

```bash
# Debian/Ubuntu
sudo apt install libgtk-3-0 libayatana-appindicator3-1
```

## Building from source

```bash
flutter pub get
flutter build linux --release
```

The bundle is written to `build/linux/x64/release/bundle/`; `packaging/install.sh` will pick it up automatically from a repo checkout.

Useful during development:

```bash
flutter run -d linux     # debug run
flutter analyze          # lints
dart format lib/         # formatting
```

## Weather data & attribution

- Forecasts: [Open-Meteo](https://open-meteo.com/), [MET Norway](https://api.met.no/), [Pirate Weather](https://pirateweather.net/)
- Radar/satellite: [RainViewer](https://www.rainviewer.com/)
- Geocoding & air quality: Open-Meteo
- Icons: [Meteocons](https://bas.dev/work/meteocons) by Bas Milius (MIT)
- Fonts: Plus Jakarta Sans, Inter

## CI

`.github/workflows/build.yml` runs `flutter analyze` + `flutter build linux --release` on every push/PR, and publishes the packaged tarball:

- pushes to `main` → updates the rolling **`latest`** release
- tags matching `v*` → a proper versioned release

## License

MIT
