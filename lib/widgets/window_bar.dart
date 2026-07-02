import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// Custom title bar with our own minimize / maximize / close controls, shown
/// when the native GTK decorations are hidden.
class WindowBar extends StatelessWidget {
  const WindowBar({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // MaterialApp's `builder` places this above _Shell's own Scaffold, so it
    // has no Material/DefaultTextStyle ancestor — without this, Text renders
    // with Flutter's debug fallback style (yellow double-underline).
    return Material(
      type: MaterialType.transparency,
      child: Container(
        height: 48,
        color: cs.surface,
        child: Row(
          children: [
            Expanded(
              child: DragToMoveArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Image.asset('assets/icons/strata-icon.png',
                          width: 18, height: 18),
                      const SizedBox(width: 8),
                      Text('Strata',
                          style: TextStyle(
                              fontFamily: 'PlusJakartaSans',
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              height: 1.0,
                              color: cs.onSurface.withValues(alpha: 0.8))),
                    ],
                  ),
                ),
              ),
            ),
            _WinBtn(
              icon: Icons.remove,
              onTap: () => windowManager.minimize(),
            ),
            _WinBtn(
              icon: Icons.crop_square,
              iconSize: 16,
              onTap: () async => await windowManager.isMaximized()
                  ? windowManager.unmaximize()
                  : windowManager.maximize(),
            ),
            _WinBtn(
              icon: Icons.close,
              hoverColor: const Color(0xFFE53935),
              onTap: () => windowManager.close(),
            ),
          ],
        ),
      ),
    );
  }
}

class _WinBtn extends StatefulWidget {
  final IconData icon;
  final double iconSize;
  final VoidCallback onTap;
  final Color? hoverColor;
  const _WinBtn({
    required this.icon,
    required this.onTap,
    this.iconSize = 18,
    this.hoverColor,
  });
  @override
  State<_WinBtn> createState() => _WinBtnState();
}

class _WinBtnState extends State<_WinBtn> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hoverBg = widget.hoverColor ?? cs.onSurface.withValues(alpha: 0.12);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 46,
          height: 48,
          color: _hover ? hoverBg : Colors.transparent,
          child: Icon(widget.icon,
              size: widget.iconSize,
              color: _hover && widget.hoverColor != null
                  ? Colors.white
                  : cs.onSurface.withValues(alpha: 0.8)),
        ),
      ),
    );
  }
}
