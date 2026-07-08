import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:todori/src/core/providers.dart';
import 'package:todori/src/generated/l10n/app_localizations.dart';
import 'package:todori/src/rust/api.dart';
import 'package:todori/src/ui/states.dart';
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
          data: (account) => ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(LucideIcons.arrowLeft300),
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).backButtonTooltip,
                    onPressed: () =>
                        context.canPop() ? context.pop() : context.go('/lists'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                l10n.accountTitle,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              _ServerUrlSection(
                controller: _serverUrlController,
                busy: _busy,
                onSave: _saveServerUrl,
              ),
              if (_recoveryKey != null) ...[
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
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              if (account.loggedIn)
                _SignedInSection(
                  account: account,
                  busy: _busy,
                  onLogout: _logout,
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
            ],
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
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  hintText: defaultSyncServerUrl,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            IconButton.filled(
              tooltip: l10n.accountSaveServerUrlTooltip,
              onPressed: busy ? null : onSave,
              icon: const Icon(LucideIcons.save300),
            ),
          ],
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
        SegmentedButton<bool>(
          segments: [
            ButtonSegment(
              value: false,
              icon: const Icon(LucideIcons.logIn300),
              label: Text(l10n.accountLoginTab),
            ),
            ButtonSegment(
              value: true,
              icon: const Icon(LucideIcons.userPlus300),
              label: Text(l10n.accountRegisterTab),
            ),
          ],
          selected: {registerMode},
          onSelectionChanged: busy
              ? null
              : (selection) => onModeChanged(selection.single),
        ),
        const SizedBox(height: AppSpacing.lg),
        TextField(
          controller: emailController,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          decoration: InputDecoration(
            labelText: l10n.accountEmailLabel,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: passwordController,
          obscureText: true,
          autofillHints: const [AutofillHints.password],
          decoration: InputDecoration(
            labelText: l10n.accountPasswordLabel,
            border: const OutlineInputBorder(),
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

class _SignedInSection extends StatelessWidget {
  const _SignedInSection({
    required this.account,
    required this.busy,
    required this.onLogout,
  });

  final AccountSessionStateDto account;
  final bool busy;
  final VoidCallback onLogout;

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
        OutlinedButton.icon(
          onPressed: busy ? null : onLogout,
          icon: const Icon(LucideIcons.logOut300),
          label: Text(l10n.accountLogoutButton),
        ),
      ],
    );
  }
}
