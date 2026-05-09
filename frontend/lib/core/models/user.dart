class User {
  final String id;
  final String email;
  final String name;
  final String? accessToken;
  final DateTime? tokenExpiry;

  const User({
    required this.id,
    required this.email,
    required this.name,
    this.accessToken,
    this.tokenExpiry,
  });

  bool get isAuthenticated => accessToken != null && tokenExpiry != null && tokenExpiry!.isAfter(DateTime.now());

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'name': name,
  };

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: json['id'] ?? '',
    email: json['email'] ?? '',
    name: json['name'] ?? '',
    accessToken: json['access_token'],
    tokenExpiry: json['expires_at'] != null ? DateTime.parse(json['expires_at']) : null,
  );
}
