import 'package:flutter/material.dart';

class AppTheme {
  static const Color primaryRed    = Color(0xFFC0152A);
  static const Color darkRed       = Color(0xFF8B0010);
  static const Color black         = Color(0xFF111111);
  static const Color charcoal      = Color(0xFF1C1C1E);
  static const Color silver        = Color(0xFF9DA5AE);
  static const Color lightSilver   = Color(0xFFE1E3E6);
  static const Color background    = Color(0xFFF3F4F6);
  static const Color userBubble    = Color(0xFFC0152A);
  static const Color aiBubble      = Color(0xFFFFFFFF);
  static const Color textDark      = Color(0xFF111111);
  static const Color textGray      = Color(0xFF6B7280);

  // Aliases para compatibilidad
  static const Color primaryBlue   = primaryRed;
  static const Color secondaryBlue = darkRed;
  static const Color accentGold    = silver;
  static const Color lightBlue     = Color(0xFFFBECEE);
  static const Color backgroundGray = background;

  static ThemeData get theme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryRed,
        primary: primaryRed,
        secondary: silver,
        surface: Colors.white,
        background: background,
      ),
      scaffoldBackgroundColor: background,
      appBarTheme: const AppBarTheme(
        backgroundColor: black,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryRed,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: const BorderSide(color: lightSilver, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: const BorderSide(color: primaryRed, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
    );
  }
}
