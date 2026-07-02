import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart';
import 'models.dart';
import 'notify.dart';
import 'settings.dart';
import 'theme.dart';
import 'weather_service.dart';
import 'widgets/window_bar.dart';
import 'weather_theme.dart';
import 'widgets/wx_icon.dart';
import 'widgets/share_card.dart';
import 'screens/home_screen.dart';
import 'screens/forecast_screen.dart';
import 'screens/map_screen.dart';
import 'screens/settings_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await settings.load();
  await windowManager.ensureInitialized();
  windowManager.waitUntilReadyToShow(
    WindowOptions(
      titleBarStyle:
          settings.customTitleBar ? TitleBarStyle.hidden : TitleBarStyle.normal,
      minimumSize:
          const Size(840, 580), // below this the side rail + grid overlap
    ),
    () async => windowManager.show(),
  );
  runApp(const WeatherApp());
}

/// Switch native decorations on/off live (called from Settings).
Future<void> applyTitleBar(bool custom) => windowManager
    .setTitleBarStyle(custom ? TitleBarStyle.hidden : TitleBarStyle.normal);

enum AppPage { home, forecast, maps, settings }

class WeatherApp extends StatefulWidget {
  const WeatherApp({super.key});
  @override
  State<WeatherApp> createState() => _WeatherAppState();
}

