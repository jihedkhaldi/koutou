import 'package:equatable/equatable.dart';

class DriverCredentials extends Equatable {
  final String userId;
  final String licenseNumber;
  final DateTime licenseExpirationDate;
  final String licensePlate;
  final String licensePhotoUrl; // Firebase Storage URL after upload
  final DateTime submittedAt;

  const DriverCredentials({
    required this.userId,
    required this.licenseNumber,
    required this.licenseExpirationDate,
    required this.licensePlate,
    this.licensePhotoUrl = '',
    required this.submittedAt,
  });

  @override
  List<Object?> get props => [
    userId,
    licenseNumber,
    licenseExpirationDate,
    licensePlate,
    licensePhotoUrl,
    submittedAt,
  ];
}
