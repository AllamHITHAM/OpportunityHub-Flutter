// Widget tests for OrganizationCandidateProfileScreen and the
// CandidateProfileView adapter, in isolation (no real network).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:opportunityhub_flutter/core/theme/app_colors.dart';
import 'package:opportunityhub_flutter/core/theme/app_theme.dart';
import 'package:opportunityhub_flutter/core/widgets/app_widgets.dart';
import 'package:opportunityhub_flutter/core/storage/theme_preference_storage.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/features/applications/data/application_repository.dart';
import 'package:opportunityhub_flutter/features/candidates/presentation/organization_candidate_profile_screen.dart';
import 'package:opportunityhub_flutter/features/messaging/data/conversation_repository.dart';
import 'package:opportunityhub_flutter/models/candidate_model.dart';
import 'package:opportunityhub_flutter/models/candidate_skill_model.dart';
import 'package:opportunityhub_flutter/models/location_model.dart';
import 'package:opportunityhub_flutter/models/recommended_candidate_model.dart';
import 'package:opportunityhub_flutter/providers/auth_provider.dart';
import 'package:opportunityhub_flutter/providers/conversations_provider.dart';
import 'package:opportunityhub_flutter/providers/organization_applications_provider.dart';
import 'package:opportunityhub_flutter/providers/theme_provider.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';

class _FakeThemePreferenceStorage extends ThemePreferenceStorage {
  ThemeMode? saved;

  @override
  Future<void> saveThemeMode(ThemeMode mode) async {
    saved = mode;
  }

  @override
  Future<ThemeMode> readThemeMode() async => saved ?? ThemeMode.system;
}

