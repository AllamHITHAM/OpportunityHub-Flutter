// Widget tests for CompanyProfileScreen (Organization Public Profile
// phase), in isolation with fake repositories (no real network).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/api/paginated_result.dart';
import 'package:opportunityhub_flutter/core/storage/theme_preference_storage.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/core/theme/app_colors.dart';
import 'package:opportunityhub_flutter/core/theme/app_theme.dart';
import 'package:opportunityhub_flutter/core/widgets/app_avatar.dart';
import 'package:opportunityhub_flutter/core/widgets/danger_button.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/features/opportunities/data/opportunity_repository.dart';
import 'package:opportunityhub_flutter/features/organization/data/organization_profile_repository.dart';
import 'package:opportunityhub_flutter/features/organization_profile/presentation/company_profile_screen.dart';
import 'package:opportunityhub_flutter/models/opportunity_model.dart';
import 'package:opportunityhub_flutter/models/organization_post_model.dart';
import 'package:opportunityhub_flutter/models/organization_profile_model.dart';
import 'package:opportunityhub_flutter/models/user_model.dart';
import 'package:opportunityhub_flutter/providers/auth_provider.dart';
import 'package:opportunityhub_flutter/providers/organization_profile_provider.dart';
import 'package:opportunityhub_flutter/providers/organization_public_profile_provider.dart';
import 'package:opportunityhub_flutter/providers/theme_provider.dart';

class _FakeThemePreferenceStorage extends ThemePreferenceStorage {
  ThemeMode? saved;

  @override
  Future<void> saveThemeMode(ThemeMode mode) async {
    saved = mode;
  }

  @override
  Future<ThemeMode> readThemeMode() async => saved ?? ThemeMode.system;
}

OrganizationProfileModel _profile({
  int id = 1,
  String name = 'Acme Corp',
  String? description,
  String? website,
  String? industry,
  String? logoUrl,
}) {
  return OrganizationProfileModel(
    id: id,
    organizationName: name,
    organizationType: 'company',
    approvalStatus: 'approved',
    industry: industry,
    description: description,
    website: website,
    logoUrl: logoUrl,
  );
}

class _FakeOrganizationProfileRepository extends OrganizationProfileRepository {
  _FakeOrganizationProfileRepository({this.profileToReturn, this.postsToReturn = const []})
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  OrganizationProfileModel? profileToReturn;
  List<OrganizationPostModel> postsToReturn;
  ApiException? profileError;

  @override
  Future<OrganizationProfileModel> getPublicProfile(int organizationId) async {
    if (profileError != null) throw profileError!;
    return profileToReturn ?? _profile(id: organizationId);
  }

  @override
  Future<List<OrganizationPostModel>> getPosts(int organizationId) async {
    return postsToReturn;
  }
}

class _FakeOpportunityRepository extends OpportunityRepository {
  _FakeOpportunityRepository({
    this.opportunitiesToReturn = const [],
    this.ownOpportunitiesToReturn = const [],
  }) : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  List<OpportunityModel> opportunitiesToReturn;

  /// Backs [_ClosedOpportunitiesSection] via [getClosedOpportunities] --
  /// the full underlying dataset (any status); this fake filters/sorts/
  /// paginates it the same way the real backend endpoint does, closely
  /// enough to drive meaningful widget-level tests (the exact calendar
  /// boundary math for each date preset is already exhaustively covered
  /// by the backend's own PHP test suite -- this fake only needs to be
  /// "obviously correct" for typical fixture data, not bit-for-bit
  /// identical).
  List<OpportunityModel> ownOpportunitiesToReturn;
  int deleteClosedCallCount = 0;
  int? lastDeletedClosedId;
  ApiException? deleteClosedError;

  int getClosedOpportunitiesCallCount = 0;
  ApiException? closedOpportunitiesError;
  String? lastDatePreset;
  DateTime? lastClosedFrom;
  DateTime? lastClosedTo;
  String? lastSort;
  int? lastPage;

  @override
  Future<PaginatedResult<OpportunityModel>> getPublicOpportunities({
    String? opportunityType,
    String? employmentType,
    String? workMode,
    String? experienceLevel,
    String? location,
    String? fieldOfStudy,
    String? keyword,
    int? organizationId,
    int page = 1,
    int perPage = 15,
  }) async {
    return PaginatedResult(
      items: opportunitiesToReturn,
      currentPage: 1,
      lastPage: 1,
      total: opportunitiesToReturn.length,
    );
  }

  @override
  Future<List<OpportunityModel>> getOpportunities() async {
    return ownOpportunitiesToReturn;
  }

