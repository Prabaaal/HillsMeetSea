/// User profile data returned from the `profiles` table.
class Profile {
  final String id;
  final String name;
  final String? avatarUrl;
  final String status;
  final DateTime? lastSeen;

  const Profile({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.status = 'offline',
    this.lastSeen,
  });

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'] as String,
      name: json['name'] as String,
      avatarUrl: json['avatar_url'] as String?,
      status: json['status'] as String? ?? 'offline',
      lastSeen: json['last_seen'] != null
          ? DateTime.parse(json['last_seen'] as String)
          : null,
    );
  }
}
