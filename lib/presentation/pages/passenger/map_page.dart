import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../domain/entities/driver_location.dart';
import '../../../domain/entities/ride.dart';
import '../../blocs/map_bloc.dart';
import '../../widgets/shared_widgets.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});
  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final _mapController = MapController();
  final _searchCtrl = TextEditingController();
  final _sheetController = DraggableScrollableController();

  // Track which driver was last tapped so second tap navigates
  String? _lastTappedDriverId;

  @override
  void initState() {
    super.initState();
    context.read<MapBloc>().add(const MapInitialized());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _sheetController.dispose();
    super.dispose();
  }

  void _onDriverTap(MapLoaded state, DriverLocation driver) {
    if (_lastTappedDriverId == driver.driverId &&
        state.selectedDriver?.driverId == driver.driverId) {
      // Second tap on same driver → navigate to trip detail
      if (driver.rideId != null) {
        context.push('${AppRoutes.tripDetail}/${driver.rideId}');
      }
    } else {
      // First tap → select driver, fetch route, animate map
      _lastTappedDriverId = driver.driverId;
      context.read<MapBloc>().add(MapDriverSelected(driver));
      _mapController.move(LatLng(driver.latitude, driver.longitude), 12.5);
      // Expand sheet slightly to show callout details
      if (_sheetController.isAttached) {
        _sheetController.animateTo(
          0.30,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceLight,
      appBar: RideLeafAppBar(
        onNotificationTap: () => context.push(AppRoutes.notifications),
        avatarUrl: '',
      ),
      body: BlocBuilder<MapBloc, MapState>(
        builder: (context, state) {
          final isLoaded = state is MapLoaded;
          final userLat = isLoaded ? state.userLat : 36.8065;
          final userLng = isLoaded ? state.userLng : 10.1815;
          final drivers = isLoaded ? state.nearbyDrivers : <DriverLocation>[];
          // Use filteredRides getter — applies search query
          final rides = isLoaded ? state.filteredRides : <Ride>[];
          final allRides = isLoaded ? state.nearbyRides : <Ride>[];
          final selected = isLoaded ? state.selectedDriver : null;
          final polyline = isLoaded ? state.routePolyline : <List<double>>[];

          return Stack(
            children: [
              // ── Full screen map
              Positioned.fill(
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: LatLng(userLat, userLng),
                    initialZoom: 12,
                    onTap: (_, __) {
                      context.read<MapBloc>().add(const MapDriverDeselected());
                      _lastTappedDriverId = null;
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.rideleaf.app',
                    ),

                    // ── Route polyline
                    if (polyline.isNotEmpty)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: polyline
                                .map((p) => LatLng(p[0], p[1]))
                                .toList(),
                            strokeWidth: 5,
                            color: AppColors.forestGreen.withOpacity(0.85),
                            borderStrokeWidth: 2,
                            borderColor: Colors.white,
                          ),
                        ],
                      ),

                    // ── Departure & Arrival pins when route active
                    if (polyline.isNotEmpty && selected != null)
                      MarkerLayer(
                        markers: [
                          if (selected.departureLat != null)
                            Marker(
                              point: LatLng(
                                selected.departureLat!,
                                selected.departureLng!,
                              ),
                              width: 32,
                              height: 32,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: AppColors.forestGreen,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 2,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.circle,
                                  color: Colors.white,
                                  size: 10,
                                ),
                              ),
                            ),
                          if (selected.arrivalLat != null)
                            Marker(
                              point: LatLng(
                                selected.arrivalLat!,
                                selected.arrivalLng!,
                              ),
                              width: 32,
                              height: 32,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: AppColors.orange,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 2,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.location_on,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ),
                            ),
                        ],
                      ),

                    // ── User location dot
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: LatLng(userLat, userLng),
                          width: 24,
                          height: 24,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.blue,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.blue.withOpacity(0.4),
                                  blurRadius: 10,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),

                    // ── Driver markers
                    MarkerLayer(
                      markers: drivers.map((d) {
                        final isSel = selected?.driverId == d.driverId;
                        return Marker(
                          point: LatLng(d.latitude, d.longitude),
                          width: 64,
                          height: 64,
                          child: GestureDetector(
                            onTap: () =>
                                isLoaded ? _onDriverTap(state, d) : null,
                            child: _DriverMarker(driver: d, isSelected: isSel),
                          ),
                        );
                      }).toList(),
                    ),

                    // ── Callout bubble on first tap
                    if (selected != null)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: LatLng(
                              selected.latitude + 0.005,
                              selected.longitude,
                            ),
                            width: 240,
                            height: 85,
                            child: GestureDetector(
                              onTap: () {
                                if (selected.rideId != null) {
                                  context.push(
                                    '${AppRoutes.tripDetail}/${selected.rideId}',
                                  );
                                }
                              },
                              child: _DriverCallout(driver: selected),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),

              // ── Search bar
              Positioned(
                top: 16,
                left: 16,
                right: 16,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(32),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.12),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (v) =>
                        context.read<MapBloc>().add(MapSearchChanged(v)),
                    decoration: InputDecoration(
                      hintText: 'Search by destination...',
                      hintStyle: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 15,
                      ),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: AppColors.textMuted,
                      ),
                      suffixIcon: _searchCtrl.text.isNotEmpty
                          ? GestureDetector(
                              onTap: () {
                                _searchCtrl.clear();
                                context.read<MapBloc>().add(
                                  const MapSearchChanged(''),
                                );
                              },
                              child: const Icon(
                                Icons.close_rounded,
                                color: AppColors.textMuted,
                              ),
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ),

              // ── Second-tap hint badge
              if (selected != null && selected.rideId != null)
                Positioned(
                  top: 80,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.forestGreen,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.touch_app_rounded,
                            color: Colors.white,
                            size: 14,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Tap again to view trip details',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // ── Bottom sheet
              DraggableScrollableSheet(
                controller: _sheetController,
                initialChildSize: 0.28,
                minChildSize: 0.10,
                maxChildSize: 0.88,
                snap: true,
                snapSizes: const [0.10, 0.28, 0.55, 0.88],
                builder: (context, scrollCtrl) {
                  return Container(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(24),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x1A000000),
                          blurRadius: 20,
                          offset: Offset(0, -4),
                        ),
                      ],
                    ),
                    child: CustomScrollView(
                      controller: scrollCtrl,
                      slivers: [
                        // ── Sheet header (sticky)
                        SliverPersistentHeader(
                          pinned: true,
                          delegate: _SheetHeader(
                            rideCount: allRides.length,
                            filteredCount: rides.length,
                            searchQuery: isLoaded ? state.searchQuery : '',
                            onClearSearch: () {
                              _searchCtrl.clear();
                              context.read<MapBloc>().add(
                                const MapSearchChanged(''),
                              );
                            },
                            onFilter: () => _showFilterSheet(context, state),
                          ),
                        ),

                        // ── Ride cards
                        if (state is MapLoading)
                          const SliverFillRemaining(
                            child: Center(
                              child: CircularProgressIndicator(
                                color: AppColors.forestGreen,
                              ),
                            ),
                          )
                        else if (rides.isEmpty && allRides.isEmpty)
                          const SliverFillRemaining(
                            child: Padding(
                              padding: EdgeInsets.all(32),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.directions_car_outlined,
                                    color: AppColors.textMuted,
                                    size: 48,
                                  ),
                                  SizedBox(height: 12),
                                  Text(
                                    'No nearby rides right now.',
                                    style: TextStyle(
                                      color: AppColors.textMuted,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else if (rides.isEmpty && allRides.isNotEmpty)
                          SliverFillRemaining(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.search_off_rounded,
                                    color: AppColors.textMuted,
                                    size: 48,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'No rides to "${isLoaded ? state.searchQuery : ''}".',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: AppColors.textMuted,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(20, 4, 20, 48),
                            sliver: SliverList(
                              delegate: SliverChildBuilderDelegate((
                                context,
                                i,
                              ) {
                                final ride = rides[i];
                                final isSel = selected?.rideId == ride.id;
                                return _RideSheetCard(
                                  ride: ride,
                                  isHighlighted: isSel,
                                  onTap: () => context.push(
                                    '${AppRoutes.tripDetail}/${ride.id}',
                                  ),
                                );
                              }, childCount: rides.length),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  void _showFilterSheet(BuildContext context, MapState state) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFDDDDDD),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Filter Rides',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'More filter options coming soon.',
              style: TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// ── Persistent sheet header delegate ─────────────────────────────────────────

class _SheetHeader extends SliverPersistentHeaderDelegate {
  final int rideCount;
  final int filteredCount;
  final String searchQuery;
  final VoidCallback onClearSearch;
  final VoidCallback onFilter;

  const _SheetHeader({
    required this.rideCount,
    required this.filteredCount,
    required this.searchQuery,
    required this.onClearSearch,
    required this.onFilter,
  });

  @override
  double get minExtent => 110;
  @override
  double get maxExtent => 110;
  @override
  bool shouldRebuild(_SheetHeader old) =>
      old.rideCount != rideCount ||
      old.filteredCount != filteredCount ||
      old.searchQuery != searchQuery;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final title = searchQuery.isNotEmpty
        ? '$filteredCount of $rideCount rides'
        : rideCount == 0
        ? 'Looking for drivers...'
        : '$rideCount Driver${rideCount != 1 ? 's' : ''} found nearby';

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFDDDDDD),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'NEARBY TRIPS',
            style: TextStyle(
              color: AppColors.orange,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textDark,
                    height: 1.2,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Row(
                children: [
                  if (searchQuery.isNotEmpty)
                    GestureDetector(
                      onTap: onClearSearch,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.orange.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.close_rounded,
                              color: AppColors.orange,
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              searchQuery,
                              style: const TextStyle(
                                color: AppColors.orange,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: onFilter,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F0F0),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'Filter',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textDark,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Driver marker ─────────────────────────────────────────────────────────────

class _DriverMarker extends StatelessWidget {
  final DriverLocation driver;
  final bool isSelected;
  const _DriverMarker({required this.driver, required this.isSelected});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isSelected ? AppColors.orange : AppColors.forestGreen,
          width: isSelected ? 3 : 2,
        ),
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: AppColors.forestGreen.withOpacity(0.3),
            blurRadius: isSelected ? 16 : 8,
          ),
        ],
      ),
      child: ClipOval(
        child: Container(
          color: const Color(0xFFD4EDDA),
          child: const Icon(
            Icons.person_rounded,
            color: AppColors.forestGreen,
            size: 28,
          ),
        ),
      ),
    );
  }
}

// ── Driver callout ────────────────────────────────────────────────────────────

class _DriverCallout extends StatelessWidget {
  final DriverLocation driver;
  const _DriverCallout({required this.driver});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(
                Icons.route_rounded,
                color: AppColors.forestGreen,
                size: 14,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  '${driver.departure ?? '—'} → ${driver.destination ?? '—'}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: AppColors.textDark,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                '${driver.departureTime ?? '--:--'}  •  ${driver.seatsLeft} seats  ',
                style: const TextStyle(
                  color: AppColors.orange,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (driver.pricePerSeat != null)
                Text(
                  '${driver.pricePerSeat!.toStringAsFixed(0)} DT',
                  style: const TextStyle(
                    color: AppColors.forestGreen,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          const Row(
            children: [
              Icon(
                Icons.touch_app_rounded,
                color: AppColors.textMuted,
                size: 11,
              ),
              SizedBox(width: 3),
              Text(
                'Tap again for details',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 10,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Ride sheet card ───────────────────────────────────────────────────────────

class _RideSheetCard extends StatelessWidget {
  final Ride ride;
  final bool isHighlighted;
  final VoidCallback onTap;
  const _RideSheetCard({
    required this.ride,
    required this.isHighlighted,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isHighlighted
              ? AppColors.forestGreen.withOpacity(0.06)
              : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(16),
          border: isHighlighted
              ? Border.all(
                  color: AppColors.forestGreen.withOpacity(0.4),
                  width: 1.5,
                )
              : null,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.access_time_rounded,
                        size: 13,
                        color: AppColors.textMuted,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'STARTS ${DateFormat('HH:mm').format(ride.dateHour)}',
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${ride.departureAddress.isNotEmpty ? ride.departureAddress : 'Departure'}'
                    ' → '
                    '${ride.arrivalAddress.isNotEmpty ? ride.arrivalAddress : 'Arrival'}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD4EDDA),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'CO2: ${(ride.availableSeats * 2.4).toStringAsFixed(1)}kg',
                          style: const TextStyle(
                            color: AppColors.forestGreen,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${ride.seatsLeft} seats left',
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${ride.pricePerPassenger.toStringAsFixed(0)} DT',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                    color: AppColors.textDark,
                  ),
                ),
                const Text(
                  'PER SEAT',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 10),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.brownOrange,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Book',
                    style: TextStyle(
                      color: AppColors.orange,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
