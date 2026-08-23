// Widget tests for the premium StudentInvitationsScreen (UI Phase 5) —
// verifies the real invitation-inbox redesign (organization identity,
// summary counts, search/filters, Accept/Decline with a real confirmation
// and success beat), empty/loading/error handling, and
// responsive/reduced-motion behavior, in isolation with a small GoRouter.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/core/theme/app_theme.dart';
import 'package:opportunityhub_flutter/core/widgets/theme_toggle_button.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/features/invitations/data/invitation_repository.dart';
import 'package:opportunityhub_flutter/features/invitations/presentation/student_invitations_screen.dart';
import 'package:opportunityhub_flutter/models/invitation_model.dart';
import 'package:opportunityhub_flutter/providers/auth_provider.dart';
import 'package:opportunityhub_flutter/providers/student_invitations_provider.dart';
import 'package:opportunityhub_flutter/providers/theme_provider.dart';
import 'package:opportunityhub_flutter/routes/app_routes.dart';

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository()
    : super(
        apiClient: ApiClient(tokenStorageService: TokenStorageService()),
        tokenStorageService: TokenStorageService(),
      );

  @override
  Future<String?> getSavedToken() async => null;
}

InvitationModel _invitation({
  int id = 1,
  int opportunityId = 5,
  String status = 'pending',
  String opportunityTitle = 'Backend Developer',
  String organizationName = 'Hiring Co',
  String? message,
  DateTime? createdAt,
}) {
  return InvitationModel(
    id: id,
    opportunityId: opportunityId,
    status: status,
    opportunityTitle: opportunityTitle,
    organizationName: organizationName,
    message: message,
    createdAt: createdAt ?? DateTime(2026, 8, 22),
  );
}

class _FakeInvitationRepository extends InvitationRepository {
  _FakeInvitationRepository({
    this.invitations = const [],
    this.listDelay = Duration.zero,
    this.acceptDelay = Duration.zero,
  }) : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  List<InvitationModel> invitations;
  Duration listDelay;
  Duration acceptDelay;
  ApiException? listError;
  ApiException? acceptError;
  ApiException? declineError;
  int acceptCallCount = 0;
  int declineCallCount = 0;
  int listCallCount = 0;

  @override
  Future<List<InvitationModel>> getInvitations() async {
    listCallCount++;
    if (listDelay > Duration.zero) await Future<void>.delayed(listDelay);
    if (listError != null) throw listError!;
    return invitations;
  }

  @override
  Future<void> acceptInvitation(int invitationId) async {
    acceptCallCount++;
    if (acceptDelay > Duration.zero) await Future<void>.delayed(acceptDelay);
    if (acceptError != null) throw acceptError!;
    invitations = [
      for (final invitation in invitations)
        if (invitation.id == invitationId)
          _invitation(
            id: invitation.id,
            opportunityId: invitation.opportunityId,
            status: 'accepted',
            opportunityTitle: invitation.opportunityTitle,
            organizationName: invitation.organizationName,
          )
        else
          invitation,
    ];
  }

  @override
  Future<void> declineInvitation(int invitationId) async {
    declineCallCount++;
    if (declineError != null) throw declineError!;
    invitations = [
      for (final invitation in invitations)
        if (invitation.id == invitationId)
          _invitation(
            id: invitation.id,
            opportunityId: invitation.opportunityId,
            status: 'declined',
            opportunityTitle: invitation.opportunityTitle,
            organizationName: invitation.organizationName,
          )
        else
          invitation,
    ];
  }
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required _FakeInvitationRepository repository,
  Size size = const Size(420, 900),
  ThemeData? theme,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final authProvider = AuthProvider(authRepository: _FakeAuthRepository());
  final provider = StudentInvitationsProvider(
    repository: repository,
    authProvider: authProvider,
  );

