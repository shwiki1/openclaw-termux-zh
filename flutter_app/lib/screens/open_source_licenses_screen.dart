import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/open_source_license_service.dart';
import '../widgets/responsive_layout.dart';

class OpenSourceLicensesScreen extends StatefulWidget {
  const OpenSourceLicensesScreen({super.key});

  @override
  State<OpenSourceLicensesScreen> createState() =>
      _OpenSourceLicensesScreenState();
}

class _OpenSourceLicensesScreenState extends State<OpenSourceLicensesScreen> {
  final _service = OpenSourceLicenseService();

  late Future<_OpenSourceDocuments> _documentsFuture;

  @override
  void initState() {
    super.initState();
    _documentsFuture = _loadDocuments();
  }

  Future<_OpenSourceDocuments> _loadDocuments() async {
    final values = await Future.wait([
      _service.loadRepositoryIndex(),
      _service.loadOpenSourceNotices(),
    ]);
    return _OpenSourceDocuments(
      repositories: values[0],
      notices: values[1],
    );
  }

  void _retry() {
    setState(() {
      _documentsFuture = _loadDocuments();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.t('settingsOpenSourceLicensesPageTitle')),
      ),
      body: FutureBuilder<_OpenSourceDocuments>(
        future: _documentsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Center(
              child: _LoadingMessage(
                label: l10n.t('settingsOpenSourceLicensesLoading'),
              ),
            );
          }

          if (snapshot.hasError) {
            return Center(child: _ErrorMessage(onRetry: _retry));
          }

          final documents = snapshot.data;
          if (documents == null || documents.isEmpty) {
            return Center(child: Text(l10n.t('settingsOpenSourceLicensesEmpty')));
          }

          return ListView(
            padding: ResponsiveLayout.pagePadding(context),
            children: [
              ResponsiveLayout.constrainContent(
                child: _LicenseDocument(
                  repositoriesTitle:
                      l10n.t('settingsOpenSourceLicensesRepositoryIndex'),
                  noticesTitle: l10n.t('settingsOpenSourceLicensesNotices'),
                  repositories: documents.repositories,
                  notices: documents.notices,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _OpenSourceDocuments {
  const _OpenSourceDocuments({
    required this.repositories,
    required this.notices,
  });

  final String repositories;
  final String notices;

  bool get isEmpty => repositories.trim().isEmpty && notices.trim().isEmpty;
}

class _LicenseDocument extends StatelessWidget {
  const _LicenseDocument({
    required this.repositoriesTitle,
    required this.noticesTitle,
    required this.repositories,
    required this.notices,
  });

  final String repositoriesTitle;
  final String noticesTitle;
  final String repositories;
  final String notices;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textStyle = theme.textTheme.bodySmall?.copyWith(
      fontFamily: 'DejaVuSansMono',
      height: 1.4,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SelectionArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              repositoriesTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            SelectableText(repositories.trim(), style: textStyle),
            const SizedBox(height: 24),
            Text(
              noticesTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            SelectableText(notices.trim(), style: textStyle),
          ],
        ),
      ),
    );
  }
}

class _LoadingMessage extends StatelessWidget {
  const _LoadingMessage({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _ErrorMessage extends StatelessWidget {
  const _ErrorMessage({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.t('settingsOpenSourceLicensesLoadFailed')),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: Text(l10n.t('commonRetry')),
        ),
      ],
    );
  }
}
