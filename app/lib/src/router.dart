import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:todori/src/screens/home_screen.dart';
import 'package:todori/src/screens/lists_screen.dart';
import 'package:todori/src/screens/task_detail_screen.dart';
import 'package:todori/src/screens/tasks_screen.dart';
import 'package:todori/src/screens/trash_screen.dart';

/// Centralizes all route definitions for the app in one place.
///
/// This is the intended single extension point for Phase 3 UI-mode work
/// (see `docs/07_Phase1計画書.md` §5 "UIモード切替の設計負債化"): adding a
/// second (higher-functionality) UI mode should mean adding new top-level
/// routes/branches here, not scattering routing logic across screens.
///
/// Route tree (Phase 1 "simple UI", F-02):
///   /                                   -> [HomeScreen] (initial route)
///   /lists                              -> [ListsScreen]
///   /lists/:listId/tasks                -> [TasksScreen]
///   /lists/:listId/tasks/:taskId        -> [TaskDetailScreen]
///   /trash                              -> [TrashScreen]
GoRouter buildAppRouter() {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        name: 'home',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/trash',
        name: 'trash',
        builder: (context, state) => const TrashScreen(),
      ),
      GoRoute(
        path: '/lists',
        name: 'lists',
        pageBuilder: (context, state) => CustomTransitionPage<void>(
          key: state.pageKey,
          child: const ListsScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(-1, 0),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            );
          },
        ),
        routes: [
          GoRoute(
            path: ':listId/tasks',
            name: 'tasks',
            builder: (context, state) =>
                TasksScreen(listId: state.pathParameters['listId']!),
            routes: [
              GoRoute(
                path: ':taskId',
                name: 'taskDetail',
                builder: (context, state) => TaskDetailScreen(
                  listId: state.pathParameters['listId']!,
                  taskId: state.pathParameters['taskId']!,
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}
