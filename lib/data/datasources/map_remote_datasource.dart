import 'dart:convert';
import 'package:firebase_database/firebase_database.dart';
import 'package:http/http.dart' as http;
import '../../core/errors/exceptions.dart';
import '../../domain/entities/driver_location.dart';

abstract class MapRemoteDataSource {
  Stream<List<DriverLocation>> getNearbyDrivers({
    required double latitude,
    required double longitude,
    double radiusKm = 20,
  });
  Future<void> publishDriverLocation(DriverLocation location);
  Future<void> removeDriverLocation(String driverId);
  Future<List<List<double>>> getRoute({
    required double fromLat,
    required double fromLng,
    required double toLat,
    required double toLng,
  });
}

class MapRemoteDataSourceImpl implements MapRemoteDataSource {
  final FirebaseDatabase _realtimeDb;
  final String _orsApiKey;

  MapRemoteDataSourceImpl({
    required FirebaseDatabase realtimeDb,
    required String orsApiKey,
  }) : _realtimeDb = realtimeDb,
       _orsApiKey = orsApiKey;

  DatabaseReference get _driversRef => _realtimeDb.ref('active_drivers');

  @override
  Stream<List<DriverLocation>> getNearbyDrivers({
    required double latitude,
    required double longitude,
    double radiusKm = 20,
  }) {
    return _driversRef.onValue.map((event) {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data == null) return [];

      final result = <DriverLocation>[];
      data.forEach((key, value) {
        try {
          final map = Map<String, dynamic>.from(value as Map);
          final dLat = (map['latitude'] as num).toDouble();
          final dLng = (map['longitude'] as num).toDouble();
          final distKm = _haversineKm(latitude, longitude, dLat, dLng);
          if (distKm <= radiusKm) {
            result.add(
              DriverLocation(
                driverId: key as String,
                latitude: dLat,
                longitude: dLng,
                rideId: map['rideId'] as String?,
                destination: map['destination'] as String?,
                departure: map['departure'] as String?,
                departureTime: map['departureTime'] as String?,
                departureLat: (map['departureLat'] as num?)?.toDouble(),
                departureLng: (map['departureLng'] as num?)?.toDouble(),
                arrivalLat: (map['arrivalLat'] as num?)?.toDouble(),
                arrivalLng: (map['arrivalLng'] as num?)?.toDouble(),
                seatsLeft: (map['seatsLeft'] as num?)?.toInt() ?? 0,
                pricePerSeat: (map['pricePerSeat'] as num?)?.toDouble(),
                updatedAt: DateTime.fromMillisecondsSinceEpoch(
                  (map['updatedAt'] as num?)?.toInt() ??
                      DateTime.now().millisecondsSinceEpoch,
                ),
              ),
            );
          }
        } catch (_) {}
      });
      return result;
    });
  }

  @override
  Future<void> publishDriverLocation(DriverLocation location) async {
    try {
      await _driversRef.child(location.driverId).set({
        'latitude': location.latitude,
        'longitude': location.longitude,
        'rideId': location.rideId,
        'destination': location.destination,
        'departure': location.departure,
        'departureTime': location.departureTime,
        'departureLat': location.departureLat,
        'departureLng': location.departureLng,
        'arrivalLat': location.arrivalLat,
        'arrivalLng': location.arrivalLng,
        'seatsLeft': location.seatsLeft,
        'pricePerSeat': location.pricePerSeat,
        'updatedAt': location.updatedAt.millisecondsSinceEpoch,
      });
    } catch (e) {
      throw ServerException(message: e.toString());
    }
  }

  @override
  Future<void> removeDriverLocation(String driverId) async {
    try {
      await _driversRef.child(driverId).remove();
    } catch (e) {
      throw ServerException(message: e.toString());
    }
  }

  @override
  Future<List<List<double>>> getRoute({
    required double fromLat,
    required double fromLng,
    required double toLat,
    required double toLng,
  }) async {
    const baseUrl =
        'https://api.openrouteservice.org/v2/directions/driving-car';
    final body = jsonEncode({
      'coordinates': [
        [fromLng, fromLat],
        [toLng, toLat],
      ],
    });
    try {
      final response = await http.post(
        Uri.parse(baseUrl),
        headers: {
          'Authorization': _orsApiKey,
          'Content-Type': 'application/json',
        },
        body: body,
      );
      if (response.statusCode != 200) {
        throw ServerException(message: 'ORS error: ${response.statusCode}');
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final coords =
          (json['features'] as List?)?.first['geometry']['coordinates']
              as List? ??
          [];
      return coords
          .map<List<double>>(
            (c) => [(c as List)[1].toDouble(), c[0].toDouble()],
          )
          .toList();
    } catch (e) {
      throw ServerException(message: e.toString());
    }
  }

  double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    final dLat = (lat2 - lat1) * 3.141592653589793 / 180;
    final dLng = (lng2 - lng1) * 3.141592653589793 / 180;
    final sinDLat = dLat / 2;
    final sinDLng = dLng / 2;
    final a =
        sinDLat * sinDLat +
        _cos(lat1 * 3.141592653589793 / 180) *
            _cos(lat2 * 3.141592653589793 / 180) *
            sinDLng *
            sinDLng;
    double sq = a < 0 ? 0 : a;
    for (int i = 0; i < 10; i++) sq = (sq + a / (sq == 0 ? 1 : sq)) / 2;
    return r * 2 * (sq + sq * sq * sq / 6);
  }

  double _cos(double x) => 1 - x * x / 2 + x * x * x * x / 24;
}
