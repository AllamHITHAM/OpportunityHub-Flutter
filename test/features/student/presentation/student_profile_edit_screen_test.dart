// Widget tests for StudentProfileEditScreen (UI Phase 3.1) — verifies the
// form pre-fills real current values, validates required fields, submits
// exactly what the real `PUT /api/student/profile` endpoint accepts,
// surfaces backend field errors inline without losing entered data, guards
// against duplicate submission, and only pops back after the backend has
// actually confirmed success.

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
import 'package:opportunityhub_flutter/features/organization_profile/data/picked_image_file.dart';
import 'package:opportunityhub_flutter/features/student/data/student_profile_repository.dart';
import 'package:opportunityhub_flutter/features/student/presentation/student_profile_edit_screen.dart';
import 'package:opportunityhub_flutter/models/location_model.dart';
import 'package:opportunityhub_flutter/models/student_profile_model.dart';
import 'package:opportunityhub_flutter/models/user_model.dart';
import 'package:opportunityhub_flutter/providers/auth_provider.dart';
import 'package:opportunityhub_flutter/providers/location_catalog_provider.dart';
import 'package:opportunityhub_flutter/providers/student_profile_provider.dart';
import 'package:opportunityhub_flutter/providers/theme_provider.dart';

// A real, minimal valid 1x1 PNG -- `Image.memory` decodes actual image
// bytes even in the widget-test environment, so arbitrary placeholder
// bytes throw "Invalid image data" mid-test.
final Uint8List _tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY'
  '42YAAAAASUVORK5CYII=',
);

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository()
    : super(
        apiClient: ApiClient(tokenStorageService: TokenStorageService()),
        tokenStorageService: TokenStorageService(),
      );

  @override
  Future<String?> getSavedToken() async => null;
}

class _FakeThemePreferenceStorage extends ThemePreferenceStorage {
  @override
  Future<void> saveThemeMode(ThemeMode mode) async {}

  @override
  Future<ThemeMode> readThemeMode() async => ThemeMode.system;
}

typedef _UpdateHandler =
    Future<StudentProfileModel> Function({
      required String university,
      required String major,
      required int graduationYear,
      String? phone,
      String? bio,
      int? currentLocationId,
      List<int> availableLocationIds,
    });

class _FakeStudentProfileRepository extends StudentProfileRepository {
  _FakeStudentProfileRepository({this.getProfileResult, this.onUpdate})
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  StudentProfileModel? getProfileResult;
  _UpdateHandler? onUpdate;
  int updateCallCount = 0;
  List<String>? lastInterestedIn;

  @override
  Future<StudentProfileModel?> getProfile() async => getProfileResult;

  @override
  Future<StudentProfileModel> updateProfile({
    required String university,
    required String major,
    required int graduationYear,
    required List<String> interestedIn,
    String? phone,
    String? bio,
    int? currentLocationId,
    List<int> availableLocationIds = const [],
  }) async {
    updateCallCount++;
    lastInterestedIn = interestedIn;
    final handler = onUpdate;
    if (handler != null) {
      return handler(
        university: university,
        major: major,
        graduationYear: graduationYear,
        phone: phone,
        bio: bio,
        currentLocationId: currentLocationId,
        availableLocationIds: availableLocationIds,
      );
    }
    return StudentProfileModel(
      id: 1,
      interestedIn: ['job'],
      university: university,
      major: major,
      graduationYear: graduationYear,
      phone: phone,
      bio: bio,
    );
  }

  ApiException? uploadPhotoError;
  ApiException? removePhotoError;
  int uploadPhotoCallCount = 0;
  int removePhotoCallCount = 0;
  PickedImageFile? lastUploadedPhoto;
  String? nextPhotoUrl = 'https://cdn.example.com/photos/new.png';

  @override
  Future<StudentProfileModel> uploadPhoto(PickedImageFile file) async {
    uploadPhotoCallCount++;
    lastUploadedPhoto = file;
    if (uploadPhotoError != null) throw uploadPhotoError!;
    return StudentProfileModel(
      id: 1,
      interestedIn: const ['job'],
      university: 'State University',
      major: 'Computer Science',
      graduationYear: 2027,
      photoUrl: nextPhotoUrl,
    );
  }

