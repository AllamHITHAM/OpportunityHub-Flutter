// Direct unit tests for OrganizationProfileModel, focused on the additive
// `user` field extension added for Phase 5A-3 (Admin Organization
// Management) — see admin_organizations_repository_test.dart for the
// repository-boundary validation that sits in front of this model.

import 'package:flutter_test/flutter_test.dart';

import 'package:opportunityhub_flutter/models/organization_profile_model.dart';

void main() {
  group('fromJson', () {
    test('old existing JSON (no user field) still parses', () {
      final json = {
        'id': 1,
        'organization_name': 'Acme Corp',
        'organization_type': 'company',
        'approval_status': 'approved',
        'industry': 'Tech',
        'description': 'A company',
        'website': 'https://acme.example',
        'phone': '555-1234',
      };

      final model = OrganizationProfileModel.fromJson(json);

      expect(model.id, 1);
      expect(model.organizationName, 'Acme Corp');
      expect(model.organizationType, 'company');
      expect(model.approvalStatus, 'approved');
      expect(model.industry, 'Tech');
      expect(model.description, 'A company');
      expect(model.website, 'https://acme.example');
      expect(model.phone, '555-1234');
      expect(model.user, isNull);
    });

    test('a nested user object parses into UserModel', () {
      final json = {
        'id': 1,
        'organization_name': 'Acme Corp',
        'organization_type': 'company',
        'approval_status': 'pending',
        'user': {
          'id': 9,
          'name': 'Acme Contact',
          'email': 'contact@acme.example',
          'role': 'organization',
          'status': 'active',
        },
      };

      final model = OrganizationProfileModel.fromJson(json);

      expect(model.user, isNotNull);
      expect(model.user!.id, 9);
      expect(model.user!.email, 'contact@acme.example');
      expect(model.user!.role, 'organization');
    });

    test('a missing user field remains null (backward compatible)', () {
      final json = {
        'id': 1,
        'organization_name': 'Acme Corp',
        'organization_type': 'company',
        'approval_status': 'pending',
      };

      final model = OrganizationProfileModel.fromJson(json);

      expect(model.user, isNull);
    });

    test('a malformed (non-object) user field becomes null, not a crash', () {
      final json = {
        'id': 1,
        'organization_name': 'Acme Corp',
        'organization_type': 'company',
        'approval_status': 'pending',
        'user': 'not-an-object',
      };

      final model = OrganizationProfileModel.fromJson(json);

      expect(model.user, isNull);
    });

    test('a null user field remains null', () {
      final json = {
        'id': 1,
        'organization_name': 'Acme Corp',
        'organization_type': 'company',
        'approval_status': 'pending',
        'user': null,
      };

      final model = OrganizationProfileModel.fromJson(json);

      expect(model.user, isNull);
    });
  });

  group('constructor', () {
    test('remains backward-compatible without the user argument', () {
      const model = OrganizationProfileModel(
        id: 1,
        organizationName: 'Acme Corp',
        organizationType: 'company',
        approvalStatus: 'approved',
      );

      expect(model.user, isNull);
    });
  });
}
