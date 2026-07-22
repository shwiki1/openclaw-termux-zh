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

  late Future<String> _repositoryIndexFuture;
  Future<String>? _noticesFuture;

  @override
  void initState() {
    super.initState();
    _loadDocuments();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(_loadFullNotices);
    });
  }

  void _loadDocuments() {
    _repositoryIndexFuture = _service.loadRepositoryIndex();
    _noticesFuture = null;
  }

  void _loadFullNotices() {
    _noticesFuture = _service.loadOpenSourceNotices();
  }

  void _retry() {
    setState(() {
      _loadDocuments();
      _loadFullNotices();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.t('settingsOpenSourceLicensesPageTitle')),
      ),
      body: ListView(
        padding: ResponsiveLayout.pagePadding(context),
        children: [
          ResponsiveLayout.constrainContent(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FutureBuilder<String>(
                  future: _repositoryIndexFuture,
                  builder: (context, snapshot) {
                    return _DocumentSection(
                      title: l10n.t('settingsOpenSourceLicensesRepositoryIndex'),
                      data: snapshot.data,
                      loading: snapshot.connectionState != ConnectionState.done,
                      error: snapshot.hasError,
                      onRetry: _retry,
                    );
                  },
                ),
                const SizedBox(height: 12),
                FutureBuilder<String>(
                  future: _noticesFuture,
                  builder: (context, snapshot) {
                    return _DocumentSection(
                      title: l10n.t('settingsOpenSourceLicensesPageTitle'),
                      data: snapshot.data,
                      loading: _noticesFuture == null ||
                          snapshot.connectionState != ConnectionState.done,
                      error: snapshot.hasError,
                      onRetry: _retry,
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DocumentSection extends StatelessWidget {
  const _DocumentSection({
    required this.title,
    required this.data,
    required this.loading,
    required this.error,
    required this.onRetry,
  });

  final String title;
  final String? data;
  final bool loading;
  final bool error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final text = data?.trim() ?? '';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            if (loading)
              _LoadingMessage(
                label: l10n.t('settingsOpenSourceLicensesLoading'),
              )
            else if (error)
              _ErrorMessage(onRetry: onRetry)
            else if (text.isEmpty)
              Text(l10n.t('settingsOpenSourceLicensesEmpty'))
            else
              SelectableText(
                text,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'DejaVuSansMono',
                  height: 1.4,
                ),
              ),
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
