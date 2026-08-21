/// One skill on a candidate summary, as returned nested inside
/// `GET /api/organization/candidates`'s `skills` array. Only ever carries
/// [name]/[source] -- the backend never includes anything else here (see
/// `Organization\CandidateController`).
class CandidateSkillModel {
  const CandidateSkillModel({required this.name, required this.source});

  final String name;

  /// `manual` or `cv_ai` -- mirrors `student_skills.source` exactly.
  final String source;

  /// Mirrors `StudentSkillModel.isCvSupported`/`evidenceLabel` exactly, so
  /// a candidate card shows the identical "CV-supported"/"Self-declared"
  /// wording the student's own Skills screen already uses.
  bool get isCvSupported => source == 'cv_ai';

  String get evidenceLabel => isCvSupported ? 'CV-supported' : 'Self-declared';

  factory CandidateSkillModel.fromJson(Map<String, dynamic> json) {
    return CandidateSkillModel(
      name: json['name'] as String,
      source: json['source'] as String,
    );
  }
}
