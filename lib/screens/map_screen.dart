import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../models.dart';
import '../settings.dart';
import '../widgets/sky_card.dart';

enum BaseMap { map, satellite }

enum WxLayer { radar, clouds, temperature, wind, usRadar }

/// NOAA/NWS nowCOAST MRMS base reflectivity — a dynamic ArcGIS ImageServer,
/// not a cached XYZ tile pyramid, so each tile is fetched via an
/// `exportImage` call for that tile's Web Mercator bbox. Free, no key,
/// ~2 min updates, but only covers the US + territories. The same
/// time-enabled endpoint serves both the "current" layer (omit the `t` option)
/// and animated frames (pass a specific instant).
///
/// Must be a single long-lived instance (each one owns an `http.Client`, and
/// `flutter_map` only disposes a `TileProvider` when its `TileLayer` is torn
/// down for good — a *replaced* provider is never disposed). Read the
/// selected time from `options.additionalOptions` instead of a constructor
/// field, so a stable `TileLayer(tileProvider: sameInstance, additionalOptions:
/// {'t': ...})` can drive the animation via flutter_map's own tile-reload
/// hook (it reloads on `additionalOptions` changes) without ever recreating
/// the provider or its client.
class MrmsTileProvider extends NetworkTileProvider {
  // This free ArcGIS export endpoint isn't built for tile-pyramid traffic and
  // rate-limits bursts of concurrent requests (a whole viewport's worth of
  // tiles refetch on every animation frame) — a transient 403 shouldn't crash
  // the map or spam the console, just render that tile blank until the next
  // frame/pan.
  MrmsTileProvider() : super(silenceExceptions: true);

  static const _origin = 20037508.342789244;

  @override
  String getTileUrl(TileCoordinates coordinates, TileLayer options) {
    final n = 1 << coordinates.z;
    final res = (2 * _origin) / (256 * n);
    final xmin = -_origin + coordinates.x * 256 * res;
    final ymax = _origin - coordinates.y * 256 * res;
    final xmax = xmin + 256 * res;
    final ymin = ymax - 256 * res;
    final timeMillis = options.additionalOptions['t'];
    final time =
        (timeMillis == null || timeMillis.isEmpty) ? '' : '&time=$timeMillis';
    return 'https://mapservices.weather.noaa.gov/eventdriven/rest/services/'
        'radar/radar_base_reflectivity_time/ImageServer/exportImage'
        '?bbox=$xmin,$ymin,$xmax,$ymax&bboxSR=3857&imageSR=3857'
        '&size=256,256&format=png32&transparent=true&f=image$time';
  }
}

class _Frame {
  final int time; // unix seconds
  final String url; // ready tile template
  _Frame(this.time, this.url);
}

class MapScreen extends StatefulWidget {
  final Weather w;
  const MapScreen(this.w, {super.key});
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _map = MapController();
  // One long-lived provider (and its one http.Client) for the screen's whole
  // life — see MrmsTileProvider's doc comment for why this must not be
  // recreated per frame/build.
  final _mrmsTileProvider = MrmsTileProvider();
  List<_Frame> _radar = [];
  List<_Frame> _sat = [];
  List<_Frame> _mrms =
      []; // NOAA MRMS animation frames (url unused; see build())
  BaseMap _base = BaseMap.map;
  WxLayer _layer = WxLayer.radar;

  int _frame = 0;
  bool _playing = true;
  Timer? _timer;
  int _tick = 0;

