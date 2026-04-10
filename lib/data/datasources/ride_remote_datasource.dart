import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/errors/exceptions.dart';
import '../models/ride_model.dart';

abstract class RideRemoteDataSource {
  Future<RideModel> createRide(RideModel ride);
  Future<RideModel?> getRideById(String id);
  Stream<List<RideModel>> getNearbyRides({
    required GeoPoint location,
    double radiusKm = 20,
  });
  Stream<List<RideModel>> getUserRides(String userId);
  Future<void> requestBooking({required String rideId, required String userId});
  Future<void> confirmPassenger({
    required String rideId,
    required String passengerId,
  });
  Future<void> cancelBooking({required String rideId, required String userId});
  Future<void> cancelRide(String rideId);
  Future<void> completeRide(String rideId);

  /// Called when a ride is completed — adds CO2 savings to each passenger's profile.
  Future<void> updatePassengerCo2({
    required List<String> passengerIds,
    required double co2PerPassenger,
  });
}

class RideRemoteDataSourceImpl implements RideRemoteDataSource {
  final FirebaseFirestore _firestore;
  RideRemoteDataSourceImpl({required FirebaseFirestore firestore})
    : _firestore = firestore;

  CollectionReference<Map<String, dynamic>> get _rides =>
      _firestore.collection('rides');

  @override
  Future<RideModel> createRide(RideModel ride) async {
    try {
      final ref = await _rides.add(ride.toMap());
      return RideModel.fromMap(ride.toMap(), ref.id);
    } catch (e) {
      throw ServerException(message: e.toString());
    }
  }

  @override
  Future<RideModel?> getRideById(String id) async {
    try {
      final doc = await _rides.doc(id).get();
      if (!doc.exists) return null;
      return RideModel.fromFirestore(doc);
    } catch (e) {
      throw ServerException(message: e.toString());
    }
  }

  @override
  Stream<List<RideModel>> getNearbyRides({
    required GeoPoint location,
    double radiusKm = 20,
  }) {
    return _rides
        .where('status', isEqualTo: 'scheduled')
        .snapshots()
        .map(
          (snap) => snap.docs.map((d) => RideModel.fromFirestore(d)).where((r) {
            final dist = _haversineKm(
              location.latitude,
              location.longitude,
              r.departure.latitude,
              r.departure.longitude,
            );
            return dist <= radiusKm && r.isAvailable;
          }).toList(),
        );
  }

  @override
  Stream<List<RideModel>> getUserRides(String userId) {
    final driverStream = _rides
        .where('driverId', isEqualTo: userId)
        .snapshots()
        .map((s) => s.docs.map((d) => RideModel.fromFirestore(d)).toList());

    final pendingStream = _rides
        .where('pendingPassengerIds', arrayContains: userId)
        .snapshots()
        .map((s) => s.docs.map((d) => RideModel.fromFirestore(d)).toList());

    final confirmedStream = _rides
        .where('confirmedPassengerIds', arrayContains: userId)
        .snapshots()
        .map((s) => s.docs.map((d) => RideModel.fromFirestore(d)).toList());

    List<RideModel> a = [], b = [], c = [];
    final controller = StreamController<List<RideModel>>.broadcast();

    driverStream.listen((data) {
      a = data;
      controller.add(_merge([a, b, c]));
    });
    pendingStream.listen((data) {
      b = data;
      controller.add(_merge([a, b, c]));
    });
    confirmedStream.listen((data) {
      c = data;
      controller.add(_merge([a, b, c]));
    });

    return controller.stream;
  }

  List<RideModel> _merge(List<List<RideModel>> lists) {
    final map = <String, RideModel>{};
    for (final list in lists) {
      for (final r in list) {
        map[r.id] = r;
      }
    }
    return map.values.toList();
  }

