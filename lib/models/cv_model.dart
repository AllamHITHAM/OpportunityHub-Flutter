/// A student's CV, as returned by the Laravel `student/cvs` endpoints.
///
/// `filePath` (Phase 8A-4) is the backend's own server-managed relative
/// storage path for a real uploaded PDF (e.g. `cvs/3/<uuid>.pdf`) — it is
/// never a working client URL and must never be displayed to the user or
/// used to build one; the file itself is only ever reachable through the
/// authenticated download endpoints (`CvRepository.downloadCv` /
/// `ApplicationRepository.downloadOrganizationApplicationCv`). A CV
/// created before this phase may still carry a legacy, non-managed string
/// here (e.g. a local path a student once typed into a plain text field).
class CvModel {
  const CvModel({
    required this.id,
    required this.studentId,
    required this.title,
    required this.filePath,
    required this.version,
    required this.isDefault,
    required this.createdByAi,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final int studentId;
  final String title;
  final String filePath;
  final int version;
  final bool isDefault;
  final bool createdByAi;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory CvModel.fromJson(Map<String, dynamic> json) {
    return CvModel(
      id: json['id'] as int,
      studentId: json['student_id'] as int,
      title: json['title'] as String,
      filePath: json['file_path'] as String,
      version: _parseInt(json['version']) ?? 1,
      isDefault: _parseBool(json['is_default']),
      createdByAi: _parseBool(json['created_by_ai']),
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
    );
  }

  /// Only [isDefault] is ever produced locally after a mutation (setting a
  /// different CV as default flips every other CV's flag off without a
  /// full refetch) — every other field only ever comes from the backend.
  CvModel copyWith({bool? isDefault}) {
    return CvModel(
      id: id,
      studentId: studentId,
      title: title,
      filePath: filePath,
      version: version,
      isDefault: isDefault ?? this.isDefault,
      createdByAi: createdByAi,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return null;
  }

  static bool _parseBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) return value == '1' || value.toLowerCase() == 'true';
    return false;
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
