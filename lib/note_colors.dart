import 'package:flutter/material.dart';

/// Fixed priority palette shown on each note card. `0` means "no color";
/// the remaining entries are index-addressed (`colorIndex - 1` picks from
/// [noteColors]). Storing an index (not raw ARGB) keeps old notes valid and
/// lets each color adapt to the active theme via a translucent tint.
const int noColorIndex = 0;

/// The seven selectable priority colors.
const List<Color> noteColors = [
  Color(0xFFE53935), // red
  Color(0xFFFB8C00), // orange
  Color(0xFFF9A825), // yellow / amber
  Color(0xFF43A047), // green
  Color(0xFF1E88E5), // blue
  Color(0xFF8E24AA), // purple
  Color(0xFF00897B), // teal
];

/// Card background for a colored note: a low-alpha blend of the palette
/// color over the theme surface so text stays readable in both modes.
/// Returns null when [colorIndex] is out of range (no tint needed).
Color? noteCardColor(int colorIndex, ColorScheme scheme) {
  if (colorIndex <= noColorIndex || colorIndex > noteColors.length) return null;
  final base = scheme.surfaceContainerHighest;
  return Color.alphaBlend(noteColors[colorIndex - 1].withAlpha(46), base);
}