CandidateModel _candidateModel({
  int id = 1,
  String name = 'Omar Hassan',
  String? major = 'Computer Science',
  String? university = 'State University',
  int? graduationYear = 2026,
  String? bio,
  String educationVerificationStatus = 'verified',
  LocationModel? currentLocation,
  List<LocationModel> availableLocations = const [],
  List<CandidateSkillModel> skills = const [
    CandidateSkillModel(name: 'PHP', source: 'manual'),
  ],
  int? applicationId,
  String? phone,
  String? email,
}) {
  return CandidateModel(
    id: id,
    name: name,
    university: university,
    major: major,
    graduationYear: graduationYear,
    bio: bio,
    educationVerificationStatus: educationVerificationStatus,
    currentLocation: currentLocation,
    availableLocations: availableLocations,
    skills: skills,
    applicationId: applicationId,
    phone: phone,
    email: email,
  );
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  CandidateProfileView? candidate,
  Size size = const Size(420, 900),
}) async {
  addTearDown(() => AppColors.updateBrightness(Brightness.light));

  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final themeProvider = ThemeProvider(storage: _FakeThemePreferenceStorage());
  await themeProvider.initialize();

  final tokenStorage = TokenStorageService();
  final apiClient = ApiClient(tokenStorageService: tokenStorage);
  // `AuthProvider.initialize()` is deliberately never called here -- these
  // widget tests never touch platform-channel secure storage.
  final authProvider = AuthProvider(
    authRepository: AuthRepository(
      apiClient: apiClient,
      tokenStorageService: tokenStorage,
    ),
  );

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        Provider<ApplicationRepository>(
          create: (_) => ApplicationRepository(apiClient: apiClient),
        ),
        ChangeNotifierProxyProvider<AuthProvider, OrganizationApplicationsProvider>(
          create: (context) => OrganizationApplicationsProvider(
            repository: context.read<ApplicationRepository>(),
            authProvider: authProvider,
          ),
          update: (_, _, previous) => previous!,
        ),
        Provider<ConversationRepository>(
          create: (_) => ConversationRepository(apiClient: apiClient),
        ),
        ChangeNotifierProxyProvider<AuthProvider, ConversationsProvider>(
          create: (context) => ConversationsProvider(
            repository: context.read<ConversationRepository>(),
            authProvider: authProvider,
          ),
          update: (_, _, previous) => previous!,
        ),
      ],
      child: Builder(
        builder: (context) {
          final mode = context.watch<ThemeProvider>().mode;
          return MaterialApp(
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: mode,
            home: OrganizationCandidateProfileScreen(candidate: candidate),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders the candidate\'s real name, university, major, and '
      'graduation year', (tester) async {
    await _pumpScreen(
      tester,
      candidate: CandidateProfileView.fromCandidate(
        _candidateModel(
          name: 'Omar Hassan',
          university: 'State University',
          major: 'Computer Science',
          graduationYear: 2026,
        ),
      ),
    );

    expect(find.text('Omar Hassan'), findsOneWidget);
    expect(find.textContaining('State University'), findsWidgets);
    expect(find.textContaining('Computer Science'), findsWidgets);
    expect(find.textContaining('2026'), findsWidgets);
  });

  testWidgets('shows the real bio when present', (tester) async {
    await _pumpScreen(
      tester,
      candidate: CandidateProfileView.fromCandidate(
        _candidateModel(bio: 'Passionate backend engineer.'),
      ),
    );

    expect(find.text('Passionate backend engineer.'), findsOneWidget);
  });

  testWidgets('omits the Bio line entirely when bio is missing', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      candidate: CandidateProfileView.fromCandidate(_candidateModel(bio: null)),
    );

    expect(find.text('Bio'), findsNothing);
  });

  testWidgets('shows real canonical Location & Work Availability, with '
      'truthful fallbacks when missing', (tester) async {
    await _pumpScreen(
      tester,
      candidate: CandidateProfileView.fromCandidate(_candidateModel()),
    );

    expect(find.text('Location & Work Availability'), findsOneWidget);
    expect(find.text('Not provided'), findsOneWidget);
    expect(find.text('No work locations provided'), findsOneWidget);
  });

  testWidgets('shows real canonical location names, never raw IDs', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      candidate: CandidateProfileView.fromCandidate(
        _candidateModel(
          currentLocation: const LocationModel(id: 1, canonicalName: 'Ramallah'),
          availableLocations: const [
            LocationModel(id: 2, canonicalName: 'Nablus'),
            LocationModel(id: 3, canonicalName: 'Hebron'),
          ],
        ),
      ),
    );

    expect(find.text('Ramallah'), findsOneWidget);
    expect(find.text('Nablus'), findsOneWidget);
    expect(find.text('Hebron'), findsOneWidget);
  });

  testWidgets('shows the real Education Verification status, never a bare '
      'chip', (tester) async {
    await _pumpScreen(
      tester,
      candidate: CandidateProfileView.fromCandidate(
        _candidateModel(educationVerificationStatus: 'not_submitted'),
      ),
    );

    expect(find.text('Education Verification'), findsOneWidget);
    expect(find.text('Not Submitted'), findsOneWidget);
  });

  testWidgets('shows every real skill with its evidence label', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      candidate: CandidateProfileView.fromCandidate(
        _candidateModel(
          skills: const [
            CandidateSkillModel(name: 'PHP', source: 'manual'),
            CandidateSkillModel(name: 'Laravel', source: 'cv_ai'),
          ],
        ),
      ),
    );

    expect(find.textContaining('PHP'), findsOneWidget);
    expect(find.textContaining('Laravel'), findsOneWidget);
  });

  testWidgets('never shows a match score, CV, or Contact section from a '
      'Talent Directory (no Opportunity context) visit', (tester) async {
    await _pumpScreen(
      tester,
      candidate: CandidateProfileView.fromCandidate(_candidateModel()),
    );

    expect(find.textContaining('Match'), findsNothing);
    expect(find.text('CV'), findsNothing);
    expect(find.text('Contact'), findsNothing);
    expect(find.text('Message Candidate'), findsNothing);
  });

  testWidgets('shows CV and Contact only when a real applicationId is '
      'present (already-applied gate)', (tester) async {
    await _pumpScreen(
      tester,
      candidate: CandidateProfileView.fromCandidate(
        _candidateModel(
          applicationId: 42,
          phone: '555-1234',
          email: 'omar@example.com',
        ),
      ),
    );

    expect(find.text('CV'), findsOneWidget);
    expect(find.text('View CV'), findsOneWidget);
    expect(find.text('Contact'), findsOneWidget);
    expect(find.text('555-1234'), findsOneWidget);
    expect(find.text('omar@example.com'), findsOneWidget);
  });

  testWidgets('a null candidate (missing extra, e.g. a direct URL visit) '
      'renders a graceful empty state instead of crashing', (tester) async {
    await _pumpScreen(tester, candidate: null);

    expect(find.text('Candidate Not Found'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('CandidateProfileView.fromRecommended carries the same real '
      'fields as fromCandidate, with no fabricated data', (tester) async {
    const recommended = RecommendedCandidateModel(
      id: 9,
      name: 'Layla Kareem',
      university: 'Tech University',
      major: 'Software Engineering',
      graduationYear: 2027,
      bio: null,
      educationVerificationStatus: 'verified',
      currentLocation: null,
      availableLocations: [],
      skills: [CandidateSkillModel(name: 'Dart', source: 'manual')],
      matchScore: 88,
      alreadyApplied: false,
    );

    await _pumpScreen(
      tester,
      candidate: CandidateProfileView.fromRecommended(
        recommended,
        opportunityId: 42,
        opportunityTitle: 'Backend Developer',
      ),
    );

    expect(find.text('Layla Kareem'), findsOneWidget);
    expect(find.textContaining('Tech University'), findsWidgets);
    expect(find.textContaining('Dart'), findsOneWidget);
  });

  testWidgets('with a real Opportunity context, shows "Recommended for" '
      'and the real Match score plus a Message Candidate action', (
    tester,
  ) async {
    const recommended = RecommendedCandidateModel(
      id: 9,
      name: 'Layla Kareem',
      university: 'Tech University',
      major: 'Software Engineering',
      graduationYear: 2027,
      bio: null,
      educationVerificationStatus: 'verified',
      currentLocation: null,
      availableLocations: [],
      skills: [CandidateSkillModel(name: 'Dart', source: 'manual')],
      matchScore: 88,
      alreadyApplied: false,
    );

    await _pumpScreen(
      tester,
      candidate: CandidateProfileView.fromRecommended(
        recommended,
        opportunityId: 42,
        opportunityTitle: 'Backend Developer',
      ),
    );

    expect(find.textContaining('Recommended for Backend Developer'), findsOneWidget);
    expect(find.textContaining('Match 88%'), findsOneWidget);
    expect(find.text('Message Candidate'), findsOneWidget);
  });

  testWidgets('the theme toggle is present in the AppBar', (tester) async {
    await _pumpScreen(
      tester,
      candidate: CandidateProfileView.fromCandidate(_candidateModel()),
    );

    expect(find.byType(ThemeToggleButton), findsOneWidget);
  });

  group('responsive layout', () {
    for (final width in [375.0, 390.0, 430.0]) {
      testWidgets('mobile ${width.toInt()} renders with no overflow', (
        tester,
      ) async {
        await _pumpScreen(
          tester,
          candidate: CandidateProfileView.fromCandidate(
            _candidateModel(
              name: 'Omar Abdulrahman Hassan Al-Farouq',
              major: 'Computer Science and Software Engineering',
              university:
                  'The National University of Science, Technology, and '
                  'Advanced Engineering',
              bio:
                  'A very long bio describing extensive backend, frontend, '
                  'and DevOps experience across many different projects.',
              currentLocation: const LocationModel(
                id: 1,
                canonicalName: 'Ramallah',
              ),
              availableLocations: const [
                LocationModel(id: 2, canonicalName: 'Nablus'),
                LocationModel(id: 3, canonicalName: 'Hebron'),
              ],
              applicationId: 42,
              phone: '555-1234',
              email: 'omar.abdulrahman.hassan@example.com',
            ),
          ),
          size: Size(width, 900),
        );

        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('desktop (1000x900) renders with no overflow', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        candidate: CandidateProfileView.fromCandidate(_candidateModel()),
        size: const Size(1000, 900),
      );

      expect(tester.takeException(), isNull);
    });
  });

  group('light/dark theme', () {
    testWidgets('renders in dark mode with no overflow', (tester) async {
      AppColors.updateBrightness(Brightness.dark);
      addTearDown(() => AppColors.updateBrightness(Brightness.light));

      await _pumpScreen(
        tester,
        candidate: CandidateProfileView.fromCandidate(
          _candidateModel(applicationId: 42, phone: '555-1234'),
        ),
      );

      expect(tester.takeException(), isNull);
    });
  });
}