class _WeatherAppState extends State<WeatherApp>
    with WindowListener, TrayListener {
  Weather? _weather;
  Geo? _currentGeo; // coords of the active location, for robust refresh
  String? _error;
  bool _loading = false;
  AppPage _page = AppPage.home;

  // Live weather for each sidebar mini, keyed by place label.
  final Map<String, Weather> _savedWx = {};
  late List<int> _wxStamp; // invalidates mini cache on provider/unit change
  Timer? _autoRefresh;
  final _shareKey = GlobalKey();
  final _searchFocus = FocusNode();
  String? _lastAlertKey; // de-dupes severe-weather notifications

  @override
  void initState() {
    super.initState();
    _wxStamp = _stamp();
    settings.addListener(_onSettings);
    windowManager.addListener(this);
    trayManager.addListener(this);
    windowManager.setPreventClose(true);
    _initTray();
    if (settings.lastLat != null && settings.lastLon != null) {
      // Restore last location by coordinates (geocoding a full label fails).
      _pick(Geo(settings.lastLat!, settings.lastLon!, settings.lastPlace));
    } else {
      // First launch: auto-detect location, fall back to a default.
      _locate(fallback: settings.lastPlace);
    }
    _refreshSaved(); // populate minis even if the current load fails
    // Keep the current location fresh.
    _autoRefresh =
        Timer.periodic(const Duration(minutes: 30), (_) => _refresh());
  }

  @override
  void dispose() {
    _autoRefresh?.cancel();
    settings.removeListener(_onSettings);
    windowManager.removeListener(this);
    trayManager.removeListener(this);
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _initTray() async {
    await trayManager.setIcon('assets/tray/tray_icon.png');
    await _updateTray();
  }

  // tray_manager's Linux backend has no setToolTip — the title (label next
  // to the icon) and the context menu carry the live conditions instead.
  // The menu reproduces the hero banner as native GNOME menu rows: place,
  // temp + condition, H/L + feels-like, then the stat chips.
  Future<void> _updateTray() async {
    final w = _weather;
    await trayManager
        .setTitle(w != null ? '${w.temp.round()}${w.tempUnit}' : '');

    final hero = <MenuItem>[];
    if (w != null) {
      final rain = w.hourly.isNotEmpty ? w.hourly.first.precipProb : null;
      final chips = [
        '💧 ${w.humidity}%',
        '🌬 ${w.wind.round()} ${w.windUnit}',
        if (rain != null) '☔ $rain%',
        if (w.uvIndex != null) 'UV ${w.uvIndex!.round()}',
      ].join('  ·  ');
      hero.addAll([
        MenuItem(label: '📍 ${w.place}', disabled: true),
        MenuItem(
            label: '${_conditionGlyph(w.condition, w.isDay)}  '
                '${w.temp.round()}${w.tempUnit} · ${w.description}',
            disabled: true),
        if (w.daily.isNotEmpty)
          MenuItem(
              label: '↑ ${w.daily.first.max.round()}°  '
                  '↓ ${w.daily.first.min.round()}°  ·  '
                  'Feels ${w.feelsLike.round()}°',
              disabled: true),
        MenuItem(label: chips, disabled: true),
        MenuItem.separator(),
      ]);
    }
    await trayManager.setContextMenu(Menu(items: [
      ...hero,
      MenuItem(key: 'show', label: 'Show Strata'),
      MenuItem.separator(),
      MenuItem(key: 'quit', label: 'Quit'),
    ]));
  }

  String _conditionGlyph(Condition c, bool isDay) => switch (c) {
        Condition.clear => isDay ? '☀️' : '🌙',
        Condition.cloudy => isDay ? '⛅' : '☁️',
        Condition.fog => '🌫',
        Condition.rain => '🌧',
        Condition.snow => '🌨',
        Condition.thunder => '⛈',
      };

  @override
  void onTrayIconMouseDown() {
    // "Quick glance": land on the hero banner, not whatever page was left
    // open (Settings/Forecast/Maps), so the click shows current conditions.
    setState(() => _page = AppPage.home);
    windowManager.show();
    windowManager.focus();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == 'show') {
      setState(() => _page = AppPage.home);
      windowManager.show();
      windowManager.focus();
    } else if (menuItem.key == 'quit') {
      windowManager.destroy();
    }
  }

  @override
  void onWindowClose() async {
    if (settings.minimizeToTray) {
      await windowManager.hide();
    } else {
      await windowManager.destroy();
    }
  }

  // Detect location by IP; on failure optionally load a fallback place.
  Future<void> _locate({String? fallback}) async {
    await _run(() async {
      try {
        await _apply(await ipLocation());
      } catch (e) {
        if (fallback != null) {
          await _apply(await geocode(fallback));
        } else {
          rethrow;
        }
      }
    });
  }

  List<int> _stamp() => [
        settings.providerIndex,
        settings.tempUnit.index,
        settings.windUnit.index,
        settings.inchPrecip ? 1 : 0,
      ];

  void _onSettings() {
    final s = _stamp();
    if (!_listEq(s, _wxStamp)) {
      _wxStamp = s;
      // Don't clear — keep last values shown until fresh ones arrive.
      _refresh();
      _refreshSaved(force: true);
    }
  }

  bool _listEq(List<int> a, List<int> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  WeatherProvider get _provider =>
      providers[settings.providerIndex.clamp(0, providers.length - 1)];

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) return;
    await _run(() async => _apply(await geocode(q)));
  }

  Future<void> _pick(Geo geo) => _run(() => _apply(geo));

  Future<void> _apply(Geo geo) async {
    final w = await _provider.fetch(geo);
    settings.update(place: geo.label, lat: geo.lat, lon: geo.lon);
    if (!mounted) return;
    setState(() {
      _weather = w;
      _currentGeo = geo;
      _savedWx[geo.label] = w;
    });
    _maybeAlert(w);
    _refreshSaved();
    _updateTray();
  }

  void _maybeAlert(Weather w) {
    if (!settings.notifications || w.condition != Condition.thunder) return;
    final key = '${w.place}|${w.condition}';
    if (key == _lastAlertKey) return; // already alerted for this
    _lastAlertKey = key;
    notify('Severe weather · ${w.place}',
        '${w.description}. ${w.temp.round()}${w.tempUnit}.');
  }

  void _refresh() =>
      _currentGeo != null ? _pick(_currentGeo!) : _search(settings.lastPlace);

  Future<void> _exportImage(BuildContext context) async {
    final boundary =
        _shareKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;
    final image = await boundary.toImage(pixelRatio: 2.5);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) return;
    final dir = await getDownloadsDirectory() ?? await getTemporaryDirectory();
    final place = (_weather?.place ?? 'weather')
        .split(',')
        .first
        .replaceAll(RegExp(r'[^\w-]'), '_');
    final now = DateTime.now();
    final stamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}'
        '-${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    final file = File('${dir.path}/Strata-$place-$stamp.png');
    await file.writeAsBytes(bytes.buffer.asUint8List());
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Saved to ${file.path}'),
      action: SnackBarAction(
          label: 'Open', onPressed: () => Process.run('xdg-open', [file.path])),
    ));
  }

  // Switch using exact coordinates (from the mini) — never re-geocodes a label.
  void _selectSaved(Geo geo) {
    setState(() => _page = AppPage.home);
    _pick(geo);
  }

  // Populate sidebar minis by their stored coordinates (no geocoding).
  Future<void> _refreshSaved({bool force = false}) async {
    for (final sp in List<SavedPlace>.from(settings.savedPlaces)) {
      if (!force && _savedWx.containsKey(sp.label)) continue;
      try {
        final w = await _provider.fetch(Geo(sp.lat, sp.lon, sp.label));
        if (mounted) setState(() => _savedWx[sp.label] = w);
      } catch (_) {/* keep whatever's already shown */}
    }
  }

  Future<void> _run(Future<void> Function() task) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await task();
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) {
        return MaterialApp(
          title: 'Strata',
          debugShowCheckedModeBanner: false,
          theme: SkyTheme.light(),
          darkTheme: SkyTheme.dark(),
          themeMode: settings.themeMode,
          builder: (context, child) => Column(
            children: [
              if (settings.customTitleBar) const WindowBar(),
              Expanded(child: child ?? const SizedBox.shrink()),
            ],
          ),
          home: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.keyF, control: true):
                  () => _searchFocus.requestFocus(),
              const SingleActivator(LogicalKeyboardKey.keyR, control: true):
                  _refresh,
              const SingleActivator(LogicalKeyboardKey.digit1, control: true):
                  () => setState(() => _page = AppPage.home),
              const SingleActivator(LogicalKeyboardKey.digit2, control: true):
                  () => setState(() => _page = AppPage.forecast),
              const SingleActivator(LogicalKeyboardKey.digit3, control: true):
                  () => setState(() => _page = AppPage.maps),
              const SingleActivator(LogicalKeyboardKey.digit4, control: true):
                  () => setState(() => _page = AppPage.settings),
              const SingleActivator(LogicalKeyboardKey.escape): () {
                if (_page != AppPage.home) setState(() => _page = AppPage.home);
              },
            },
            child: Focus(
              autofocus: true,
              child: Stack(
                children: [
                  _Shell(
                    weather: _weather,
                    error: _error,
                    loading: _loading,
                    page: _page,
                    savedWx: _savedWx,
                    searchFocus: _searchFocus,
                    onPage: (p) => setState(() => _page = p),
                    onSearch: _search,
                    onPick: _pick,
                    onSelectSaved: _selectSaved,
                    onRefresh: _refresh,
                    onLocate: () => _locate(),
                    onExport: (ctx) => _exportImage(ctx),
                  ),
                  // Off-screen: painted every frame (so it's always ready to
                  // capture) but positioned outside the visible canvas, so
                  // the export is a dedicated compact summary rather than a
                  // screenshot of whatever page happens to be open.
                  if (_weather != null)
                    Positioned(
                      left: -ShareCard.width - 100,
                      top: 0,
                      // ShareCard sits outside _Shell's Scaffold/Material, so
                      // its Text widgets had no DefaultTextStyle to inherit —
                      // Flutter rendered them with its debug fallback style
                      // (yellow double-underline). A transparent Material
                      // ancestor fixes that without adding visible chrome.
                      child: Material(
                        type: MaterialType.transparency,
                        child: RepaintBoundary(
                          key: _shareKey,
                          child: ShareCard(_weather!),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Shell extends StatelessWidget {
  final Weather? weather;
  final String? error;
  final bool loading;
  final AppPage page;
  final Map<String, Weather> savedWx;
  final ValueChanged<AppPage> onPage;
  final ValueChanged<String> onSearch;
  final ValueChanged<Geo> onPick;
  final ValueChanged<Geo> onSelectSaved;
  final VoidCallback onRefresh;
  final VoidCallback onLocate;
  final FocusNode searchFocus;
  final ValueChanged<BuildContext> onExport;

  const _Shell({
    required this.weather,
    required this.error,
    required this.loading,
    required this.page,
    required this.savedWx,
    required this.searchFocus,
    required this.onPage,
    required this.onSearch,
    required this.onPick,
    required this.onSelectSaved,
    required this.onRefresh,
    required this.onLocate,
    required this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final w = weather;
    final currentGeo = w != null ? Geo(w.lat, w.lon, w.place) : null;

    Widget body;
    String viewKey;
    if (loading && w == null) {
      body = const Center(child: CircularProgressIndicator());
      viewKey = 'loading';
    } else if (error != null && w == null) {
      body = _ErrorView(error!, onRefresh);
      viewKey = 'error';
    } else if (w == null) {
      body = const SizedBox.shrink();
      viewKey = 'empty';
    } else {
      viewKey = page.name;
      body = switch (page) {
        AppPage.forecast => ForecastScreen(w),
        AppPage.maps => MapScreen(w),
        AppPage.settings => SettingsScreen(onChanged: onRefresh),
        AppPage.home => HomeScreen(
            w,
            onOpenMaps: () => onPage(AppPage.maps),
            onOpenForecast: () => onPage(AppPage.forecast),
          ),
      };
    }

    return Scaffold(
      body: Row(
        children: [
          _SideRail(
            currentGeo: currentGeo,
            currentWeather: w,
            savedWx: savedWx,
            onSelect: onSelectSaved,
            onAllSettings: () => onPage(AppPage.settings),
          ),
          VerticalDivider(
              width: 1, color: cs.onSurface.withValues(alpha: 0.08)),
          Expanded(
            child: Column(
              children: [
                _TopBar(
                  page: page,
                  place: w?.place ?? settings.lastPlace,
                  currentGeo: currentGeo,
                  loading: loading && w != null,
                  onBack: () => onPage(AppPage.home),
                  onSearch: onSearch,
                  onPick: onPick,
                  onRefresh: onRefresh,
                  onLocate: onLocate,
                  onExport: w == null ? null : () => onExport(context),
                  searchFocus: searchFocus,
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    // M3 emphasized fade-through for view changes.
                    duration: const Duration(milliseconds: 300),
                    switchInCurve: Curves.easeInOutCubicEmphasized,
                    switchOutCurve: Curves.easeInOutCubicEmphasized,
                    transitionBuilder: (child, a) => FadeTransition(
                      opacity: a,
                      child: ScaleTransition(
                        scale: Tween(begin: 0.97, end: 1.0).animate(a),
                        child: child,
                      ),
                    ),
                    child: KeyedSubtree(key: ValueKey(viewKey), child: body),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SideRail extends StatefulWidget {
  final Geo? currentGeo;
  final Weather? currentWeather;
  final Map<String, Weather> savedWx;
  final ValueChanged<Geo> onSelect;
  final VoidCallback onAllSettings;
  const _SideRail({
    required this.currentGeo,
    required this.currentWeather,
    required this.savedWx,
    required this.onSelect,
    required this.onAllSettings,
  });

  @override
  State<_SideRail> createState() => _SideRailState();
}

class _SideRailState extends State<_SideRail> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Current location first (if not already saved), then saved.
    final saved = settings.savedPlaces;
    final curLabel = widget.currentGeo?.label;
    final entries = <Geo>[
      if (widget.currentGeo != null &&
          !saved.any((p) => p.label.toLowerCase() == curLabel!.toLowerCase()))
        widget.currentGeo!,
      for (final sp in saved) Geo(sp.lat, sp.lon, sp.label),
    ];

    Widget list() => entries.isEmpty
        ? (_expanded
            ? Center(
                child: Text('Search & ⭐ to save',
                    style: TextStyle(
                        color: cs.onSurface.withValues(alpha: 0.5),
                        fontSize: 12)))
            : const SizedBox.shrink())
        : ListView.builder(
            padding: EdgeInsets.symmetric(horizontal: _expanded ? 12 : 10),
            itemCount: entries.length,
            itemBuilder: (_, i) {
              final geo = entries[i];
              final isCurrent = geo.label == curLabel;
              final wx =
                  isCurrent ? widget.currentWeather : widget.savedWx[geo.label];
              return _expanded
                  ? _LocationMini(
                      label: geo.label,
                      weather: wx,
                      selected: isCurrent,
                      onTap: () => widget.onSelect(geo),
                    )
                  : _LocationDot(
                      label: geo.label,
                      weather: wx,
                      selected: isCurrent,
                      onTap: () => widget.onSelect(geo),
                    );
            },
          );

    return SizedBox(
      // ponytail: instant toggle — animating the width while the two layouts
      // differ caused transient RenderFlex overflow. Snap instead.
      width: _expanded ? 224 : 76,
      child: ClipRect(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Collapse / expand toggle
            Padding(
              padding: const EdgeInsets.only(top: 10, left: 6, right: 6),
              child: Align(
                alignment: _expanded ? Alignment.centerRight : Alignment.center,
                child: IconButton(
                  tooltip: _expanded ? 'Collapse' : 'Expand',
                  onPressed: () => setState(() => _expanded = !_expanded),
                  icon: Icon(
                      _expanded ? Icons.chevron_left : Icons.chevron_right),
                ),
              ),
            ),
            if (_expanded)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Text('LOCATIONS',
                    style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface.withValues(alpha: 0.45))),
              ),
            const SizedBox(height: 8),
            Expanded(child: list()),
            Divider(color: cs.onSurface.withValues(alpha: 0.08), height: 1),
            _expanded
                ? _UserChip(onAllSettings: widget.onAllSettings)
                : IconButton(
                    tooltip: 'Settings',
                    padding: const EdgeInsets.all(16),
                    onPressed: () => showDialog(
                      context: context,
                      barrierColor: Colors.black26,
                      builder: (_) => _QuickSettingsDialog(
                          onAllSettings: widget.onAllSettings),
                    ),
                    icon: const Icon(Icons.settings),
                  ),
          ],
        ),
      ),
    );
  }
}

/// Compact location chip shown when the rail is collapsed.
class _LocationDot extends StatelessWidget {
  final String label;
  final Weather? weather;
  final bool selected;
  final VoidCallback onTap;
  const _LocationDot({
    required this.label,
    required this.weather,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final w = weather;
    final g = w != null
        ? WeatherVisuals.of(w.condition, w.isDay).gradient
        : [cs.surfaceContainerHighest, cs.surfaceContainerHighest];
    return Tooltip(
      message:
          w != null ? '${label.split(',').first}  ${w.temp.round()}°' : label,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: AspectRatio(
          aspectRatio: 1,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                  colors: g,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
              border: Border.all(
                color: selected ? cs.primary : Colors.transparent,
                width: 2,
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: onTap,
                child: Center(
                  child: w != null
                      ? Text('${w.temp.round()}°',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 16))
                      : const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LocationMini extends StatelessWidget {
  final String label;
  final Weather? weather;
  final bool selected;
  final VoidCallback onTap;
  const _LocationMini({
    required this.label,
    required this.weather,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final w = weather;
    final g = w != null
        ? WeatherVisuals.of(w.condition, w.isDay).gradient
        : [cs.surfaceContainerHighest, cs.surfaceContainerHighest];
    final fg = w != null ? Colors.white : cs.onSurface;
    final short = label.split(',').first;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
              colors: g, begin: Alignment.topLeft, end: Alignment.bottomRight),
          border: Border.all(
            color: selected ? cs.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(short,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontWeight: FontWeight.w700, color: fg)),
                        const SizedBox(height: 2),
                        Text(w != null ? w.description : 'Loading…',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11,
                                color: fg.withValues(alpha: 0.85))),
                      ],
                    ),
                  ),
                  if (w != null) ...[
                    WxTile(w.condition, size: 30, isDay: w.isDay),
                    const SizedBox(width: 6),
                    Text('${w.temp.round()}°',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: fg)),
                  ] else
                    const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UserChip extends StatelessWidget {
  final VoidCallback onAllSettings;
  const _UserChip({required this.onAllSettings});

  void _openMenu(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.black26,
      builder: (_) => _QuickSettingsDialog(onAllSettings: onAllSettings),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => _openMenu(context),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: cs.primaryContainer,
              child:
                  Icon(Icons.settings, color: cs.onPrimaryContainer, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Settings',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  Text('Theme, units & more',
                      style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurface.withValues(alpha: 0.55))),
                ],
              ),
            ),
            Icon(Icons.expand_less, color: cs.onSurface.withValues(alpha: 0.5)),
          ],
        ),
      ),
    );
  }
}

class _QuickSettingsDialog extends StatelessWidget {
  final VoidCallback onAllSettings;
  const _QuickSettingsDialog({required this.onAllSettings});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: AnimatedBuilder(
        animation: settings,
        builder: (context, _) => ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Quick settings',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 16),
                const Text('Theme',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                SegmentedButton<ThemeMode>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                        value: ThemeMode.system, label: Text('System')),
                    ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                    ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                  ],
                  selected: {settings.themeMode},
                  onSelectionChanged: (s) => settings.update(mode: s.first),
                ),
                const SizedBox(height: 16),
                const Text('Temperature',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                SegmentedButton<TempUnit>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: TempUnit.celsius, label: Text('°C')),
                    ButtonSegment(
                        value: TempUnit.fahrenheit, label: Text('°F')),
                  ],
                  selected: {settings.tempUnit},
                  onSelectionChanged: (s) => settings.update(temp: s.first),
                ),
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonalIcon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      onAllSettings();
                    },
                    icon: const Icon(Icons.settings, size: 18),
                    label: const Text('All settings'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final AppPage page;
  final String place;
  final Geo? currentGeo;
  final bool loading;
  final VoidCallback onBack;
  final ValueChanged<String> onSearch;
  final ValueChanged<Geo> onPick;
  final VoidCallback onRefresh;
  final VoidCallback onLocate;
  final VoidCallback? onExport;
  final FocusNode searchFocus;
  const _TopBar({
    required this.page,
    required this.place,
    required this.currentGeo,
    required this.loading,
    required this.onBack,
    required this.onSearch,
    required this.onPick,
    required this.onRefresh,
    required this.onLocate,
    required this.onExport,
    required this.searchFocus,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      child: Row(
        children: [
          if (page != AppPage.home)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton.filledTonal(
                tooltip: 'Back to Home',
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back),
              ),
            ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: _SearchField(
                initial: place,
                onSubmit: onSearch,
                onPick: onPick,
                focusNode: searchFocus),
          ),
          const Spacer(),
          if (loading)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          IconButton.filledTonal(
            tooltip: settings.isSaved(place) ? 'Remove saved' : 'Save location',
            onPressed: currentGeo == null
                ? null
                : () => settings.toggleSaved(
                    currentGeo!.lat, currentGeo!.lon, currentGeo!.label),
            icon: Icon(settings.isSaved(place) ? Icons.star : Icons.star_border,
                color:
                    settings.isSaved(place) ? const Color(0xFFFFC107) : null),
          ),
          const SizedBox(width: 8),
          // ponytail: export button hidden — ShareCard rendering had a
          // Material/DefaultTextStyle gap (yellow debug-underline text in the
          // output PNG). Machinery (onExport, ShareCard, _exportImage) left
          // in place; re-add the button once that's fixed.
          IconButton(
            tooltip: 'Use my location',
            onPressed: onLocate,
            icon: const Icon(Icons.my_location),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatefulWidget {
  final String initial;
  final ValueChanged<String> onSubmit;
  final ValueChanged<Geo> onPick;
  final FocusNode? focusNode;
  const _SearchField(
      {required this.initial,
      required this.onSubmit,
      required this.onPick,
      this.focusNode});

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  // Autocomplete requires an externally-owned FocusNode to be paired with an
  // externally-owned TextEditingController — this is what lets Ctrl+F focus
  // the field from outside (e.g. the global keyboard shortcut).
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final onSubmit = widget.onSubmit;
    final onPick = widget.onPick;
    return Autocomplete<Geo>(
      textEditingController: _controller,
      focusNode: widget.focusNode,
      displayStringForOption: (g) => g.label,
      optionsBuilder: (v) async {
        final q = v.text.trim();
        if (q.length < 2) return const Iterable<Geo>.empty();
        return geocodeSuggest(q);
      },
      onSelected: onPick,
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        return SizedBox(
          height: 46,
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            textInputAction: TextInputAction.search,
            onSubmitted: (t) {
              onSubmit(t);
              focusNode.unfocus();
            },
            decoration: InputDecoration(
              hintText: 'Search cities…',
              prefixIcon: const Icon(Icons.search, size: 20),
              isDense: true,
              filled: true,
              fillColor: cs.onSurface.withValues(alpha: 0.05),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300, maxWidth: 420),
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 6),
                shrinkWrap: true,
                children: options
                    .map((g) => InkWell(
                          onTap: () => onSelected(g),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            child: Row(
                              children: [
                                const Icon(Icons.place_outlined, size: 18),
                                const SizedBox(width: 10),
                                Expanded(
                                    child: Text(g.label,
                                        overflow: TextOverflow.ellipsis)),
                              ],
                            ),
                          ),
                        ))
                    .toList(),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView(this.message, this.onRetry);
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off, size: 56),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton.tonal(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
