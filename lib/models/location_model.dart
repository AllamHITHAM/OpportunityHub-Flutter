/// One entry from the canonical Location Catalog (Phase O8.2) —
/// `GET /api/locations`. A real place with one stable ID; there is no
/// free-text location input anywhere in this app any more, so a Student's
/// available work locations and an Opportunity's own location both
/// reference this exact model.
///
/// [aliasNames] (Recommendation Accuracy Patch) are the real alternate
/// spellings/names/languages the backend already resolves to this exact
/// Location (see `LocationCatalogService` on the backend) -- typing any one
/// of them into the searchable location picker must locally match this
/// entry too, not just [canonicalName].
class LocationModel {
  const LocationModel({
    required this.id,
    required this.canonicalName,
    this.aliasNames = const [],
  });

  final int id;
  final String canonicalName;
  final List<String> aliasNames;

  /// True when [query] (already trimmed) case/whitespace-insensitively
  /// matches [canonicalName] or any [aliasNames] entry as a substring --
  /// the same normalization rule the backend's `LocationNormalizer` uses,
  /// applied client-side purely for instant local filtering as the Student
  /// types (never for eligibility -- that stays backend-only).
  bool matchesQuery(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return true;

    if (canonicalName.toLowerCase().contains(needle)) return true;

    return aliasNames.any((alias) => alias.toLowerCase().contains(needle));
  }

  factory LocationModel.fromJson(Map<String, dynamic> json) {
    final aliasNamesJson = json['alias_names'];

    return LocationModel(
      id: json['id'] as int,
      canonicalName: json['canonical_name'] as String,
      aliasNames: aliasNamesJson is List
          ? aliasNamesJson.map((a) => a as String).toList()
          : const [],
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LocationModel && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
