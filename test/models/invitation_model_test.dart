import 'package:flutter_test/flutter_test.dart';

import 'package:opportunityhub_flutter/models/invitation_model.dart';

Map<String, dynamic> _json({
  String status = 'pending',
  String? message,
  bool includeOpportunity = true,
}) {
  return {
    'id': 1,
    'opportunity_id': 5,
    'student_id': 3,
    'status': status,
    'message': message,
    'created_at': '2026-08-20T09:00:00.000000Z',
    'updated_at': '2026-08-20T09:00:00.000000Z',
    if (includeOpportunity)
      'opportunity': {
        'id': 5,
        'title': 'Backend Developer',
        'organization_id': 2,
        'organization_profile': {'id': 2, 'organization_name': 'Hiring Co'},
      },
  };
}

void main() {
  group('InvitationModel.fromJson', () {
    test('parses every field', () {
      final invitation = InvitationModel.fromJson(
        _json(message: 'Please apply!'),
      );

      expect(invitation.id, 1);
      expect(invitation.opportunityId, 5);
      expect(invitation.status, 'pending');
      expect(invitation.opportunityTitle, 'Backend Developer');
      expect(invitation.organizationName, 'Hiring Co');
      expect(invitation.message, 'Please apply!');
      expect(invitation.createdAt, DateTime.parse('2026-08-20T09:00:00.000Z'));
    });

    test('message is null when the backend sends null', () {
      final invitation = InvitationModel.fromJson(_json());

      expect(invitation.message, isNull);
    });

    test('a missing opportunity relation is handled safely', () {
      final invitation = InvitationModel.fromJson(
        _json(includeOpportunity: false),
      );

      expect(invitation.opportunityTitle, '');
      expect(invitation.organizationName, '');
    });

    test('isPending/isAccepted/isDeclined reflect status', () {
      expect(InvitationModel.fromJson(_json(status: 'pending')).isPending, isTrue);
      expect(
        InvitationModel.fromJson(_json(status: 'accepted')).isAccepted,
        isTrue,
      );
      expect(
        InvitationModel.fromJson(_json(status: 'declined')).isDeclined,
        isTrue,
      );
      expect(
        InvitationModel.fromJson(_json(status: 'accepted')).isPending,
        isFalse,
      );
    });
  });
}
