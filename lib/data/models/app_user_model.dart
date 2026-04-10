import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/app_user.dart';

class AppUserModel extends AppUser {
  const AppUserModel({
    required super.uid,
    required super.name,
    required super.email,
    required super.phone,
    super.photoUrl,
    required super.dateInscription,
    super.preferences,
    super.averageRating,
    super.verification,
    super.role,
    super.co2SavedKg,
  });

  factory AppUserModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return AppUserModel.fromMap(data, doc.id);
  }

  factory AppUserModel.fromMap(Map<String, dynamic> map, String uid) {
    return AppUserModel(
      uid: uid,
      name: map['name'] as String? ?? '',
      email: map['email'] as String? ?? '',
      phone: map['phone'] as String? ?? '',
      photoUrl: map['photoUrl'] as String? ?? '',
      dateInscription: map['dateInscription'] != null
          ? (map['dateInscription'] as Timestamp).toDate()
          : DateTime.now(),
      preferences: List<String>.from(map['preferences'] ?? []),
      averageRating: (map['averageRating'] as num?)?.toDouble() ?? 0.0,
      verification: _parseVerification(map['verification']),
      role: _parseRole(map['role']),
      co2SavedKg: (map['co2SavedKg'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'email': email,
      'phone': phone,
      'photoUrl': photoUrl,
      'dateInscription': Timestamp.fromDate(dateInscription),
      'preferences': preferences,
      'averageRating': averageRating,
      'verification': verification.name,
      'role': role.name,
      'co2SavedKg': co2SavedKg,
    };
  }

  static VerificationStatus _parseVerification(dynamic value) {
    switch (value as String?) {
      case 'pending':
        return VerificationStatus.pending;
      case 'verified':
        return VerificationStatus.verified;
      default:
        return VerificationStatus.unverified;
    }
  }

  static UserRole _parseRole(dynamic value) {
    switch (value as String?) {
      case 'driver':
        return UserRole.driver;
      default:
        return UserRole.passenger;
    }
  }

  factory AppUserModel.fromEntity(AppUser user) => AppUserModel(
    uid: user.uid,
    name: user.name,
    email: user.email,
    phone: user.phone,
    photoUrl: user.photoUrl,
    dateInscription: user.dateInscription,
    preferences: user.preferences,
    averageRating: user.averageRating,
    verification: user.verification,
    role: user.role,
    co2SavedKg: user.co2SavedKg,
  );
}
