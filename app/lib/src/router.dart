import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:todori/src/screens/account_screen.dart';
import 'package:todori/src/screens/calendar_screen.dart';
import 'package:todori/src/screens/home_screen.dart';
import 'package:todori/src/screens/lists_screen.dart';
import 'package:todori/src/screens/search_screen.dart';
import 'package:todori/src/screens/task_detail_screen.dart';
import 'package:todori/src/screens/tasks_screen.dart';
import 'package:todori/src/ui/app_navigation_shell.dart';

/// Centralizes all route definitions for the app in one place.
///
/// This is the intended single extension point for Phase 3 UI-mode work
/// (see `docs/07_Phase1計画書.md` §5 "UIモード切替の設計負債化"): adding a
/// second (higher-functionality) UI mode should mean adding new top-level
/// routes/branches here, not scattering routing logic across screens.
///
/// Home, Lists, and Account live in a persistent product shell. List task
/// screens stay in that shell; task detail becomes an immersive route and
/// hides the global navigation.
GoRouter buildAppRouter() {
  return GoRouter(
    initialLocation: '/',
    routes: [
      ShellRoute(
        builder: (context, state, child) => AppNavigationShell(child: child),
        routes: [
          GoRoute(
            path: '/',
            name: 'home',
            pageBuilder: (context, state) =>
                _topLevelPage(state: state, child: const HomeScreen()),
          ),
          GoRoute(
            path: '/calendar',
            name: 'calendar',
            pageBuilder: (context, state) =>
                _topLevelPage(state: state, child: const CalendarScreen()),
            routes: [
              GoRoute(
                path: 'tasks/:listId/:taskId',
                name: 'calendarTaskDetail',
                pageBuilder: (context, state) => _detailPage(
                  state: state,
                  child: TaskDetailScreen(
                    listId: state.pathParameters['listId']!,
                    taskId: state.pathParameters['taskId']!,
                  ),
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/account',
            name: 'account',
            pageBuilder: (context, state) =>
                _topLevelPage(state: state, child: const AccountScreen()),
          ),
          GoRoute(
            path: '/lists',
            name: 'lists',
            pageBuilder: (context, state) =>
                _topLevelPage(state: state, child: const ListsScreen()),
            routes: [
              GoRoute(
                path: ':listId/tasks',
                name: 'tasks',
                pageBuilder: (context, state) => _listPage(
                  state: state,
                  child: TasksScreen(listId: state.pathParameters['listId']!),
                ),
                routes: [
                  GoRoute(
                    path: ':taskId',
                    name: 'taskDetail',
                    pageBuilder: (context, state) => _detailPage(
                      state: state,
                      child: TaskDetailScreen(
                        listId: state.pathParameters['listId']!,
                        taskId: state.pathParameters['taskId']!,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/search',
        name: 'search',
        pageBuilder: (context, state) =>
            _detailPage(state: state, child: const SearchScreen()),
        routes: [
          GoRoute(
            path: 'tasks/:listId/:taskId',
            name: 'searchTaskDetail',
            pageBuilder: (context, state) => _detailPage(
              state: state,
              child: TaskDetailScreen(
                listId: state.pathParameters['listId']!,
                taskId: state.pathParameters['taskId']!,
              ),
            ),
          ),
        ],
      ),
    ],
  );
}

CustomTransitionPage<void> _topLevelPage({
  required GoRouterState state,
  required Widget child,
}) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 220),
    reverseTransitionDuration: const Duration(milliseconds: 180),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.018),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

CustomTransitionPage<void> _listPage({
  required GoRouterState state,
  required Widget child,
}) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 260),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0.08, 0),
          end: Offset.zero,
        ).animate(curved),
        child: FadeTransition(opacity: curved, child: child),
      );
    },
  );
}

CustomTransitionPage<void> _detailPage({
  required GoRouterState state,
  required Widget child,
}) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 240),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.985, end: 1).animate(curved),
          alignment: Alignment.topCenter,
          child: child,
        ),
      );
    },
  );
}
