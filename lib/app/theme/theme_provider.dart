import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Provider for application theme mode (ThemeMode.system, ThemeMode.light, ThemeMode.dark).
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);
