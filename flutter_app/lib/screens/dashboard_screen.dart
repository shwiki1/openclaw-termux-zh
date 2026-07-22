import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../widgets/status_card.dart';
import 'cli_tools_screen.dart';
import 'settings_screen.dart';
import 'terminal_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  Future<void> _openScreen(BuildContext context, Widget screen) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.t('appName')),
        actions: [
          IconButton(
            tooltip: l10n.t('settingsTitle'),
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => _openScreen(context, const SettingsScreen()),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              l10n.t('dashboardQuickActions'),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),
          ),
          StatusCard(
            title: l10n.t('dashboardCliToolsTitle'),
            subtitle: l10n.t('dashboardCliToolsSubtitle'),
            icon: Icons.construction_rounded,
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openScreen(context, const CliToolsScreen()),
          ),
          StatusCard(
            title: l10n.t('dashboardTerminalTitle'),
            subtitle: l10n.t('dashboardTerminalSubtitle'),
            icon: Icons.terminal_rounded,
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openScreen(context, const TerminalScreen()),
          ),
        ],
      ),
    );
  }
}
