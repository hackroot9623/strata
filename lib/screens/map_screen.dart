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

enum WxLayer { radar, clouds, temperature, wind }

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
  List<_Frame> _radar = [];
  List<_Frame> _sat = [];
  BaseMap _base = BaseMap.map;
  WxLayer _layer = WxLayer.radar;

  int _frame = 0;
  bool _playing = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _loadRainViewer();
    _timer = Timer.periodic(const Duration(milliseconds: 600), (_) {
      if (!_playing) return;
      final frames = _frames();
      if (frames == null || frames.isEmpty) return;
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

  List<_Frame>? _frames() => switch (_layer) {
        WxLayer.radar => _radar,
        WxLayer.clouds => _sat,
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
            if (overlay != null)
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
            RichAttributionWidget(attributions: [
              TextSourceAttribution(_base == BaseMap.satellite
                  ? 'Esri World Imagery · RainViewer'
                  : 'OpenTopoMap · RainViewer'),
            ]),
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
          Row(
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
