import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:todori/src/ui/theme.dart';

class AppLoadingState extends StatelessWidget {
  const AppLoadingState({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        liveRegion: true,
        child: const SizedBox.square(
          dimension: 22,
          child: CircularProgressIndicator(
            color: AppColors.forest,
            strokeWidth: 1.5,
          ),
        ),
      ),
    );
  }
}

class AppErrorState extends StatelessWidget {
  const AppErrorState({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return _AppStateLayout(
      icon: LucideIcons.cloudOff300,
      iconColor: AppColors.coral,
      title: message,
      isError: true,
    );
  }
}

class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.body,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return _AppStateLayout(
      icon: icon,
      iconColor: AppColors.forest,
      title: title,
      body: body,
      action: action,
    );
  }
}

class _AppStateLayout extends StatelessWidget {
  const _AppStateLayout({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.body,
    this.action,
    this.isError = false,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String? body;
  final Widget? action;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Semantics(
            liveRegion: isError,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox.square(
                  dimension: 38,
                  child: Icon(icon, color: iconColor, size: 21),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title, style: theme.textTheme.titleMedium),
                      if (body != null) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          body!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                      if (action != null) ...[
                        const SizedBox(height: AppSpacing.md),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: action!,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