  @override
  void initState() {
    super.initState();
    _loadRainViewer();
    _loadMrmsFrames();
    _timer = Timer.periodic(const Duration(milliseconds: 600), (_) {
      if (!_playing) return;
      final frames = _frames();
      if (frames == null || frames.isEmpty) return;
      // NOAA's export endpoint rate-limits bursts of concurrent tile
      // requests, so this layer advances a whole viewport's worth of tiles
      // every 3rd tick (~1.8s) instead of every tick (~0.6s) like the
      // lightweight CDN-backed RainViewer/satellite layers.
      if (_layer == WxLayer.usRadar && (_tick++) % 3 != 0) return;
      setState(() => _frame = (_frame + 1) % frames.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // RainViewer: radar (past + nowcast) and infrared satellite frames in one JSON.
  Future<void> _loadRainViewer() async {
    try {
      final res = await http.get(
          Uri.parse('https://api.rainviewer.com/public/weather-maps.json'));
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final host = j['host'] as String;

      List<_Frame> build(List? list, String suffix) => (list ?? [])
          .map((e) => _Frame((e['time'] as num).toInt(),
              '$host${e['path']}/256/{z}/{x}/{y}/$suffix.png'))
          .toList();

      final radar = [
        ...build(j['radar']?['past'] as List?, '4/1_1'),
        ...build(j['radar']?['nowcast'] as List?, '4/1_1'),
      ];
      final sat = build(j['satellite']?['infrared'] as List?, '0/0_0');
      setState(() {
        _radar = radar;
        _sat = sat;
        _frame = _latestIndex(_frames());
      });
    } catch (_) {/* layers just won't show */}
  }

  // NOAA MRMS: the ImageServer exposes a timeExtent, not a frame list — build
  // one ourselves at a fixed step. `.url` is left blank; MrmsTileProvider is
  // constructed directly with the selected frame's time in build() instead.
  Future<void> _loadMrmsFrames() async {
    try {
      final res = await http.get(Uri.parse(
          'https://mapservices.weather.noaa.gov/eventdriven/rest/services/'
          'radar/radar_base_reflectivity_time/ImageServer?f=json'));
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final extent = (j['timeInfo'] as Map?)?['timeExtent'] as List?;
      if (extent == null || extent.length < 2) return;
      final start = (extent[0] as num).toInt();
      final end = (extent[1] as num).toInt();
      const stepMs = 5 * 60 * 1000; // 5 min per frame
      const maxFrames = 24;
      final frames = <_Frame>[];
      for (var t = start; t <= end && frames.length < maxFrames; t += stepMs) {
        frames.add(_Frame(t ~/ 1000, ''));
      }
      if (frames.isEmpty || frames.last.time * 1000 < end) {
        frames.add(_Frame(end ~/ 1000, '')); // always end on the latest scan
      }
      setState(() {
        _mrms = frames;
        if (_layer == WxLayer.usRadar) _frame = _latestIndex(_mrms);
      });
    } catch (_) {/* layer just won't animate */}
  }

  List<_Frame>? _frames() => switch (_layer) {
        WxLayer.radar => _radar,
        WxLayer.clouds => _sat,
        WxLayer.usRadar => _mrms,
        _ => null, // OWM layers are static, no playback
      };

  // Newest "observed" frame: last past radar (before nowcast) or last sat.
  int _latestIndex(List<_Frame>? frames) {
    if (frames == null || frames.isEmpty) return 0;
    return frames.length - 1;
  }

  String _baseUrl() => _base == BaseMap.satellite
      ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
      : 'https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png';

  String? _overlayUrl() {
    if (_layer == WxLayer.usRadar) return null; // rendered via MrmsTileProvider
    final frames = _frames();
    if (frames != null) {
      if (frames.isEmpty) return null;
      return frames[_frame.clamp(0, frames.length - 1)].url;
    }
    // temperature / wind via OpenWeatherMap (needs key)
    final key = settings.owmKey;
    if (key.isEmpty) return null;
    final name = _layer == WxLayer.temperature ? 'temp_new' : 'wind_new';
    return 'https://tile.openweathermap.org/map/$name/{z}/{x}/{y}.png?appid=$key';
  }

  void _select(WxLayer l) {
    if ((l == WxLayer.temperature || l == WxLayer.wind) &&
        settings.owmKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content:
            Text('Add an OpenWeatherMap API key in Settings for this layer'),
      ));
      return;
    }
    setState(() {
      _layer = l;
      _frame = _latestIndex(switch (l) {
        WxLayer.radar => _radar,
        WxLayer.clouds => _sat,
        WxLayer.usRadar => _mrms,
        _ => null,
      });
    });
  }

  String _stamp(int unix) {
    final d = DateTime.fromMillisecondsSinceEpoch(unix * 1000).toLocal();
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.w;
    final center = LatLng(w.lat, w.lon);
    final overlay = _overlayUrl();
    final frames = _frames();
    final animatable = frames != null && frames.isNotEmpty;

    return Stack(
      children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
              initialCenter: center, initialZoom: 7, minZoom: 2, maxZoom: 16),
          children: [
            TileLayer(
              key: ValueKey(_base),
              urlTemplate: _baseUrl(),
              subdomains:
                  _base == BaseMap.map ? const ['a', 'b', 'c'] : const [],
              userAgentPackageName: 'com.example.gnome_weather',
            ),
            if (_layer == WxLayer.usRadar)
              Opacity(
                opacity: 0.75,
                child: TileLayer(
                  // Stable key + stable tileProvider instance (see its doc
                  // comment) — changing `additionalOptions` is what tells
                  // flutter_map to reload tiles for the new frame.
                  key: const ValueKey('usRadar'),
                  tileProvider: _mrmsTileProvider,
                  additionalOptions: {
                    't': (frames != null && frames.isNotEmpty)
                        ? (frames[_frame.clamp(0, frames.length - 1)].time *
                                1000)
                            .toString()
                        : '',
                  },
                  userAgentPackageName: 'com.example.gnome_weather',
                ),
              )
            else if (overlay != null)
              Opacity(
                opacity: _layer == WxLayer.clouds ? 0.85 : 0.7,
                child: TileLayer(
                  key: ValueKey(overlay),
                  urlTemplate: overlay,
                  userAgentPackageName: 'com.example.gnome_weather',
                ),
              ),
            MarkerLayer(markers: [
              Marker(
                point: center,
                width: 40,
                height: 40,
                child:
                    const Icon(Icons.location_on, color: Colors.red, size: 40),
              ),
            ]),
            RichAttributionWidget(
              // Our own TextSourceAttribution already credits every layer;
              // flutter_map's own logo attribution just adds a bundled asset
              // that doesn't resolve in this build.
              showFlutterMapAttribution: false,
              attributions: [
                TextSourceAttribution([
                  _base == BaseMap.satellite
                      ? 'Esri World Imagery'
                      : 'OpenTopoMap',
                  _layer == WxLayer.usRadar ? 'NOAA/NWS' : 'RainViewer',
                ].join(' · ')),
              ],
            ),
          ],
        ),

        // Base map toggle (top-left)
        Positioned(
          top: 16,
          left: 16,
          child: _Segment(
            options: const {BaseMap.map: 'Map', BaseMap.satellite: 'Satellite'},
            value: _base,
            onChanged: (v) => setState(() => _base = v),
          ),
        ),

        // Legend (top-right)
        Positioned(top: 16, right: 16, child: _Legend(_layer)),

        // Weather layer toggles (bottom-left)
        Positioned(
          left: 16,
          bottom: animatable ? 92 : 16,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _LayerBtn('Radar', Icons.radar, _layer == WxLayer.radar,
                  () => _select(WxLayer.radar)),
              const SizedBox(height: 10),
              _LayerBtn('US Radar (NOAA)', Icons.blur_on,
                  _layer == WxLayer.usRadar, () => _select(WxLayer.usRadar)),
              const SizedBox(height: 10),
              _LayerBtn('Satellite (clouds)', Icons.satellite_alt,
                  _layer == WxLayer.clouds, () => _select(WxLayer.clouds)),
              const SizedBox(height: 10),
              _LayerBtn(
                  'Temperature',
                  Icons.thermostat,
                  _layer == WxLayer.temperature,
                  () => _select(WxLayer.temperature)),
              const SizedBox(height: 10),
              _LayerBtn('Wind Speed', Icons.air, _layer == WxLayer.wind,
                  () => _select(WxLayer.wind)),
            ],
          ),
        ),

