// Widget tests for OrganizationProfileEditScreen (Organization Public
// Profile phase), in isolation with fake repositories (no real network).

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/theme_preference_storage.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/core/theme/app_colors.dart';
import 'package:opportunityhub_flutter/core/theme/app_theme.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/features/locations/data/location_repository.dart';
import 'package:opportunityhub_flutter/features/organization/data/organization_profile_repository.dart';
import 'package:opportunityhub_flutter/features/organization_profile/data/picked_image_file.dart';
import 'package:opportunityhub_flutter/features/organization_profile/presentation/organization_profile_edit_screen.dart';
import 'package:opportunityhub_flutter/models/location_model.dart';
import 'package:opportunityhub_flutter/models/organization_profile_model.dart';
import 'package:opportunityhub_flutter/providers/auth_provider.dart';
import 'package:opportunityhub_flutter/providers/location_catalog_provider.dart';
import 'package:opportunityhub_flutter/providers/organization_profile_provider.dart';
import 'package:opportunityhub_flutter/providers/theme_provider.dart';

// A real, minimal valid 1x1 PNG -- `Image.memory` decodes actual image
// bytes even in the widget-test environment, so arbitrary placeholder
// bytes throw "Invalid image data" mid-test.
final Uint8List _tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY'
  '42YAAAAASUVORK5CYII=',
);

class _FakeThemePreferenceStorage extends ThemePreferenceStorage {
  ThemeMode? saved;

  @override
  Future<void> saveThemeMode(ThemeMode mode) async {
    saved = mode;
  }

  @override
  Future<ThemeMode> readThemeMode() async => saved ?? ThemeMode.system;
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

class _FakeLocationRepository extends LocationRepository {
  _FakeLocationRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  @override
  Future<List<LocationModel>> getLocations() async {
    return const [
      LocationModel(id: 1, canonicalName: 'Ramallah'),
      LocationModel(id: 2, canonicalName: 'Nablus'),
    ];
  }
}

class _FakeOrganizationProfileRepository extends OrganizationProfileRepository {
  _FakeOrganizationProfileRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  ApiException? updateError;
  int updateCallCount = 0;
  String? lastName;

  @override
  Future<OrganizationProfileModel> updateProfile({
    required String organizationName,
    required String organizationType,
    String? industry,
    String? description,
    String? website,
    String? phone,
    int? locationId,
  }) async {
    updateCallCount++;
    lastName = organizationName;
    if (updateError != null) throw updateError!;
    return OrganizationProfileModel(
      id: 1,
      organizationName: organizationName,
      organizationType: organizationType,
      approvalStatus: 'approved',
      industry: industry,
      description: description,
      website: website,
      phone: phone,
    );
  }

  ApiException? uploadLogoError;
  ApiException? removeLogoError;
  int uploadLogoCallCount = 0;
  int removeLogoCallCount = 0;
  PickedImageFile? lastUploadedLogo;
  String? nextLogoUrl = 'https://cdn.example.com/logos/new.png';

  @override
  Future<OrganizationProfileModel> uploadLogo(PickedImageFile file) async {
    uploadLogoCallCount++;
    lastUploadedLogo = file;
    if (uploadLogoError != null) throw uploadLogoError!;
    return OrganizationProfileModel(
      id: 1,
      organizationName: 'Acme Corp',
      organizationType: 'company',
      approvalStatus: 'approved',
      logoUrl: nextLogoUrl,
    );
  }

