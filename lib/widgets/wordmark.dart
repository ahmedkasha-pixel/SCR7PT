import 'package:flutter/material.dart';

import '../core/app_config.dart';
import '../core/theme/app_theme.dart';

/// Brand name stays left-to-right in every locale.
class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.size = 28, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final ink = color ?? Theme.of(context).colorScheme.onSurface;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Text(
        AppConfig.appName,
        style: TextStyle(
          fontFamily: AppTheme.latinFamily,
          fontWeight: FontWeight.w800,
          fontSize: size,
          letterSpacing: size * 0.04,
          height: 1,
          color: ink,
        ),
      ),
    );
  }
}
