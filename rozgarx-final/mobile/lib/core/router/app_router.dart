import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../features/auth/screens/splash_screen.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/onboarding_screen.dart';
import '../../features/dashboard/screens/dashboard_screen.dart';
import '../../features/jobs/screens/jobs_list_screen.dart';
import '../../features/jobs/screens/job_detail_screen.dart';
import '../../features/jobs/screens/pdf_viewer_screen.dart';
import '../../features/preparation/screens/study_plan_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../features/premium/screens/premium_screen.dart';
import '../../features/apply/screens/ad_unlock_screen.dart';
import '../../shared/widgets/main_shell.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/splash',
    redirect: (context, state) {
      final user = FirebaseAuth.instance.currentUser;
      final isAuth = user != null;
      final onAuthPages = state.matchedLocation == '/login' ||
          state.matchedLocation == '/splash';

      if (!isAuth && !onAuthPages) return '/login';
      if (isAuth && state.matchedLocation == '/login') return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingScreen()),

      // Main shell with bottom nav
      ShellRoute(
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          GoRoute(path: '/', builder: (_, __) => const DashboardScreen()),
          GoRoute(path: '/jobs', builder: (_, __) => const JobsListScreen()),
          GoRoute(path: '/preparation', builder: (_, __) => const StudyPlanScreen()),
          GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
        ],
      ),

      // Detail screens (outside shell — full screen)
      GoRoute(
        path: '/jobs/:jobId',
        builder: (context, state) {
          final jobId = state.pathParameters['jobId']!;
          return JobDetailScreen(jobId: jobId);
        },
      ),
      GoRoute(
        path: '/pdf',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>;
          return PDFViewerScreen(
            jobId: extra['jobId'] as String,
            jobTitle: extra['jobTitle'] as String,
            storageRef: extra['storageRef'] as String?,
            directUrl: extra['directUrl'] as String?,
          );
        },
      ),
      GoRoute(path: '/premium', builder: (_, __) => const PremiumScreen()),
      GoRoute(
        path: '/ad-unlock',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return AdUnlockScreen(
            feature: extra['feature'] as String? ?? 'apply_assistance',
            jobTitle: extra['jobTitle'] as String? ?? '',
          );
        },
      ),
    ],
  );
});
