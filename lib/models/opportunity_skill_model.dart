import 'skill_model.dart';

/// A skill attached to an opportunity, as returned nested inside the
/// `opportunity_skills` relation (`GET /api/opportunities`,
/// `GET /api/opportunities/{id}`) — the public-facing endpoints eager-load
/// `opportunitySkills.skill`; the organization-side endpoints don't include
/// this relation at all, so it's always an empty list there.
class OpportunitySkillModel {
  const OpportunitySkillModel({
    required this.id,
    required this.isRequired,
    required this.skill,
  });

  final int id;
  final bool isRequired;
  final SkillModel skill;

  factory OpportunitySkillModel.fromJson(Map<String, dynamic> json) {
    return OpportunitySkillModel(
      id: json['id'] as int,
      isRequired: json['is_required'] as bool? ?? false,
      skill: SkillModel.fromJson(json['skill'] as Map<String, dynamic>),
    );
  }
}
