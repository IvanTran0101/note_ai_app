import 'package:flutter/material.dart';

/// Product-specific semantic colors that are not part of Material's core
/// [ColorScheme]. Components read these through [ThemeExtension] so light and
/// dark themes keep the same semantic contract.
@immutable
final class NoteFlowSemanticColors
    extends ThemeExtension<NoteFlowSemanticColors> {
  const NoteFlowSemanticColors({
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.onSuccessContainer,
  });

  factory NoteFlowSemanticColors.fromColorScheme(ColorScheme colorScheme) {
    // Tertiary is the approved first-pass semantic accent. It can be replaced
    // by a dedicated success palette later without changing component APIs.
    return NoteFlowSemanticColors(
      success: colorScheme.tertiary,
      onSuccess: colorScheme.onTertiary,
      successContainer: colorScheme.tertiaryContainer,
      onSuccessContainer: colorScheme.onTertiaryContainer,
    );
  }

  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color onSuccessContainer;

  @override
  NoteFlowSemanticColors copyWith({
    Color? success,
    Color? onSuccess,
    Color? successContainer,
    Color? onSuccessContainer,
  }) {
    return NoteFlowSemanticColors(
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      successContainer: successContainer ?? this.successContainer,
      onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
    );
  }

  @override
  NoteFlowSemanticColors lerp(
    covariant ThemeExtension<NoteFlowSemanticColors>? other,
    double t,
  ) {
    if (other is! NoteFlowSemanticColors) {
      return this;
    }
    return NoteFlowSemanticColors(
      success: Color.lerp(success, other.success, t) ?? success,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t) ?? onSuccess,
      successContainer:
          Color.lerp(successContainer, other.successContainer, t) ??
          successContainer,
      onSuccessContainer:
          Color.lerp(onSuccessContainer, other.onSuccessContainer, t) ??
          onSuccessContainer,
    );
  }
}