  @override
  Future<({PaginatedResult<OpportunityModel> result, int totalClosed})>
  getClosedOpportunities({
    String? datePreset,
    DateTime? closedFrom,
    DateTime? closedTo,
    String sort = 'newest',
    int page = 1,
    int perPage = 15,
  }) async {
    getClosedOpportunitiesCallCount++;
    lastDatePreset = datePreset;
    lastClosedFrom = closedFrom;
    lastClosedTo = closedTo;
    lastSort = sort;
    lastPage = page;
    if (closedOpportunitiesError != null) throw closedOpportunitiesError!;

    final allClosed = ownOpportunitiesToReturn
        .where((o) => o.status == 'closed')
        .toList();
    final totalClosed = allClosed.length;

    var from = closedFrom;
    var to = closedTo;
    if (from == null && to == null && datePreset != null && datePreset != 'all') {
      final now = DateTime.now();
      switch (datePreset) {
        case 'last_30_days':
          from = now.subtract(const Duration(days: 30));
        case 'last_3_months':
          from = now.subtract(const Duration(days: 90));
        case 'last_6_months':
          from = now.subtract(const Duration(days: 180));
        case 'this_year':
          from = DateTime(now.year);
        case 'older':
          to = DateTime(now.year);
      }
    }

    var filtered = allClosed;
    if (from != null || to != null) {
      filtered = allClosed.where((o) {
        if (datePreset == 'older') {
          return o.closedAt == null || o.closedAt!.isBefore(to!);
        }
        if (o.closedAt == null) return false;
        if (from != null && o.closedAt!.isBefore(from)) return false;
        if (to != null && o.closedAt!.isAfter(to)) return false;
        return true;
      }).toList();
    }

    filtered.sort((a, b) {
      if (a.closedAt == null && b.closedAt == null) return 0;
      if (a.closedAt == null) return 1;
      if (b.closedAt == null) return -1;
      return sort == 'oldest'
          ? a.closedAt!.compareTo(b.closedAt!)
          : b.closedAt!.compareTo(a.closedAt!);
    });

    final filteredTotal = filtered.length;
    final start = (page - 1) * perPage;
    final pageItems = start >= filtered.length
        ? <OpportunityModel>[]
        : filtered.skip(start).take(perPage).toList();
    final lastPageNum = filteredTotal == 0
        ? 1
        : (filteredTotal / perPage).ceil();

    return (
      result: PaginatedResult(
        items: pageItems,
        currentPage: page,
        lastPage: lastPageNum,
        total: filteredTotal,
      ),
      totalClosed: totalClosed,
    );
  }

  @override
  Future<void> deleteClosedOpportunity(int id) async {
    deleteClosedCallCount++;
    lastDeletedClosedId = id;
    if (deleteClosedError != null) throw deleteClosedError!;
  }
}

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository()
    : super(
        apiClient: ApiClient(tokenStorageService: TokenStorageService()),
        tokenStorageService: TokenStorageService(),
      );

  @override
  Future<String?> getSavedToken() async => null;
}

