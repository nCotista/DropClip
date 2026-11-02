import 'package:flutter/material.dart';

import 'tokens.dart';

/// WCAG 2.x contrast ratio between two opaque colors (1–21).
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// Builds the app theme for [brightness]; desktop follows the OS setting
/// (T1.12: Dark/Light mode per OS).
ThemeData buildDropClipTheme(Brightness brightness) {
  final c = DropClipColors.forBrightness(brightness);
  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.accent,
    onPrimary: c.onAccent,
    secondary: c.cyan,
    onSecondary: c.canvas,
    error: c.danger,
    onError: c.canvas,
    surface: c.surface,
    onSurface: c.textPrimary,
    onSurfaceVariant: c.textSecondary,
    surfaceContainerLowest: c.canvas,
    surfaceContainer: c.elevated,
    surfaceContainerHighest: c.hover,
    outline: c.border,
    outlineVariant: c.border,
  );
  final base = ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    fontFamily: DropClipFonts.ui,
    fontFamilyFallback: DropClipFonts.uiFallback,
  );

  RoundedRectangleBorder rounded(double r) =>
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(r));

  return base.copyWith(
    scaffoldBackgroundColor: c.canvas,
    dividerColor: c.border,
    hoverColor: c.hover,
    extensions: [c],
    textTheme: base.textTheme.apply(
      bodyColor: c.textPrimary,
      displayColor: c.textPrimary,
    ),
    cardTheme: CardThemeData(
      color: c.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: rounded(DropClipRadius.card).copyWith(
        side: BorderSide(color: c.border),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.accent,
        foregroundColor: c.onAccent,
        shape: rounded(DropClipRadius.button),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.textPrimary,
        side: BorderSide(color: c.border),
        shape: rounded(DropClipRadius.button),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.elevated,
      hintStyle: TextStyle(color: c.textTertiary),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(DropClipRadius.button),
        borderSide: BorderSide(color: c.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(DropClipRadius.button),
        borderSide: BorderSide(color: c.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(DropClipRadius.button),
        borderSide: BorderSide(color: c.accent, width: 2),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? c.onAccent : c.textTertiary,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? c.accent : c.hover,
      ),
    ),
    // Filter chips: violet when selected, as in the design (Material 3
    // would use the secondary color, which is cyan here).
    chipTheme: ChipThemeData(
      color: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? c.accent : c.surface,
      ),
      // RawChip resolves the label *color* per state, not the whole style.
      labelStyle: TextStyle(
        color: WidgetStateColor.resolveWith(
          (s) =>
              s.contains(WidgetState.selected) ? c.onAccent : c.textSecondary,
        ),
      ),
      checkmarkColor: c.onAccent,
      side: BorderSide(color: c.border),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DropClipRadius.button)),
    ),
  );
}

/// Monospace style for IPs, PINs, SAS codes and sizes.
TextStyle dropClipMono(BuildContext context, {double? fontSize}) => TextStyle(
      fontFamily: DropClipFonts.mono,
      fontFamilyFallback: const ['Consolas', 'Menlo', 'monospace'],
      fontSize: fontSize,
      color: DropClipColors.of(context).textPrimary,
    );
