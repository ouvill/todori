import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:todori/src/core/providers.dart';
import 'package:todori/src/generated/l10n/app_localizations.dart';
import 'package:todori/src/rust/api.dart';
import 'package:todori/src/ui/states.dart';
import 'package:todori/src/ui/header_actions.dart';
import 'package:todori/src/ui/theme.dart';

class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _serverUrlController = TextEditingController();
  bool _registerMode = false;
  bool _busy = false;
  String? _recoveryKey;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _serverUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final accountAsync = ref.watch(accountProvider);
    final serverUrlAsync = ref.watch(syncServerUrlProvider);
    final syncStatusAsync = ref.watch(syncStatusProvider);

    serverUrlAsync.whenData((serverUrl) {
      if (_serverUrlController.text.isEmpty) {
        _serverUrlController.text = serverUrl;
      }
    });

    return Scaffold(
      body: SafeArea(
        child: accountAsync.when(
          loading: () => const AppLoadingState(),
          error: (error, stackTrace) =>
              AppErrorState(message: l10n.accountLoadFailed),
          data: (account) => Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.xl,
                ),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.accountTitle,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.onSurface,
                                fontSize: 28,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                      const AppHeaderSearchAction(),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  if (account.loggedIn)
                    _SignedInSection(
                      account: account,
                      syncStatusAsync: syncStatusAsync,
                      busy: _busy,
                      onLogout: _logout,
                      onSyncNow: _syncNow,
                    )
                  else
                    _SignedOutSection(
                      registerMode: _registerMode,
                      busy: _busy,
                      emailController: _emailController,
                      passwordController: _passwordController,
                      recoveryKey: _recoveryKey,
                      onModeChanged: (registerMode) {
                        setState(() {
                          _registerMode = registerMode;
                          _recoveryKey = null;
                          _error = null;
                        });
                      },
                      onSubmit: _submit,
                    ),
                  if (_recoveryKey != null && account.loggedIn) ...[
                    const SizedBox(height: AppSpacing.lg),
                    SelectableText(
                      _recoveryKey!,
                      key: const ValueKey('account-recovery-key'),
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  Divider(color: Theme.of(context).colorScheme.outlineVariant),
                  const SizedBox(height: AppSpacing.lg),
                  _ServerUrlSection(
                    controller: _serverUrlController,
                    busy: _busy,
                    onSave: _saveServerUrl,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _saveServerUrl() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(syncServerUrlProvider.notifier)
          .setServerUrl(_serverUrlController.text.trim());
    } catch (_) {
      setState(() => _error = l10n.accountRequestFailed);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _busy = true;
      _error = null;
      _recoveryKey = null;
    });
    try {
      final notifier = ref.read(accountProvider.notifier);
      final result = _registerMode
          ? await notifier.register(
              email: _emailController.text.trim(),
              password: _passwordController.text,
              serverUrl: _serverUrlController.text.trim(),
            )
          : await notifier.login(
              email: _emailController.text.trim(),
              password: _passwordController.text,
              serverUrl: _serverUrlController.text.trim(),
            );
      _passwordController.clear();
      if (mounted) {
        setState(() => _recoveryKey = result.recoveryKey);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = l10n.accountRequestFailed);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _logout() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _busy = true;
      _error = null;
      _recoveryKey = null;
    });
    try {
      await ref.read(accountProvider.notifier).logout();
    } catch (_) {
      if (mounted) {
        setState(() => _error = l10n.accountRequestFailed);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _syncNow() async {
    await ref.read(syncStatusProvider.notifier).syncNow();
  }
}

class _ServerUrlSection extends StatelessWidget {
  const _ServerUrlSection({
    required this.controller,
    required this.busy,
    required this.onSave,
  });

  final TextEditingController controller;
  final bool busy;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.accountServerUrlLabel,
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: controller,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.done,
          onSubmitted: busy ? null : (_) => onSave(),
          decoration: InputDecoration(
            hintText: defaultSyncServerUrl,
            border: const UnderlineInputBorder(),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            suffixIcon: IconButton(
              tooltip: l10n.accountSaveServerUrlTooltip,
              onPressed: busy ? null : onSave,
              icon: const Icon(LucideIcons.save300),
            ),
          ),
        ),
      ],
    );
  }
}

class _SignedOutSection extends StatelessWidget {
  const _SignedOutSection({
    required this.registerMode,
    required this.busy,
    required this.emailController,
    required this.passwordController,
    required this.recoveryKey,
    required this.onModeChanged,
    required this.onSubmit,
  });

