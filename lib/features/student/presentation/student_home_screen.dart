import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../providers/auth_provider.dart';
import '../../../providers/notification_provider.dart';
import '../../../routes/app_routes.dart';
import '../../auth/presentation/email_verification_banner.dart';
import '../../notifications/presentation/notification_bell_action.dart';

/// A temporary home screen for logged-in students.
class StudentHomeScreen extends StatefulWidget {
  const StudentHomeScreen({super.key});

  @override
  State<StudentHomeScreen> createState() => _StudentHomeScreenState();
}

class _StudentHomeScreenState extends State<StudentHomeScreen> {
  @override
  void initState() {
    super.initState();
    // Deferred to the post-frame callback — see
    // StudentOpportunitiesScreen.initState for why calling this directly
    // here would violate Flutter's build-phase constraints. Only one Home
    // screen is ever active at a time (the router only ever shows one
    // role's Home), so this is the single load for the badge on app entry
    // — the provider's own duplicate-load guard makes a second call from
    // NotificationScreen safe regardless.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<NotificationProvider>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final user = authProvider.user;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Student'),
        actions: const [NotificationBellAction()],
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const EmailVerificationBanner(),
              const SizedBox(height: 12),
              const Text('Role: Student'),
              const SizedBox(height: 8),
              Text(user?.name ?? ''),
              Text(user?.email ?? ''),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => context.push(AppRoutes.studentOpportunities),
                child: const Text('Browse Opportunities'),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => context.push(AppRoutes.studentCvs),
                child: const Text('My CVs'),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => context.push(AppRoutes.studentSkills),
                child: const Text('My Skills'),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => context.push(AppRoutes.studentApplications),
                child: const Text('My Applications'),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () =>
                    context.push(AppRoutes.studentEducationVerification),
                child: const Text('Education Verification'),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => context.push(AppRoutes.studentInvitations),
                child: const Text('Invitations'),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => authProvider.logout(),
                child: const Text('Logout'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
