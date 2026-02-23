import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Gradient palette
  static const Color gradientStart = Color(0xFF020024);
  static const Color gradientMid   = Color(0xFF090979);
  static const Color gradientEnd   = Color(0xFF00D4FF);

  // Accent
  static const Color lightBlue = Color(0xFF2E5BFF);
  static const Color cyan      = Color(0xFF00D4FF);

  // Semantic
  static const Color success  = Color(0xFF00C853);
  static const Color warning  = Color(0xFFFFAB00);
  static const Color danger   = Color(0xFFFF3D00);
  static const Color info     = Color(0xFF29B6F6);

  // Text
  static const Color textPrimary   = Colors.white;
  static const Color textSecondary = Color(0xFFB0BEC5);

  // Card / surface
  static const Color cardSurface = Color(0x1AFFFFFF); // 10% white
  static const Color cardBorder  = Color(0x2EFFFFFF); // 18% white
}
