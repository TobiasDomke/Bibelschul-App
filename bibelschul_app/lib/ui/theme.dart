import 'package:flutter/material.dart';

/// Colour tokens taken from the web app's app/globals.css (light and dark).
class Palette extends ThemeExtension<Palette> {
  final Color background, foreground, card, primary, onPrimary, secondary, muted, mutedForeground, accent, border,
      ring, destructive, warningBackground, warningForeground, previewBackground, previewForeground, previewMuted;
  const Palette({
    required this.background,
    required this.foreground,
    required this.card,
    required this.primary,
    required this.onPrimary,
    required this.secondary,
    required this.muted,
    required this.mutedForeground,
    required this.accent,
    required this.border,
    required this.ring,
    required this.destructive,
    required this.warningBackground,
    required this.warningForeground,
    required this.previewBackground,
    required this.previewForeground,
    required this.previewMuted,
  });

  static const light = Palette(
    background: Color(0xFFF3F6F7),
    foreground: Color(0xFF173D37),
    card: Color(0xFFFFFFFF),
    primary: Color(0xFF174E43),
    onPrimary: Color(0xFFFFFFFF),
    secondary: Color(0xFFEDF2F0),
    muted: Color(0xFFEDF2F0),
    mutedForeground: Color(0xFF61746D),
    accent: Color(0xFFE2EEE8),
    border: Color(0xFFDCE5E0),
    ring: Color(0xFF518975),
    destructive: Color(0xFFA33035),
    warningBackground: Color(0xFFFFF1CF),
    warningForeground: Color(0xFF714D15),
    previewBackground: Color(0xFF174E43),
    previewForeground: Color(0xFFFFFFFF),
    previewMuted: Color(0xFFBFD6CA),
  );

  static const dark = Palette(
    background: Color(0xFF191C1B),
    foreground: Color(0xFFEEEFE8),
    card: Color(0xFF242927),
    primary: Color(0xFFADCCAF),
    onPrimary: Color(0xFF19241C),
    secondary: Color(0xFF2E3530),
    muted: Color(0xFF2E3530),
    mutedForeground: Color(0xFFB3BCB5),
    accent: Color(0xFF344237),
    border: Color(0xFF3E4842),
    ring: Color(0xFFADCCAF),
    destructive: Color(0xFFFF999E),
    warningBackground: Color(0xFF393125),
    warningForeground: Color(0xFFE5C895),
    previewBackground: Color(0xFF242927),
    previewForeground: Color(0xFFEEEFE8),
    previewMuted: Color(0xFFB3BCB5),
  );

  @override
  Palette copyWith() => this;

  @override
  Palette lerp(ThemeExtension<Palette>? other, double t) => t < 0.5 ? this : (other as Palette? ?? this);
}

ThemeData buildTheme(Brightness brightness) {
  final p = brightness == Brightness.dark ? Palette.dark : Palette.light;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: p.primary,
    onPrimary: p.onPrimary,
    secondary: p.secondary,
    onSecondary: p.foreground,
    error: p.destructive,
    onError: p.onPrimary,
    surface: p.card,
    onSurface: p.foreground,
    surfaceContainerHighest: p.muted,
    outline: p.border,
    outlineVariant: p.border,
  );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: p.background,
    extensions: [p],
    dividerColor: p.border,
    appBarTheme: AppBarTheme(
      backgroundColor: p.background,
      foregroundColor: p.foreground,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: p.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: p.border)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: shape,
        backgroundColor: p.primary,
        foregroundColor: p.onPrimary,
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: shape,
        foregroundColor: p.foreground,
        side: BorderSide(color: p.border),
        backgroundColor: p.secondary,
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: p.primary, minimumSize: const Size(44, 44)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.card,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: p.border)),
      enabledBorder:
          OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: p.border)),
      focusedBorder:
          OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: p.ring, width: 2)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      side: BorderSide(color: p.mutedForeground, width: 1.5),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.card,
      indicatorColor: p.accent,
      // Five tabs: keep "Einstellungen" on one line on small phones.
      labelTextStyle: WidgetStatePropertyAll(
          TextStyle(color: p.foreground, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: -0.3)),
      iconTheme: WidgetStatePropertyAll(IconThemeData(color: p.foreground)),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: p.primary, linearTrackColor: p.muted),
    dialogTheme: DialogThemeData(backgroundColor: p.card, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
  );
}

extension PaletteX on BuildContext {
  Palette get palette => Theme.of(this).extension<Palette>()!;
}
