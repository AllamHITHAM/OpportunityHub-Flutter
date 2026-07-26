import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../routes/app_routes.dart';
import '../../../providers/auth_provider.dart';

/// A temporary home screen for logged-in organizations.
class OrganizationHomeScreen extends StatelessWidget {
  const OrganizationHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final user = authProvider.user;

    return Scaffold(
      appBar: AppBar(title: const Text('Organization')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
              onPressed: () => authProvider.logout(),
              child: const Text('Logout'),
            ),
          ],
        ),
      ),
    );
  }
}
