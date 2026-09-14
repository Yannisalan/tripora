import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/logger.dart';
import '../../models/trip_model.dart';
import '../../services/places_service.dart';

/// Live, interactive map of a trip.
///
/// Resolves the itinerary's free-text locations through the backend
/// geocoder, drops a marker on each one, and (best-effort) draws a driving
/// route between them in itinerary order.
class TripMapScreen extends StatefulWidget {
  final TripModel trip;

  const TripMapScreen({super.key, required this.trip});

  @override
  State<TripMapScreen> createState() => _TripMapScreenState();
}

class _MapSpot {
  final String title;
  final String subtitle;
  final double latitude;
  final double longitude;

  const _MapSpot({
    required this.title,
    required this.subtitle,
    required this.latitude,
    required this.longitude,
  });
}

class _TripMapScreenState extends State<TripMapScreen> {
  final PlacesService _placesService = PlacesService();
  final MapController _mapController = MapController();

  final List<_MapSpot> _spots = [];
  List<LatLng> _routePoints = [];

  bool _isLoading = true;
  bool _routing = false;
  String? _error;
  int _unresolvedLocations = 0;

  LatLng? _userLocation;

  @override
  void initState() {
    super.initState();
    _buildMap();
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  // ============================================================
  // DATA COLLECTION
  // ============================================================

  /// Ordered (day, activity) pairs so the map mirrors the itinerary.
  List<({int day, String title, String location})> _collectLocations() {
    final result = <({int day, String title, String location})>[];
    final days = widget.trip.itinerary;

    if (days.isEmpty) return result;

    var dayNumber = 0;
    for (final day in days) {
      if (day is! Map) continue;
      dayNumber += 1;

      final activities = day['activities'];
      if (activities is! List) continue;

      for (final activity in activities) {
        if (activity is! Map) continue;

        final location = activity['location']?.toString().trim() ?? '';
        final title = activity['title']?.toString() ?? '';

        if (location.isEmpty) continue;

        result.add((day: dayNumber, title: title, location: location));
      }
    }

    return result;
  }

  Future<void> _buildMap() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final locations = _collectLocations();

    // De-duplicate while keeping first-seen order.
    final orderedQueries = <String>[
      widget.trip.destination.trim(),
      ...locations.map((item) => item.location),
    ];
    final seen = <String>{};

    final uniqueQueries = orderedQueries
        .where((location) => location.isNotEmpty)
        .where((location) => seen.add(location.toLowerCase()))
        .toList();

    setState(() => _unresolvedLocations = uniqueQueries.length);

    for (final query in uniqueQueries) {
      try {
        final place = await _placesService.geocode(query);

        if (!mounted) return;

        if (place != null) {
          final matched = locations
              .where(
                (item) =>
                    item.location.toLowerCase() == query.toLowerCase(),
              )
              .firstOrNull;

          setState(() {
            _spots.add(
              _MapSpot(
                title: matched != null && matched.title.isNotEmpty
                    ? matched.title
                    : query,
                subtitle: matched != null
                    ? 'Day ${matched.day}'
                    : 'Trip destination',
                latitude: place.latitude,
                longitude: place.longitude,
              ),
            );
            _unresolvedLocations -= 1;
          });
        } else {
          setState(() => _unresolvedLocations -= 1);
        }
      } catch (error) {
        appLog('MAP GEOCODE ERROR for "$query": $error');
        if (!mounted) return;
        setState(() => _unresolvedLocations -= 1);
      }
    }

    if (!mounted) return;

    if (_spots.isEmpty) {
      setState(() {
        _isLoading = false;
        _error = 'Could not place any of the trip locations on the map. '
            'The location service may be unavailable right now.';
      });
      return;
    }

    setState(() => _isLoading = false);

    _fitToSpots();

    if (_spots.length >= 2) {
      _drawRoute();
    }
  }

  Future<void> _drawRoute() async {
    setState(() => _routing = true);

    final points = <LatLng>[];

    for (var index = 0; index < _spots.length - 1; index++) {
      final from = _spots[index];
      final to = _spots[index + 1];

      try {
        final route = await _placesService.getRoute(
          fromLat: from.latitude,
          fromLng: from.longitude,
          toLat: to.latitude,
          toLng: to.longitude,
        );

        if (route.isNotEmpty) {
          points.addAll(route.map((p) => LatLng(p.$1, p.$2)));
        }
      } catch (error) {
        // Routing is best-effort; a failed leg just means no line.
        appLog('MAP ROUTE ERROR: $error');
      }
    }

    if (!mounted) return;

    setState(() {
      _routePoints = points;
      _routing = false;
    });
  }

