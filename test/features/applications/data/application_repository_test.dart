// Direct unit tests for ApplicationRepository.
//
// These exercise the real Dio/ApiClient pipeline against a fake HTTP
// transport, exactly like the other repository test files in this project
// — nothing about ApiClient's architecture is duplicated or bypassed.

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/features/applications/data/application_repository.dart';

const _secureStorageChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

class _FakeHttpClientAdapter implements HttpClientAdapter {
  _FakeHttpClientAdapter(this.handler);

  final ResponseBody Function(RequestOptions options) handler;
  RequestOptions? lastRequest;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    return handler(options);
  }
}

ResponseBody _jsonResponse(Map<String, dynamic> body, int statusCode) {
  return ResponseBody.fromString(
    jsonEncode(body),
    statusCode,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

ResponseBody _pdfResponse(List<int> bytes, int statusCode) {
  return ResponseBody.fromBytes(
    bytes,
    statusCode,
    headers: {
      Headers.contentTypeHeader: ['application/pdf'],
    },
  );
}

/// A JSON error body encoded the same way [ResponseBody.fromBytes] would
/// deliver it when the request's `responseType` is `bytes` — used to test
/// `ApiClient.handleBytesError`'s JSON-from-bytes decoding path.
ResponseBody _jsonErrorAsBytes(Map<String, dynamic> body, int statusCode) {
  return ResponseBody.fromBytes(
    utf8.encode(jsonEncode(body)),
    statusCode,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

ApplicationRepository _repositoryWithAdapter(_FakeHttpClientAdapter adapter) {
  final apiClient = ApiClient(tokenStorageService: TokenStorageService())
    ..dio.httpClientAdapter = adapter;
  return ApplicationRepository(apiClient: apiClient);
}

Map<String, dynamic> _opportunityJson({
  int id = 1,
  String title = 'Software Engineer',
}) {
  return {
    'id': id,
    'title': title,
    'description': 'A great opportunity.',
    'opportunity_type': 'job',
    'employment_type': 'full_time',
    'work_mode': 'remote',
    'experience_level': 'junior',
    'education_level': null,
    'field_of_study': null,
    'location': 'Amman, Jordan',
    'salary_min': null,
    'salary_max': null,
    'application_deadline': null,
    'positions_available': 1,
    'status': 'open',
    'created_at': '2026-07-01T10:00:00.000000Z',
    'updated_at': '2026-07-01T10:00:00.000000Z',
  };
}

Map<String, dynamic> _cvJson({int id = 1, String title = 'My CV'}) {
  return {
    'id': id,
    'student_id': 1,
    'title': title,
    'file_path': 'cvs/my-cv.pdf',
    'version': 1,
    'is_default': false,
    'created_by_ai': false,
    'created_at': '2026-07-01T10:00:00.000000Z',
    'updated_at': '2026-07-01T10:00:00.000000Z',
  };
}

Map<String, dynamic> _studentProfileJson({
  int id = 1,
  int userId = 10,
  String name = 'Jane Student',
  String email = 'jane@example.com',
}) {
  return {
    'id': id,
    'user_id': userId,
    'phone': '0599111111',
    'university': 'An-Najah National University',
    'major': 'Software Engineering',
    'graduation_year': 2027,
    'bio': 'Backend Laravel Developer',
    'profile_image': null,
    'user': {'id': userId, 'name': name, 'email': email},
  };
}

Map<String, dynamic> _applicationJson({
  int id = 1,
  int studentId = 1,
  int opportunityId = 1,
  int cvId = 1,
  String status = 'pending',
  dynamic matchScore,
  String? coverLetter,
  bool includeOpportunity = true,
  bool includeStudentProfile = false,
}) {
  return {
    'id': id,
    'student_id': studentId,
    'opportunity_id': opportunityId,
    'cv_id': cvId,
    'status': status,
    'match_score': matchScore,
    'cover_letter': coverLetter,
    'applied_at': '2026-07-20T09:00:00.000000Z',
    'reviewed_at': null,
    'created_at': '2026-07-20T09:00:00.000000Z',
    'updated_at': '2026-07-20T09:00:00.000000Z',
    if (includeOpportunity) 'opportunity': _opportunityJson(id: opportunityId),
    'cv': _cvJson(id: cvId),
    if (includeStudentProfile) 'student_profile': _studentProfileJson(),
  };
}

Map<String, dynamic> _analysisJson({
  dynamic overallMatchScore = 87,
  dynamic skillsMatchScore = 90,
  dynamic experienceMatchScore = 66.67,
  dynamic strengths = const ['Matches required skill: Laravel'],
  dynamic weaknesses = const ['Missing preferred skill: Docker'],
  dynamic recommendation = 'Strong candidate, recommended for interview.',
}) {
  return {
    'overall_match_score': overallMatchScore,
    'skills_match_score': skillsMatchScore,
    'experience_match_score': experienceMatchScore,
    'strengths': strengths,
    'weaknesses': weaknesses,
    'recommendation': recommendation,
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, (call) async {
          if (call.method == 'read') return null;
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, null);
  });

  group('getStudentApplications', () {
    test('uses the exact documented method and path', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({'data': []}, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      await repository.getStudentApplications();

      expect(adapter.lastRequest?.method, 'GET');
      expect(adapter.lastRequest?.path, '/student/applications');
    });

    test(
      'parses a valid application list, with nested opportunity and cv',
      () async {
        final adapter = _FakeHttpClientAdapter((options) {
          return _jsonResponse({
            'data': [
              _applicationJson(id: 1, opportunityId: 5, cvId: 2),
              _applicationJson(id: 2, opportunityId: 6, cvId: 2),
            ],
          }, 200);
        });
        final repository = _repositoryWithAdapter(adapter);

        final result = await repository.getStudentApplications();

        expect(result, hasLength(2));
        expect(result[0].id, 1);
        expect(result[0].opportunity?.id, 5);
        expect(result[0].cv.id, 2);
        expect(result[1].id, 2);
      },
    );

    test('parses decimal match_score serialized as a string', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': [_applicationJson(matchScore: '75.50')],
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      final result = await repository.getStudentApplications();

      expect(result.single.matchScore, 75.5);
      expect(result.single.matchScore, isA<double>());
    });

    test('parses an empty list', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({'data': []}, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      final result = await repository.getStudentApplications();

      expect(result, isEmpty);
    });

    test(
      'malformed response data is never silently swallowed (surfaces as an error)',
      () async {
        final adapter = _FakeHttpClientAdapter((options) {
          return _jsonResponse({
            'data': [
              {'id': 1},
            ],
          }, 200);
        });
        final repository = _repositoryWithAdapter(adapter);

        await expectLater(
          repository.getStudentApplications(),
          throwsA(anything),
        );
      },
    );

    test('throws ApiException on a 401', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'success': false,
          'message': 'Unauthenticated',
          'data': null,
        }, 401);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.getStudentApplications(),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401),
        ),
      );
    });

    test('throws ApiException on a 403', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'success': false,
          'message': 'This action is unauthorized for your account type',
          'data': null,
        }, 403);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.getStudentApplications(),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 403),
        ),
      );
    });

    test('throws ApiException on a 404', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'success': false,
          'message': 'You must create a student profile first',
          'data': null,
        }, 404);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.getStudentApplications(),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'You must create a student profile first',
          ),
        ),
      );
    });
  });

  group('applyToOpportunity', () {
    test('uses the exact documented method and path', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({'data': _applicationJson()}, 201);
      });
      final repository = _repositoryWithAdapter(adapter);

      await repository.applyToOpportunity(opportunityId: 7, cvId: 1);

      expect(adapter.lastRequest?.method, 'POST');
      expect(adapter.lastRequest?.path, '/opportunities/7/apply');
    });

    test('sends cv_id, and omits cover_letter when null', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({'data': _applicationJson()}, 201);
      });
      final repository = _repositoryWithAdapter(adapter);

      await repository.applyToOpportunity(opportunityId: 7, cvId: 3);

      final body = adapter.lastRequest?.data as Map<String, dynamic>;
      expect(body.keys.toSet(), {'cv_id'});
      expect(body['cv_id'], 3);
    });

    test('includes cover_letter when provided', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({'data': _applicationJson()}, 201);
      });
      final repository = _repositoryWithAdapter(adapter);

      await repository.applyToOpportunity(
        opportunityId: 7,
        cvId: 3,
        coverLetter: 'I would love to join.',
      );

      final body = adapter.lastRequest?.data as Map<String, dynamic>;
      expect(body['cover_letter'], 'I would love to join.');
    });

    test('returns the parsed created application', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': _applicationJson(id: 42, opportunityId: 7, cvId: 3),
        }, 201);
      });
      final repository = _repositoryWithAdapter(adapter);

      final result = await repository.applyToOpportunity(
        opportunityId: 7,
        cvId: 3,
      );

      expect(result.id, 42);
      expect(result.opportunityId, 7);
      expect(result.cvId, 3);
      expect(result.status, 'pending');
    });

    test(
      'throws with the exact 409 message on a duplicate application',
      () async {
        final adapter = _FakeHttpClientAdapter((options) {
          return _jsonResponse({
            'success': false,
            'message': 'You have already applied to this opportunity',
            'data': null,
          }, 409);
        });
        final repository = _repositoryWithAdapter(adapter);

        await expectLater(
          repository.applyToOpportunity(opportunityId: 7, cvId: 1),
          throwsA(
            isA<ApiException>()
                .having((e) => e.statusCode, 'statusCode', 409)
                .having(
                  (e) => e.message,
                  'message',
                  'You have already applied to this opportunity',
                ),
          ),
        );
      },
    );

    test(
      'throws on the documented 404 (opportunity not open / not approved)',
      () async {
        final adapter = _FakeHttpClientAdapter((options) {
          return _jsonResponse({
            'success': false,
            'message': 'Opportunity not found',
            'data': null,
          }, 404);
        });
        final repository = _repositoryWithAdapter(adapter);

        await expectLater(
          repository.applyToOpportunity(opportunityId: 999, cvId: 1),
          throwsA(isA<ApiException>()),
        );
      },
    );

    test(
      'throws with the backend message on 422 (e.g. foreign CV or missing CV)',
      () async {
        final adapter = _FakeHttpClientAdapter((options) {
          return _jsonResponse({
            'message': 'The given data was invalid.',
            'errors': {
              'cv_id': ['The selected cv id is invalid.'],
            },
          }, 422);
        });
        final repository = _repositoryWithAdapter(adapter);

        await expectLater(
          repository.applyToOpportunity(opportunityId: 7, cvId: 999),
          throwsA(
            isA<ApiException>().having(
              (e) => e.errors?['cv_id'],
              'errors[cv_id]',
              contains('The selected cv id is invalid.'),
            ),
          ),
        );
      },
    );
  });

  group('getApplicationsForOpportunity', () {
    test('uses the exact documented method and path', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({'data': []}, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      await repository.getApplicationsForOpportunity(5);

      expect(adapter.lastRequest?.method, 'GET');
      expect(
        adapter.lastRequest?.path,
        '/organization/opportunities/5/applications',
      );
    });

    test('parses applicants, including the nested student_profile.user, '
        'even though opportunity is omitted from this endpoint', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': [
            _applicationJson(
              id: 1,
              opportunityId: 5,
              includeOpportunity: false,
              includeStudentProfile: true,
            ),
          ],
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      final result = await repository.getApplicationsForOpportunity(5);

      expect(result, hasLength(1));
      expect(result.single.opportunity, isNull);
      expect(result.single.opportunityId, 5);
      expect(result.single.applicant?.name, 'Jane Student');
      expect(result.single.applicant?.email, 'jane@example.com');
    });

    test('parses an empty list', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({'data': []}, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      final result = await repository.getApplicationsForOpportunity(5);

      expect(result, isEmpty);
    });

    test('malformed response data is never silently swallowed', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': [
            {'id': 1},
          ],
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.getApplicationsForOpportunity(5),
        throwsA(anything),
      );
    });

    test('throws ApiException on a 401', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'success': false,
          'message': 'Unauthenticated',
          'data': null,
        }, 401);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.getApplicationsForOpportunity(5),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401),
        ),
      );
    });

    test('throws ApiException on a 403', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'success': false,
          'message': 'This action is unauthorized for your account type',
          'data': null,
        }, 403);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.getApplicationsForOpportunity(5),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 403),
        ),
      );
    });

    test(
      'throws on the documented 404 (opportunity not owned / not found)',
      () async {
        final adapter = _FakeHttpClientAdapter((options) {
          return _jsonResponse({
            'success': false,
            'message': 'Opportunity not found',
            'data': null,
          }, 404);
        });
        final repository = _repositoryWithAdapter(adapter);

        await expectLater(
          repository.getApplicationsForOpportunity(999),
          throwsA(
            isA<ApiException>().having(
              (e) => e.message,
              'message',
              'Opportunity not found',
            ),
          ),
        );
      },
    );
  });

  group('getOrganizationApplication', () {
    test('uses the exact documented method and path', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': _applicationJson(id: 9, includeStudentProfile: true),
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      final result = await repository.getOrganizationApplication(9);

      expect(adapter.lastRequest?.method, 'GET');
      expect(adapter.lastRequest?.path, '/organization/applications/9');
      expect(result.id, 9);
    });

    test('parses the nested applicant identity', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': _applicationJson(includeStudentProfile: true),
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      final result = await repository.getOrganizationApplication(1);

      expect(result.applicant?.name, 'Jane Student');
      expect(result.applicant?.email, 'jane@example.com');
      expect(result.applicant?.university, 'An-Najah National University');
      expect(result.opportunity, isNotNull);
    });

    test('throws on the documented 404 (not owned / not found)', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'success': false,
          'message': 'Application not found',
          'data': null,
        }, 404);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.getOrganizationApplication(999),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'Application not found',
          ),
        ),
      );
    });

    test('malformed response data is never silently swallowed', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': {'id': 1},
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.getOrganizationApplication(1),
        throwsA(anything),
      );
    });
  });

  group('updateOrganizationApplicationStatus', () {
    test('uses the exact documented method and path', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': _applicationJson(status: 'reviewed'),
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      await repository.updateOrganizationApplicationStatus(
        applicationId: 1,
        status: 'reviewed',
      );

      expect(adapter.lastRequest?.method, 'PUT');
      expect(adapter.lastRequest?.path, '/organization/applications/1/status');
    });

    test('sends exactly the status field in the request body', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': _applicationJson(status: 'shortlisted'),
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      await repository.updateOrganizationApplicationStatus(
        applicationId: 1,
        status: 'shortlisted',
      );

      final body = adapter.lastRequest?.data as Map<String, dynamic>;
      expect(body, {'status': 'shortlisted'});
    });

    test('reviewed succeeds and returns the updated application', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': _applicationJson(status: 'reviewed'),
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      final result = await repository.updateOrganizationApplicationStatus(
        applicationId: 1,
        status: 'reviewed',
      );

      expect(result.status, 'reviewed');
    });

    test('shortlisted succeeds and returns the updated application', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': _applicationJson(status: 'shortlisted'),
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      final result = await repository.updateOrganizationApplicationStatus(
        applicationId: 1,
        status: 'shortlisted',
      );

      expect(result.status, 'shortlisted');
    });

    test('rejected succeeds and returns the updated application', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': _applicationJson(status: 'rejected'),
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      final result = await repository.updateOrganizationApplicationStatus(
        applicationId: 1,
        status: 'rejected',
      );

      expect(result.status, 'rejected');
    });

    test(
      'throws with the exact 409 message for a withdrawn application',
      () async {
        final adapter = _FakeHttpClientAdapter((options) {
          return _jsonResponse({
            'success': false,
            'message': 'Cannot change the status of a withdrawn application',
            'data': null,
          }, 409);
        });
        final repository = _repositoryWithAdapter(adapter);

        await expectLater(
          repository.updateOrganizationApplicationStatus(
            applicationId: 1,
            status: 'reviewed',
          ),
          throwsA(
            isA<ApiException>()
                .having((e) => e.statusCode, 'statusCode', 409)
                .having(
                  (e) => e.message,
                  'message',
                  'Cannot change the status of a withdrawn application',
                ),
          ),
        );
      },
    );

    test('throws with the backend message on 422 (invalid status)', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'message': 'The given data was invalid.',
          'errors': {
            'status': ['The selected status is invalid.'],
          },
        }, 422);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.updateOrganizationApplicationStatus(
          applicationId: 1,
          status: 'not-a-real-status',
        ),
        throwsA(
          isA<ApiException>().having(
            (e) => e.errors?['status'],
            'errors[status]',
            contains('The selected status is invalid.'),
          ),
        ),
      );
    });

    test('malformed response data is never silently swallowed', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': {'id': 1},
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.updateOrganizationApplicationStatus(
          applicationId: 1,
          status: 'reviewed',
        ),
        throwsA(anything),
      );
    });
  });

  group('getApplicationAnalysis', () {
    test('uses the exact documented method and path', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({'data': _analysisJson()}, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      await repository.getApplicationAnalysis(1);

      expect(adapter.lastRequest?.method, 'GET');
      expect(
        adapter.lastRequest?.path,
        '/organization/applications/1/analysis',
      );
    });

    test('parses a valid analysis response', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': _analysisJson(overallMatchScore: 72.5),
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      final result = await repository.getApplicationAnalysis(1);

      expect(result.overallMatchScore, 72.5);
    });

    test('a null factor score parses correctly', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': _analysisJson(skillsMatchScore: null),
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      final result = await repository.getApplicationAnalysis(1);

      expect(result.skillsMatchScore, isNull);
    });

    test('throws ApiException on a 404 (never analyzed / not owned)', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'success': false,
          'message': 'Application analysis not found',
          'data': null,
        }, 404);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.getApplicationAnalysis(1),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 404)
              .having(
                (e) => e.message,
                'message',
                'Application analysis not found',
              ),
        ),
      );
    });

    test('throws ApiException on a 401', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'success': false,
          'message': 'Unauthenticated',
          'data': null,
        }, 401);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.getApplicationAnalysis(1),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401),
        ),
      );
    });

    test('throws ApiException on a 403', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'success': false,
          'message': 'This action is unauthorized for your account type',
          'data': null,
        }, 403);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.getApplicationAnalysis(1),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 403),
        ),
      );
    });

    test('malformed success response is never silently swallowed', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': {'overall_match_score': 'not-a-number'},
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.getApplicationAnalysis(1),
        throwsA(isA<TypeError>()),
      );
    });
  });

  group('analyzeApplication', () {
    test(
      'uses the exact documented method and path, with no request body',
      () async {
        final adapter = _FakeHttpClientAdapter((options) {
          return _jsonResponse({'data': _analysisJson()}, 200);
        });
        final repository = _repositoryWithAdapter(adapter);

        await repository.analyzeApplication(1);

        expect(adapter.lastRequest?.method, 'POST');
        expect(
          adapter.lastRequest?.path,
          '/organization/applications/1/analyze',
        );
        expect(adapter.lastRequest?.data, isNull);
      },
    );

    test('parses the returned analysis', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': _analysisJson(overallMatchScore: 88),
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      final result = await repository.analyzeApplication(1);

      expect(result.overallMatchScore, 88.0);
    });

    test(
      'throws ApiException on a 404 (application not owned/missing)',
      () async {
        final adapter = _FakeHttpClientAdapter((options) {
          return _jsonResponse({
            'success': false,
            'message': 'Application not found',
            'data': null,
          }, 404);
        });
        final repository = _repositoryWithAdapter(adapter);

        await expectLater(
          repository.analyzeApplication(1),
          throwsA(
            isA<ApiException>()
                .having((e) => e.statusCode, 'statusCode', 404)
                .having((e) => e.message, 'message', 'Application not found'),
          ),
        );
      },
    );

    test('throws ApiException on a 403', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'success': false,
          'message': 'This action is unauthorized for your account type',
          'data': null,
        }, 403);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.analyzeApplication(1),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 403),
        ),
      );
    });

    test('throws ApiException on a 422', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'message': 'The given data was invalid.',
          'data': null,
        }, 422);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.analyzeApplication(1),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 422),
        ),
      );
    });

    test('malformed success response is never silently swallowed', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': {'overall_match_score': 'not-a-number'},
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.analyzeApplication(1),
        throwsA(isA<TypeError>()),
      );
    });
  });

  group('downloadOrganizationApplicationCv', () {
    test('uses the exact documented method and path', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _pdfResponse([0x25, 0x50, 0x44, 0x46], 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      await repository.downloadOrganizationApplicationCv(7);

      expect(adapter.lastRequest?.method, 'GET');
      expect(adapter.lastRequest?.path, '/organization/applications/7/cv');
    });

    test('returns the exact raw bytes', () async {
      final bytes = [0x25, 0x50, 0x44, 0x46, 0x2d, 0x31, 0x2e, 0x34];
      final adapter = _FakeHttpClientAdapter((options) {
        return _pdfResponse(bytes, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      final result = await repository.downloadOrganizationApplicationCv(7);

      expect(result, bytes);
    });

    test(
      'throws ApiException with the decoded backend message on a 404',
      () async {
        final adapter = _FakeHttpClientAdapter((options) {
          return _jsonErrorAsBytes({
            'success': false,
            'message': 'Application not found',
            'data': null,
          }, 404);
        });
        final repository = _repositoryWithAdapter(adapter);

        await expectLater(
          repository.downloadOrganizationApplicationCv(999),
          throwsA(
            isA<ApiException>()
                .having((e) => e.statusCode, 'statusCode', 404)
                .having((e) => e.message, 'message', 'Application not found'),
          ),
        );
      },
    );

    test(
      'throws ApiException with the decoded backend message when the CV file is missing',
      () async {
        final adapter = _FakeHttpClientAdapter((options) {
          return _jsonErrorAsBytes({
            'success': false,
            'message': 'CV file not found',
            'data': null,
          }, 404);
        });
        final repository = _repositoryWithAdapter(adapter);

        await expectLater(
          repository.downloadOrganizationApplicationCv(7),
          throwsA(
            isA<ApiException>().having(
              (e) => e.message,
              'message',
              'CV file not found',
            ),
          ),
        );
      },
    );

    test('throws ApiException on a 403', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonErrorAsBytes({
          'success': false,
          'message': 'This action is unauthorized for your account type',
          'data': null,
        }, 403);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.downloadOrganizationApplicationCv(7),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 403),
        ),
      );
    });
  });
}