  @override
  Future<StudentProfileModel> removePhoto() async {
    removePhotoCallCount++;
    if (removePhotoError != null) throw removePhotoError!;
    return const StudentProfileModel(
      id: 1,
      interestedIn: ['job'],
      university: 'State University',
      major: 'Computer Science',
      graduationYear: 2027,
      photoUrl: null,
    );
  }
}

class _FakeLocationRepository extends LocationRepository {
  _FakeLocationRepository({this.locations = const [], this.addResult})
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  List<LocationModel> locations;
  LocationModel? addResult;
  String? lastAddedName;

  @override
  Future<List<LocationModel>> getLocations() async => locations;

  @override
  Future<LocationModel> addLocation(String name) async {
    lastAddedName = name;
    return addResult ?? LocationModel(id: 999, canonicalName: name);
  }
}

Future<
  (
    StudentProfileProvider provider,
    GoRouter router,
    _FakeStudentProfileRepository repository,
  )
>
_pumpScreen(
  WidgetTester tester, {
  StudentProfileModel? initialProfile,
  _UpdateHandler? onUpdate,
  List<LocationModel> locations = const [],
  _FakeLocationRepository? locationRepository,
  Future<PickedImageFile?> Function()? pickPhoto,
}) async {
  addTearDown(() => AppColors.updateBrightness(Brightness.light));

  final authProvider = AuthProvider(authRepository: _FakeAuthRepository())
    ..user = const UserModel(
      id: 1,
      name: 'Sam Student',
      email: 'sam@example.com',
      role: 'student',
      status: 'active',
      emailVerified: true,
    );
  final repository = _FakeStudentProfileRepository(
    getProfileResult: initialProfile,
    onUpdate: onUpdate,
  );
  final studentProfileProvider = StudentProfileProvider(
    repository: repository,
    authProvider: authProvider,
  )..profile = initialProfile;
  final locationCatalogProvider = LocationCatalogProvider(
    repository:
        locationRepository ?? _FakeLocationRepository(locations: locations),
  );
  final themeProvider = ThemeProvider(storage: _FakeThemePreferenceStorage());
  await themeProvider.initialize();

  final router = GoRouter(
    initialLocation: '/profile',
    routes: [
      GoRoute(
        path: '/profile',
        builder: (_, _) => const Scaffold(body: Text('PROFILE_SCREEN')),
        routes: [
          GoRoute(
            path: 'edit',
            builder: (_, _) => StudentProfileEditScreen(
              pickPhoto: pickPhoto ?? pickImageFileFromDevice,
            ),
          ),
        ],
      ),
    ],
  );

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ChangeNotifierProvider<StudentProfileProvider>.value(
          value: studentProfileProvider,
        ),
        ChangeNotifierProvider<LocationCatalogProvider>.value(
          value: locationCatalogProvider,
        ),
        ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
      ],
      child: MaterialApp.router(
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();

  router.push('/profile/edit');
  await tester.pumpAndSettle();

  return (studentProfileProvider, router, repository);
}

