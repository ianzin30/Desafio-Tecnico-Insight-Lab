import 'package:flutter/material.dart';

/// Bundled fonts (assets/fonts, OFL).
const sansFont = 'IBM Plex Sans';
const monoFont = 'IBM Plex Mono';

/// Design tokens of the high-fidelity prototype ("Grafite e cobalto").
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.bg,
    required this.side,
    required this.surface,
    required this.text,
    required this.text2,
    required this.line,
    required this.line2,
    required this.accent,
    required this.accentInk,
    required this.accentSoft,
    required this.own,
    required this.ownLine,
    required this.other,
    required this.hover,
    required this.sel,
    required this.selInk,
    required this.warnBg,
    required this.warnInk,
    required this.errBg,
    required this.errInk,
    required this.infoBg,
    required this.infoInk,
    required this.scrim,
    required this.shadow,
  });

  static const light = AppColors(
    bg: Color(0xFFF6F7F9),
    side: Color(0xFFEDEFF2),
    surface: Color(0xFFFFFFFF),
    text: Color(0xFF15181D),
    text2: Color(0xFF555D6B),
    line: Color(0xFFDFE2E8),
    line2: Color(0xFFC9CFD8),
    accent: Color(0xFF2B59C3),
    accentInk: Color(0xFFFFFFFF),
    accentSoft: Color(0xFFDCE5FA),
    own: Color(0xFFE6EDFB),
    ownLine: Color(0xFFC3D2F4),
    other: Color(0xFFFFFFFF),
    hover: Color(0xFFE2E6EC),
    sel: Color(0xFFDCE4F7),
    selInk: Color(0xFF173A8A),
    warnBg: Color(0xFFFFF1D1),
    warnInk: Color(0xFF5E4100),
    errBg: Color(0xFFFCE9E7),
    errInk: Color(0xFF9E2118),
    infoBg: Color(0xFFE9EFFC),
    infoInk: Color(0xFF1D3F91),
    scrim: Color(0x7A11141A),
    shadow: Color(0x2911141A),
  );

  static const dark = AppColors(
    bg: Color(0xFF111317),
    side: Color(0xFF16191E),
    surface: Color(0xFF1C2026),
    text: Color(0xFFE7E9EC),
    text2: Color(0xFFA0A7B3),
    line: Color(0xFF272C34),
    line2: Color(0xFF3A404A),
    accent: Color(0xFF7FA2F5),
    accentInk: Color(0xFF0D1630),
    accentSoft: Color(0xFF24314F),
    own: Color(0xFF223052),
    ownLine: Color(0xFF34497A),
    other: Color(0xFF1C2026),
    hover: Color(0xFF232831),
    sel: Color(0xFF25325A),
    selInk: Color(0xFFD6E1FF),
    warnBg: Color(0xFF3A2D0F),
    warnInk: Color(0xFFF4D78F),
    errBg: Color(0xFF3B1C1A),
    errInk: Color(0xFFF6B4AD),
    infoBg: Color(0xFF1F2A44),
    infoInk: Color(0xFFC9D7FF),
    scrim: Color(0x99000000),
    shadow: Color(0x80000000),
  );

  final Color bg, side, surface, text, text2, line, line2;
  final Color accent, accentInk, accentSoft;
  final Color own, ownLine, other, hover, sel, selInk;
  final Color warnBg, warnInk, errBg, errInk, infoBg, infoInk;
  final Color scrim, shadow;

  static AppColors of(BuildContext context) =>
      Theme.of(context).extension<AppColors>()!;

  List<BoxShadow> get raised => [
    BoxShadow(color: shadow, blurRadius: 32, offset: const Offset(0, 10)),
  ];

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(AppColors? other, double t) =>
      t < 0.5 ? this : (other ?? this);
}

ThemeData buildTheme(Brightness brightness) {
  final colors = brightness == Brightness.dark
      ? AppColors.dark
      : AppColors.light;
  final base = ThemeData(
    brightness: brightness,
    fontFamily: sansFont,
    useMaterial3: true,
    scaffoldBackgroundColor: colors.bg,
    colorScheme: ColorScheme.fromSeed(
      seedColor: colors.accent,
      brightness: brightness,
      primary: colors.accent,
      onPrimary: colors.accentInk,
      surface: colors.surface,
      onSurface: colors.text,
      error: colors.errInk,
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: colors.accent,
      selectionColor: colors.accentSoft,
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 500),
      textStyle: TextStyle(
        fontFamily: sansFont,
        fontSize: 12,
        color: colors.surface,
      ),
      decoration: BoxDecoration(
        color: colors.text,
        borderRadius: BorderRadius.circular(6),
      ),
    ),
    extensions: [colors],
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      fontFamily: sansFont,
      bodyColor: colors.text,
      displayColor: colors.text,
    ),
  );
}

/// Text styles of the prototype.
abstract final class AppText {
  static TextStyle body(AppColors c) =>
      TextStyle(fontSize: 14, height: 1.45, color: c.text);

  static TextStyle meta(AppColors c) => TextStyle(fontSize: 12, color: c.text2);

  static TextStyle mono(AppColors c, {double size = 12.5}) => TextStyle(
    fontFamily: monoFont,
    fontSize: size,
    fontWeight: FontWeight.w600,
    color: c.text,
  );

  static TextStyle section(AppColors c) => TextStyle(
    fontSize: 11.5,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.6,
    color: c.text2,
  );
}
