import 'dart:io';

/// Fire a desktop notification via libnotify (GNOME). No-op if unavailable.
Future<void> notify(String title, String body) async {
  try {
    await Process.run('notify-send', ['-a', 'Strata', title, body]);
  } catch (_) {/* notify-send missing — ignore */}
}