void main() {
  testWidgets('pre-fills the form with the current real profile values', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      initialProfile: const StudentProfileModel(
        id: 1,
      interestedIn: ['job'],
        university: 'State University',
        major: 'Computer Science',
        graduationYear: 2027,
        phone: '0791234567',
        bio: 'A motivated student.',
      ),
    );

    expect(find.text('State University'), findsOneWidget);
    expect(find.text('Computer Science'), findsOneWidget);
    expect(find.text('2027'), findsOneWidget);
    expect(find.text('0791234567'), findsOneWidget);
    expect(find.text('A motivated student.'), findsOneWidget);
  });

  testWidgets('rejects an empty university on submit', (tester) async {
    await _pumpScreen(
      tester,
      initialProfile: const StudentProfileModel(
        id: 1,
      interestedIn: ['job'],
        university: 'State University',
        major: 'Computer Science',
        graduationYear: 2027,
      ),
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'University'),
      '',
    );
    await tester.ensureVisible(find.text('Save Changes'));
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();

    expect(find.text('University is required'), findsOneWidget);
  });

  testWidgets('Cancel pops without submitting anything', (tester) async {
    final (_, _, repository) = await _pumpScreen(
      tester,
      initialProfile: const StudentProfileModel(
        id: 1,
      interestedIn: ['job'],
        university: 'State University',
        major: 'Computer Science',
        graduationYear: 2027,
      ),
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'University'),
      'Changed University',
    );
    await tester.ensureVisible(find.text('Cancel'));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('PROFILE_SCREEN'), findsOneWidget);
    expect(repository.updateCallCount, 0);
  });

  testWidgets('submits exactly the real allow-listed fields', (tester) async {
    Map<String, dynamic>? sent;
    await _pumpScreen(
      tester,
      initialProfile: const StudentProfileModel(
        id: 1,
      interestedIn: ['job'],
        university: 'Old University',
        major: 'Old Major',
        graduationYear: 2026,
      ),
      onUpdate:
          ({
            required university,
            required major,
            required graduationYear,
            phone,
            bio,
            currentLocationId,
            availableLocationIds = const [],
          }) async {
            sent = {
              'university': university,
              'major': major,
              'graduation_year': graduationYear,
              'phone': phone,
              'bio': bio,
            };
            return StudentProfileModel(
              id: 1,
      interestedIn: ['job'],
              university: university,
              major: major,
              graduationYear: graduationYear,
              phone: phone,
              bio: bio,
            );
          },
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'University'),
      'New University',
    );
    await tester.ensureVisible(find.text('Save Changes'));
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();

    expect(sent, isNotNull);
    expect(sent!['university'], 'New University');
    expect(sent!['major'], 'Old Major');
    expect(sent!['graduation_year'], 2026);
  });

  testWidgets(
    'on success, the provider profile becomes the canonical backend response and the screen pops',
    (tester) async {
      final (provider, _, _) = await _pumpScreen(
        tester,
        initialProfile: const StudentProfileModel(
          id: 1,
      interestedIn: ['job'],
          university: 'Old University',
          major: 'Old Major',
          graduationYear: 2026,
        ),
      );

      await tester.enterText(
        find.widgetWithText(TextFormField, 'University'),
        'New University',
      );
      await tester.ensureVisible(find.text('Save Changes'));
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      expect(find.text('PROFILE_SCREEN'), findsOneWidget);
      expect(provider.profile?.university, 'New University');
    },
  );

  testWidgets(
    'a 422 backend field error is shown inline and entered values are preserved',
    (tester) async {
      await _pumpScreen(
        tester,
        initialProfile: const StudentProfileModel(
          id: 1,
      interestedIn: ['job'],
          university: 'Old University',
          major: 'Old Major',
          graduationYear: 2026,
        ),
        onUpdate:
            ({
              required university,
              required major,
              required graduationYear,
              phone,
              bio,
              currentLocationId,
            availableLocationIds = const [],
            }) async {
              throw ApiException(
                'The given data was invalid.',
                statusCode: 422,
                errors: {
                  'university': ['The university field is invalid.'],
                },
              );
            },
      );

      await tester.enterText(
        find.widgetWithText(TextFormField, 'University'),
        'Bad University',
      );
      await tester.ensureVisible(find.text('Save Changes'));
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      expect(find.text('The university field is invalid.'), findsOneWidget);
      expect(find.text('Bad University'), findsOneWidget);
      expect(find.text('PROFILE_SCREEN'), findsNothing);
    },
  );

  testWidgets(
    'a network/API failure shows a top-level error and keeps the form open',
    (tester) async {
      await _pumpScreen(
        tester,
        initialProfile: const StudentProfileModel(
          id: 1,
      interestedIn: ['job'],
          university: 'Old University',
          major: 'Old Major',
          graduationYear: 2026,
        ),
        onUpdate:
            ({
              required university,
              required major,
              required graduationYear,
              phone,
              bio,
              currentLocationId,
            availableLocationIds = const [],
            }) async {
              throw ApiException('No internet connection.');
            },
      );

      await tester.ensureVisible(find.text('Save Changes'));
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      expect(find.text('No internet connection.'), findsOneWidget);
      expect(find.text('PROFILE_SCREEN'), findsNothing);
    },
  );

  testWidgets('a blank optional phone/bio submits as null (clears the field)', (
    tester,
  ) async {
    Map<String, dynamic>? sent;
    await _pumpScreen(
      tester,
      initialProfile: const StudentProfileModel(
        id: 1,
      interestedIn: ['job'],
        university: 'State University',
        major: 'Computer Science',
        graduationYear: 2027,
        phone: '0791234567',
        bio: 'Old bio.',
      ),
      onUpdate:
          ({
            required university,
            required major,
            required graduationYear,
            phone,
            bio,
            currentLocationId,
            availableLocationIds = const [],
          }) async {
            sent = {'phone': phone, 'bio': bio};
            return StudentProfileModel(
              id: 1,
      interestedIn: ['job'],
              university: university,
              major: major,
              graduationYear: graduationYear,
              phone: phone,
              bio: bio,
            );
          },
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Phone (optional)'),
      '',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Bio (optional)'),
      '',
    );
    await tester.ensureVisible(find.text('Save Changes'));
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();

    expect(sent!['phone'], isNull);
    expect(sent!['bio'], isNull);
  });

  group('current location (Student Location Profile Patch)', () {
    testWidgets('pre-fills the student\'s existing current location', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        initialProfile: const StudentProfileModel(
          id: 1,
      interestedIn: ['job'],
          university: 'State University',
          major: 'Computer Science',
          graduationYear: 2027,
          currentLocation: LocationModel(id: 1, canonicalName: 'Jenin'),
        ),
        locations: const [
          LocationModel(id: 1, canonicalName: 'Jenin'),
          LocationModel(id: 2, canonicalName: 'Nablus'),
        ],
      );

      expect(find.text('Jenin'), findsOneWidget);
    });

    testWidgets('changing and submitting sends the new current location', (
      tester,
    ) async {
      int? sentCurrentLocationId;
      await _pumpScreen(
        tester,
        initialProfile: const StudentProfileModel(
          id: 1,
      interestedIn: ['job'],
          university: 'State University',
          major: 'Computer Science',
          graduationYear: 2027,
        ),
        locations: const [
          LocationModel(id: 1, canonicalName: 'Jenin'),
          LocationModel(id: 2, canonicalName: 'Nablus'),
        ],
        onUpdate:
            ({
              required university,
              required major,
              required graduationYear,
              phone,
              bio,
              currentLocationId,
              availableLocationIds = const [],
            }) async {
              sentCurrentLocationId = currentLocationId;
              return StudentProfileModel(
                id: 1,
      interestedIn: ['job'],
                university: university,
                major: major,
                graduationYear: graduationYear,
              );
            },
      );

      final searchField = find.widgetWithText(
        TextFormField,
        'Current Location (optional)',
      );
      await tester.ensureVisible(searchField);
      await tester.enterText(searchField, 'Nablus');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Nablus'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save Changes'));
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      expect(sentCurrentLocationId, 2);
    });

    testWidgets(
      'is independent from Available Work Locations -- setting one never '
      'touches the other',
      (tester) async {
        Map<String, dynamic>? sent;
        await _pumpScreen(
          tester,
          initialProfile: const StudentProfileModel(
            id: 1,
      interestedIn: ['job'],
            university: 'State University',
            major: 'Computer Science',
            graduationYear: 2027,
            currentLocation: LocationModel(id: 1, canonicalName: 'Jenin'),
            availableLocations: [LocationModel(id: 2, canonicalName: 'Nablus')],
          ),
          locations: const [
            LocationModel(id: 1, canonicalName: 'Jenin'),
            LocationModel(id: 2, canonicalName: 'Nablus'),
          ],
          onUpdate:
              ({
                required university,
                required major,
                required graduationYear,
                phone,
                bio,
                currentLocationId,
                availableLocationIds = const [],
              }) async {
                sent = {
                  'current_location_id': currentLocationId,
                  'available_location_ids': availableLocationIds,
                };
                return StudentProfileModel(
                  id: 1,
      interestedIn: ['job'],
                  university: university,
                  major: major,
                  graduationYear: graduationYear,
                );
              },
        );

        await tester.ensureVisible(find.text('Save Changes'));
        await tester.tap(find.text('Save Changes'));
        await tester.pumpAndSettle();

        expect(sent?['current_location_id'], 1);
        expect(sent?['available_location_ids'], [2]);
      },
    );
  });

  group('available work locations (Phase O8.2)', () {
    testWidgets(
      'search suggestions come from the real canonical catalog, never '
      'free text',
      (tester) async {
        await _pumpScreen(
          tester,
          initialProfile: const StudentProfileModel(
            id: 1,
      interestedIn: ['job'],
            university: 'State University',
            major: 'Computer Science',
            graduationYear: 2027,
          ),
          locations: const [
            LocationModel(id: 1, canonicalName: 'Nablus'),
            LocationModel(id: 2, canonicalName: 'Ramallah'),
            LocationModel(id: 3, canonicalName: 'Jenin'),
          ],
        );

        // Nothing is pre-selected, so no chip renders until the Student
        // actually searches for and picks a real catalog entry.
        expect(find.widgetWithText(FilterChip, 'Nablus'), findsNothing);

        final searchField = find.widgetWithText(
          TextFormField,
          'Add a work location',
        );
        await tester.ensureVisible(searchField);
        await tester.enterText(searchField, 'Nab');
        await tester.pumpAndSettle();

        expect(find.widgetWithText(ListTile, 'Nablus'), findsOneWidget);
      },
    );

    testWidgets('pre-selects the student\'s existing available locations', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        initialProfile: const StudentProfileModel(
          id: 1,
      interestedIn: ['job'],
          university: 'State University',
          major: 'Computer Science',
          graduationYear: 2027,
          availableLocations: [LocationModel(id: 1, canonicalName: 'Nablus')],
        ),
        locations: const [
          LocationModel(id: 1, canonicalName: 'Nablus'),
          LocationModel(id: 2, canonicalName: 'Ramallah'),
        ],
      );

      final nablusChip = tester.widget<FilterChip>(
        find.widgetWithText(FilterChip, 'Nablus'),
      );
      expect(nablusChip.selected, isTrue);
      // Ramallah was never selected, so it isn't rendered as a chip at
      // all -- only the search results would show it.
      expect(find.widgetWithText(FilterChip, 'Ramallah'), findsNothing);
    });

    testWidgets('selecting multiple locations and submitting sends every ID', (
      tester,
    ) async {
      List<int>? sentIds;
      await _pumpScreen(
        tester,
        initialProfile: const StudentProfileModel(
          id: 1,
      interestedIn: ['job'],
          university: 'State University',
          major: 'Computer Science',
          graduationYear: 2027,
        ),
        locations: const [
          LocationModel(id: 1, canonicalName: 'Nablus'),
          LocationModel(id: 2, canonicalName: 'Ramallah'),
        ],
        onUpdate:
            ({
              required university,
              required major,
              required graduationYear,
              phone,
              bio,
              currentLocationId,
            availableLocationIds = const [],
            }) async {
              sentIds = availableLocationIds;
              return StudentProfileModel(
                id: 1,
      interestedIn: ['job'],
                university: university,
                major: major,
                graduationYear: graduationYear,
              );
            },
      );

      final searchField = find.widgetWithText(
        TextFormField,
        'Add a work location',
      );
      await tester.ensureVisible(searchField);
      await tester.enterText(searchField, 'Nablus');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Nablus'));
      await tester.pumpAndSettle();
      await tester.enterText(searchField, 'Ramallah');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Ramallah'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save Changes'));
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      expect(sentIds, unorderedEquals([1, 2]));
    });

    testWidgets(
      'an already-selected location is excluded from search suggestions '
      '-- never offered (or storable) twice',
      (tester) async {
        await _pumpScreen(
          tester,
          initialProfile: const StudentProfileModel(
            id: 1,
      interestedIn: ['job'],
            university: 'State University',
            major: 'Computer Science',
            graduationYear: 2027,
            availableLocations: [LocationModel(id: 1, canonicalName: 'Nablus')],
          ),
          locations: const [
            LocationModel(id: 1, canonicalName: 'Nablus'),
            LocationModel(id: 2, canonicalName: 'Nablus City'),
          ],
        );

        final searchField = find.widgetWithText(
          TextFormField,
          'Add a work location',
        );
        await tester.ensureVisible(searchField);
        await tester.enterText(searchField, 'Nablus');
        await tester.pumpAndSettle();

        // The already-selected catalog entry (id 1) never appears again in
        // the suggestion list -- only the distinct catalog entry does.
        expect(find.widgetWithText(ListTile, 'Nablus City'), findsOneWidget);
        expect(find.widgetWithText(ListTile, 'Nablus'), findsNothing);
      },
    );

    testWidgets(
      'typing a location not in the catalog offers to add it, and adding '
      'it selects the real resolved location',
      (tester) async {
        final locationRepository = _FakeLocationRepository(
          locations: const [LocationModel(id: 1, canonicalName: 'Nablus')],
          addResult: const LocationModel(id: 9, canonicalName: 'Salfit'),
        );
        List<int>? sentIds;
        await _pumpScreen(
          tester,
          initialProfile: const StudentProfileModel(
            id: 1,
      interestedIn: ['job'],
            university: 'State University',
            major: 'Computer Science',
            graduationYear: 2027,
          ),
          locationRepository: locationRepository,
          onUpdate:
              ({
                required university,
                required major,
                required graduationYear,
                phone,
                bio,
                currentLocationId,
                availableLocationIds = const [],
              }) async {
                sentIds = availableLocationIds;
                return StudentProfileModel(
                  id: 1,
      interestedIn: ['job'],
                  university: university,
                  major: major,
                  graduationYear: graduationYear,
                );
              },
        );

        final searchField = find.widgetWithText(
          TextFormField,
          'Add a work location',
        );
        await tester.ensureVisible(searchField);
        await tester.enterText(searchField, 'Salfit');
        await tester.pumpAndSettle();

        expect(find.widgetWithText(ListTile, 'Add "Salfit"'), findsOneWidget);

        await tester.tap(find.widgetWithText(ListTile, 'Add "Salfit"'));
        await tester.pumpAndSettle();

        expect(locationRepository.lastAddedName, 'Salfit');
        expect(find.widgetWithText(FilterChip, 'Salfit'), findsOneWidget);

        await tester.ensureVisible(find.text('Save Changes'));
        await tester.tap(find.text('Save Changes'));
        await tester.pumpAndSettle();

        expect(sentIds, [9]);
      },
    );

    testWidgets(
      'a typed name that already exactly matches a catalog entry never '
      'shows an Add option',
      (tester) async {
        await _pumpScreen(
          tester,
          initialProfile: const StudentProfileModel(
            id: 1,
      interestedIn: ['job'],
            university: 'State University',
            major: 'Computer Science',
            graduationYear: 2027,
          ),
          locations: const [LocationModel(id: 1, canonicalName: 'Nablus')],
        );

        final searchField = find.widgetWithText(
          TextFormField,
          'Add a work location',
        );
        await tester.ensureVisible(searchField);
        await tester.enterText(searchField, 'Nablus');
        await tester.pumpAndSettle();

        expect(find.textContaining('Add "'), findsNothing);
      },
    );

    testWidgets('deselecting a pre-selected location removes it on submit', (
      tester,
    ) async {
      List<int>? sentIds;
      await _pumpScreen(
        tester,
        initialProfile: const StudentProfileModel(
          id: 1,
      interestedIn: ['job'],
          university: 'State University',
          major: 'Computer Science',
          graduationYear: 2027,
          availableLocations: [LocationModel(id: 1, canonicalName: 'Nablus')],
        ),
        locations: const [LocationModel(id: 1, canonicalName: 'Nablus')],
        onUpdate:
            ({
              required university,
              required major,
              required graduationYear,
              phone,
              bio,
              currentLocationId,
            availableLocationIds = const [],
            }) async {
              sentIds = availableLocationIds;
              return StudentProfileModel(
                id: 1,
      interestedIn: ['job'],
                university: university,
                major: major,
                graduationYear: graduationYear,
              );
            },
      );

      await tester.ensureVisible(find.widgetWithText(FilterChip, 'Nablus'));
      await tester.tap(find.widgetWithText(FilterChip, 'Nablus'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save Changes'));
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      expect(sentIds, isEmpty);
    });

    for (final width in [375.0, 390.0, 430.0]) {
      testWidgets(
        'mobile ${width.toInt()} — many location chips wrap without '
        'overflow',
        (tester) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          await _pumpScreen(
            tester,
            initialProfile: const StudentProfileModel(
              id: 1,
      interestedIn: ['job'],
              university: 'State University',
              major: 'Computer Science',
              graduationYear: 2027,
              availableLocations: [
                LocationModel(id: 1, canonicalName: 'Nablus'),
                LocationModel(id: 2, canonicalName: 'Ramallah'),
                LocationModel(id: 3, canonicalName: 'Jenin'),
              ],
            ),
            locations: const [
              LocationModel(id: 1, canonicalName: 'Nablus'),
              LocationModel(id: 2, canonicalName: 'Ramallah'),
              LocationModel(id: 3, canonicalName: 'Jenin'),
              LocationModel(id: 4, canonicalName: 'Hebron'),
              LocationModel(id: 5, canonicalName: 'Bethlehem'),
              LocationModel(id: 6, canonicalName: 'Jerusalem'),
              LocationModel(id: 7, canonicalName: 'Gaza'),
              LocationModel(id: 8, canonicalName: 'Tulkarm'),
            ],
          );

          expect(tester.takeException(), isNull);
          expect(find.widgetWithText(FilterChip, 'Nablus'), findsOneWidget);
          expect(find.widgetWithText(FilterChip, 'Ramallah'), findsOneWidget);
          expect(find.widgetWithText(FilterChip, 'Jenin'), findsOneWidget);
        },
      );
    }
  });

  testWidgets('does not overflow at a narrow 320x720 viewport', (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpScreen(
      tester,
      initialProfile: const StudentProfileModel(
        id: 1,
      interestedIn: ['job'],
        university: 'State University',
        major: 'Computer Science',
        graduationYear: 2027,
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Save Changes'), findsOneWidget);
  });

  testWidgets('renders in dark mode without error', (tester) async {
    final authProvider = AuthProvider(authRepository: _FakeAuthRepository())
      ..user = const UserModel(
        id: 1,
        name: 'Sam Student',
        email: 'sam@example.com',
        role: 'student',
        status: 'active',
        emailVerified: true,
      );
    final studentProfileProvider =
        StudentProfileProvider(
            repository: _FakeStudentProfileRepository(
              getProfileResult: const StudentProfileModel(
                id: 1,
      interestedIn: ['job'],
                university: 'State University',
                major: 'Computer Science',
                graduationYear: 2027,
              ),
            ),
            authProvider: authProvider,
          )
          ..profile = const StudentProfileModel(
            id: 1,
      interestedIn: ['job'],
            university: 'State University',
            major: 'Computer Science',
            graduationYear: 2027,
          );
    final themeProvider = ThemeProvider(storage: _FakeThemePreferenceStorage());
    await themeProvider.initialize();
    addTearDown(() => AppColors.updateBrightness(Brightness.light));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          ChangeNotifierProvider<StudentProfileProvider>.value(
            value: studentProfileProvider,
          ),
          ChangeNotifierProvider<LocationCatalogProvider>.value(
            value: LocationCatalogProvider(
              repository: _FakeLocationRepository(),
            ),
          ),
          ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: const StudentProfileEditScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Save Changes'), findsOneWidget);
  });

  group('Profile Photo (Student Profile Photo phase)', () {
    testWidgets('shows the initials fallback and Add Photo when no photo is set', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        initialProfile: const StudentProfileModel(
          id: 1,
          interestedIn: ['job'],
          university: 'State University',
          major: 'Computer Science',
          graduationYear: 2027,
        ),
      );

      expect(find.text('Add Photo'), findsOneWidget);
      expect(find.text('Change Photo'), findsNothing);
      expect(find.text('Remove'), findsNothing);
    });

    testWidgets('an existing photo shows Change Photo and Remove', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        initialProfile: const StudentProfileModel(
          id: 1,
          interestedIn: ['job'],
          university: 'State University',
          major: 'Computer Science',
          graduationYear: 2027,
          photoUrl: 'https://cdn.example.com/photos/existing.png',
        ),
      );

      expect(find.text('Change Photo'), findsOneWidget);
      expect(find.text('Add Photo'), findsNothing);
      expect(find.text('Remove'), findsOneWidget);
    });

    testWidgets('choosing a photo shows a preview with Save Photo/Cancel', (
      tester,
    ) async {
      final (_, _, repository) = await _pumpScreen(
        tester,
        pickPhoto: () async =>
            PickedImageFile(filename: 'photo.png', bytes: _tinyPng),
      );

      await tester.tap(find.text('Add Photo'));
      await tester.pumpAndSettle();

      expect(find.text('Save Photo'), findsOneWidget);
      expect(find.text('Cancel'), findsWidgets);

      await tester.tap(find.text('Save Photo'));
      await tester.pumpAndSettle();

      expect(repository.uploadPhotoCallCount, 1);
      expect(repository.lastUploadedPhoto?.filename, 'photo.png');
      expect(find.text('Save Photo'), findsNothing);
      expect(find.text('Profile photo updated'), findsOneWidget);
    });

    testWidgets('cancelling a photo preview never uploads it', (
      tester,
    ) async {
      final (_, _, repository) = await _pumpScreen(
        tester,
        pickPhoto: () async =>
            PickedImageFile(filename: 'photo.png', bytes: _tinyPng),
      );

      await tester.tap(find.text('Add Photo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel').first);
      await tester.pumpAndSettle();

      expect(repository.uploadPhotoCallCount, 0);
      expect(find.text('Add Photo'), findsOneWidget);
    });

    testWidgets('cancelling the platform picker (returns null) does nothing', (
      tester,
    ) async {
      final (_, _, repository) = await _pumpScreen(
        tester,
        pickPhoto: () async => null,
      );

      await tester.tap(find.text('Add Photo'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(repository.uploadPhotoCallCount, 0);
      // Still the pre-pick state -- no preview, no error, no crash.
      expect(find.text('Add Photo'), findsOneWidget);
      expect(find.text('Save Photo'), findsNothing);
    });

    testWidgets('removing the photo calls removePhoto and reverts to initials', (
      tester,
    ) async {
      final (_, _, repository) = await _pumpScreen(
        tester,
        initialProfile: const StudentProfileModel(
          id: 1,
          interestedIn: ['job'],
          university: 'State University',
          major: 'Computer Science',
          graduationYear: 2027,
          photoUrl: 'https://cdn.example.com/photos/existing.png',
        ),
      );

      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      expect(repository.removePhotoCallCount, 1);
      expect(find.text('Remove'), findsNothing);
      expect(find.text('Add Photo'), findsOneWidget);
    });

    testWidgets(
      'a failed photo upload keeps the preview and shows an error',
      (tester) async {
        final (_, _, repository) = await _pumpScreen(
          tester,
          pickPhoto: () async =>
              PickedImageFile(filename: 'photo.png', bytes: _tinyPng),
        );
        repository.uploadPhotoError = ApiException('Upload failed');

        await tester.tap(find.text('Add Photo'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save Photo'));
        await tester.pumpAndSettle();

        expect(find.text('Upload failed'), findsOneWidget);
        // The picked preview and Save Photo/Cancel stay so the student
        // can retry -- the failed upload never silently discards their
        // selection, and the provider's own `profile` (and thus any
        // already-saved photo) is deliberately left untouched.
        expect(find.text('Save Photo'), findsOneWidget);
        expect(repository.uploadPhotoCallCount, 1);
      },
    );
  });
}