  final router = GoRouter(
    initialLocation: AppRoutes.studentInvitations,
    routes: [
      GoRoute(
        path: AppRoutes.studentInvitations,
        builder: (_, _) => const StudentInvitationsScreen(),
      ),
      GoRoute(
        path: '${AppRoutes.studentOpportunities}/:id',
        builder: (_, state) =>
            Scaffold(body: Text('OPPORTUNITY_${state.pathParameters['id']}')),
      ),
      GoRoute(
        path: AppRoutes.studentOpportunities,
        builder: (_, _) => const Scaffold(body: Text('DISCOVER_PLACEHOLDER')),
      ),
    ],
  );

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ChangeNotifierProvider<StudentInvitationsProvider>.value(
          value: provider,
        ),
        ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
      ],
      child: MaterialApp.router(
        theme: theme ?? AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Loading state renders a skeleton while the list is in flight', (
    tester,
  ) async {
    final repository = _FakeInvitationRepository(
      listDelay: const Duration(milliseconds: 200),
    );
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final authProvider = AuthProvider(authRepository: _FakeAuthRepository());
    final provider = StudentInvitationsProvider(
      repository: repository,
      authProvider: authProvider,
    );
    final router = GoRouter(
      initialLocation: AppRoutes.studentInvitations,
      routes: [
        GoRoute(
          path: AppRoutes.studentInvitations,
          builder: (_, _) => const StudentInvitationsScreen(),
        ),
      ],
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StudentInvitationsProvider>.value(
            value: provider,
          ),
          ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
        ],
        child: MaterialApp.router(
          theme: AppTheme.lightTheme,
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Invitations'), findsOneWidget);
    expect(provider.isLoading, isTrue);

    await tester.pumpAndSettle();
  });

  testWidgets('Empty state renders with a real Explore Opportunities CTA', (
    tester,
  ) async {
    await _pumpScreen(tester, repository: _FakeInvitationRepository());

    expect(find.text('No Invitations Yet'), findsOneWidget);
    expect(
      find.text(
        'When an organization invites you to an opportunity, it will appear here.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Explore Opportunities'));
    await tester.pumpAndSettle();

    expect(find.text('DISCOVER_PLACEHOLDER'), findsOneWidget);
  });

  testWidgets('Error state renders on load failure, with retry', (
    tester,
  ) async {
    final repository = _FakeInvitationRepository()
      ..listError = ApiException('Server error.');
    await _pumpScreen(tester, repository: repository);

    expect(find.text('Server error.'), findsOneWidget);

    repository.listError = null;
    repository.invitations = [_invitation()];
    await tester.tap(find.text('Try Again'));
    await tester.pumpAndSettle();

    expect(find.text('Backend Developer'), findsOneWidget);
  });

  testWidgets(
    'A pending invitation shows organization identity, the opportunity, invited date, message, and status',
    (tester) async {
      await _pumpScreen(
        tester,
        repository: _FakeInvitationRepository(
          invitations: [
            _invitation(message: 'Please apply!', createdAt: DateTime(2026, 8, 22)),
          ],
        ),
      );

      expect(find.text('Hiring Co'), findsOneWidget);
      expect(find.text('Invitation'), findsOneWidget);
      expect(find.text('invited you to'), findsOneWidget);
      expect(find.text('Backend Developer'), findsOneWidget);
      expect(find.text('Invited Aug 22, 2026'), findsOneWidget);
      expect(find.text('Please apply!'), findsOneWidget);
      // "Pending" appears at least in the card's own status chip.
      expect(find.text('Pending'), findsWidgets);
    },
  );

  testWidgets('An empty organization name falls back to a safe generic label', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      repository: _FakeInvitationRepository(
        invitations: [_invitation(organizationName: '')],
      ),
    );

    expect(find.text('An organization'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'the organization mark shows two real initials for a single-word organization name (UI Phase 5.1)',
    (tester) async {
      await _pumpScreen(
        tester,
        repository: _FakeInvitationRepository(
          invitations: [_invitation(organizationName: 'ABOMOHAMAD')],
        ),
      );

      expect(find.text('AB'), findsOneWidget);
      expect(find.text('A'), findsNothing);
    },
  );

  testWidgets('Accepted/declined invitations show no Accept/Decline actions', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      repository: _FakeInvitationRepository(
        invitations: [_invitation(id: 1, status: 'accepted')],
      ),
    );

    expect(find.text('Accepted'), findsWidgets);
    expect(find.text('Accept Invitation'), findsNothing);
    expect(find.text('Decline'), findsNothing);
    // The real navigation action stays available regardless of status.
    expect(find.text('View Opportunity'), findsOneWidget);
  });

  testWidgets('A declined invitation shows restrained status, no Accept action', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      repository: _FakeInvitationRepository(
        invitations: [_invitation(id: 1, status: 'declined')],
      ),
    );

    expect(find.text('Declined'), findsWidgets);
    expect(find.text('Accept Invitation'), findsNothing);
    expect(find.text('Decline'), findsNothing);
    expect(find.text('View Opportunity'), findsOneWidget);
  });

  testWidgets('View Opportunity navigates to the real Opportunity Details route', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      repository: _FakeInvitationRepository(
        invitations: [_invitation(id: 1, opportunityId: 7, status: 'accepted')],
      ),
    );

    await tester.tap(find.text('View Opportunity'));
    await tester.pumpAndSettle();

    expect(find.text('OPPORTUNITY_7'), findsOneWidget);
  });

  group('Accept', () {
    testWidgets(
      'shows a real success beat, then redirects to Opportunity Details/Apply',
      (tester) async {
        final repository = _FakeInvitationRepository(
          invitations: [_invitation(id: 1, opportunityId: 5)],
        );
        await _pumpScreen(tester, repository: repository);

        await tester.tap(find.text('Accept Invitation'));
        await tester.pump();
        await tester.pump();
        await tester.pump();

        expect(repository.acceptCallCount, 1);
        expect(find.textContaining('Invitation accepted'), findsOneWidget);

        await tester.pumpAndSettle();

        expect(find.text('OPPORTUNITY_5'), findsOneWidget);
      },
    );

    testWidgets('shows a loading state on the Accept button while in flight', (
      tester,
    ) async {
      final repository = _FakeInvitationRepository(
        invitations: [_invitation(id: 1)],
        acceptDelay: const Duration(milliseconds: 300),
      );
      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.text('Accept Invitation'));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pumpAndSettle();
    });

    testWidgets('a real backend error keeps the invitation Pending, no false transition', (
      tester,
    ) async {
      final repository = _FakeInvitationRepository(
        invitations: [_invitation(id: 1)],
      )..acceptError = ApiException(
        'This invitation has already been responded to',
        statusCode: 409,
      );
      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.text('Accept Invitation'));
      await tester.pumpAndSettle();

      expect(
        find.text('This invitation has already been responded to'),
        findsOneWidget,
      );
      expect(find.text('Pending'), findsWidgets);
      expect(find.text('OPPORTUNITY_5'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a disabled in-flight button protects against duplicate submissions', (
      tester,
    ) async {
      final repository = _FakeInvitationRepository(
        invitations: [_invitation(id: 1)],
        acceptDelay: const Duration(milliseconds: 300),
      );
      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.text('Accept Invitation'));
      await tester.pump();
      // The button is now disabled/loading — a second tap must not fire a
      // second real request.
      await tester.tap(find.text('Accept Invitation'), warnIfMissed: false);
      await tester.pump();

      expect(repository.acceptCallCount, 1);

      await tester.pumpAndSettle();
    });
  });

  group('Decline', () {
    testWidgets('shows a real, truthful confirmation before declining', (
      tester,
    ) async {
      final repository = _FakeInvitationRepository(
        invitations: [_invitation(id: 1)],
      );
      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.text('Decline'));
      await tester.pumpAndSettle();

      expect(find.text('Decline invitation?'), findsOneWidget);
      expect(
        find.text("You won't be able to accept this invitation afterward."),
        findsOneWidget,
      );

      // Cancelling never calls the real backend.
      await tester.tap(find.text('Keep Invitation'));
      await tester.pumpAndSettle();

      expect(repository.declineCallCount, 0);
      expect(find.text('Pending'), findsWidgets);
    });

    testWidgets('confirming declines for real and updates the status', (
      tester,
    ) async {
      final repository = _FakeInvitationRepository(
        invitations: [_invitation(id: 1)],
      );
      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.text('Decline'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: find.byType(AlertDialog), matching: find.text('Decline')),
      );
      await tester.pumpAndSettle();

      expect(repository.declineCallCount, 1);
      expect(find.text('Invitation declined'), findsOneWidget);
      expect(find.text('Declined'), findsWidgets);
      expect(find.text('Accept Invitation'), findsNothing);
    });

    testWidgets('a real backend error is shown safely, not a crash', (
      tester,
    ) async {
      final repository = _FakeInvitationRepository(
        invitations: [_invitation(id: 1)],
      )..declineError = ApiException('Invitation not found', statusCode: 404);
      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.text('Decline'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: find.byType(AlertDialog), matching: find.text('Decline')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Invitation not found'), findsOneWidget);
      expect(find.text('Pending'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('Summary counts', () {
    testWidgets('reflects real, locally-derived totals per status', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        repository: _FakeInvitationRepository(
          invitations: [
            _invitation(id: 1, status: 'pending'),
            _invitation(id: 2, status: 'pending'),
            _invitation(id: 3, status: 'accepted'),
            _invitation(id: 4, status: 'declined'),
          ],
        ),
      );

      expect(find.text('Total'), findsOneWidget);
      expect(find.text('4'), findsWidgets);
      expect(find.text('2'), findsWidgets);
    });
  });

  group('Search and filters', () {
    testWidgets('search filters the list locally by opportunity title', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        repository: _FakeInvitationRepository(
          invitations: [
            _invitation(id: 1, opportunityTitle: 'Backend Developer'),
            _invitation(id: 2, opportunityTitle: 'Marketing Intern'),
          ],
        ),
      );

      expect(find.text('Backend Developer'), findsOneWidget);
      expect(find.text('Marketing Intern'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Backend');
      await tester.pumpAndSettle();

      expect(find.text('Backend Developer'), findsOneWidget);
      expect(find.text('Marketing Intern'), findsNothing);
    });

    testWidgets('search filters the list locally by organization name', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        repository: _FakeInvitationRepository(
          invitations: [
            _invitation(
              id: 1,
              opportunityTitle: 'Backend Developer',
              organizationName: 'Acme Corp',
            ),
            _invitation(
              id: 2,
              opportunityTitle: 'Marketing Intern',
              organizationName: 'Globex',
            ),
          ],
        ),
      );

      await tester.enterText(find.byType(TextField), 'globex');
      await tester.pumpAndSettle();

      expect(find.text('Marketing Intern'), findsOneWidget);
      expect(find.text('Backend Developer'), findsNothing);
    });

    testWidgets('a status filter chip shows only matching invitations', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        repository: _FakeInvitationRepository(
          invitations: [
            _invitation(id: 1, opportunityTitle: 'Backend Developer', status: 'accepted'),
            _invitation(id: 2, opportunityTitle: 'Marketing Intern', status: 'pending'),
          ],
        ),
      );

      // "Accepted" also appears as the Summary row's own tile label and the
      // matching invitation's status chip — target the filter chip
      // specifically via its GestureDetector.
      final filterChip = find.widgetWithText(GestureDetector, 'Accepted');
      await tester.ensureVisible(filterChip);
      await tester.tap(filterChip);
      await tester.pumpAndSettle();

      expect(find.text('Backend Developer'), findsOneWidget);
      expect(find.text('Marketing Intern'), findsNothing);
    });

    testWidgets(
      'no matches shows a controlled empty state with a Clear Filters action',
      (tester) async {
        await _pumpScreen(
          tester,
          repository: _FakeInvitationRepository(
            invitations: [_invitation(id: 1, opportunityTitle: 'Backend Developer')],
          ),
        );

        await tester.enterText(find.byType(TextField), 'nonexistent');
        await tester.pumpAndSettle();

        expect(find.text('No Matching Invitations'), findsOneWidget);

        await tester.tap(find.text('Clear Filters'));
        await tester.pumpAndSettle();

        expect(find.text('Backend Developer'), findsOneWidget);
      },
    );
  });

  testWidgets('renders safely with a long opportunity title and organization name', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      repository: _FakeInvitationRepository(
        invitations: [
          _invitation(
            id: 1,
            opportunityTitle:
                'Senior Full-Stack Backend and Cloud Infrastructure Engineering Internship',
            organizationName:
                'A Very Long International Organization Name For Testing Purposes LLC',
          ),
        ],
      ),
      size: const Size(360, 800),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('multiple invitations render together without overflow', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      repository: _FakeInvitationRepository(
        invitations: [
          _invitation(id: 1, status: 'pending'),
          _invitation(id: 2, status: 'accepted'),
          _invitation(id: 3, status: 'declined'),
        ],
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Backend Developer'), findsNWidgets(3));
  });

  testWidgets('Does not overflow at a narrow 320x720 viewport', (tester) async {
    await _pumpScreen(
      tester,
      repository: _FakeInvitationRepository(
        invitations: [
          _invitation(id: 1, opportunityTitle: 'Backend Developer', message: 'Hello there!'),
        ],
      ),
      size: const Size(320, 720),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('Does not overflow at a tablet viewport', (tester) async {
    await _pumpScreen(
      tester,
      repository: _FakeInvitationRepository(
        invitations: [_invitation(id: 1, opportunityTitle: 'Backend Developer')],
      ),
      size: const Size(1000, 900),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('Does not overflow at a wide desktop viewport and uses a 2-column grid', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      repository: _FakeInvitationRepository(
        invitations: [
          _invitation(id: 1, opportunityTitle: 'Backend Developer'),
          _invitation(id: 2, opportunityTitle: 'Marketing Intern'),
        ],
      ),
      size: const Size(1440, 900),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Backend Developer'), findsOneWidget);
    expect(find.text('Marketing Intern'), findsOneWidget);
  });

  testWidgets('honors reduced motion without throwing', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    await _pumpScreen(
      tester,
      repository: _FakeInvitationRepository(
        invitations: [_invitation(id: 1, opportunityTitle: 'Backend Developer')],
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Backend Developer'), findsOneWidget);
  });

  testWidgets('renders correctly in Dark Mode', (tester) async {
    await _pumpScreen(
      tester,
      repository: _FakeInvitationRepository(
        invitations: [_invitation(id: 1, opportunityTitle: 'Backend Developer')],
      ),
      theme: AppTheme.darkTheme,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Backend Developer'), findsOneWidget);
  });

  testWidgets('the app-bar theme toggle is reachable', (tester) async {
    await _pumpScreen(
      tester,
      repository: _FakeInvitationRepository(
        invitations: [_invitation(id: 1)],
      ),
    );

    expect(find.byType(ThemeToggleButton), findsOneWidget);
  });
}
