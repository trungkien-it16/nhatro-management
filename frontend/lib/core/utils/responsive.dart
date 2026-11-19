import 'package:flutter/material.dart';

/// Breakpoints chuẩn theo yêu cầu:
/// Desktop: >= 1200px
/// Tablet: 768px - 1199px
/// Mobile: < 768px
class AppResponsive {
  AppResponsive._();

  static bool isDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= 1200;

  static bool isTablet(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return w >= 768 && w < 1200;
  }

  static bool isMobile(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 768;

  static int statGridCrossAxisCount(double width) {
    if (width >= 1100) return 3;
    if (width >= 680) return 2;
    return 1;
  }
}