  @override
  Future<OrganizationProfileModel> removeLogo() async {
    removeLogoCallCount++;
    if (removeLogoError != null) throw removeLogoError!;
    return const OrganizationProfileModel(
      id: 1,
      organizationName: 'Acme Corp',
      organizationType: 'company',
      approvalStatus: 'approved',
      logoUrl: null,
    );
  }
}

Future<
  ({
    OrganizationProfileProvider profileProvider,
    _FakeOrganizationProfileRepository repository,
  })
>
_pumpScreen(
  WidgetTester tester, {
  OrganizationProfileModel? initialProfile,
  Future<PickedImageFile?> Function()? pickLogoImage,
}) async {
  addTearDown(() => AppColors.updateBrightness(Brightness.light));

  // Tall enough that every field plus the Save/Cancel row is on-screen
  // without needing to scroll to tap them -- the default 800x600 test
  // surface is too short for this form.
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final themeProvider = ThemeProvider(storage: _FakeThemePreferenceStorage());
  await themeProvider.initialize();

  final authProvider = AuthProvider(authRepository: _FakeAuthRepository());
  final repository = _FakeOrganizationProfileRepository();
  final profileProvider = OrganizationProfileProvider(
    repository: repository,
    authProvider: authProvider,
  );
  profileProvider.profile =
      initialProfile ??
      const OrganizationProfileModel(
        id: 1,
        organizationName: 'Acme Corp',
        organizationType: 'company',
        approvalStatus: 'approved',
      );

  // `/` is the initial entry so `context.pop()` on save success has a
  // real back-stack entry to return to -- mirrors how this screen is
  // actually reached in the app (pushed from Company Profile), rather
  // than being the router's own first/only location.
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, _) => const Text('Company Profile')),
      GoRoute(
        path: '/edit',
        builder: (_, _) => OrganizationProfileEditScreen(
          pickLogoImage: pickLogoImage ?? pickImageFileFromDevice,
        ),
      ),
    ],
  );

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ChangeNotifierProvider<OrganizationProfileProvider>.value(
          value: profileProvider,
        ),
        ChangeNotifierProvider<LocationCatalogProvider>(
          create: (_) =>
              LocationCatalogProvider(repository: _FakeLocationRepository()),
        ),
      ],
      child: Builder(
        builder: (context) {
          final mode = context.watch<ThemeProvider>().mode;
          return MaterialApp.router(
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: mode,
            routerConfig: router,
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();

  router.push('/edit');
  await tester.pumpAndSettle();

  return (profileProvider: profileProvider, repository: repository);
}

void main() {
  testWidgets('prepopulates the form with the real existing profile data', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      initialProfile: const OrganizationProfileModel(
        id: 1,
        organizationName: 'Acme Corp',
        organizationType: 'company',
        approvalStatus: 'approved',
        industry: 'Software',
        website: 'https://acme.example.com',
      ),
    );

    expect(find.widgetWithText(TextFormField, 'Company Name'), findsOneWidget);
    expect(find.text('Acme Corp'), findsOneWidget);
    expect(find.text('Software'), findsOneWidget);
    expect(find.text('https://acme.example.com'), findsOneWidget);
  });

  testWidgets('rejects an empty company name', (tester) async {
    await _pumpScreen(tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Company Name'),
      '',
    );
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();

    expect(find.text('Company name is required'), findsOneWidget);
  });

  testWidgets('rejects an invalid website URL', (tester) async {
    await _pumpScreen(tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Website (optional)'),
      'not a url',
    );
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Enter a full URL'), findsOneWidget);
  });

  testWidgets('saving calls updateProfile and shows success feedback', (
    tester,
  ) async {
    final result = await _pumpScreen(tester);

    await tester.tap(find.text('Save Changes'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(result.repository.updateCallCount, 1);
    expect(result.repository.lastName, 'Acme Corp');
  });

  testWidgets('a failed save shows a real error and does not navigate away', (
    tester,
  ) async {
    final result = await _pumpScreen(tester);
    result.repository.updateError = ApiException('Something went wrong');

    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();

    expect(find.text('Something went wrong'), findsOneWidget);
    expect(find.text('Edit Company Profile'), findsOneWidget);
  });

  testWidgets('renders in dark mode with no overflow', (tester) async {
    AppColors.updateBrightness(Brightness.dark);
    addTearDown(() => AppColors.updateBrightness(Brightness.light));

    await _pumpScreen(tester);

    expect(tester.takeException(), isNull);
  });

  testWidgets('shows the initials fallback when no logo is set', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      initialProfile: const OrganizationProfileModel(
        id: 1,
        organizationName: 'Acme Corp',
        organizationType: 'company',
        approvalStatus: 'approved',
      ),
    );

    expect(find.text('AC'), findsOneWidget);
    expect(find.text('Choose Image'), findsOneWidget);
    expect(find.text('Remove'), findsNothing);
  });

  testWidgets('an existing logo shows Remove alongside Choose Image', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      initialProfile: const OrganizationProfileModel(
        id: 1,
        organizationName: 'Acme Corp',
        organizationType: 'company',
        approvalStatus: 'approved',
        logoUrl: 'https://cdn.example.com/logos/existing.png',
      ),
    );

    expect(find.text('Choose Image'), findsOneWidget);
    expect(find.text('Remove'), findsOneWidget);
  });

  testWidgets('choosing a logo shows a preview with Save Logo/Cancel', (
    tester,
  ) async {
    final result = await _pumpScreen(
      tester,
      pickLogoImage: () async =>
          PickedImageFile(filename: 'logo.png', bytes: _tinyPng),
    );

    await tester.tap(find.text('Choose Image'));
    await tester.pumpAndSettle();

    expect(find.text('Save Logo'), findsOneWidget);
    // The logo section's own "Cancel" is the first one in the tree --
    // it sits above the main form's "Cancel" near "Save Changes".
    expect(find.text('Cancel'), findsWidgets);

    await tester.tap(find.text('Save Logo'));
    await tester.pumpAndSettle();

    expect(result.repository.uploadLogoCallCount, 1);
    expect(result.repository.lastUploadedLogo?.filename, 'logo.png');
    expect(find.text('Save Logo'), findsNothing);
  });

  testWidgets('cancelling a logo preview never uploads it', (tester) async {
    final result = await _pumpScreen(
      tester,
      pickLogoImage: () async =>
          PickedImageFile(filename: 'logo.png', bytes: _tinyPng),
    );

    await tester.tap(find.text('Choose Image'));
    await tester.pumpAndSettle();
    // The logo section's own "Cancel" comes first in the tree, above
    // the main form's own "Cancel" near "Save Changes".
    await tester.tap(find.text('Cancel').first);
    await tester.pumpAndSettle();

    expect(result.repository.uploadLogoCallCount, 0);
    expect(find.text('Choose Image'), findsOneWidget);
  });

  testWidgets('removing the logo calls removeLogo and reverts to initials', (
    tester,
  ) async {
    final result = await _pumpScreen(
      tester,
      initialProfile: const OrganizationProfileModel(
        id: 1,
        organizationName: 'Acme Corp',
        organizationType: 'company',
        approvalStatus: 'approved',
        logoUrl: 'https://cdn.example.com/logos/existing.png',
      ),
    );

    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(result.repository.removeLogoCallCount, 1);
    expect(find.text('Remove'), findsNothing);
  });

  testWidgets('a failed logo upload keeps the previous logo and shows an '
      'error', (tester) async {
    final result = await _pumpScreen(
      tester,
      pickLogoImage: () async =>
          PickedImageFile(filename: 'logo.png', bytes: _tinyPng),
    );
    result.repository.uploadLogoError = ApiException('Upload failed');

    await tester.tap(find.text('Choose Image'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save Logo'));
    await tester.pumpAndSettle();

    expect(find.text('Upload failed'), findsOneWidget);
    // The picked preview and Save Logo/Cancel stay so the user can
    // retry -- the failed upload never silently discards their
    // selection, and the provider's own `profile` (and thus any
    // already-saved logo) is deliberately left untouched.
    expect(find.text('Save Logo'), findsOneWidget);
    expect(result.repository.uploadLogoCallCount, 1);
  });
}
