import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Active navigation tab index (0: Home, 1: Files, 2: AI, 3: Clean, 4: Vault).
final currentTabProvider = StateProvider<int>((ref) => 0);
