import 'package:flutter/material.dart';
import 'package:todori/src/generated/l10n/app_localizations.dart';
import 'package:todori/src/ui/theme.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onComplete});

  final Future<void> Function() onComplete;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const _pageCount = 3;

  final PageController _pageController = PageController();
  int _pageIndex = 0;
  bool _submitting = false;
  bool _saveFailed = false;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _advance() async {
    if (_pageIndex < _pageCount - 1) {
      final nextPage = _pageIndex + 1;
      if (MediaQuery.disableAnimationsOf(context)) {
        _pageController.jumpToPage(nextPage);
      } else {
        await _pageController.animateToPage(
          nextPage,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
        );
      }
      return;
    }

    setState(() {
      _submitting = true;
      _saveFailed = false;
    });
    try {
      await widget.onComplete();
    } catch (_) {
      if (mounted) {
        setState(() => _saveFailed = true);
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final pages = [
      _OnboardingPageData(
        icon: Icons.spa_outlined,
        title: l10n.onboardingWelcomeTitle,
        body: l10n.onboardingWelcomeBody,
        semanticLabel: l10n.onboardingWelcomeArtworkSemantics,
      ),
      _OnboardingPageData(
        icon: Icons.shield_outlined,
        title: l10n.onboardingPrivacyTitle,
        body: l10n.onboardingPrivacyBody,
        note: l10n.onboardingPrivacyNote,
        semanticLabel: l10n.onboardingPrivacyArtworkSemantics,
      ),
      _OnboardingPageData(
        icon: Icons.check_rounded,
        title: l10n.onboardingBeginTitle,
        body: l10n.onboardingBeginBody,
        semanticLabel: l10n.onboardingBeginArtworkSemantics,
      ),
    ];

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                0,
              ),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  l10n.appTitle,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                key: const ValueKey('onboarding-pages'),
                controller: _pageController,
                itemCount: pages.length,
                onPageChanged: (index) => setState(() {
                  _pageIndex = index;
                  _saveFailed = false;
                }),
                itemBuilder: (context, index) => _OnboardingPage(
                  data: pages[index],
                  pageIndex: index,
                  pageCount: pages.length,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    label: l10n.onboardingPagePosition(
                      _pageIndex + 1,
                      pages.length,
                    ),
                    child: ExcludeSemantics(
                      child: Row(
                        children: [
                          for (
                            var index = 0;
                            index < pages.length;
                            index++
                          ) ...[
                            Expanded(
                              child: AnimatedContainer(
                                duration:
                                    MediaQuery.disableAnimationsOf(context)
                                    ? Duration.zero
                                    : const Duration(milliseconds: 180),
                                curve: Curves.easeOutCubic,
                                height: index <= _pageIndex ? 2 : 1,
                                color: index <= _pageIndex
                                    ? colorScheme.primary
                                    : colorScheme.outlineVariant,
                              ),
                            ),
                            if (index != pages.length - 1)
                              const SizedBox(width: AppSpacing.xs),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (_saveFailed) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      l10n.onboardingSaveFailed,
                      key: const ValueKey('onboarding-save-error'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  FilledButton(
                    key: const ValueKey('onboarding-primary-action'),
                    onPressed: _submitting ? null : _advance,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _submitting
                        ? SizedBox.square(
                            dimension: AppSpacing.lg,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colorScheme.onPrimary,
                            ),
                          )
                        : Text(
                            _pageIndex == pages.length - 1
                                ? l10n.onboardingStartButton
                                : l10n.continueButton,
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingPageData {
  const _OnboardingPageData({
    required this.icon,
    required this.title,
    required this.body,
    required this.semanticLabel,
    this.note,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? note;
  final String semanticLabel;
}

class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({
    required this.data,
    required this.pageIndex,
    required this.pageCount,
  });

  final _OnboardingPageData data;
  final int pageIndex;
  final int pageCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Semantics(
      namesRoute: true,
      label: AppLocalizations.of(
        context,
      )!.onboardingPagePosition(pageIndex + 1, pageCount),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.xl,
          AppSpacing.lg,
          AppSpacing.md,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: MediaQuery.sizeOf(context).height * 0.58,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                image: true,
                label: data.semanticLabel,
                child: ExcludeSemantics(
                  child: SizedBox.square(
                    dimension: 52,
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Icon(
                        data.icon,
                        size: 28,
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                data.title,
                textAlign: TextAlign.start,
                style: theme.textTheme.headlineLarge?.copyWith(
                  color: colorScheme.onSurface,
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.8,
                  height: 1.08,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                data.body,
                textAlign: TextAlign.start,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: colorScheme.onSurface,
                  height: 1.45,
                ),
              ),
              if (data.note != null) ...[
                const SizedBox(height: AppSpacing.md),
                Padding(
                  padding: const EdgeInsetsDirectional.only(
                    start: AppSpacing.md,
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(
                          color: colorScheme.outlineVariant,
                          width: 2,
                        ),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(
                        start: AppSpacing.md,
                      ),
                      child: Text(
                        data.note!,
                        textAlign: TextAlign.start,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
