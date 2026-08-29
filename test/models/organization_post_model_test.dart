// Direct unit tests for OrganizationPostModel's `image_url` parsing (Final
// Company Profile Manual-E2E Bug Fix regression coverage) -- the real
// bug was the backend's returned URL never actually rendering in a real
// browser (see MediaController's own doc comment for the CORS/dev-server
// root cause). This model's job is simply to pass whatever URL the
// backend returns straight through, verbatim -- never rebuild, re-host,
// or hardcode any part of it.

import 'package:flutter_test/flutter_test.dart';

import 'package:opportunityhub_flutter/models/organization_post_model.dart';

void main() {
  group('fromJson', () {
    test('a real image_url in the current /api/media/ shape parses through '
        'unmodified', () {
      final json = {
        'id': 2,
        'organization_id': 7,
        'title': 'test image',
        'body': 'goooooooooood',
        'image_url':
            'http://127.0.0.1:8000/api/media/organization-posts/7/f5506906-c6ca-49d5-8cb2-6ac8dcdc6eca.jpg',
        'created_at': '2026-08-29T13:36:08.000000Z',
      };

      final model = OrganizationPostModel.fromJson(json);

      expect(
        model.imageUrl,
        'http://127.0.0.1:8000/api/media/organization-posts/7/f5506906-c6ca-49d5-8cb2-6ac8dcdc6eca.jpg',
      );
    });

    test('a text-only post has a null image_url', () {
      final json = {
        'id': 1,
        'organization_id': 7,
        'title': 'test',
        'body': 'hi',
        'image_url': null,
        'created_at': '2026-08-29T11:51:08.000000Z',
      };

      final model = OrganizationPostModel.fromJson(json);

      expect(model.imageUrl, isNull);
    });

    test('a missing image_url key remains null, not a crash', () {
      final json = {
        'id': 1,
        'organization_id': 7,
        'title': 'test',
        'body': 'hi',
        'created_at': '2026-08-29T11:51:08.000000Z',
      };

      final model = OrganizationPostModel.fromJson(json);

      expect(model.imageUrl, isNull);
    });
  });
}
