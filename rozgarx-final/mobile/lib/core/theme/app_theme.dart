// lib/core/theme/app_theme.dart
// ============================================================
// RozgarX AI — App Theme
// Supports dark + light mode, system detection, manual toggle.
// Optimized contrast ratios for long study sessions.
// Inter font family throughout.
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // Brand
  static const primary     = Color(0xFF1A73E8);
  static const primaryDark = Color(0xFF4D90F0);
  static const secondary   = Color(0xFF0D47A1);

  // Semantic
  static const success = Color(0xFF34A853);
  static const warning = Color(0xFFFBBC04);
  static const error   = Color(0xFFEA4335);
  static const info    = Color(0xFF4FC3F7);

  // Light mode surfaces
  static const backgroundLight = Color(0xFFF8F9FA);
  static const cardLight       = Color(0xFFFFFFFF);
  static const dividerLight    = Color(0xFFE8EAED);

  // Dark mode surfaces
  static const backgroundDark = Color(0xFF0F0F0F);
  static const cardDark       = Color(0xFF1E1E1E);
  static const dividerDark    = Color(0xFF2D2D2D);

  // Text
  static const textPrimaryLight   = Color(0xFF1A1A1A);
  static const textSecondaryLight = Color(0xFF5F6368);
  static const textPrimaryDark    = Color(0xFFE8EAED);
  static const textSecondaryDark  = Color(0xFF9AA0A6);
}

class AppTheme {
  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.light,
        background: AppColors.backgroundLight,
        surface: AppColors.cardLight,
        onBackground: AppColors.textPrimaryLight,
        onSurface: AppColors.textPrimaryLight,
        primary: AppColors.primary,
        error: AppColors.error,
      ),

      scaffoldBackgroundColor: AppColors.backgroundLight,

      textTheme: _textTheme(AppColors.textPrimaryLight),

      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.cardLight,
        foregroundColor: AppColors.textPrimaryLight,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: AppColors.dividerLight,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimaryLight,
        ),
      ),

      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.cardLight,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textSecondaryLight,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        unselectedLabelStyle: TextStyle(fontSize: 11),
      ),

      cardTheme: CardTheme(
        color: AppColors.cardLight,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: AppColors.dividerLight, width: 1),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.backgroundLight,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.dividerLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.dividerLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        hintStyle: const TextStyle(
          color: AppColors.textSecondaryLight,
          fontSize: 14,
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: AppColors.primary.withOpacity(0.1),
        labelStyle: const TextStyle(
          color: AppColors.primary,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),

      dividerTheme: const DividerThemeData(
        color: AppColors.dividerLight,
        thickness: 1,
        space: 0,
      ),
    );
  }

  // ── DARK THEME
  static ThemeData dark() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primaryDark,
        brightness: Brightness.dark,
        background: AppColors.backgroundDark,
        surface: AppColors.cardDark,
        onBackground: AppColors.textPrimaryDark,
        onSurface: AppColors.textPrimaryDark,
        primary: AppColors.primaryDark,
        error: AppColors.error,
      ),

      scaffoldBackgroundColor: AppColors.backgroundDark,

      textTheme: _textTheme(AppColors.textPrimaryDark),

      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.cardDark,
        foregroundColor: AppColors.textPrimaryDark,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: AppColors.dividerDark,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimaryDark,
        ),
      ),

      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.cardDark,
        selectedItemColor: AppColors.primaryDark,
        unselectedItemColor: AppColors.textSecondaryDark,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),

      cardTheme: CardTheme(
        color: AppColors.cardDark,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.dividerDark, width: 1),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF2A2A2A),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.dividerDark),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.dividerDark),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.primaryDark, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        hintStyle: const TextStyle(
          color: AppColors.textSecondaryDark,
          fontSize: 14,
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryDark,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: AppColors.primaryDark.withOpacity(0.15),
        labelStyle: const TextStyle(
          color: AppColors.primaryDark,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        side: BorderSide.none,
      ),

      dividerTheme: const DividerThemeData(
        color: AppColors.dividerDark,
        thickness: 1,
        space: 0,
      ),
    );
  }

  static TextTheme _textTheme(Color primaryColor) {
    return GoogleFonts.interTextTheme().copyWith(
      displayLarge:   GoogleFonts.inter(fontSize: 32, fontWeight: FontWeight.w700, color: primaryColor),
      displayMedium:  GoogleFonts.inter(fontSize: 26, fontWeight: FontWeight.w700, color: primaryColor),
      headlineLarge:  GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w700, color: primaryColor),
      headlineMedium: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w600, color: primaryColor),
      titleLarge:     GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: primaryColor),
      titleMedium:    GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: primaryColor),
      titleSmall:     GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: primaryColor),
      bodyLarge:      GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w400, color: primaryColor),
      bodyMedium:     GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w400, color: primaryColor),
      bodySmall:      GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w400,
          color: primaryColor == AppColors.textPrimaryLight
              ? AppColors.textSecondaryLight
              : AppColors.textSecondaryDark),
      labelLarge:     GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
      labelSmall:     GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500),
    );
  }
}


// ── Theme Notifier (for manual toggle)
class ThemeNotifier extends ChangeNotifier {
  ThemeMode _mode = ThemeMode.system;

  ThemeMode get mode => _mode;
  bool get isDark => _mode == ThemeMode.dark;

  void setLight() {
    _mode = ThemeMode.light;
    notifyListeners();
  }

  void setDark() {
    _mode = ThemeMode.dark;
    notifyListeners();
  }

  void setSystem() {
    _mode = ThemeMode.system;
    notifyListeners();
  }

  void toggle() {
    _mode = _mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
  }
}
