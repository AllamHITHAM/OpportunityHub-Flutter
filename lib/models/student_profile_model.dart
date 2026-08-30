import 'location_model.dart';

/// A student's profile, as returned by the Laravel `student_profile`
/// endpoints (`GET`/`POST`/`PUT /api/student/profile`).
///
/// Models every field the backend actually returns and accepts for this
/// record (`university`, `major`, `graduation_year`, `phone`, `bio`,
/// `current_location`, `available_locations`, `profile_photo_url`).
class StudentProfileModel {
  const StudentProfileModel({
    required this.id,
    required this.university,
    required this.major,
    required this.graduationYear,
    this.phone,
    this.bio,
    this.currentLocation,
    this.availableLocations = const [],
    this.interestedIn,
    this.photoUrl,
  });

  final int id;
  final String? university;
  final String? major;
  final int? graduationYear;
  final String? phone;
  final String? bio;

  /// Student Profile Photo: the full, publicly-reachable
  /// `/api/media/...` URL of the student's uploaded profile photo --
  /// mirrors `OrganizationProfileModel.logoUrl` exactly. `null` until the
  /// student uploads one, in which case the existing initials-avatar
  /// fallback (`AppAvatar`) keeps rendering exactly as it already does
  /// everywhere else in this app. Never a raw storage path.
  final String? photoUrl;

  /// Candidate Opportunity Preferences patch: the canonical Opportunity
  /// Type(s) (`job`/`internship`/`volunteer`/`scholarship`/`competition`
  /// -- the exact same values `OpportunityModel.opportunityType` uses,
  /// never a second vocabulary) this Student wants to be recommended for.
  /// `null` for a profile created before this patch shipped (never
  /// backfilled, never guessed) -- distinct from an empty list, which the
  /// backend never actually persists (`min:1` whenever this is set).
  final List<String>? interestedIn;

  /// The Student's own current/home location (Student Location Profile
  /// Patch) -- a single, optional canonical Location Catalog entry.
  /// Deliberately distinct from [availableLocations]: a Student may live
  /// in one city but be willing to work in several others. `null` is a
  /// completely valid, truthful state, never guessed from unrelated data.
  final LocationModel? currentLocation;

  /// The student's own selected available/preferred work locations (Phase
  /// O8.2) -- real canonical Location Catalog entries, never free text.
  /// Empty is a completely valid, truthful state, not an error.
  final List<LocationModel> availableLocations;

  factory StudentProfileModel.fromJson(Map<String, dynamic> json) {
    final currentLocationJson = json['current_location'];
    final availableLocationsJson = json['available_locations'];
    final interestedInJson = json['interested_in'];

    return StudentProfileModel(
      id: json['id'] as int,
      university: json['university'] as String?,
      major: json['major'] as String?,
      graduationYear: json['graduation_year'] as int?,
      phone: json['phone'] as String?,
      bio: json['bio'] as String?,
      currentLocation: currentLocationJson is Map<String, dynamic>
          ? LocationModel.fromJson(currentLocationJson)
          : null,
      availableLocations: availableLocationsJson is List
          ? availableLocationsJson
                .map(
                  (json) =>
                      LocationModel.fromJson(json as Map<String, dynamic>),
                )
                .toList()
          : const [],
      interestedIn: interestedInJson is List
          ? interestedInJson.map((value) => value as String).toList()
          : null,
      photoUrl: json['profile_photo_url'] as String?,
    );
  }
}