        // Zoom + locate (bottom-right)
        Positioned(
          right: 16,
          bottom: animatable ? 92 : 16,
          child: Column(
            children: [
              _RoundBtn(Icons.add, () => _zoom(1)),
              const SizedBox(height: 8),
              _RoundBtn(Icons.remove, () => _zoom(-1)),
              const SizedBox(height: 8),
              _RoundBtn(Icons.my_location, () => _map.move(center, 7)),
            ],
          ),
        ),

        // Timeline player (bottom, when animatable)
        if (animatable)
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: _Timeline(
              playing: _playing,
              frame: _frame.clamp(0, frames.length - 1),
              count: frames.length,
              label: _stamp(frames[_frame.clamp(0, frames.length - 1)].time),
              onPlayPause: () => setState(() => _playing = !_playing),
              onSeek: (v) => setState(() {
                _playing = false;
                _frame = v;
              }),
            ),
          ),
      ],
    );
  }

  void _zoom(double delta) {
    final c = _map.camera;
    _map.move(c.center, (c.zoom + delta).clamp(2, 16));
  }
}

class _Timeline extends StatelessWidget {
  final bool playing;
  final int frame;
  final int count;
  final String label;
  final VoidCallback onPlayPause;
  final ValueChanged<int> onSeek;
  const _Timeline({
    required this.playing,
    required this.frame,
    required this.count,
    required this.label,
    required this.onPlayPause,
    required this.onSeek,
  });