OpportunityModel _opportunity({
  int id = 1,
  String title = 'Backend Developer',
  String status = 'open',
  bool canDelete = false,
  DateTime? closedAt,
}) {
  return OpportunityModel(
    id: id,
    title: title,
    description: 'Great role.',
    opportunityType: 'job',
    employmentType: 'full_time',
    workMode: 'remote',
    experienceLevel: 'junior',
    positionsAvailable: 1,
    status: status,
    canDelete: canDelete,
    closedAt: closedAt,
  );
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required int organizationId,
  _FakeOrganizationProfileRepository? profileRepository,
  _FakeOpportunityRepository? opportunityRepository,
  UserModel? signedInUser,
  int? ownOrganizationId,
  Size size = const Size(420, 1000),
  bool settle = true,
}) async {
  addTearDown(() => AppColors.updateBrightness(Brightness.light));

  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final themeProvider = ThemeProvider(storage: _FakeThemePreferenceStorage());
  await themeProvider.initialize();

  final authProvider = AuthProvider(authRepository: _FakeAuthRepository());
  authProvider.user = signedInUser;

  final ownProfileRepository = _FakeOrganizationProfileRepository(
    profileToReturn: ownOrganizationId == null
        ? null
        : _profile(id: ownOrganizationId),
  );
  final ownProfileProvider = OrganizationProfileProvider(
    repository: ownProfileRepository,
    authProvider: authProvider,
  );
  if (ownOrganizationId != null) {
    ownProfileProvider.profile = _profile(id: ownOrganizationId);
  }

  final publicProfileProvider = OrganizationPublicProfileProvider(
    repository: profileRepository ?? _FakeOrganizationProfileRepository(),
    opportunityRepository: opportunityRepository ?? _FakeOpportunityRepository(),
  );

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ChangeNotifierProvider<OrganizationProfileProvider>.value(
          value: ownProfileProvider,
        ),
        ChangeNotifierProvider<OrganizationPublicProfileProvider>.value(
          value: publicProfileProvider,
        ),
      ],
      child: Builder(
        builder: (context) {
          final mode = context.watch<ThemeProvider>().mode;
          return MaterialApp(
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: mode,
            home: CompanyProfileScreen(organizationId: organizationId),
          );
        },
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

/// Scrolls [finder] into view before tapping it -- several of these tests
/// pump a realistically narrow/short viewport with a long scrollable
/// profile (many opportunities, or an opened accordion), so the naive
/// `tester.tap(find...)` can otherwise land outside the visible viewport.
Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows a loading state before the profile arrives', (
    tester,
  ) async {
    await _pumpScreen(tester, organizationId: 1, settle: false);

    // Before the post-frame load resolves, a skeleton is shown rather
    // than a blank/not-found screen.
    expect(find.text('Company Not Found'), findsNothing);
  });

  testWidgets('shows a retryable error when the profile fails to load', (
    tester,
  ) async {
    final repository = _FakeOrganizationProfileRepository();
    repository.profileError = ApiException('Something went wrong');

    await _pumpScreen(
      tester,
      organizationId: 1,
      profileRepository: repository,
    );

    expect(find.text('Something went wrong'), findsOneWidget);
    expect(find.text('Try Again'), findsOneWidget);
  });

  testWidgets('renders the real profile fields for a public (Student) viewer', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      organizationId: 1,
      profileRepository: _FakeOrganizationProfileRepository(
        profileToReturn: _profile(
          name: 'Acme Corp',
          description: 'We build great things.',
          industry: 'Software',
        ),
      ),
    );

    expect(find.text('Acme Corp'), findsOneWidget);
    expect(find.text('We build great things.'), findsOneWidget);
    expect(find.textContaining('Software'), findsWidgets);
  });

  testWidgets('shows Edit Profile and Create Update only for the owner', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      organizationId: 1,
      signedInUser: const UserModel(
        id: 1,
        name: 'Acme Owner',
        email: 'owner@acme.example.com',
        role: 'organization',
        status: 'active',
      ),
      ownOrganizationId: 1,
      profileRepository: _FakeOrganizationProfileRepository(
        profileToReturn: _profile(id: 1),
      ),
    );

    expect(find.text('Edit Profile'), findsOneWidget);
    expect(find.text('Create Update'), findsOneWidget);
  });

  testWidgets('never shows owner controls for a non-owner (Student) viewer', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      organizationId: 1,
      signedInUser: const UserModel(
        id: 2,
        name: 'A Student',
        email: 'student@example.com',
        role: 'student',
        status: 'active',
      ),
      profileRepository: _FakeOrganizationProfileRepository(
        profileToReturn: _profile(id: 1),
      ),
    );

    expect(find.text('Edit Profile'), findsNothing);
    expect(find.text('Create Update'), findsNothing);
  });

  testWidgets('shows restrained empty states for missing optional data', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      organizationId: 1,
      profileRepository: _FakeOrganizationProfileRepository(
        profileToReturn: _profile(id: 1),
      ),
    );

    expect(
      find.text('This organization hasn\'t added a description yet.'),
      findsOneWidget,
    );
    expect(find.text('No open opportunities right now.'), findsOneWidget);
    expect(find.text('No updates published yet.'), findsOneWidget);
  });

  testWidgets('owner sees an owner-specific empty About message', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      organizationId: 1,
      signedInUser: const UserModel(
        id: 1,
        name: 'Acme Owner',
        email: 'owner@acme.example.com',
        role: 'organization',
        status: 'active',
      ),
      ownOrganizationId: 1,
      profileRepository: _FakeOrganizationProfileRepository(
        profileToReturn: _profile(id: 1),
      ),
    );

    expect(find.text('Share your first company update.'), findsOneWidget);
  });

  testWidgets('shows real open opportunities', (tester) async {
    await _pumpScreen(
      tester,
      organizationId: 1,
      profileRepository: _FakeOrganizationProfileRepository(
        profileToReturn: _profile(id: 1),
      ),
      opportunityRepository: _FakeOpportunityRepository(
        opportunitiesToReturn: [_opportunity(id: 1, title: 'Backend Developer')],
      ),
    );

    expect(find.text('Backend Developer'), findsOneWidget);
  });

  testWidgets('shows real posts newest first as returned by the backend', (
    tester,
  ) async {
    final now = DateTime.now();
    await _pumpScreen(
      tester,
      organizationId: 1,
      profileRepository: _FakeOrganizationProfileRepository(
        profileToReturn: _profile(id: 1),
        postsToReturn: [
          OrganizationPostModel(
            id: 1,
            organizationId: 1,
            title: 'Summer Internship',
            body: 'Applications are now open.',
            createdAt: now,
          ),
        ],
      ),
    );

    expect(find.text('Summer Internship'), findsOneWidget);
    expect(find.text('Applications are now open.'), findsOneWidget);
  });

  group('responsive layout', () {
    for (final width in [375.0, 390.0, 430.0]) {
      testWidgets('mobile ${width.toInt()} renders with no overflow', (
        tester,
      ) async {
        await _pumpScreen(
          tester,
          organizationId: 1,
          profileRepository: _FakeOrganizationProfileRepository(
            profileToReturn: _profile(
              name: 'A Very Long Organization Name For Testing Wrapping',
              description:
                  'A long description that should wrap correctly across '
                  'multiple lines on a narrow mobile viewport without '
                  'ever overflowing horizontally.',
              industry: 'Software Engineering And Cloud Infrastructure',
            ),
          ),
          opportunityRepository: _FakeOpportunityRepository(
            opportunitiesToReturn: [
              _opportunity(id: 1, title: 'A Very Long Opportunity Title For Testing'),
            ],
          ),
          size: Size(width, 1000),
        );

        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('desktop (1200x900) renders with no overflow', (tester) async {
      await _pumpScreen(
        tester,
        organizationId: 1,
        profileRepository: _FakeOrganizationProfileRepository(
          profileToReturn: _profile(id: 1),
        ),
        size: const Size(1200, 900),
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
        organizationId: 1,
        profileRepository: _FakeOrganizationProfileRepository(
          profileToReturn: _profile(id: 1),
        ),
      );

      expect(tester.takeException(), isNull);
    });
  });

  group('Open Opportunities accordion (Company Profile Polish)', () {
    const ownerUser = UserModel(
      id: 1,
      name: 'Acme Owner',
      email: 'owner@acme.example.com',
      role: 'organization',
      status: 'active',
    );

    testWidgets('4 or fewer opportunities never shows View all', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        organizationId: 1,
        profileRepository: _FakeOrganizationProfileRepository(
          profileToReturn: _profile(id: 1),
        ),
        opportunityRepository: _FakeOpportunityRepository(
          opportunitiesToReturn: [
            _opportunity(id: 1, title: 'Role One'),
            _opportunity(id: 2, title: 'Role Two'),
            _opportunity(id: 3, title: 'Role Three'),
            _opportunity(id: 4, title: 'Role Four'),
          ],
        ),
      );

      expect(find.text('Open Opportunities (4)'), findsOneWidget);
      expect(find.text('Role One'), findsOneWidget);
      expect(find.text('Role Four'), findsOneWidget);
      expect(find.textContaining('View all'), findsNothing);
    });

    testWidgets('more than 4 caps at 4 with View all, then Show less', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        organizationId: 1,
        profileRepository: _FakeOrganizationProfileRepository(
          profileToReturn: _profile(id: 1),
        ),
        opportunityRepository: _FakeOpportunityRepository(
          opportunitiesToReturn: List.generate(
            20,
            (i) => _opportunity(id: i + 1, title: 'Role ${i + 1}'),
          ),
        ),
      );

      expect(find.text('Open Opportunities (20)'), findsOneWidget);
      expect(find.text('Role 1'), findsOneWidget);
      expect(find.text('Role 4'), findsOneWidget);
      expect(find.text('Role 5'), findsNothing);
      expect(find.text('View all 20'), findsOneWidget);

      await _tapVisible(tester, find.text('View all 20'));

      expect(find.text('Role 5'), findsOneWidget);
      expect(find.text('Role 20'), findsOneWidget);
      expect(find.text('Show less'), findsOneWidget);

      await _tapVisible(tester, find.text('Show less'));

      expect(find.text('Role 5'), findsNothing);
      expect(find.text('View all 20'), findsOneWidget);
    });

    testWidgets('the whole section collapses and re-expands', (tester) async {
      await _pumpScreen(
        tester,
        organizationId: 1,
        profileRepository: _FakeOrganizationProfileRepository(
          profileToReturn: _profile(id: 1),
        ),
        opportunityRepository: _FakeOpportunityRepository(
          opportunitiesToReturn: [_opportunity(id: 1, title: 'Role One')],
        ),
      );

      expect(find.text('Role One'), findsOneWidget);

      await _tapVisible(tester, find.text('Open Opportunities (1)'));

      expect(find.text('Role One'), findsNothing);

      await _tapVisible(tester, find.text('Open Opportunities (1)'));

      expect(find.text('Role One'), findsOneWidget);
    });

    testWidgets('renders correctly with 0 open opportunities', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        organizationId: 1,
        profileRepository: _FakeOrganizationProfileRepository(
          profileToReturn: _profile(id: 1),
        ),
      );
      expect(find.text('Open Opportunities (0)'), findsOneWidget);
      expect(find.text('No open opportunities right now.'), findsOneWidget);
    });

    testWidgets('renders correctly with 5 open opportunities', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        organizationId: 2,
        profileRepository: _FakeOrganizationProfileRepository(
          profileToReturn: _profile(id: 2),
        ),
        opportunityRepository: _FakeOpportunityRepository(
          opportunitiesToReturn: List.generate(
            5,
            (i) => _opportunity(id: i + 1, title: 'Role ${i + 1}'),
          ),
        ),
      );
      expect(find.text('Open Opportunities (5)'), findsOneWidget);
      expect(find.text('View all 5'), findsOneWidget);
    });

    testWidgets('a signed-in owner never sees Closed Opportunities on a '
        'different organization\'s profile', (tester) async {
      await _pumpScreen(
        tester,
        organizationId: 2,
        signedInUser: ownerUser,
        ownOrganizationId: 1,
        profileRepository: _FakeOrganizationProfileRepository(
          profileToReturn: _profile(id: 2),
        ),
      );

      expect(find.textContaining('Closed Opportunities'), findsNothing);
    });
  });

  group('Closed Opportunities (Company Profile Polish)', () {
    const ownerUser = UserModel(
      id: 1,
      name: 'Acme Owner',
      email: 'owner@acme.example.com',
      role: 'organization',
      status: 'active',
    );

    testWidgets('is owner-only -- never shown to a public/Student viewer', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        organizationId: 1,
        profileRepository: _FakeOrganizationProfileRepository(
          profileToReturn: _profile(id: 1),
        ),
        opportunityRepository: _FakeOpportunityRepository(
          ownOpportunitiesToReturn: [
            _opportunity(id: 9, title: 'Old Role', status: 'closed'),
          ],
        ),
      );

      expect(find.textContaining('Closed Opportunities'), findsNothing);
      expect(find.text('Old Role'), findsNothing);
    });

    testWidgets('shows collapsed by default for the owner', (tester) async {
      await _pumpScreen(
        tester,
        organizationId: 1,
        signedInUser: ownerUser,
        ownOrganizationId: 1,
        profileRepository: _FakeOrganizationProfileRepository(
          profileToReturn: _profile(id: 1),
        ),
        opportunityRepository: _FakeOpportunityRepository(
          ownOpportunitiesToReturn: [
            _opportunity(id: 9, title: 'Old Role', status: 'closed'),
          ],
        ),
      );

      expect(find.text('Closed Opportunities (1)'), findsOneWidget);
      expect(find.text('Old Role'), findsNothing);

      await _tapVisible(tester, find.text('Closed Opportunities (1)'));

      expect(find.text('Old Role'), findsOneWidget);
    });

    testWidgets('client-side filters out open/draft rows, keeping only '
        'closed', (tester) async {
      await _pumpScreen(
        tester,
        organizationId: 1,
        signedInUser: ownerUser,
        ownOrganizationId: 1,
        profileRepository: _FakeOrganizationProfileRepository(
          profileToReturn: _profile(id: 1),
        ),
        opportunityRepository: _FakeOpportunityRepository(
          ownOpportunitiesToReturn: [
            _opportunity(id: 1, title: 'Open Role', status: 'open'),
            _opportunity(id: 2, title: 'Draft Role', status: 'draft'),
            _opportunity(id: 3, title: 'Closed Role A', status: 'closed'),
            _opportunity(id: 4, title: 'Closed Role B', status: 'closed'),
          ],
        ),
      );

      expect(find.text('Closed Opportunities (2)'), findsOneWidget);
    });

    testWidgets('a safe (no-history) closed opportunity can be deleted '
        'after confirmation', (tester) async {
      final opportunityRepository = _FakeOpportunityRepository(
        ownOpportunitiesToReturn: [
          _opportunity(
            id: 9,
            title: 'Disposable Role',
            status: 'closed',
            canDelete: true,
          ),
        ],
      );
      await _pumpScreen(
        tester,
        organizationId: 1,
        signedInUser: ownerUser,
        ownOrganizationId: 1,
        profileRepository: _FakeOrganizationProfileRepository(
          profileToReturn: _profile(id: 1),
        ),
        opportunityRepository: opportunityRepository,
      );

      await _tapVisible(tester, find.text('Closed Opportunities (1)'));

      expect(find.text('Delete Permanently'), findsOneWidget);

      await _tapVisible(tester, find.text('Delete Permanently'));

      expect(find.text('Delete Opportunity?'), findsOneWidget);
      expect(
        find.textContaining('This opportunity has no recruitment history'),
        findsOneWidget,
      );

      await _tapVisible(
        tester,
        find.widgetWithText(DangerButton, 'Delete Permanently'),
      );

      expect(opportunityRepository.deleteClosedCallCount, 1);
      expect(opportunityRepository.lastDeletedClosedId, 9);
      expect(find.text('Disposable Role'), findsNothing);
    });

    testWidgets('a closed opportunity with recruitment history never shows '
        'an active delete button', (tester) async {
      await _pumpScreen(
        tester,
        organizationId: 1,
        signedInUser: ownerUser,
        ownOrganizationId: 1,
        profileRepository: _FakeOrganizationProfileRepository(
          profileToReturn: _profile(id: 1),
        ),
        opportunityRepository: _FakeOpportunityRepository(
          ownOpportunitiesToReturn: [
            _opportunity(
              id: 9,
              title: 'Protected Role',
              status: 'closed',
              canDelete: false,
            ),
          ],
        ),
      );

      await _tapVisible(tester, find.text('Closed Opportunities (1)'));

      expect(find.text('Delete Permanently'), findsNothing);
      expect(
        find.textContaining('cannot be permanently deleted'),
        findsOneWidget,
      );
    });

    testWidgets('a failed delete keeps the item visible with a real error', (
      tester,
    ) async {
      final opportunityRepository = _FakeOpportunityRepository(
        ownOpportunitiesToReturn: [
          _opportunity(
            id: 9,
            title: 'Disposable Role',
            status: 'closed',
            canDelete: true,
          ),
        ],
      )..deleteClosedError = ApiException('Cannot delete right now');

      await _pumpScreen(
        tester,
        organizationId: 1,
        signedInUser: ownerUser,
        ownOrganizationId: 1,
        profileRepository: _FakeOrganizationProfileRepository(
          profileToReturn: _profile(id: 1),
        ),
        opportunityRepository: opportunityRepository,
      );

      await _tapVisible(tester, find.text('Closed Opportunities (1)'));
      await _tapVisible(tester, find.text('Delete Permanently'));
      await _tapVisible(
        tester,
        find.widgetWithText(DangerButton, 'Delete Permanently'),
      );

      expect(find.text('Cannot delete right now'), findsOneWidget);
      expect(find.text('Disposable Role'), findsOneWidget);
    });

    testWidgets('renders correctly with 10+ closed opportunities', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        organizationId: 1,
        signedInUser: ownerUser,
        ownOrganizationId: 1,
        profileRepository: _FakeOrganizationProfileRepository(
          profileToReturn: _profile(id: 1),
        ),
        opportunityRepository: _FakeOpportunityRepository(
          ownOpportunitiesToReturn: List.generate(
            12,
            (i) => _opportunity(
              id: i + 1,
              title: 'Closed Role ${i + 1}',
              status: 'closed',
            ),
          ),
        ),
      );

      expect(find.text('Closed Opportunities (12)'), findsOneWidget);

      await _tapVisible(tester, find.text('Closed Opportunities (12)'));

      expect(tester.takeException(), isNull);
      expect(find.text('Closed Role 1'), findsOneWidget);
      expect(find.text('Closed Role 12'), findsOneWidget);
    });
  });

  group('Closed Opportunities filtering, sorting & pagination '
      '(Closed Opportunities Scalability Polish)', () {
    const ownerUser = UserModel(
      id: 1,
      name: 'Acme Owner',
      email: 'owner@acme.example.com',
      role: 'organization',
      status: 'active',
    );

    testWidgets('shows the real closure date on each card', (tester) async {
      await _pumpScreen(
        tester,
        organizationId: 1,
        signedInUser: ownerUser,
        ownOrganizationId: 1,
        profileRepository: _FakeOrganizationProfileRepository(
          profileToReturn: _profile(id: 1),
        ),
        opportunityRepository: _FakeOpportunityRepository(
          ownOpportunitiesToReturn: [
            _opportunity(
              id: 9,
              title: 'Old Role',
              status: 'closed',
              closedAt: DateTime(2026, 8, 18),
            ),
          ],
        ),
      );

      await _tapVisible(tester, find.text('Closed Opportunities (1)'));

      expect(find.text('Closed Aug 18, 2026'), findsOneWidget);
    });

    testWidgets('a legacy row with no known closure date shows "Closure '
        'date unavailable"', (tester) async {
      await _pumpScreen(
        tester,
        organizationId: 1,
        signedInUser: ownerUser,
        ownOrganizationId: 1,
        profileRepository: _FakeOrganizationProfileRepository(
          profileToReturn: _profile(id: 1),
        ),
        opportunityRepository: _FakeOpportunityRepository(
          ownOpportunitiesToReturn: [
            _opportunity(id: 9, title: 'Legacy Role', status: 'closed'),
          ],
        ),
      );

      await _tapVisible(tester, find.text('Closed Opportunities (1)'));

      expect(find.text('Closure date unavailable'), findsOneWidget);
    });

    testWidgets('date preset chips render once expanded', (tester) async {
      await _pumpScreen(
        tester,
        organizationId: 1,
        signedInUser: ownerUser,
        ownOrganizationId: 1,
        profileRepository: _FakeOrganizationProfileRepository(
          profileToReturn: _profile(id: 1),
        ),
        opportunityRepository: _FakeOpportunityRepository(
          ownOpportunitiesToReturn: [
            _opportunity(
              id: 9,
              title: 'Role',
              status: 'closed',
              closedAt: DateTime.now(),
            ),
          ],
        ),
      );

      // Not visible while collapsed.
      expect(find.text('All'), findsNothing);

      await _tapVisible(tester, find.text('Closed Opportunities (1)'));

      expect(find.text('All'), findsOneWidget);
      expect(find.text('30 Days'), findsOneWidget);
      expect(find.text('3 Months'), findsOneWidget);
      expect(find.text('6 Months'), findsOneWidget);
      expect(find.text('This Year'), findsOneWidget);
      expect(find.text('Older'), findsOneWidget);
      expect(find.text('Custom'), findsOneWidget);
    });

    testWidgets('selecting a date preset sends it to the repository and '
        'resets to page 1', (tester) async {
      final opportunityRepository = _FakeOpportunityRepository(
        ownOpportunitiesToReturn: [
          _opportunity(
            id: 9,
            title: 'Role',
            status: 'closed',
            closedAt: DateTime.now(),
          ),
        ],
      );
      await _pumpScreen(
        tester,
        organizationId: 1,
        signedInUser: ownerUser,
        ownOrganizationId: 1,
        profileRepository: _FakeOrganizationProfileRepository(
          profileToReturn: _profile(id: 1),
        ),
        opportunityRepository: opportunityRepository,
      );

      await _tapVisible(tester, find.text('Closed Opportunities (1)'));
      await _tapVisible(tester, find.text('30 Days'));

      expect(opportunityRepository.lastDatePreset, 'last_30_days');
      expect(opportunityRepository.lastPage, 1);
    });

    testWidgets('selecting a sort order sends it to the repository', (
      tester,
    ) async {
      final opportunityRepository = _FakeOpportunityRepository(
        ownOpportunitiesToReturn: [
          _opportunity(
            id: 9,
            title: 'Role',
            status: 'closed',
            closedAt: DateTime.now(),
          ),
        ],
      );
      await _pumpScreen(
        tester,
        organizationId: 1,
        signedInUser: ownerUser,
        ownOrganizationId: 1,
        profileRepository: _FakeOrganizationProfileRepository(
          profileToReturn: _profile(id: 1),
        ),
        opportunityRepository: opportunityRepository,
      );

      await _tapVisible(tester, find.text('Closed Opportunities (1)'));
      expect(opportunityRepository.lastSort, 'newest');

      await _tapVisible(tester, find.text('Newest first'));
      await _tapVisible(tester, find.text('Oldest first').last);

      expect(opportunityRepository.lastSort, 'oldest');
    });

    testWidgets('Load More fetches and appends the next page', (
      tester,
    ) async {
      final opportunityRepository = _FakeOpportunityRepository(
        ownOpportunitiesToReturn: List.generate(
          20,
          (i) => _opportunity(
            id: i + 1,
            title: 'Closed Role ${i + 1}',
            status: 'closed',
            closedAt: DateTime.now().subtract(Duration(days: i)),
          ),
        ),
      );
      await _pumpScreen(
        tester,
        organizationId: 1,
        signedInUser: ownerUser,
        ownOrganizationId: 1,
        profileRepository: _FakeOrganizationProfileRepository(
          profileToReturn: _profile(id: 1),
        ),
        opportunityRepository: opportunityRepository,
        size: const Size(420, 2400),
      );

      await _tapVisible(tester, find.text('Closed Opportunities (20)'));

      // Newest-first: rows 1..15 (page 1) are visible, 16+ require Load
      // More (the fake's default perPage matches the real backend's: 15).
      expect(find.text('Closed Role 1'), findsOneWidget);
      expect(find.text('Closed Role 16'), findsNothing);
      expect(find.text('Load More'), findsOneWidget);

      await _tapVisible(tester, find.text('Load More'));

      expect(opportunityRepository.lastPage, 2);
      expect(find.text('Closed Role 16'), findsOneWidget);
      expect(find.text('Closed Role 20'), findsOneWidget);
      // All 20 rows are now loaded -- no more pages remain.
      expect(find.text('Load More'), findsNothing);
    });

    testWidgets('a failed Load More preserves already-loaded rows and '
        'shows a real error', (tester) async {
      final opportunityRepository = _FakeOpportunityRepository(
        ownOpportunitiesToReturn: List.generate(
          20,
          (i) => _opportunity(
            id: i + 1,
            title: 'Closed Role ${i + 1}',
            status: 'closed',
            closedAt: DateTime.now().subtract(Duration(days: i)),
          ),
        ),
      );
      await _pumpScreen(
        tester,
        organizationId: 1,
        signedInUser: ownerUser,
        ownOrganizationId: 1,
        profileRepository: _FakeOrganizationProfileRepository(
          profileToReturn: _profile(id: 1),
        ),
        opportunityRepository: opportunityRepository,
        size: const Size(420, 2400),
      );

      await _tapVisible(tester, find.text('Closed Opportunities (20)'));
      opportunityRepository.closedOpportunitiesError = ApiException(
        'Could not load more right now',
      );
      await _tapVisible(tester, find.text('Load More'));

      expect(find.text('Could not load more right now'), findsOneWidget);
      // The first page's rows are still there -- a failed page 2 fetch
      // never discards what was already loaded.
      expect(find.text('Closed Role 1'), findsOneWidget);
    });

    testWidgets('an empty org-wide history shows the unfiltered empty '
        'message', (tester) async {
      await _pumpScreen(
        tester,
        organizationId: 1,
        signedInUser: ownerUser,
        ownOrganizationId: 1,
        profileRepository: _FakeOrganizationProfileRepository(
          profileToReturn: _profile(id: 1),
        ),
        opportunityRepository: _FakeOpportunityRepository(),
      );

      await _tapVisible(tester, find.text('Closed Opportunities (0)'));

      expect(find.text('No closed opportunities yet.'), findsOneWidget);
    });

    testWidgets('a filter with zero matches shows the filtered empty '
        'message, not the unfiltered one', (tester) async {
      await _pumpScreen(
        tester,
        organizationId: 1,
        signedInUser: ownerUser,
        ownOrganizationId: 1,
        profileRepository: _FakeOrganizationProfileRepository(
          profileToReturn: _profile(id: 1),
        ),
        opportunityRepository: _FakeOpportunityRepository(
          ownOpportunitiesToReturn: [
            _opportunity(
              id: 9,
              title: 'Old Role',
              status: 'closed',
              closedAt: DateTime.now().subtract(const Duration(days: 400)),
            ),
          ],
        ),
      );

      await _tapVisible(tester, find.text('Closed Opportunities (1)'));
      await _tapVisible(tester, find.text('30 Days'));

      expect(
        find.text('No closed opportunities in this period.'),
        findsOneWidget,
      );
      expect(find.text('No closed opportunities yet.'), findsNothing);
      // The org-wide total in the header never implies "no history".
      expect(find.text('Closed Opportunities (1)'), findsOneWidget);
    });

    testWidgets('shows a "Showing X of Y" caption once a filter narrows '
        'the results', (tester) async {
      await _pumpScreen(
        tester,
        organizationId: 1,
        signedInUser: ownerUser,
        ownOrganizationId: 1,
        profileRepository: _FakeOrganizationProfileRepository(
          profileToReturn: _profile(id: 1),
        ),
        opportunityRepository: _FakeOpportunityRepository(
          ownOpportunitiesToReturn: [
            _opportunity(
              id: 1,
              title: 'Recent Role',
              status: 'closed',
              closedAt: DateTime.now(),
            ),
            _opportunity(
              id: 2,
              title: 'Old Role',
              status: 'closed',
              closedAt: DateTime.now().subtract(const Duration(days: 400)),
            ),
          ],
        ),
      );

      await _tapVisible(tester, find.text('Closed Opportunities (2)'));
      expect(find.textContaining('Showing'), findsNothing);

      await _tapVisible(tester, find.text('30 Days'));

      expect(find.text('Showing 1 of 1'), findsOneWidget);
    });

    testWidgets('deleting a closed opportunity decrements the header '
        'count', (tester) async {
      final opportunityRepository = _FakeOpportunityRepository(
        ownOpportunitiesToReturn: [
          _opportunity(
            id: 9,
            title: 'Disposable Role',
            status: 'closed',
            canDelete: true,
            closedAt: DateTime.now(),
          ),
        ],
      );
      await _pumpScreen(
        tester,
        organizationId: 1,
        signedInUser: ownerUser,
        ownOrganizationId: 1,
        profileRepository: _FakeOrganizationProfileRepository(
          profileToReturn: _profile(id: 1),
        ),
        opportunityRepository: opportunityRepository,
      );

      await _tapVisible(tester, find.text('Closed Opportunities (1)'));
      await _tapVisible(tester, find.text('Delete Permanently'));
      await _tapVisible(
        tester,
        find.widgetWithText(DangerButton, 'Delete Permanently'),
      );

      expect(find.text('Closed Opportunities (0)'), findsOneWidget);
    });

    testWidgets('renders in dark mode with no overflow', (tester) async {
      AppColors.updateBrightness(Brightness.dark);
      addTearDown(() => AppColors.updateBrightness(Brightness.light));

      await _pumpScreen(
        tester,
        organizationId: 1,
        signedInUser: ownerUser,
        ownOrganizationId: 1,
        profileRepository: _FakeOrganizationProfileRepository(
          profileToReturn: _profile(id: 1),
        ),
        opportunityRepository: _FakeOpportunityRepository(
          ownOpportunitiesToReturn: [
            _opportunity(
              id: 9,
              title: 'Old Role',
              status: 'closed',
              closedAt: DateTime.now(),
            ),
          ],
        ),
      );

      await _tapVisible(tester, find.text('Closed Opportunities (1)'));

      expect(tester.takeException(), isNull);
    });

    testWidgets('renders on a narrow phone width with no overflow', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        organizationId: 1,
        signedInUser: ownerUser,
        ownOrganizationId: 1,
        profileRepository: _FakeOrganizationProfileRepository(
          profileToReturn: _profile(id: 1),
        ),
        opportunityRepository: _FakeOpportunityRepository(
          ownOpportunitiesToReturn: List.generate(
            5,
            (i) => _opportunity(
              id: i + 1,
              title: 'A Fairly Long Closed Opportunity Title $i',
              status: 'closed',
              closedAt: DateTime.now().subtract(Duration(days: i)),
            ),
          ),
        ),
        size: const Size(375, 1400),
      );

      await _tapVisible(tester, find.text('Closed Opportunities (5)'));

      expect(tester.takeException(), isNull);
    });
  });

  group('Company Logo (Company Profile Polish)', () {
    testWidgets('renders without error when a real logo URL is set', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        organizationId: 1,
        profileRepository: _FakeOrganizationProfileRepository(
          profileToReturn: _profile(
            id: 1,
            logoUrl: 'https://cdn.example.com/logos/acme.png',
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(AppAvatar), findsOneWidget);
    });

    // Final Company Profile Manual-E2E Bug Fix: regression coverage for
    // the real fix -- Flutter must render the EXACT URL the backend
    // returned, never rebuild/re-host/hardcode any part of it (the actual
    // bug was that URL never resolving in a real browser, a backend-side
    // CORS/routing issue this app never worked around client-side).
    testWidgets('renders the exact logo URL the backend returned, verbatim', (
      tester,
    ) async {
      const realBackendUrl =
          'http://127.0.0.1:8000/api/media/organization-logos/7/'
          'f57795a6-c133-45b4-9f8e-101d81aee7ea.jpg';

      await _pumpScreen(
        tester,
        organizationId: 1,
        profileRepository: _FakeOrganizationProfileRepository(
          profileToReturn: _profile(id: 1, logoUrl: realBackendUrl),
        ),
      );

      final image = tester.widget<Image>(find.byType(Image));
      expect((image.image as NetworkImage).url, realBackendUrl);
    });

    testWidgets('falls back to clean initials when no logo is set', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        organizationId: 1,
        profileRepository: _FakeOrganizationProfileRepository(
          profileToReturn: _profile(id: 1, name: 'Acme Corp'),
        ),
      );

      expect(find.text('AC'), findsOneWidget);
    });
  });

  group('Post images (Company Profile Polish)', () {
    testWidgets('a post with an image renders it without error', (
      tester,
    ) async {
      final now = DateTime.now();
      await _pumpScreen(
        tester,
        organizationId: 1,
        profileRepository: _FakeOrganizationProfileRepository(
          profileToReturn: _profile(id: 1),
          postsToReturn: [
            OrganizationPostModel(
              id: 1,
              organizationId: 1,
              body: 'Look at our new office!',
              imageUrl: 'https://cdn.example.com/posts/1.png',
              createdAt: now,
            ),
          ],
        ),
      );

      expect(find.text('Look at our new office!'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(find.byType(Image), findsOneWidget);
    });

    // Final Company Profile Manual-E2E Bug Fix: regression coverage --
    // Flutter must render the EXACT URL the backend returned, verbatim.
    testWidgets('renders the exact post image URL the backend returned, '
        'verbatim', (tester) async {
      const realBackendUrl =
          'http://127.0.0.1:8000/api/media/organization-posts/7/'
          'f5506906-c6ca-49d5-8cb2-6ac8dcdc6eca.jpg';
      final now = DateTime.now();

      await _pumpScreen(
        tester,
        organizationId: 1,
        profileRepository: _FakeOrganizationProfileRepository(
          profileToReturn: _profile(id: 1),
          postsToReturn: [
            OrganizationPostModel(
              id: 1,
              organizationId: 1,
              body: 'Look at our new office!',
              imageUrl: realBackendUrl,
              createdAt: now,
            ),
          ],
        ),
      );

      final image = tester.widget<Image>(find.byType(Image));
      expect((image.image as NetworkImage).url, realBackendUrl);
    });

    testWidgets('a text-only post never renders an image', (tester) async {
      final now = DateTime.now();
      await _pumpScreen(
        tester,
        organizationId: 1,
        profileRepository: _FakeOrganizationProfileRepository(
          profileToReturn: _profile(id: 1),
          postsToReturn: [
            OrganizationPostModel(
              id: 1,
              organizationId: 1,
              body: 'A text-only update.',
              createdAt: now,
            ),
          ],
        ),
      );

      expect(find.text('A text-only update.'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });
  });
}
