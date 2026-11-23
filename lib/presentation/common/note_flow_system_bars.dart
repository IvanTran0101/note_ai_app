import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Keeps system icons readable as the existing app theme changes.
///
/// This owns system-bar appearance only. Screen widgets retain ownership of
/// their safe-area padding; adding another inset here would duplicate it.
final class NoteFlowSystemBars extends StatelessWidget {
  const NoteFlowSystemBars({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final iconBrightness = dark ? Brightness.light : Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarBrightness: theme.brightness,
        statusBarIconBrightness: iconBrightness,
        systemStatusBarContrastEnforced: false,
        systemNavigationBarColor: theme.colorScheme.surface,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarIconBrightness: iconBrightness,
        systemNavigationBarContrastEnforced: false,
      ),
      child: child,
    );
  }
}
