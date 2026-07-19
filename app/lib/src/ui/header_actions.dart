import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:taskveil/src/generated/l10n/app_localizations.dart';

/// A shared, precisely centered search affordance for production headers.
class AppHeaderSearchAction extends StatelessWidget {
  const AppHeaderSearchAction({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SizedBox.square(
      dimension: 48,
      child: IconButton(
        tooltip: l10n.openSearchTooltip,
        onPressed: () => context.push('/search'),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 48, height: 48),
        icon: const Icon(LucideIcons.search300, size: 21),
      ),
    );
  }
}
