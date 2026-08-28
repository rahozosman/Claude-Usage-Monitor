import 'package:flutter/material.dart';

import '../../core/utils/usage_math.dart';
import '../../models/connection_status.dart';

/// Semantic colour tokens in a macOS system idiom (label tiers, fills,
/// separators, system status colours, traffic lights). Widgets read colours
/// only from here.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.background,
    required this.surface,
    required this.surfaceElevated,
    required this.surfaceHover,
    required this.border,
    required this.borderStrong,
    required this.separator,
    required this.fill,
    required this.fillStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.accent,
    required this.accentSoft,
    required this.mark,
    required this.track,
    required this.statusNormal,
    required this.statusModerate,
    required this.statusWarning,
    required this.statusCritical,
    required this.statusOffline,
    required this.connected,
    required this.shadow,
    required this.highlight,
    required this.trafficRed,
    required this.trafficYellow,
    required this.trafficGreen,
  });

  final Color background;
  final Color surface;
  final Color surfaceElevated;
  final Color surfaceHover;
  final Color border;
  final Color borderStrong;
  final Color separator;
  final Color fill;
  final Color fillStrong;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color accent;
  final Color accentSoft;

  /// The Claude spark — the only brand colour in the app.
  final Color mark;
  final Color track;
  final Color statusNormal;
  final Color statusModerate;
  final Color statusWarning;
  final Color statusCritical;
  final Color statusOffline;
  final Color connected;
  final Color shadow;
  final Color highlight;
  final Color trafficRed;
  final Color trafficYellow;
  final Color trafficGreen;

  static const Color claudeTerracotta = Color(0xFFD97757);

  static const AppColors dark = AppColors(
    background: Color(0xFF1E1E20),
    surface: Color(0xFF1F1F22),
    surfaceElevated: Color(0xFF2A2A2E),
    surfaceHover: Color(0xFF353539),
    border: Color(0x14FFFFFF),
    borderStrong: Color(0x26FFFFFF),
    separator: Color(0x1AFFFFFF),
    fill: Color(0x0FFFFFFF),
    fillStrong: Color(0x1FFFFFFF),
    textPrimary: Color(0xFFF5F5F7),
    textSecondary: Color(0x99EBEBF5),
    textTertiary: Color(0x4DEBEBF5),
    accent: claudeTerracotta, // Claude orange everywhere the macOS blue used to be
    accentSoft: Color(0x33D97757),
    mark: claudeTerracotta,
    track: Color(0x1FFFFFFF),
    statusNormal: Color(0xFF30D158),
    statusModerate: Color(0xFFFFD60A),
    statusWarning: Color(0xFFFF9F0A),
    statusCritical: Color(0xFFFF453A),
    statusOffline: Color(0xFF8E8E93),
    connected: Color(0xFF30D158),
    shadow: Color(0xFF000000),
    highlight: Color(0x1AFFFFFF),
    trafficRed: Color(0xFFFF5F57),
    trafficYellow: Color(0xFFFEBC2E),
    trafficGreen: Color(0xFF28C840),
  );

  static const AppColors light = AppColors(
    background: Color(0xFFF5F5F7),
    surface: Color(0xFFF3F3F5),
    surfaceElevated: Color(0xFFFFFFFF),
    surfaceHover: Color(0xFFEBEBED),
    border: Color(0x12000000),
    borderStrong: Color(0x1F000000),
    separator: Color(0x14000000),
    fill: Color(0x0A000000),
    fillStrong: Color(0x14000000),
    textPrimary: Color(0xDD000000),
    textSecondary: Color(0x80000000),
    textTertiary: Color(0x4D000000),
    accent: claudeTerracotta,
    accentSoft: Color(0x26D97757),
    mark: claudeTerracotta,
    track: Color(0x14000000),
    statusNormal: Color(0xFF34C759),
    statusModerate: Color(0xFFE5B800),
    statusWarning: Color(0xFFFF9500),
    statusCritical: Color(0xFFFF3B30),
    statusOffline: Color(0xFF8E8E93),
    connected: Color(0xFF34C759),
    shadow: Color(0xFF000000),
    highlight: Color(0xB3FFFFFF),
    trafficRed: Color(0xFFFF5F57),
    trafficYellow: Color(0xFFFEBC2E),
    trafficGreen: Color(0xFF28C840),
  );

  @override
  AppColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceElevated,
    Color? surfaceHover,
    Color? border,
    Color? borderStrong,
    Color? separator,
    Color? fill,
    Color? fillStrong,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? accent,
    Color? accentSoft,
    Color? mark,
    Color? track,
    Color? statusNormal,
    Color? statusModerate,
    Color? statusWarning,
    Color? statusCritical,
    Color? statusOffline,
    Color? connected,
    Color? shadow,
    Color? highlight,
    Color? trafficRed,
    Color? trafficYellow,
    Color? trafficGreen,
  }) {
    return AppColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      surfaceHover: surfaceHover ?? this.surfaceHover,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      separator: separator ?? this.separator,
      fill: fill ?? this.fill,
      fillStrong: fillStrong ?? this.fillStrong,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      accent: accent ?? this.accent,
      accentSoft: accentSoft ?? this.accentSoft,
      mark: mark ?? this.mark,
      track: track ?? this.track,
      statusNormal: statusNormal ?? this.statusNormal,
      statusModerate: statusModerate ?? this.statusModerate,
      statusWarning: statusWarning ?? this.statusWarning,
      statusCritical: statusCritical ?? this.statusCritical,
      statusOffline: statusOffline ?? this.statusOffline,
      connected: connected ?? this.connected,
      shadow: shadow ?? this.shadow,
      highlight: highlight ?? this.highlight,
      trafficRed: trafficRed ?? this.trafficRed,
      trafficYellow: trafficYellow ?? this.trafficYellow,
      trafficGreen: trafficGreen ?? this.trafficGreen,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t) ?? a;
    return AppColors(
      background: l(background, other.background),
      surface: l(surface, other.surface),
      surfaceElevated: l(surfaceElevated, other.surfaceElevated),
      surfaceHover: l(surfaceHover, other.surfaceHover),
      border: l(border, other.border),
      borderStrong: l(borderStrong, other.borderStrong),
      separator: l(separator, other.separator),
      fill: l(fill, other.fill),
      fillStrong: l(fillStrong, other.fillStrong),
      textPrimary: l(textPrimary, other.textPrimary),
      textSecondary: l(textSecondary, other.textSecondary),
      textTertiary: l(textTertiary, other.textTertiary),
      accent: l(accent, other.accent),
      accentSoft: l(accentSoft, other.accentSoft),
      mark: l(mark, other.mark),
      track: l(track, other.track),
      statusNormal: l(statusNormal, other.statusNormal),
      statusModerate: l(statusModerate, other.statusModerate),
      statusWarning: l(statusWarning, other.statusWarning),
      statusCritical: l(statusCritical, other.statusCritical),
      statusOffline: l(statusOffline, other.statusOffline),
      connected: l(connected, other.connected),
      shadow: l(shadow, other.shadow),
      highlight: l(highlight, other.highlight),
      trafficRed: l(trafficRed, other.trafficRed),
      trafficYellow: l(trafficYellow, other.trafficYellow),
      trafficGreen: l(trafficGreen, other.trafficGreen),
    );
  }
}

extension AppColorsContext on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>() ?? AppColors.dark;
}

extension AppStatusColors on AppColors {
  Color forStatus(UsageStatus status) {
    switch (status) {
      case UsageStatus.normal:
        return statusNormal;
      case UsageStatus.moderate:
        return statusModerate;
      case UsageStatus.warning:
        return statusWarning;
      case UsageStatus.critical:
        return statusCritical;
      case UsageStatus.unknown:
        return statusOffline;
    }
  }

  Color forConnection(ConnectionStatus status) {
    switch (status) {
      case ConnectionStatus.live:
        return connected;
      case ConnectionStatus.unauthenticated:
      case ConnectionStatus.error:
        return statusCritical;
      case ConnectionStatus.stale:
        return statusModerate;
      case ConnectionStatus.offline:
      case ConnectionStatus.notConfigured:
      case ConnectionStatus.idle:
        return statusOffline;
    }
  }
}
