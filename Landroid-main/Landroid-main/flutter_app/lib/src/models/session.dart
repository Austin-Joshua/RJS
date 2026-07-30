enum Role { consultant, landowner }

class Session {
  const Session({
    required this.token,
    required this.role,
    required this.uid,
    this.email,
    this.displayName,
    this.phone,
  });

  final String token;
  final Role role;
  final String uid;
  final String? email;
  final String? displayName;
  final String? phone;

  bool get isConsultant => role == Role.consultant;
  bool get isLandowner => role == Role.landowner;

  Session copyWith({
    String? token,
    Role? role,
    String? uid,
    String? email,
    String? displayName,
    String? phone,
  }) {
    return Session(
      token: token ?? this.token,
      role: role ?? this.role,
      uid: uid ?? this.uid,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      phone: phone ?? this.phone,
    );
  }
}
