// Direct unit tests for OpportunityRepository.
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
import 'package:opportunityhub_flutter/features/opportunities/data/opportunity_repository.dart';

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

OpportunityRepository _repositoryWithAdapter(_FakeHttpClientAdapter adapter) {
  final apiClient = ApiClient(tokenStorageService: TokenStorageService())
    ..dio.httpClientAdapter = adapter;
  return OpportunityRepository(apiClient: apiClient);
}

Map<String, dynamic> _opportunityJson({
  int id = 1,
  String title = 'Software Engineer',
  String opportunityType = 'job',
  String status = 'open',
  dynamic salaryMin = '1500.00',
  dynamic salaryMax = '2500.00',
  String? applicationDeadline = '2027-01-15',
  int positionsAvailable = 1,
}) {
  return {
    'id': id,
    'title': title,
    'description': 'A great opportunity.',
    'opportunity_type': opportunityType,
    'employment_type': 'full_time',
    'work_mode': 'remote',
    'experience_level': 'junior',
    'education_level': null,
    'field_of_study': null,
    'location': 'Amman, Jordan',
    'salary_min': salaryMin,
    'salary_max': salaryMax,
    'application_deadline': applicationDeadline,
    'positions_available': positionsAvailable,
    'status': status,
    'created_at': '2026-07-01T10:00:00.000000Z',
    'updated_at': '2026-07-01T10:00:00.000000Z',
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

  group('getOpportunities', () {
    test('uses the exact documented method and path', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({'data': []}, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      await repository.getOpportunities();

      expect(adapter.lastRequest?.method, 'GET');
      expect(adapter.lastRequest?.path, '/organization/opportunities');
    });

    test('parses a flat, unpaginated list', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': [
            _opportunityJson(id: 1, title: 'Software Engineer'),
            _opportunityJson(id: 2, title: 'Marketing Intern'),
          ],
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      final result = await repository.getOpportunities();

      expect(result, hasLength(2));
      expect(result[0].id, 1);
      expect(result[0].title, 'Software Engineer');
      expect(result[1].id, 2);
      expect(result[1].title, 'Marketing Intern');
    });

    test('parses an empty list', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({'data': []}, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      final result = await repository.getOpportunities();

      expect(result, isEmpty);
    });

    test(
      'parses decimal salary fields serialized as strings, and job/internship enums',
      () async {
        final adapter = _FakeHttpClientAdapter((options) {
          return _jsonResponse({
            'data': [
              _opportunityJson(
                opportunityType: 'internship',
                salaryMin: '1500.00',
                salaryMax: '2500.50',
              ),
            ],
          }, 200);
        });
        final repository = _repositoryWithAdapter(adapter);

        final result = await repository.getOpportunities();

        expect(result.single.opportunityType, 'internship');
        expect(result.single.salaryMin, 1500.0);
        expect(result.single.salaryMax, 2500.5);
        expect(result.single.salaryMin, isA<double>());
      },
    );

    test('throws ApiException on a server error', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'success': false,
          'message': 'Server error, please try again later.',
          'data': null,
        }, 500);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.getOpportunities(),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('getOpportunity', () {
    test('uses the exact documented method and path', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({'data': _opportunityJson(id: 7)}, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      final result = await repository.getOpportunity(7);

      expect(adapter.lastRequest?.method, 'GET');
      expect(adapter.lastRequest?.path, '/organization/opportunities/7');
      expect(result.id, 7);
    });

    test(
      'throws ApiException on the documented 404 (not found / not yours)',
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
          repository.getOpportunity(999),
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

  group('createOpportunity', () {
    test(
      'sends exactly the required key set when optional fields are omitted',
      () async {
        final adapter = _FakeHttpClientAdapter((options) {
          return _jsonResponse({'data': _opportunityJson()}, 201);
        });
        final repository = _repositoryWithAdapter(adapter);

        await repository.createOpportunity(
          title: 'Software Engineer',
          description: 'A great opportunity.',
          opportunityType: 'job',
          employmentType: 'full_time',
          workMode: 'remote',
          experienceLevel: 'junior',
        );

        expect(adapter.lastRequest?.method, 'POST');
        expect(adapter.lastRequest?.path, '/organization/opportunities');
        final body = adapter.lastRequest?.data as Map<String, dynamic>;
        // `location_id` is always sent, even when null (Phase O8.2) --
        // unlike every other optional field here, which is omitted
        // entirely when absent.
        expect(body.keys.toSet(), {
          'title',
          'description',
          'opportunity_type',
          'employment_type',
          'work_mode',
          'experience_level',
          'location_id',
        });
        expect(body['location_id'], isNull);
      },
    );

    test(
      'includes optional fields only when provided, as correct JSON types',
      () async {
        final adapter = _FakeHttpClientAdapter((options) {
          return _jsonResponse({'data': _opportunityJson()}, 201);
        });
        final repository = _repositoryWithAdapter(adapter);

        await repository.createOpportunity(
          title: 'Software Engineer',
          description: 'A great opportunity.',
          opportunityType: 'job',
          employmentType: 'full_time',
          workMode: 'onsite',
          experienceLevel: 'junior',
          educationLevel: 'bachelor',
          locationId: 5,
          salaryMin: 1500,
          salaryMax: 2500,
          applicationDeadline: DateTime(2027, 1, 15),
          positionsAvailable: 3,
          status: 'draft',
        );

        final body = adapter.lastRequest?.data as Map<String, dynamic>;
        expect(body.keys.toSet(), {
          'title',
          'description',
          'opportunity_type',
          'employment_type',
          'work_mode',
          'experience_level',
          'education_level',
          'location_id',
          'salary_min',
          'salary_max',
          'application_deadline',
          'positions_available',
          'status',
        });
        expect(body['location_id'], 5);
        expect(body['salary_min'], isA<num>());
        expect(body['salary_max'], isA<num>());
        expect(body['positions_available'], isA<int>());
        expect(body['application_deadline'], '2027-01-15');
      },
    );

    test(
      'never sends field_of_study -- deprecated by the Opportunity '
      'Academic Matching Cleanup, not a parameter on this method at all',
      () async {
        final adapter = _FakeHttpClientAdapter((options) {
          return _jsonResponse({'data': _opportunityJson()}, 201);
        });
        final repository = _repositoryWithAdapter(adapter);

        await repository.createOpportunity(
          title: 'Software Engineer',
          description: 'A great opportunity.',
          opportunityType: 'job',
          employmentType: 'full_time',
          workMode: 'remote',
          experienceLevel: 'junior',
        );

        final body = adapter.lastRequest?.data as Map<String, dynamic>;
        expect(body.containsKey('field_of_study'), isFalse);
      },
    );

    test('sends eligible_majors and skills atomically, never a separate later '
        'call (Opportunity Requirements Integrity Patch)', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({'data': _opportunityJson()}, 201);
      });
      final repository = _repositoryWithAdapter(adapter);

      await repository.createOpportunity(
        title: 'Software Engineer',
        description: 'A great opportunity.',
        opportunityType: 'job',
        employmentType: 'full_time',
        workMode: 'remote',
        experienceLevel: 'junior',
        eligibleMajors: ['Civil Engineering'],
        skills: {10: true, 11: false},
      );

      final body = adapter.lastRequest?.data as Map<String, dynamic>;
      expect(body['eligible_majors'], ['Civil Engineering']);
      expect(body['skills'], [
        {'skill_id': 10, 'is_required': true},
        {'skill_id': 11, 'is_required': false},
      ]);
    });

    test(
      'throws with the exact 403 approval message on an unapproved organization',
      () async {
        final adapter = _FakeHttpClientAdapter((options) {
          return _jsonResponse({
            'success': false,
            'message': 'Organization is not approved to publish opportunities',
            'data': null,
          }, 403);
        });
        final repository = _repositoryWithAdapter(adapter);

        await expectLater(
          repository.createOpportunity(
            title: 'Software Engineer',
            description: 'A great opportunity.',
            opportunityType: 'job',
            employmentType: 'full_time',
            workMode: 'remote',
            experienceLevel: 'junior',
          ),
          throwsA(
            isA<ApiException>()
                .having((e) => e.statusCode, 'statusCode', 403)
                .having(
                  (e) => e.message,
                  'message',
                  'Organization is not approved to publish opportunities',
                ),
          ),
        );
      },
    );

    test('throws with the backend message on 422 validation', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'message': 'The given data was invalid.',
          'errors': {
            'title': ['The title field is required.'],
          },
        }, 422);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.createOpportunity(
          title: '',
          description: 'A great opportunity.',
          opportunityType: 'job',
          employmentType: 'full_time',
          workMode: 'remote',
          experienceLevel: 'junior',
        ),
        throwsA(
          isA<ApiException>().having(
            (e) => e.errors?['title'],
            'errors[title]',
            contains('The title field is required.'),
          ),
        ),
      );
    });
  });

  group('updateOpportunity', () {
    test('uses the exact documented method, path, and payload', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': _opportunityJson(id: 5, title: 'Senior Software Engineer'),
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      final result = await repository.updateOpportunity(
        id: 5,
        title: 'Senior Software Engineer',
        description: 'A great opportunity.',
        opportunityType: 'job',
        employmentType: 'full_time',
        workMode: 'remote',
        experienceLevel: 'senior',
      );

      expect(adapter.lastRequest?.method, 'PUT');
      expect(adapter.lastRequest?.path, '/organization/opportunities/5');
      final body = adapter.lastRequest?.data as Map<String, dynamic>;
      expect(body['title'], 'Senior Software Engineer');
      expect(result.title, 'Senior Software Engineer');
    });

    test('throws on the documented 404 (not found / not yours)', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'success': false,
          'message': 'Opportunity not found',
          'data': null,
        }, 404);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.updateOpportunity(
          id: 999,
          title: 'Hijacked Title',
          description: 'A great opportunity.',
          opportunityType: 'job',
          employmentType: 'full_time',
          workMode: 'remote',
          experienceLevel: 'junior',
        ),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('getPublicOpportunities', () {
    test('uses the exact documented method and path', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': {'current_page': 1, 'data': [], 'last_page': 1, 'total': 0},
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      await repository.getPublicOpportunities();

      expect(adapter.lastRequest?.method, 'GET');
      expect(adapter.lastRequest?.path, '/opportunities');
    });

    test('sends only page/per_page when no filters are given', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': {'current_page': 1, 'data': [], 'last_page': 1, 'total': 0},
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      await repository.getPublicOpportunities();

      final query = adapter.lastRequest?.queryParameters;
      expect(query?.keys.toSet(), {'page', 'per_page'});
      expect(query?['page'], 1);
      expect(query?['per_page'], 15);
    });

    test('includes filters only when provided', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': {'current_page': 1, 'data': [], 'last_page': 1, 'total': 0},
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      await repository.getPublicOpportunities(
        opportunityType: 'job',
        employmentType: 'full_time',
        workMode: 'remote',
        experienceLevel: 'junior',
        location: 'Amman',
        fieldOfStudy: 'Computer Science',
        keyword: 'engineer',
        page: 2,
        perPage: 20,
      );

      final query = adapter.lastRequest?.queryParameters;
      expect(query?['opportunity_type'], 'job');
      expect(query?['employment_type'], 'full_time');
      expect(query?['work_mode'], 'remote');
      expect(query?['experience_level'], 'junior');
      expect(query?['location'], 'Amman');
      expect(query?['field_of_study'], 'Computer Science');
      expect(query?['keyword'], 'engineer');
      expect(query?['page'], 2);
      expect(query?['per_page'], 20);
    });

    test(
      'parses the paginator envelope: items, current/last page, total',
      () async {
        final adapter = _FakeHttpClientAdapter((options) {
          return _jsonResponse({
            'data': {
              'current_page': 1,
              'data': [
                _opportunityJson(id: 1, title: 'Software Engineer'),
                _opportunityJson(id: 2, title: 'Marketing Intern'),
              ],
              'last_page': 3,
              'total': 42,
            },
          }, 200);
        });
        final repository = _repositoryWithAdapter(adapter);

        final result = await repository.getPublicOpportunities();

        expect(result.items, hasLength(2));
        expect(result.items[0].id, 1);
        expect(result.currentPage, 1);
        expect(result.lastPage, 3);
        expect(result.total, 42);
        expect(result.hasMore, isTrue);
      },
    );

    test(
      'parses nested organizationProfile and opportunitySkills relations',
      () async {
        final adapter = _FakeHttpClientAdapter((options) {
          return _jsonResponse({
            'data': {
              'current_page': 1,
              'data': [
                {
                  ..._opportunityJson(id: 1),
                  'organization_profile': {
                    'id': 3,
                    'organization_name': 'Acme Corp',
                    'organization_type': 'company',
                    'approval_status': 'approved',
                  },
                  'opportunity_skills': [
                    {
                      'id': 9,
                      'is_required': true,
                      'skill': {'id': 4, 'name': 'Flutter', 'category': 'Tech'},
                    },
                  ],
                },
              ],
              'last_page': 1,
              'total': 1,
            },
          }, 200);
        });
        final repository = _repositoryWithAdapter(adapter);

        final result = await repository.getPublicOpportunities();

        final opportunity = result.items.single;
        expect(opportunity.organizationProfile?.organizationName, 'Acme Corp');
        expect(opportunity.opportunitySkills, hasLength(1));
        expect(opportunity.opportunitySkills.single.skill.name, 'Flutter');
        expect(opportunity.opportunitySkills.single.isRequired, isTrue);
      },
    );

    test(
      'a response with no relations parses with null organizationProfile and empty skills',
      () async {
        final adapter = _FakeHttpClientAdapter((options) {
          return _jsonResponse({
            'data': {
              'current_page': 1,
              'data': [_opportunityJson(id: 1)],
              'last_page': 1,
              'total': 1,
            },
          }, 200);
        });
        final repository = _repositoryWithAdapter(adapter);

        final result = await repository.getPublicOpportunities();

        expect(result.items.single.organizationProfile, isNull);
        expect(result.items.single.opportunitySkills, isEmpty);
      },
    );

    test('throws ApiException on a 422 invalid filter value', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'message': 'The given data was invalid.',
          'errors': {
            'opportunity_type': ['The selected opportunity type is invalid.'],
          },
        }, 422);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.getPublicOpportunities(),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('getPublicOpportunity', () {
    test('uses the exact documented method and path', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({'data': _opportunityJson(id: 6)}, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      final result = await repository.getPublicOpportunity(6);

      expect(adapter.lastRequest?.method, 'GET');
      expect(adapter.lastRequest?.path, '/opportunities/6');
      expect(result.id, 6);
    });

    test(
      'throws ApiException on the documented 404 (not open / not approved / nonexistent)',
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
          repository.getPublicOpportunity(999),
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

  group('deleteOpportunity', () {
    test('uses the exact documented method and path', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'success': true,
          'message': 'Opportunity deleted successfully',
          'data': null,
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      await repository.deleteOpportunity(5);

      expect(adapter.lastRequest?.method, 'DELETE');
      expect(adapter.lastRequest?.path, '/organization/opportunities/5');
    });

    test(
      'throws with the documented 409 message when applications exist',
      () async {
        final adapter = _FakeHttpClientAdapter((options) {
          return _jsonResponse({
            'success': false,
            'message': 'Cannot delete an opportunity that has applications',
            'data': null,
          }, 409);
        });
        final repository = _repositoryWithAdapter(adapter);

        await expectLater(
          repository.deleteOpportunity(5),
          throwsA(
            isA<ApiException>()
                .having((e) => e.statusCode, 'statusCode', 409)
                .having(
                  (e) => e.message,
                  'message',
                  'Cannot delete an opportunity that has applications',
                ),
          ),
        );
      },
    );

    test('throws on the documented 404 (not found / not yours)', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'success': false,
          'message': 'Opportunity not found',
          'data': null,
        }, 404);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.deleteOpportunity(999),
        throwsA(isA<ApiException>()),
      );
    });
  });
}