  void _fitToSpots() {
    final map = _mapController;

    if (_spots.length == 1) {
      map.move(
        LatLng(_spots.first.latitude, _spots.first.longitude),
        12,
      );
      return;
    }

    final bounds = LatLngBounds.fromPoints([
      for (final spot in _spots)
        LatLng(spot.latitude, spot.longitude),
    ]);

    try {
      map.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(48),
        ),
      );
    } catch (_) {
      map.move(
        LatLng(
          (_spots.first.latitude + _spots.last.latitude) / 2,
          (_spots.first.longitude + _spots.last.longitude) / 2,
        ),
        8,
      );
    }
  }

  // ============================================================
  // LOCATE ME
  // ============================================================

  Future<void> _locateMe() async {
    try {
      var permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception(
          'Location permission was not granted. You can still explore the '
          'map manually.',
        );
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      if (!mounted) return;

      setState(() {
        _userLocation = LatLng(
          position.latitude,
          position.longitude,
        );
      });

      _mapController.move(_userLocation!, 13);
    } catch (error) {
      appLog('LOCATE ME ERROR: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              error.toString().replaceFirst('Exception: ', ''),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  void _centerOn(_MapSpot spot) {
    _mapController.move(
      LatLng(spot.latitude, spot.longitude),
      12,
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final colors = context.triporaColors;

    return Scaffold(
      backgroundColor: colors.backgroundColor,
      appBar: AppBar(
        title: Text(widget.trip.destination),
        backgroundColor: colors.backgroundColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Fit all markers',
            onPressed: _spots.isEmpty ? null : _fitToSpots,
            icon: const Icon(Icons.zoom_out_map),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildMapBody(colors),
      floatingActionButton: FloatingActionButton(
        tooltip: 'My location',
        onPressed: _locateMe,
        child: const Icon(Icons.my_location),
      ),
    );
  }

  Widget _buildMapBody(TriporaColors colors) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.map_outlined,
                size: 48,
                color: colors.appStatus.warning,
              ),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.textSecondary),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  setState(() {
                    _spots.clear();
                    _routePoints.clear();
                  });
                  _buildMap();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    final spots = _spots;

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: spots.isEmpty
                ? const LatLng(20, 0)
                : LatLng(
                    spots.first.latitude,
                    spots.first.longitude,
                  ),
            initialZoom: spots.isEmpty ? 2 : 11,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'frontend',
            ),
            if (_routePoints.length >= 2)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _routePoints,
                    strokeWidth: 4,
                    color: AppColors.secondary,
                    borderColor: Colors.white,
                    borderStrokeWidth: 1,
                  ),
                ],
              ),
            MarkerLayer(
              markers: [
                if (_userLocation != null)
                  Marker(
                    point: _userLocation!,
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    child: _UserLocationMarker(
                      color: colors.appStatus.info,
                    ),
                  ),
                for (var index = 0; index < spots.length; index++)
                  Marker(
                    point: LatLng(
                      spots[index].latitude,
                      spots[index].longitude,
                    ),
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    child: _SpotMarker(
                      index: index,
                      onTap: () => _centerOn(spots[index]),
                    ),
                  ),
              ],
            ),
          ],
        ),

        // -------------------------------------------------
        // Top banner: how many spots resolved.
        // -------------------------------------------------
        Positioned(
          top: 12,
          left: 12,
          right: 12,
          child: Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surface.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: colors.border),
                  ),
                  child: Row(
                    children: [
                      if (_unresolvedLocations > 0)
                        Icon(
                          Icons.warning_amber_outlined,
                          size: 18,
                          color: colors.appStatus.warning,
                        )
                      else
                        Icon(
                          Icons.check_circle_outline,
                          size: 18,
                          color: colors.appStatus.success,
                        ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _unresolvedLocations > 0
                              ? 'Showing ${spots.length} of '
                                    '${spots.length + _unresolvedLocations} '
                                    'locations'
                              : 'All ${spots.length} locations on the map',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (_routing)
                const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
            ],
          ),
        ),

        // -------------------------------------------------
        // Bottom legend (list of marker spots).
        // -------------------------------------------------
        if (spots.isNotEmpty)
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colors.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Itinerary Spots',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: colors.textPrimary,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: 'Open list',
                          visualDensity: VisualDensity.compact,
                          onPressed: () =>
                              _showSpotsList(colors, spots),
                          icon: Icon(
                            Icons.view_list,
                            size: 20,
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 44,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: spots.length + 1,
                        separatorBuilder: (_, _) =>
                            const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            return _LegendChip(
                              label: 'Trip',
                              index: null,
                              colors: colors,
                              onTap: spots.isEmpty
                                  ? null
                                  : () => _centerOn(spots.first),
                            );
                          }
                          final spot = spots[index - 1];
                          return _LegendChip(
                            label: spot.subtitle,
                            index: index - 1,
                            colors: colors,
                            onTap: () => _centerOn(spot),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _showSpotsList(TriporaColors colors, List<_MapSpot> spots) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Itinerary locations',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: spots.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final spot = spots[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: _SpotMarker(index: index, onTap: null),
                      title: Text(
                        spot.title,
                        style: TextStyle(color: colors.textPrimary),
                      ),
                      subtitle: Text(
                        spot.subtitle,
                        style: TextStyle(color: colors.textMuted),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        _centerOn(spot);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// MARKERS & CHIPS
// ============================================================

class _SpotMarker extends StatelessWidget {
  final int index;
  final VoidCallback? onTap;

  const _SpotMarker({required this.index, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          gradient: AppColors.brandGradient,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Container(
          width: 22,
          height: 22,
          decoration: const BoxDecoration(
            color: Color(0xFF1E1B4B),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            '${index + 1}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _UserLocationMarker extends StatelessWidget {
  final Color color;

  const _UserLocationMarker({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.25),
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 6,
          ),
        ],
      ),
    );
  }
}

class _LegendChip extends StatelessWidget {
  final String label;
  final int? index;
  final TriporaColors colors;
  final VoidCallback? onTap;

  const _LegendChip({
    required this.label,
    required this.index,
    required this.colors,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colors.surfaceSecondary,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            children: [
              if (index != null) ...[
                Container(
                  width: 18,
                  height: 18,
                  decoration: const BoxDecoration(
                    gradient: AppColors.brandGradient,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${index! + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}