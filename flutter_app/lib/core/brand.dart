import 'package:flutter/material.dart';

/// FarmSync product identity — single source for name, tagline, spacing.
abstract final class AppBrand {
  static const name = 'FarmSync';
  static const tagline = 'Soil-aware crop plans, ranked by what earns most.';
  static const loginSubtitle = 'Gates · yield model · quantum rotation — one pipeline.';

  static const pagePadding = EdgeInsets.fromLTRB(16, 12, 16, 88);
  static const cardRadius = 18.0;
}
