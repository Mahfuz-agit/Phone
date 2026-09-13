import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Apple HIG-aligned design tokens. Colors mirror iOS system colors
/// (light appearance) since the app targets a light background only.
class AppColors {
  AppColors._();

  static const systemBlue = Color(0xFF007AFF);
  static const systemRed = Color(0xFFFF3B30);
  static const systemGreen = Color(0xFF34C759);
  static const systemOrange = Color(0xFFFF9500);
  static const systemYellow = Color(0xFFFFCC00);
  static const systemGray = Color(0xFF8E8E93);
  static const systemGray2 = Color(0xFFAEAEB2);
  static const systemGray3 = Color(0xFFC7C7CC);
  static const systemGray4 = Color(0xFFD1D1D6);
  static const systemGray5 = Color(0xFFE5E5EA);
  static const systemGray6 = Color(0xFFF2F2F7);

  static const label = Color(0xFF000000);
  static const secondaryLabel = Color(0x993C3C43); // 60% opacity
  static const tertiaryLabel = Color(0x4D3C3C43); // 30% opacity
  static const separator = Color(0x493C3C43); // 29% opacity

  static const groupedBackground = systemGray6;
  static const cardBackground = Color(0xFFFFFFFF);
}

class AppTypography {
  AppTypography._();

  static const _fontFamily = '.SF Pro Text'; // falls back to system font on Android

  static const largeTitle = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 34,
    fontWeight: FontWeight.w700,
    color: AppColors.label,
    letterSpacing: 0.37,
  );

  static const title1 = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 28,
    fontWeight: FontWeight.w700,
    color: AppColors.label,
  );

  static const headline = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 17,
    fontWeight: FontWeight.w600,
    color: AppColors.label,
  );

  static const body = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 17,
    fontWeight: FontWeight.w400,
    color: AppColors.label,
  );

  static const subhead = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 15,
    fontWeight: FontWeight.w400,
    color: AppColors.secondaryLabel,
  );

  static const footnote = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: AppColors.secondaryLabel,
  );

  static const caption1 = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.tertiaryLabel,
  );
}

/// Cupertino theme so widgets like CupertinoNavigationBar,
/// CupertinoTabBar, and CupertinoButton match iOS by default.
final cupertinoAppTheme = CupertinoThemeData(
  brightness: Brightness.light,
  primaryColor: AppColors.systemBlue,
  scaffoldBackgroundColor: AppColors.groupedBackground,
  barBackgroundColor: Color(0xF2F9F9F9), // translucent-looking bar
  textTheme: CupertinoTextThemeData(
    primaryColor: AppColors.systemBlue,
    textStyle: AppTypography.body,
    navTitleTextStyle: AppTypography.headline,
    navLargeTitleTextStyle: AppTypography.largeTitle,
  ),
);

/// MaterialApp wrapper theme, kept minimal since Cupertino widgets
/// carry the actual look — this only affects Material-only widgets
/// (e.g. Scaffold used for bottom-sheet forms).
final materialAppTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.light,
  scaffoldBackgroundColor: AppColors.groupedBackground,
  colorScheme: ColorScheme.fromSeed(
    seedColor: AppColors.systemBlue,
    brightness: Brightness.light,
  ),
  fontFamily: AppTypography._fontFamily,
);
