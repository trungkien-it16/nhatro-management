import 'package:flutter/material.dart';

/// Stitch Nhatro Management spacing, corner radii, and elevation tokens.
class AppSpacing {
  AppSpacing._();

  static const double xxs = 4;
  static const double xs = 4;
  static const double labelGap = 6;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;

  static const double sidebarWidth = 288;
  static const double topBarHeight = 64;

  static const double badgeRadius = 8;
  static const double inputRadius = 12;
  static const double buttonRadius = 12;
  static const double cardRadius = 16;
  static const double pillRadius = 9999;

  static const EdgeInsets pagePaddingDesktop = EdgeInsets.all(24);
  static const EdgeInsets pagePaddingMobile = EdgeInsets.all(16);
  static const EdgeInsets cardPadding = EdgeInsets.all(16);

  /// Level 1 — Content Cards & Tiles
  static const List<BoxShadow> shadowLevel1 = [
    BoxShadow(
      color: Color(0x0A0F172A),
      blurRadius: 8,
      offset: Offset(0, 1),
    ),
  ];

  /// Level 2 — Dropdowns & Mobile Bottom Navigation
  static const List<BoxShadow> shadowLevel2 = [
    BoxShadow(
      color: Color(0x120F172A),
      blurRadius: 6,
      offset: Offset(0, 4),
      spreadRadius: -1,
    ),
    BoxShadow(
      color: Color(0x0D0F172A),
      blurRadius: 4,
      offset: Offset(0, 2),
      spreadRadius: -2,
    ),
  ];

  /// Level 3 — Modal Dialogs & Sticky Navigation
  static const List<BoxShadow> shadowLevel3 = [
    BoxShadow(
      color: Color(0x140F172A),
      blurRadius: 15,
      offset: Offset(0, 10),
      spreadRadius: -3,
    ),
    BoxShadow(
      color: Color(0x0A0F172A),
      blurRadius: 6,
      offset: Offset(0, 4),
      spreadRadius: -4,
    ),
  ];
}

