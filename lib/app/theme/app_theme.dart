import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_dimens.dart';

/// Builds the light and dark [ThemeData] from the semantic tokens.
/// Typography follows macOS metrics: 13 pt body, 11 pt secondary, tight
/// tracking on titles, tabular figures where numbers change.
class AppTheme {
  AppTheme._();

  static const String fontFamily = 'Inter';
  static const List<String> fontFallback = <String>['Segoe UI Variable Text', 'Segoe UI', 'Helvetica Neue', 'Arial'];

  static ThemeData dark() => _build(AppColors.dark, Brightness.dark);
  static ThemeData light() => _build(AppColors.light, Brightness.light);

  static ThemeData _build(AppColors c, Brightness brightness) {
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: Colors.transparent,
      colorScheme: ColorScheme.fromSeed(
        seedColor: c.accent,
        brightness: brightness,
        surface: c.surface,
        primary: c.accent,
        onPrimary: Colors.white,
        outline: c.borderStrong,
      ),
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      hoverColor: c.fill,
      visualDensity: VisualDensity.compact,
      extensions: <ThemeExtension<dynamic>>[c],
    );

    TextStyle s({
      required double size,
      FontWeight weight = FontWeight.w400,
      double tracking = 0,
      Color? color,
      double height = 1.3,
    }) =>
        TextStyle(
          fontFamily: fontFamily,
          fontFamilyFallback: fontFallback,
          fontSize: size,
          fontWeight: weight,
          letterSpacing: tracking,
          height: height,
          color: color ?? c.textPrimary,
        );

    final text = TextTheme(
      headlineSmall: s(size: 22, weight: FontWeight.w600, tracking: -0.4, height: 1.15),
      titleLarge: s(size: 15, weight: FontWeight.w600, tracking: -0.25),
      titleMedium: s(size: 13, weight: FontWeight.w600, tracking: -0.15),
      titleSmall: s(size: 11, weight: FontWeight.w600, tracking: 0, color: c.textSecondary),
      bodyLarge: s(size: 14, tracking: -0.1),
      bodyMedium: s(size: 13, tracking: -0.08),
      bodySmall: s(size: 11.5, color: c.textSecondary, height: 1.3),
      labelLarge: s(size: 13, weight: FontWeight.w500, tracking: -0.08),
      labelMedium: s(size: 11.5, weight: FontWeight.w500, color: c.textSecondary),
      labelSmall: s(size: 10.5, weight: FontWeight.w600, tracking: 0.2, color: c.textTertiary),
    );

    return base.copyWith(
      textTheme: text,
      dividerColor: c.separator,
      iconTheme: IconThemeData(color: c.textSecondary, size: AppDimens.iconMd),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 450),
        showDuration: const Duration(seconds: 8),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: brightness == Brightness.dark ? const Color(0xF2323236) : const Color(0xF7F4F4F6),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: c.borderStrong, width: 0.5),
          boxShadow: <BoxShadow>[
            BoxShadow(color: c.shadow.withValues(alpha: 0.22), blurRadius: 12, offset: const Offset(0, 4)),
          ],
        ),
        textStyle: s(size: 11, color: c.textPrimary, height: 1.35),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: brightness == Brightness.dark ? c.fill : Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppDimens.s8, vertical: AppDimens.s6),
        hintStyle: s(size: 12, color: c.textTertiary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusSm),
          borderSide: BorderSide(color: c.borderStrong, width: 0.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusSm),
          borderSide: BorderSide(color: c.borderStrong, width: 0.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusSm),
          borderSide: BorderSide(color: c.accent, width: 1.5),
        ),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 4,
        activeTrackColor: c.accent,
        inactiveTrackColor: c.fillStrong,
        thumbColor: Colors.white,
        overlayColor: Colors.transparent,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8, elevation: 2, pressedElevation: 3),
        overlayShape: SliderComponentShape.noOverlay,
        trackShape: const RoundedRectSliderTrackShape(),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: brightness == Brightness.dark ? const Color(0xF52C2C30) : const Color(0xFAFFFFFF),
        surfaceTintColor: Colors.transparent,
        elevation: 10,
        shadowColor: c.shadow.withValues(alpha: 0.35),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: c.borderStrong, width: 0.5),
        ),
        textStyle: s(size: 12.5, color: c.textPrimary),
        menuPadding: const EdgeInsets.symmetric(vertical: 5, horizontal: 5),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: c.accent,
        selectionColor: c.accentSoft,
        selectionHandleColor: c.accent,
      ),
    );
  }
}