  @override
  Widget build(BuildContext context) {
    return SkyCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          IconButton(
            onPressed: onPlayPause,
            icon: Icon(playing ? Icons.pause : Icons.play_arrow),
          ),
          Expanded(
            child: Slider(
              value: frame.toDouble(),
              min: 0,
              max: (count - 1).toDouble().clamp(1, double.infinity),
              divisions: count > 1 ? count - 1 : 1,
              onChanged: (v) => onSeek(v.round()),
            ),
          ),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class _Segment<T> extends StatelessWidget {
  final Map<T, String> options;
  final T value;
  final ValueChanged<T> onChanged;
  const _Segment(
      {required this.options, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(14),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: options.entries.map((e) {
            final sel = e.key == value;
            return GestureDetector(
              onTap: () => onChanged(e.key),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: sel ? cs.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(e.value,
                    style: TextStyle(
                        color: sel ? cs.onPrimary : cs.onSurface,
                        fontWeight: FontWeight.w600)),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final WxLayer layer;
  const _Legend(this.layer);
  @override
  Widget build(BuildContext context) {
    final (title, colors, labels) = switch (layer) {
      WxLayer.radar => (
          'Radar (rain)',
          [
            const Color(0xFF90CAF9),
            const Color(0xFF1565C0),
            const Color(0xFF4A148C)
          ],
          ['light', 'heavy']
        ),
      WxLayer.clouds => (
          'Satellite (clouds)',
          [
            const Color(0xFF263238),
            const Color(0xFF90A4AE),
            const Color(0xFFFFFFFF)
          ],
          ['clear', 'thick']
        ),
      WxLayer.temperature => (
          'Temperature',
          [
            const Color(0xFF42A5F5),
            const Color(0xFFFFEB3B),
            const Color(0xFFE53935)
          ],
          ['-10°', '30°']
        ),
      WxLayer.wind => (
          'Wind Speed',
          [
            const Color(0xFFE0F7FA),
            const Color(0xFF26C6DA),
            const Color(0xFF00695C)
          ],
          ['calm', 'strong']
        ),
      WxLayer.usRadar => (
          'US Radar (NOAA, dBZ)',
          [
            const Color(0xFF4CAF50),
            const Color(0xFFFFEB3B),
            const Color(0xFFD32F2F)
          ],
          ['light', 'severe']
        ),
    };
    return SkyCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 8),
          Container(
            width: 140,
            height: 8,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              gradient: LinearGradient(colors: colors),
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            // Match the gradient bar's width exactly so spaceBetween has a
            // fixed span to work with — without this, the row shrinks to fit
            // its text (however wide the ambient title/card happens to be)
            // and the two labels end up jammed together.
            width: 140,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: labels
                  .map((l) => Text(l,
                      style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.6))))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _LayerBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _LayerBtn(this.label, this.icon, this.selected, this.onTap);
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: selected ? cs.primary : cs.surface.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(16),
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 18, color: selected ? cs.onPrimary : cs.onSurface),
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(
                      color: selected ? cs.onPrimary : cs.onSurface,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _RoundBtn(this.icon, this.onTap);
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface.withValues(alpha: 0.92),
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, size: 22, color: cs.onSurface),
        ),
      ),
    );
  }
}
