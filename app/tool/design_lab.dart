import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:taskveil/main.dart';
import 'package:taskveil/src/core/providers.dart';
import 'package:taskveil/src/router.dart';
import 'package:taskveil/src/ui/theme.dart';

import '../test/support/design_lab_fixture.dart';

enum DesignLabMode { baseline, candidate }

typedef DesignLabCandidateBuilder = Widget Function(BuildContext context);

class DesignLabCandidate {
  const DesignLabCandidate({
    required this.id,
    required this.targetRoute,
    required this.hypothesis,
    required this.uiSpecDelta,
    required this.workItem,
    required this.builder,
  });

  final String id;
  final String targetRoute;
  final String hypothesis;
  final String uiSpecDelta;
  final String workItem;
  final DesignLabCandidateBuilder builder;
}

/// Only active, undecided candidates belong here. Accepted and rejected work
/// is removed and remains available through its work item and git history.
const activeDesignLabCandidates = <DesignLabCandidate>[];

List<String> validateDesignLabCandidates(
  Iterable<DesignLabCandidate> candidates,
) {
  final errors = <String>[];
  final ids = <String>{};
  for (final candidate in candidates) {
    if (candidate.id.trim().isEmpty) {
      errors.add('candidate id is required');
    } else if (!ids.add(candidate.id)) {
      errors.add('duplicate candidate id: ${candidate.id}');
    } else if (!RegExp(r'^[a-z0-9][a-z0-9-]*$').hasMatch(candidate.id)) {
      errors.add('${candidate.id}: id must be lowercase kebab-case');
    }
    if (!candidate.targetRoute.startsWith('/')) {
      errors.add('${candidate.id}: targetRoute must start with /');
    }
    if (candidate.hypothesis.trim().isEmpty) {
      errors.add('${candidate.id}: hypothesis is required');
    }
    if (candidate.uiSpecDelta.trim().isEmpty) {
      errors.add('${candidate.id}: uiSpecDelta is required');
    }
    if (!RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    ).hasMatch(candidate.workItem)) {
      errors.add('${candidate.id}: workItem must be a UUIDv7');
    }
  }
  return errors;
}

DesignLabMode parseDesignLabMode(String value) => switch (value) {
  '' || 'baseline' => DesignLabMode.baseline,
  'candidate' => DesignLabMode.candidate,
  _ => throw ArgumentError.value(value, 'mode', 'baseline or candidate'),
};

Future<Widget> buildDesignLabRoot({
  required DesignLabMode mode,
  String candidateId = '',
}) async {
  switch (mode) {
    case DesignLabMode.baseline:
      return (await createDesignLabBaseline()).root;
    case DesignLabMode.candidate:
      final errors = validateDesignLabCandidates(activeDesignLabCandidates);
      if (errors.isNotEmpty) {
        throw StateError(errors.join('\n'));
      }
      DesignLabCandidate? selected;
      for (final candidate in activeDesignLabCandidates) {
        if (candidate.id == candidateId) selected = candidate;
      }
      return _CandidateApp(candidate: selected, requestedId: candidateId);
  }
}

class DesignLabBaseline {
  DesignLabBaseline({required this.fixture, required this.router});

  final DesignLabFixture fixture;
  final GoRouter router;

  Widget get root => TaskveilApp(
    router: router,
    overrides: [bridgeServiceProvider.overrideWithValue(fixture.fake)],
  );
}

Future<DesignLabBaseline> createDesignLabBaseline() async {
  return DesignLabBaseline(
    fixture: await createDesignLabFixture(),
    router: buildAppRouter(),
  );
}

class _CandidateApp extends StatelessWidget {
  const _CandidateApp({required this.candidate, required this.requestedId});

  final DesignLabCandidate? candidate;
  final String requestedId;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Taskveil Design Lab Candidate',
      theme: buildTaskveilTheme(Brightness.light),
      home: candidate == null
          ? _CandidateEmptyState(requestedId: requestedId)
          : Builder(builder: candidate!.builder),
    );
  }
}

class _CandidateEmptyState extends StatelessWidget {
  const _CandidateEmptyState({required this.requestedId});

  final String requestedId;

  @override
  Widget build(BuildContext context) {
    final requested = requestedId.trim();
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    requested.isEmpty
                        ? 'No active design candidate'
                        : 'Unknown design candidate: $requested',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Add an undecided DesignLabCandidate with a work item, '
                    'target route, hypothesis, and UI Spec delta. Remove it '
                    'after the decision is implemented or rejected.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
