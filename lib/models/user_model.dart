/// Represents an authenticated user returned by the Laravel API.
class UserModel {
  const UserModel({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.status,
  });

  final int id;
  final String name;
  final String email;

  /// One of: student, organization, admin.
  final String role;

  /// One of: active, suspended (or pending, for new organizations).
  final String status;

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      role: json['role'] as String? ?? '',
      status: json['status'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'name': name, 'email': email, 'role': role, 'status': status};
  }
}
