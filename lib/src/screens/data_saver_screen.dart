import 'package:flutter/material.dart';

import '../data/source_settings.dart';
import '../theme.dart';

/// "Ustawienia › Oszczędzanie danych i tryb offline".
class DataSaverScreen extends StatelessWidget {
  const DataSaverScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = SourceSettingsScope.of(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: context.palette.surface,
        title: const Text('Oszczędzanie danych i tryb offline'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 12),
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.wifi),
            title: const Text(
              "Cache'uj przyszłe utwory w kolejce tylko przez Wi-Fi",
            ),
            subtitle: const Text(
              'Przez sieć komórkową utwory z kolejki nie są pobierane z wyprzedzeniem '
              '(Źródła muzyki › Cachowanie kolejki)',
            ),
            value: settings.queuePrefetchWifiOnly,
            onChanged: settings.setQueuePrefetchWifiOnly,
          ),
        ],
      ),
    );
  }
}
