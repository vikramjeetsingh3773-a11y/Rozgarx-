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
import '../../features/preparation/screens/study_plan_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../features/premium/screens/premium_screen.dart';
import '../../features/apply/screens/ad_unlock_screen.dart';
import '../../features/apply/screens/apply_assistance_screen.dart';
import '../../shared/widgets/main_shell.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/splash',
    redirect: (context, state) {
      final user = FirebaseAuth.instance.currentUser;
      final isAuth = user != null;
      final isSplash = state.matchedLocation == '/splash';
      final isLogin = state.matchedLocation == '/login';
      final isOnboarding = state.matchedLocation == '/onboarding';

      if (isSplash || isLogin || isOnboarding) return null;
      if (!isAuth) return '/login';
      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/premium',
        builder: (context, state) => const PremiumScreen(),
      ),
      GoRoute(
        path: '/ad-unlock',
        builder: (context, state) => const AdUnlockScreen(),
      ),
      GoRoute(
        path: '/apply-assistance',
        builder: (context, state) {
          final jobId = state.uri.queryParameters['jobId'] ?? '';
          final jobTitle = state.uri.queryParameters['jobTitle'] ?? '';
          return ApplyAssistanceScreen(jobId: jobId, jobTitle: jobTitle);
        },
      ),
      ShellRoute(
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const DashboardScreen(),
          ),
          GoRoute(
            path: '/jobs',
            builder: (context, state) => const JobsListScreen(),
            routes: [
              GoRoute(
                path: ':jobId',
                builder: (context, state) {
                  final jobId = state.pathParameters['jobId']!;
                  return JobDetailScreen(jobId: jobId);
                },
              ),
            ],
          ),
          GoRoute(
            path: '/preparation',
            builder: (context, state) => const StudyPlanScreen(),
          ),
          GoRoute(
            path: '/profile',
            builder: (context, state) => const ProfileScreen(),
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Text('Page not found: ${state.matchedLocation}'),
      ),
    ),
  );
});