  @override
  Future<void> requestBooking({
    required String rideId,
    required String userId,
  }) async {
    try {
      await _firestore.runTransaction((tx) async {
        final ref = _rides.doc(rideId);
        final snap = await tx.get(ref);
        if (!snap.exists)
          throw const ServerException(message: 'Ride not found.');
        final ride = RideModel.fromFirestore(snap);
        if (ride.isFull)
          throw const ServerException(message: 'No seats available.');
        if (ride.pendingPassengerIds.contains(userId) ||
            ride.confirmedPassengerIds.contains(userId)) {
          throw const ServerException(message: 'Already booked.');
        }
        tx.update(ref, {
          'pendingPassengerIds': FieldValue.arrayUnion([userId]),
        });
      });
    } on ServerException {
      rethrow;
    } catch (e) {
      throw ServerException(message: e.toString());
    }
  }

  @override
  Future<void> confirmPassenger({
    required String rideId,
    required String passengerId,
  }) async {
    try {
      await _firestore.runTransaction((tx) async {
        final ref = _rides.doc(rideId);
        final snap = await tx.get(ref);
        if (!snap.exists)
          throw const ServerException(message: 'Ride not found.');
        final ride = RideModel.fromFirestore(snap);
        if (ride.isFull)
          throw const ServerException(message: 'Ride is already full.');
        tx.update(ref, {
          'pendingPassengerIds': FieldValue.arrayRemove([passengerId]),
          'confirmedPassengerIds': FieldValue.arrayUnion([passengerId]),
        });
      });
    } on ServerException {
      rethrow;
    } catch (e) {
      throw ServerException(message: e.toString());
    }
  }

  @override
  Future<void> cancelBooking({
    required String rideId,
    required String userId,
  }) async {
    try {
      await _rides.doc(rideId).update({
        'pendingPassengerIds': FieldValue.arrayRemove([userId]),
        'confirmedPassengerIds': FieldValue.arrayRemove([userId]),
      });
    } catch (e) {
      throw ServerException(message: e.toString());
    }
  }

  @override
  Future<void> cancelRide(String rideId) async {
    try {
      await _rides.doc(rideId).update({'status': 'cancelled'});
    } catch (e) {
      throw ServerException(message: e.toString());
    }
  }

  @override
  Future<void> completeRide(String rideId) async {
    try {
      final doc = await _rides.doc(rideId).get();
      if (!doc.exists) return;
      final ride = RideModel.fromFirestore(doc);

      await _rides.doc(rideId).update({'status': 'completed'});

      // Add CO2 savings to each confirmed passenger's Firestore document
      final co2PerPassenger =
          ride.availableSeats *
          2.4 /
          (ride.confirmedPassengerIds.isEmpty
              ? 1
              : ride.confirmedPassengerIds.length);
      await updatePassengerCo2(
        passengerIds: ride.confirmedPassengerIds,
        co2PerPassenger: co2PerPassenger,
      );
    } catch (e) {
      throw ServerException(message: e.toString());
    }
  }

  @override
  Future<void> updatePassengerCo2({
    required List<String> passengerIds,
    required double co2PerPassenger,
  }) async {
    try {
      final batch = _firestore.batch();
      for (final uid in passengerIds) {
        final ref = _firestore.collection('users').doc(uid);
        batch.update(ref, {
          'co2SavedKg': FieldValue.increment(co2PerPassenger),
        });
      }
      await batch.commit();
    } catch (e) {
      throw ServerException(message: e.toString());
    }
  }

  double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    final dLat = (lat2 - lat1) * 3.141592653589793 / 180;
    final dLng = (lng2 - lng1) * 3.141592653589793 / 180;
    final sinDLat = dLat / 2 - (dLat * dLat * dLat) / 48;
    final sinDLng = dLng / 2 - (dLng * dLng * dLng) / 48;
    final a =
        sinDLat * sinDLat +
        _cosRad(lat1 * 3.141592653589793 / 180) *
            _cosRad(lat2 * 3.141592653589793 / 180) *
            sinDLng *
            sinDLng;
    double sq = a;
    for (int i = 0; i < 10; i++) sq = (sq + a / sq) / 2;
    return r * 2 * (a + a * a * a / 6);
  }

  double _cosRad(double x) => 1 - x * x / 2 + x * x * x * x / 24;
}
