import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import '../../../domain/entities/driver_location.dart';
import '../../../domain/entities/ride.dart';
import '../../../domain/repositories/map_repository.dart';
import '../../../domain/repositories/ride_repository.dart';

// ── Events ────────────────────────────────────────────────────────────────────

abstract class MapEvent extends Equatable {
  const MapEvent();
  @override
  List<Object?> get props => [];
}

class MapInitialized extends MapEvent {
  const MapInitialized();
}

class MapLocationUpdated extends MapEvent {
  final double lat;
  final double lng;
  const MapLocationUpdated({required this.lat, required this.lng});
  @override
  List<Object?> get props => [lat, lng];
}

class MapDriverSelected extends MapEvent {
  final DriverLocation driver;
  const MapDriverSelected(this.driver);
  @override
  List<Object?> get props => [driver];
}

class MapDriverDeselected extends MapEvent {
  const MapDriverDeselected();
}

class MapFetchRoute extends MapEvent {
  final DriverLocation driver;
  const MapFetchRoute(this.driver);
  @override
  List<Object?> get props => [driver];
}

class MapSearchChanged extends MapEvent {
  final String query;
  const MapSearchChanged(this.query);
  @override
  List<Object?> get props => [query];
}

class _DriversUpdated extends MapEvent {
  final List<DriverLocation> drivers;
  const _DriversUpdated(this.drivers);
  @override
  List<Object?> get props => [drivers];
}

class _RidesUpdated extends MapEvent {
  final List<Ride> rides;
  const _RidesUpdated(this.rides);
  @override
  List<Object?> get props => [rides];
}

// ── States ────────────────────────────────────────────────────────────────────

abstract class MapState extends Equatable {
  const MapState();
  @override
  List<Object?> get props => [];
}

class MapInitial extends MapState {}

class MapLoading extends MapState {}

class MapPermissionDenied extends MapState {}

class MapLoaded extends MapState {
  final double userLat;
  final double userLng;
  final List<DriverLocation> nearbyDrivers;
  final List<Ride> nearbyRides; // all rides from Firestore
  final DriverLocation? selectedDriver;
  final List<List<double>> routePolyline;
  final String searchQuery;

  const MapLoaded({
    required this.userLat,
    required this.userLng,
    required this.nearbyDrivers,
    required this.nearbyRides,
    this.selectedDriver,
    this.routePolyline = const [],
    this.searchQuery = '',
  });

  /// Rides filtered by search query on arrivalAddress.
  List<Ride> get filteredRides {
    if (searchQuery.isEmpty) return nearbyRides;
    final q = searchQuery.toLowerCase();
    return nearbyRides
        .where(
          (r) =>
              r.arrivalAddress.toLowerCase().contains(q) ||
              r.departureAddress.toLowerCase().contains(q),
        )
        .toList();
  }

  MapLoaded copyWith({
    double? userLat,
    double? userLng,
    List<DriverLocation>? nearbyDrivers,
    List<Ride>? nearbyRides,
    DriverLocation? selectedDriver,
    List<List<double>>? routePolyline,
    String? searchQuery,
    bool clearSelected = false,
  }) => MapLoaded(
    userLat: userLat ?? this.userLat,
    userLng: userLng ?? this.userLng,
    nearbyDrivers: nearbyDrivers ?? this.nearbyDrivers,
    nearbyRides: nearbyRides ?? this.nearbyRides,
    selectedDriver: clearSelected
        ? null
        : selectedDriver ?? this.selectedDriver,
    routePolyline: clearSelected ? [] : routePolyline ?? this.routePolyline,
    searchQuery: searchQuery ?? this.searchQuery,
  );

  @override
  List<Object?> get props => [
    userLat,
    userLng,
    nearbyDrivers,
    nearbyRides,
    selectedDriver,
    routePolyline,
    searchQuery,
  ];
}

class MapError extends MapState {
  final String message;
  const MapError({required this.message});
  @override
  List<Object?> get props => [message];
}

// ── BLoC ──────────────────────────────────────────────────────────────────────

class MapBloc extends Bloc<MapEvent, MapState> {
  final MapRepository _mapRepository;
  final RideRepository _rideRepository;

  StreamSubscription<List<DriverLocation>>? _driverSub;
  StreamSubscription<List<Ride>>? _rideSub;

