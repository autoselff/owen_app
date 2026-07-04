import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/db/app_database.dart';
import 'data/secure/secret_store.dart';
import 'state/app_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Unlock the encrypted store before the UI starts. The database key never
  // leaves the OS keystore.
  final secretStore = SecretStore();
  final dbKey = await secretStore.databaseKey();
  final database = await AppDatabase.open(dbKey);

  runApp(
    ProviderScope(
      overrides: [
        secretStoreProvider.overrideWithValue(secretStore),
        databaseProvider.overrideWithValue(database),
      ],
      child: const OwenApp(),
    ),
  );
}
