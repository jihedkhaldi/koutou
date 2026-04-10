import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/errors/exceptions.dart';
import '../models/app_user_model.dart';

abstract class UserRemoteDataSource {
  Future<AppUserModel?> getUserById(String uid);
  Future<List<AppUserModel>> getUsersByIds(List<String> uids);
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
}
