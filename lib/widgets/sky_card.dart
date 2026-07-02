import 'package:flutter/material.dart';

/// Flat Strata card: solid surface, large radius, hairline border + soft
/// shadow. Replaces the old glassmorphism look to match the mockups.
class SkyCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  const SkyCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius = 22,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final light = cs.brightness == Brightness.light;
    return Container(
      decoration: BoxDecoration(
        color: light ? Colors.white : const Color(0xFF131C22),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: light
              ? Colors.black.withValues(alpha: 0.05)
              : Colors.white.withValues(alpha: 0.06),
        ),
        boxShadow: light
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                )
              ]
            : null,
      ),
      // Material ancestor so child ink/splashes (ListTile, InkWell) render.
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}
