import 'package:flutter/material.dart';

/// Color tokens from the DropClip UI design (T1.12, NFR-A01). Dark values are
/// the design's; light values are derived so every text color still passes
/// WCAG AA (4.5:1) on every surface. Read with `DropClipColors.of(context)`.
class DropClipColors extends ThemeExtension<DropClipColors> {
  final Brightness brightness;

  final Color canvas;
  final Color surface;
  final Color elevated;
  final Color hover;
  final Color border;

  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color textAccent;

  /// Fill for primary buttons and selection; pair with [onAccent].
  final Color accent;
  final Color onAccent;

  /// Network / latency indicators.
  final Color cyan;
  final Color success;
  final Color warning;
  final Color danger;

  const DropClipColors._({
    required this.brightness,
    required this.canvas,
    required this.surface,
    required this.elevated,
    required this.hover,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textAccent,
    required this.accent,
    required this.onAccent,
    required this.cyan,
    required this.success,
    required this.warning,
    required this.danger,
  });

  static const dark = DropClipColors._(
    brightness: Brightness.dark,
    canvas: Color(0xFF0B0B12),
    surface: Color(0xFF14141F),
    elevated: Color(0xFF1C1C2B),
    hover: Color(0xFF242437),
    border: Color(0xFF2A2A3D),
    textPrimary: Color(0xFFF4F4F8),
    textSecondary: Color(0xFFA1A1B8),
    textTertiary: Color(0xFF8B8BA3),
    textAccent: Color(0xFFA48BFF),
    // Design uses #7C5CFF, but white labels on it are only 4.35:1.
    accent: Color(0xFF6E4EF5),
    onAccent: Color(0xFFFFFFFF),
    cyan: Color(0xFF22D3EE),
    success: Color(0xFF34D399),
    warning: Color(0xFFFBBF24),
    danger: Color(0xFFF87171),
  );

  static const light = DropClipColors._(
    brightness: Brightness.light,
    canvas: Color(0xFFF6F6F9),
    surface: Color(0xFFFFFFFF),
    elevated: Color(0xFFF0F0F5),
    hover: Color(0xFFE7E7EF),
    border: Color(0xFFD5D5E0),
    textPrimary: Color(0xFF14141F),
    textSecondary: Color(0xFF4A4A5E),
    textTertiary: Color(0xFF5C5C70),
    textAccent: Color(0xFF5B3FD9),
    accent: Color(0xFF6A4BF0),
    onAccent: Color(0xFFFFFFFF),
    cyan: Color(0xFF0B6B85),
    success: Color(0xFF036C4E),
    warning: Color(0xFF8A5A06),
    danger: Color(0xFFB91C1C),
  );

  static DropClipColors forBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  static DropClipColors of(BuildContext context) =>
      Theme.of(context).extension<DropClipColors>() ??
      forBrightness(Theme.of(context).brightness);

  // Tokens are fixed per brightness, so there is nothing to override.
  @override
  DropClipColors copyWith() => this;

  @override
  DropClipColors lerp(DropClipColors? other, double t) =>
      other == null || t < 0.5 ? this : other;

  List<Color> get surfaces => [canvas, surface, elevated, hover];

  /// Colors used as text or icons on [surfaces].
  List<Color> get foregrounds => [
        textPrimary,
        textSecondary,
        textTertiary,
        textAccent,
        cyan,
        success,
        warning,
        danger,
      ];
}

/// Corner radii from the design.
abstract final class DropClipRadius {
  static const double tag = 6;
  static const double button = 10;
  static const double card = 14;
  static const double window = 16;
  static const double phone = 44;
}

/// Spacing scale from the design.
abstract final class DropClipSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Font families from the design. Fonts must ship as bundled assets
/// (Zero-Cloud: no runtime download, e.g. no `google_fonts`).
abstract final class DropClipFonts {
  static const String ui = 'Plus Jakarta Sans';
  static const String thai = 'IBM Plex Sans Thai';

  /// IPs, PINs, SAS codes and sizes.
  static const String mono = 'JetBrains Mono';

  static const List<String> uiFallback = [thai, 'Segoe UI', 'sans-serif'];
}
