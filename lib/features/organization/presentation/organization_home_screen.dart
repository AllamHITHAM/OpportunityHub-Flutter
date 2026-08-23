import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/widgets/theme_toggle_button.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/notification_provider.dart';
import '../../../routes/app_routes.dart';
import '../../auth/presentation/email_verification_banner.dart';
import '../../notifications/presentation/notification_bell_action.dart';

/// A temporary home screen for logged-in organizations.
class OrganizationHomeScreen extends StatefulWidget {
  const OrganizationHomeScreen({super.key});

  @override
  State<OrganizationHomeScreen> createState() => _OrganizationHomeScreenState();
}

class _OrganizationHomeScreenState extends State<OrganizationHomeScreen> {
  @override
  void initState() {
    super.initState();
    // See StudentHomeScreen's own initState doc comment — same reasoning.
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
        title: const Text('Organization'),
        actions: const [ThemeToggleButton(), NotificationBellAction()],
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const EmailVerificationBanner(),
              const SizedBox(height: 12),
              const Text('Role: Organization'),
              const SizedBox(height: 8),
              Text(user?.name ?? ''),
              Text(user?.email ?? ''),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () =>
                    context.push(AppRoutes.organizationOpportunities),
                child: const Text('Manage Opportunities'),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () =>
                    context.push(AppRoutes.organizationCandidates),
                child: const Text('Find Candidates'),
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
