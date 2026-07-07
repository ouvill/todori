import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:todori/src/screens/tasks_screen.dart';

/// Task-first root surface.
///
/// Phase 1 still stores tasks inside lists, but the product entry should feel
/// like opening Todori to today's work rather than choosing a container first.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      const TasksScreen.today();
}
