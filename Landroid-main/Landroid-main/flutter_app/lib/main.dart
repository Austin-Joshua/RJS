import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/api/client.dart';
import 'src/app.dart';
import 'src/auth/auth_repository.dart';
import 'src/config/supabase_constants.dart';

/// Single shared client so Settings can change base URL and Map/Dashboard see it.
final ApiClient landroidApiClient = ApiClient();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await landroidApiClient.hydrateFromPrefs();
  if (AuthRepository.isSupabaseConfigured) {
    await Supabase.initialize(
      url: SupabaseConstants.url,
      anonKey: SupabaseConstants.anonKey,
    );
  }
  runApp(LandroidApp(apiClient: landroidApiClient));
}
