import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class OrbitColors {
  static const desk = Color(0xFF11161D);
  static const panel = Color(0xFF171D26);
  static const raised = Color(0xFF1E2530);
  static const line = Color(0xFF2A3340);
  static const ink = Color(0xFFE7ECF3);
  static const soft = Color(0xFF8B97A8);
  static const mute = Color(0xFF667182);
  static const accent = Color(0xFF3B82F6);
  static const mine = Color(0xFF2563EB);
  static const theirs = Color(0xFF232B36);
}

ThemeData buildOrbitTheme() {
  final text = GoogleFonts.ibmPlexSansTextTheme(
    ThemeData(brightness: Brightness.dark).textTheme,
  ).apply(bodyColor: OrbitColors.ink, displayColor: OrbitColors.ink);

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: OrbitColors.desk,
    colorScheme: const ColorScheme.dark(
      primary: OrbitColors.accent,
      onPrimary: Colors.white,
      surface: OrbitColors.panel,
      onSurface: OrbitColors.ink,
      outline: OrbitColors.line,
    ),
    textTheme: text,
    appBarTheme: AppBarTheme(
      backgroundColor: OrbitColors.desk,
      foregroundColor: OrbitColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: GoogleFonts.sora(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
        color: OrbitColors.ink,
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: OrbitColors.accent,
      foregroundColor: Colors.white,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: OrbitColors.raised,
      hintStyle: const TextStyle(color: OrbitColors.mute),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: OrbitColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: OrbitColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: OrbitColors.accent, width: 1.4),
      ),
    ),
  );
}