  final bool registerMode;
  final bool busy;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final String? recoveryKey;
  final ValueChanged<bool> onModeChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _AccountModeButton(
                label: l10n.accountLoginTab,
                selected: !registerMode,
                onPressed: busy ? null : () => onModeChanged(false),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _AccountModeButton(
                label: l10n.accountRegisterTab,
                selected: registerMode,
                onPressed: busy ? null : () => onModeChanged(true),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        TextField(
          controller: emailController,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          decoration: InputDecoration(
            labelText: l10n.accountEmailLabel,
            border: const UnderlineInputBorder(),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: passwordController,
          obscureText: true,
          autofillHints: const [AutofillHints.password],
          decoration: InputDecoration(
            labelText: l10n.accountPasswordLabel,
            border: const UnderlineInputBorder(),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        FilledButton.icon(
          onPressed: busy ? null : onSubmit,
          icon: Icon(
            registerMode ? LucideIcons.userPlus300 : LucideIcons.logIn300,
          ),
          label: Text(
            registerMode ? l10n.accountRegisterButton : l10n.accountLoginButton,
          ),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        if (recoveryKey != null) ...[
          const SizedBox(height: AppSpacing.lg),
          SelectableText(
            recoveryKey!,
            key: const ValueKey('account-recovery-key'),
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      ],
    );
  }
}

class _AccountModeButton extends StatelessWidget {
  const _AccountModeButton({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: selected ? colorScheme.primary : colorScheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
      ),
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: selected
              ? colorScheme.primary
              : colorScheme.onSurfaceVariant,
          shape: const RoundedRectangleBorder(),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _SignedInSection extends StatelessWidget {
  const _SignedInSection({
    required this.account,
    required this.syncStatusAsync,
    required this.busy,
    required this.onLogout,
    required this.onSyncNow,
  });

  final AccountSessionStateDto account;
  final AsyncValue<SyncStatusDto> syncStatusAsync;
  final bool busy;
  final VoidCallback onLogout;
  final VoidCallback onSyncNow;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          account.email ?? '',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: AppSpacing.lg),
        _SyncStatusSection(
          syncStatusAsync: syncStatusAsync,
          busy: busy,
          onSyncNow: onSyncNow,
        ),
        const SizedBox(height: AppSpacing.lg),
        OutlinedButton.icon(
          onPressed: busy ? null : onLogout,
          icon: const Icon(LucideIcons.logOut300),
          label: Text(l10n.accountLogoutButton),
          style: OutlinedButton.styleFrom(
            side: BorderSide.none,
            alignment: AlignmentDirectional.centerStart,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ],
    );
  }
}

class _SyncStatusSection extends StatelessWidget {
  const _SyncStatusSection({
    required this.syncStatusAsync,
    required this.busy,
    required this.onSyncNow,
  });

  final AsyncValue<SyncStatusDto> syncStatusAsync;
  final bool busy;
  final VoidCallback onSyncNow;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final status = syncStatusAsync.value;
    final running = status?.running ?? false;
    final statusText = switch (status) {
      null => l10n.accountSyncIdle,
      SyncStatusDto(loggedIn: false) => l10n.accountSyncNotSignedIn,
      SyncStatusDto(running: true) => l10n.accountSyncRunning,
      SyncStatusDto(lastError: final error?) when error.isNotEmpty =>
        l10n.accountSyncFailed,
      _ => l10n.accountSyncIdle,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.accountSyncTitle,
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(statusText),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    l10n.accountSyncLastSuccess(
                      _formatSyncTime(context, status?.lastSuccessAt),
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: busy || running ? null : onSyncNow,
              icon: const Icon(LucideIcons.refreshCw300),
              label: Text(l10n.accountSyncNowButton),
              style: OutlinedButton.styleFrom(
                side: BorderSide.none,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _formatSyncTime(BuildContext context, int? milliseconds) {
    final l10n = AppLocalizations.of(context)!;
    if (milliseconds == null) {
      return l10n.accountSyncNever;
    }
    final dateTime = DateTime.fromMillisecondsSinceEpoch(
      milliseconds,
    ).toLocal();
    final material = MaterialLocalizations.of(context);
    return '${material.formatShortDate(dateTime)} '
        '${material.formatTimeOfDay(TimeOfDay.fromDateTime(dateTime))}';
  }
}
