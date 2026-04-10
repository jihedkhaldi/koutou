import '../entities/app_user.dart';

abstract class UserRepository {
  Future<AppUser?> getUserById(String uid);
  Future<List<AppUser>> getUsersByIds(List<String> uids);
}
