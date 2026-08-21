// Widget tests for StudentInvitationsScreen, in isolation with a small
// GoRouter (for the Accept navigation) and fake repositories.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/core/theme/app_theme.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/features/invitations/data/invitation_repository.dart';
import 'package:opportunityhub_flutter/features/invitations/presentation/student_invitations_screen.dart';
import 'package:opportunityhub_flutter/models/invitation_model.dart';
import 'package:opportunityhub_flutter/providers/auth_provider.dart';
import 'package:opportunityhub_flutter/providers/student_invitations_provider.dart';
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
  String? message,
}) {
  return InvitationModel(
    id: id,
    opportunityId: opportunityId,
    status: status,
    opportunityTitle: 'Backend Developer',
    organizationName: 'Hiring Co',
    message: message,
  );
}

class _FakeInvitationRepository extends InvitationRepository {
  _FakeInvitationRepository({this.invitations = const []})
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  List<InvitationModel> invitations;
  ApiException? listError;
  ApiException? acceptError;
  ApiException? declineError;
  int acceptCallCount = 0;
  int declineCallCount = 0;

  @override
  Future<List<InvitationModel>> getInvitations() async {
    if (listError != null) throw listError!;
    return invitations;
  }

  @override
  Future<void> acceptInvitation(int invitationId) async {
    acceptCallCount++;
    if (acceptError != null) throw acceptError!;
    invitations = [
      for (final invitation in invitations)
        if (invitation.id == invitationId)
          _invitation(
            id: invitation.id,
            opportunityId: invitation.opportunityId,
            status: 'accepted',
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
          )
        else
          invitation,
    ];
  }
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required _FakeInvitationRepository repository,
}) async {
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
    ],
  );

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ChangeNotifierProvider<StudentInvitationsProvider>.value(
          value: provider,
        ),
      ],
      child: MaterialApp.router(
        theme: AppTheme.lightTheme,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Shows an empty state when there are no invitations', (
    tester,
  ) async {
    await _pumpScreen(tester, repository: _FakeInvitationRepository());

    expect(find.text('No Invitations Yet'), findsOneWidget);
  });

  testWidgets('Shows an error view on failure', (tester) async {
    final repository = _FakeInvitationRepository()
      ..listError = ApiException('Server error.');
    await _pumpScreen(tester, repository: repository);

    expect(find.text('Server error.'), findsOneWidget);
  });

  testWidgets('Lists organization, opportunity, message and status', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      repository: _FakeInvitationRepository(
        invitations: [_invitation(message: 'Please apply!')],
      ),
    );

    expect(find.text('Backend Developer'), findsOneWidget);
    expect(find.text('Hiring Co'), findsOneWidget);
    expect(find.text('Please apply!'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
  });

  testWidgets('Accepted/declined invitations show no action buttons', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      repository: _FakeInvitationRepository(
        invitations: [_invitation(id: 1, status: 'accepted')],
      ),
    );

    expect(find.text('Accepted'), findsOneWidget);
    expect(find.text('Accept'), findsNothing);
    expect(find.text('Decline'), findsNothing);
  });

  testWidgets(
    'Accepting navigates to the opportunity details/Apply flow',
    (tester) async {
      final repository = _FakeInvitationRepository(
        invitations: [_invitation(id: 1, opportunityId: 5)],
      );
      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.text('Accept'));
      await tester.pumpAndSettle();

      expect(repository.acceptCallCount, 1);
      expect(find.text('OPPORTUNITY_5'), findsOneWidget);
    },
  );

  testWidgets('Declining shows a confirmation and updates the status', (
    tester,
  ) async {
    final repository = _FakeInvitationRepository(
      invitations: [_invitation(id: 1)],
    );
    await _pumpScreen(tester, repository: repository);

    await tester.tap(find.text('Decline'));
    await tester.pumpAndSettle();

    expect(repository.declineCallCount, 1);
    expect(find.text('Invitation declined'), findsOneWidget);
    expect(find.text('Declined'), findsOneWidget);
  });

  testWidgets('A repeated-response error is shown safely, not a crash', (
    tester,
  ) async {
    final repository = _FakeInvitationRepository(
      invitations: [_invitation(id: 1)],
    )..acceptError = ApiException(
      'This invitation has already been responded to',
      statusCode: 409,
    );
    await _pumpScreen(tester, repository: repository);

    await tester.tap(find.text('Accept'));
    await tester.pumpAndSettle();

    expect(
      find.text('This invitation has already been responded to'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
