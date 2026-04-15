import '../entities/app_user.dart';

abstract class UserRepository {
  Future<AppUser?> getUserById(String uid);
  Future<List<AppUser>> getUsersByIds(List<String> uids);
  Future<void> updateRidePreferences({
    required String uid,
    required Map<String, dynamic> ridePreferences,
  });
  Future<void> updateVehicles({required String uid, required List<String> vehicles});
}
