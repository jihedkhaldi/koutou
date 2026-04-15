import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/errors/exceptions.dart';
import '../models/app_user_model.dart';

abstract class UserRemoteDataSource {
  Future<AppUserModel?> getUserById(String uid);
  Future<List<AppUserModel>> getUsersByIds(List<String> uids);
  Future<void> updateRidePreferences({
    required String uid,
    required Map<String, dynamic> ridePreferences,
  });
  Future<void> updateVehicles({required String uid, required List<String> vehicles});
}

class UserRemoteDataSourceImpl implements UserRemoteDataSource {
  final FirebaseFirestore _firestore;
  UserRemoteDataSourceImpl({required FirebaseFirestore firestore})
    : _firestore = firestore;

  @override
  Future<AppUserModel?> getUserById(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (!doc.exists) return null;
      return AppUserModel.fromFirestore(doc);
    } catch (e) {
      throw ServerException(message: e.toString());
    }
  }

  @override
  Future<List<AppUserModel>> getUsersByIds(List<String> uids) async {
    if (uids.isEmpty) return [];
    try {
      final futures = uids.map((id) => getUserById(id));
      final results = await Future.wait(futures);
      return results.whereType<AppUserModel>().toList();
    } catch (e) {
      throw ServerException(message: e.toString());
    }
  }

  @override
  Future<void> updateRidePreferences({
    required String uid,
    required Map<String, dynamic> ridePreferences,
  }) async {
    try {
      await _firestore.collection('users').doc(uid).update({
        'ridePreferences': ridePreferences,
        'preferences': _toLegacyPreferenceTags(ridePreferences),
      });
    } catch (e) {
      throw ServerException(message: e.toString());
    }
  }

  @override
  Future<void> updateVehicles({
    required String uid,
    required List<String> vehicles,
  }) async {
    try {
      await _firestore.collection('users').doc(uid).update({'vehicles': vehicles});
    } catch (e) {
      throw ServerException(message: e.toString());
    }
  }

  List<String> _toLegacyPreferenceTags(Map<String, dynamic> pref) {
    final tags = <String>[];
    if (pref['smokingAllowed'] == false) tags.add('no_smoking');
    if (pref['petsAllowed'] == true) tags.add('pets_welcome');

    final luggage = pref['luggageSize'] as String?;
    if (luggage == 'standardSuitcase') tags.add('medium_bag');
    if (luggage == 'smallBagOnly') tags.add('small_bag_only');
    if (luggage == 'largeItems') tags.add('large_items');

    final conversation = pref['conversationLevel'] as String?;
    if (conversation == 'quietRide') tags.add('quiet_trip');
    if (conversation == 'chatty') tags.add('chatty');

    final music = pref['musicLevel'] as String?;
    if (music != null && music.isNotEmpty) {
      tags.add('music_$music');
    }
    return tags;
  }
}