  static const double _defaultLat = 36.8065;
  static const double _defaultLng = 10.1815;

  MapBloc({
    required MapRepository mapRepository,
    required RideRepository rideRepository,
  }) : _mapRepository = mapRepository,
       _rideRepository = rideRepository,
       super(MapInitial()) {
    on<MapInitialized>(_onInitialized);
    on<MapLocationUpdated>(_onLocationUpdated);
    on<MapDriverSelected>(_onDriverSelected);
    on<MapDriverDeselected>(_onDriverDeselected);
    on<MapFetchRoute>(_onFetchRoute);
    on<MapSearchChanged>(_onSearchChanged);
    on<_DriversUpdated>(_onDriversUpdated);
    on<_RidesUpdated>(_onRidesUpdated);
  }

  Future<void> _onInitialized(
    MapInitialized event,
    Emitter<MapState> emit,
  ) async {
    emit(MapLoading());
    double lat = _defaultLat, lng = _defaultLng;
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.always ||
          perm == LocationPermission.whileInUse) {
        final pos = await Geolocator.getCurrentPosition();
        lat = pos.latitude;
        lng = pos.longitude;
      }
    } catch (_) {}
    add(MapLocationUpdated(lat: lat, lng: lng));
  }

  /// Subscribes to both streams in parallel using plain listeners that
  /// dispatch internal events — avoids the blocking emit.forEach pattern.
  Future<void> _onLocationUpdated(
    MapLocationUpdated event,
    Emitter<MapState> emit,
  ) async {
    await _driverSub?.cancel();
    await _rideSub?.cancel();

    // Emit an initial loaded state so the UI shows the map immediately.
    emit(
      MapLoaded(
        userLat: event.lat,
        userLng: event.lng,
        nearbyDrivers: const [],
        nearbyRides: const [],
      ),
    );

    _driverSub = _mapRepository
        .getNearbyDrivers(latitude: event.lat, longitude: event.lng)
        .listen((drivers) => add(_DriversUpdated(drivers)));

    _rideSub = _rideRepository
        .getNearbyRides(location: GeoPoint(event.lat, event.lng), radiusKm: 200)
        .listen(
          (rides) => add(
            _RidesUpdated(
              rides.where((r) => r.status == RideStatus.scheduled).toList(),
            ),
          ),
        );
  }

  void _onDriversUpdated(_DriversUpdated event, Emitter<MapState> emit) {
    if (state is MapLoaded) {
      emit((state as MapLoaded).copyWith(nearbyDrivers: event.drivers));
    }
  }

  void _onRidesUpdated(_RidesUpdated event, Emitter<MapState> emit) {
    if (state is MapLoaded) {
      emit((state as MapLoaded).copyWith(nearbyRides: event.rides));
    }
  }

  void _onDriverSelected(MapDriverSelected event, Emitter<MapState> emit) {
    if (state is MapLoaded) {
      emit(
        (state as MapLoaded).copyWith(
          selectedDriver: event.driver,
          routePolyline: [],
        ),
      );
      add(MapFetchRoute(event.driver));
    }
  }

  void _onDriverDeselected(MapDriverDeselected event, Emitter<MapState> emit) {
    if (state is MapLoaded) {
      emit((state as MapLoaded).copyWith(clearSelected: true));
    }
  }

  Future<void> _onFetchRoute(
    MapFetchRoute event,
    Emitter<MapState> emit,
  ) async {
    final d = event.driver;
    if (d.departureLat == null || d.arrivalLat == null) return;
    try {
      final polyline = await _mapRepository.getRoute(
        fromLat: d.departureLat!,
        fromLng: d.departureLng!,
        toLat: d.arrivalLat!,
        toLng: d.arrivalLng!,
      );
      if (state is MapLoaded) {
        emit((state as MapLoaded).copyWith(routePolyline: polyline));
      }
    } catch (_) {
      // Non-fatal — no polyline shown
    }
  }

  void _onSearchChanged(MapSearchChanged event, Emitter<MapState> emit) {
    if (state is MapLoaded) {
      emit((state as MapLoaded).copyWith(searchQuery: event.query));
    }
  }

  @override
  Future<void> close() {
    _driverSub?.cancel();
    _rideSub?.cancel();
    return super.close();
  }
}
