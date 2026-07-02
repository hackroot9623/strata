import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Small non-interactive map preview; tap opens the full Maps page.
class MapMini extends StatelessWidget {
  final double lat;
  final double lon;
  final VoidCallback onTap;
  const MapMini(
      {super.key, required this.lat, required this.lon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final center = LatLng(lat, lon);
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Stack(
        fit: StackFit.expand,
        children: [
          IgnorePointer(
            child: FlutterMap(
              options: MapOptions(
                initialCenter: center,
                initialZoom: 8,
                interactionOptions:
                    const InteractionOptions(flags: InteractiveFlag.none),
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png',
                  subdomains: const ['a', 'b', 'c'],
                  userAgentPackageName: 'com.example.gnome_weather',
                ),
                MarkerLayer(markers: [
                  Marker(
                    point: center,
                    width: 36,
                    height: 36,
                    child: const Icon(Icons.location_on,
                        color: Colors.red, size: 36),
                  ),
                ]),
              ],
            ),
          ),
          // Label chip
          Positioned(
            left: 12,
            top: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: cs.surface.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.layers, size: 16, color: cs.onSurface),
                  const SizedBox(width: 6),
                  Text('Radar & Satellite',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface)),
                ],
              ),
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(onTap: onTap),
          ),
        ],
      ),
    );
  }
}
