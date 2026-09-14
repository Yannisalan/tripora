import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:frontend/screens/main_shell.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../data/destinations.dart';
import '../../models/trip_model.dart';
import '../../routes/app_routes.dart';
import '../../services/trip_service.dart';
import '../trip_details.dart';
import '../../widgets/shimmer_loader.dart';

class HomeScreen extends StatefulWidget {
const HomeScreen({super.key});

@override
State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
final TripService _tripService = TripService();

List<TripModel> _trips = [];
bool _isLoadingTrips = true;
String? _tripError;

// ---------------------------------------------------------------------------
// Nocturne Voyage design tokens
// ---------------------------------------------------------------------------

static const Color midnight = Color(0xFF1E1B4B);
static const Color midnightDark = Color(0xFF070235);
static const Color porcelain = Color(0xFFF7F9FB);
static const Color white = Color(0xFFFFFFFF);
static const Color slate100 = Color(0xFFF1F5F9);
static const Color slate200 = Color(0xFFE2E8F0);
static const Color slate300 = Color(0xFFCBD5E1);
static const Color slate500 = Color(0xFF64748B);
static const Color slate600 = Color(0xFF475569);
static const Color textSecondary = Color(0xFF47464F);
static const Color blue = Color(0xFF3B82F6);
static const Color amber = Color(0xFFF59E0B);
static const Color emerald = Color(0xFF10B981);

@override
void initState() {
super.initState();
_loadTrips();
}

Future<void> _loadTrips() async {
if (!mounted) return;

setState(() {
_isLoadingTrips = true;
_tripError = null;
});

try {
final trips = await _tripService.getTrips();

if (!mounted) return;

setState(() {
_trips = trips;
_isLoadingTrips = false;
});
} catch (error) {
if (!mounted) return;

setState(() {
_isLoadingTrips = false;
_tripError = error.toString().replaceFirst('Exception: ', '').trim();
});
}
}

void _openPlanner([String? destination]) {
HapticFeedback.lightImpact();

Navigator.pushNamed(
context,
AppRoutes.planner,
arguments: destination,
);
}

void _openExplore() {
MainShell.currentIndex.value = 1;
}

void _openTrips() {
Navigator.pushNamed(
context,
AppRoutes.trips,
).then((_) => _loadTrips());
}

void _openTrip(TripModel trip) {
Navigator.push(
context,
MaterialPageRoute(
builder: (_) => TripDetailsScreen(trip: trip),
),
).then((_) => _loadTrips());
}

// ---------------------------------------------------------------------------
// Main build
// ---------------------------------------------------------------------------

@override
Widget build(BuildContext context) {
return Scaffold(
backgroundColor: porcelain,
appBar: _buildAppBar(),
body: RefreshIndicator(
color: midnight,
backgroundColor: white,
onRefresh: _loadTrips,
child: LayoutBuilder(
builder: (context, constraints) {
final width = constraints.maxWidth;

final isMobile = width < 768;
final isTablet = width >= 768 && width < 1024;

final horizontalPadding = isMobile
? 16.0
    : isTablet
? 24.0
    : 40.0;

const maxContentWidth = 1280.0;

return ListView(
physics: const AlwaysScrollableScrollPhysics(),
padding: EdgeInsets.symmetric(
horizontal: horizontalPadding,
vertical: isMobile ? 24 : 36,
),
children: [
Center(
child: ConstrainedBox(
constraints: const BoxConstraints(
maxWidth: maxContentWidth,
),
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
_buildHero(isMobile),
SizedBox(height: isMobile ? 40 : 56),
_buildTripSnapshot(isMobile, isTablet),
SizedBox(height: isMobile ? 44 : 56),
_buildDestinationsHeader(isMobile),
const SizedBox(height: 18),
_buildDestinationStrip(isMobile),
SizedBox(height: isMobile ? 44 : 56),
_buildQuickActions(isMobile, isTablet),
],
),
),
),
],
);
},
),
),
);
}

// ---------------------------------------------------------------------------
// App bar
// ---------------------------------------------------------------------------

PreferredSizeWidget _buildAppBar() {
return AppBar(
elevation: 0,
scrolledUnderElevation: 0,
backgroundColor: porcelain,
surfaceTintColor: Colors.transparent,
titleSpacing: 20,
title: Text(
'Tripora',
style: GoogleFonts.manrope(
color: midnight,
fontSize: 20,
fontWeight: FontWeight.w800,
letterSpacing: -0.4,
),
),
actions: [
Padding(
padding: const EdgeInsets.only(right: 16),
child: SizedBox(
width: 120,
child: _primaryButton(
label: 'Plan Trip',
icon: Icons.add_rounded,
onPressed: () => _openPlanner(),
height: 44,
horizontalPadding: 8,
),
),
),
],
);
}

// ---------------------------------------------------------------------------
// Hero
// ---------------------------------------------------------------------------

Widget _buildHero(bool isMobile) {
return Container(
width: double.infinity,
padding: EdgeInsets.all(isMobile ? 24 : 40),
decoration: BoxDecoration(
color: white,
borderRadius: BorderRadius.circular(24),
border: Border.all(color: slate200),
boxShadow: const [
BoxShadow(
color: Color(0x0A1E1B4B),
blurRadius: 10,
offset: Offset(0, 3),
),
],
),
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Container(
padding: const EdgeInsets.symmetric(
horizontal: 12,
vertical: 7,
),
decoration: BoxDecoration(
color: slate100,
borderRadius: BorderRadius.circular(999),
border: Border.all(color: slate200),
),
child: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.auto_awesome_rounded,
                              size: 14,
                              color: blue,
                            ),
                            SizedBox(width: 7),
                            Text(
                              'AI-POWERED TRAVEL PLANNING',
                              style: TextStyle(
                                color: midnight,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                      ),
),

const SizedBox(height: 24),

Text(
'Plan trips that\nfit your pace.',
style: GoogleFonts.notoSerif(
color: midnightDark,
fontSize: isMobile ? 34 : 48,
height: 1.08,
fontWeight: FontWeight.w600,
letterSpacing: -1.1,
),
),

const SizedBox(height: 16),

ConstrainedBox(
constraints: const BoxConstraints(maxWidth: 650),
child: const Text(
'Start with a destination and let Tripora shape the journey around your time, budget, interests, and travel style.',
style: TextStyle(
color: textSecondary,
fontSize: 16,
height: 1.55,
fontWeight: FontWeight.w400,
),
),
),

const SizedBox(height: 28),

Wrap(
spacing: 12,
runSpacing: 12,
children: [
_primaryButton(
label: 'Start Planning',
icon: Icons.auto_awesome_rounded,
onPressed: () => _openPlanner(),
height: 48,
),
_secondaryButton(
label: 'Explore Destinations',
icon: Icons.explore_outlined,
onPressed: _openExplore,
height: 48,
),
],
),

const SizedBox(height: 28),

Container(
height: 1,
color: slate200,
),

const SizedBox(height: 18),

const Wrap(
spacing: 22,
runSpacing: 12,
children: [
_HeroMeta(
icon: Icons.schedule_outlined,
label: 'PERSONALIZED',
),
_HeroMeta(
icon: Icons.auto_awesome_outlined,
label: 'AI-GENERATED',
),
_HeroMeta(
icon: Icons.public_outlined,
label: 'GLOBAL DESTINATIONS',
),
],
),
],
),
);
}

// ---------------------------------------------------------------------------
// Trips
// ---------------------------------------------------------------------------

Widget _buildTripSnapshot(
bool isMobile,
bool isTablet,
) {
if (_isLoadingTrips) {
return Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
_sectionHeading(
title: 'Your journeys',
eyebrow: 'SAVED TRIPS',
trailing: null,
),
const SizedBox(height: 16),
Wrap(
spacing: 16,
runSpacing: 16,
children: [
TripCardShimmer(isCompact: isMobile),
if (!isMobile)
TripCardShimmer(isCompact: false),
if (!isMobile && !isTablet)
TripCardShimmer(isCompact: false),
],
),
],
);
}

if (_tripError != null) {
return _buildTripError();
}

if (_trips.isEmpty) {
return _buildEmptyTrips();
}

final recentTrips = _trips
    .take(
isMobile
? 2
    : isTablet
? 2
    : 3,
)
    .toList();

return Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
_sectionHeading(
title:
'${_trips.length} saved ${_trips.length == 1 ? 'trip' : 'trips'}',
eyebrow: 'YOUR JOURNEYS',
trailing: TextButton.icon(
onPressed: _openTrips,
icon: const Icon(
Icons.arrow_forward_rounded,
size: 16,
),
label: const Text('View all'),
style: TextButton.styleFrom(
foregroundColor: midnight,
textStyle: const TextStyle(
fontWeight: FontWeight.w700,
),
),
),
),

const SizedBox(height: 16),

LayoutBuilder(
builder: (context, constraints) {
final cardWidth = isMobile
? constraints.maxWidth
    : isTablet
? (constraints.maxWidth - 16) / 2
    : (constraints.maxWidth - 32) / 3;

return Wrap(
spacing: 16,
runSpacing: 16,
children: recentTrips.map((trip) {
return SizedBox(
width: cardWidth,
child: _buildTripCard(trip),
);
}).toList(),
);
},
),
],
);
}

Widget _buildTripCard(TripModel trip) {
return Material(
color: white,
borderRadius: BorderRadius.circular(16),
child: InkWell(
onTap: () => _openTrip(trip),
borderRadius: BorderRadius.circular(16),
child: Container(
padding: const EdgeInsets.all(20),
decoration: BoxDecoration(
borderRadius: BorderRadius.circular(16),
border: Border.all(color: slate200),
),
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Row(
children: [
Container(
width: 42,
height: 42,
decoration: BoxDecoration(
color: midnight,
borderRadius: BorderRadius.circular(10),
),
child: const Icon(
Icons.flight_takeoff_rounded,
color: white,
size: 19,
),
),
const Spacer(),
const Icon(
Icons.arrow_outward_rounded,
size: 18,
color: slate500,
),
],
),

const SizedBox(height: 22),

Text(
trip.destination,
maxLines: 1,
overflow: TextOverflow.ellipsis,
style: GoogleFonts.notoSerif(
color: midnightDark,
fontSize: 22,
height: 1.2,
fontWeight: FontWeight.w600,
letterSpacing: -0.3,
),
),

const SizedBox(height: 8),

Text(
'${trip.numberOfDays} '
'${trip.numberOfDays == 1 ? 'day' : 'days'} · '
'${trip.travelers} '
'${trip.travelers == 1 ? 'traveler' : 'travelers'}',
style: const TextStyle(
color: slate500,
fontSize: 13,
fontWeight: FontWeight.w500,
),
),

const SizedBox(height: 18),

Container(
height: 1,
color: slate200,
),

const SizedBox(height: 14),

const Row(
children: [
Icon(
Icons.check_circle_outline_rounded,
size: 15,
color: emerald,
),
SizedBox(width: 7),
Text(
'SAVED ITINERARY',
style: TextStyle(
color: slate600,
fontSize: 10,
fontWeight: FontWeight.w800,
letterSpacing: 0.7,
),
),
],
),
],
),
),
),
);
}

Widget _buildEmptyTrips() {
return Container(
width: double.infinity,
padding: const EdgeInsets.all(24),
decoration: BoxDecoration(
color: white,
borderRadius: BorderRadius.circular(16),
border: Border.all(color: slate200),
),
child: Row(
children: [
Container(
width: 48,
height: 48,
decoration: BoxDecoration(
color: slate100,
borderRadius: BorderRadius.circular(12),
),
child: const Icon(
Icons.luggage_outlined,
color: midnight,
),
),

const SizedBox(width: 16),

Expanded(
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Text(
'No saved journeys yet',
style: GoogleFonts.notoSerif(
fontSize: 20,
fontWeight: FontWeight.w600,
color: midnightDark,
),
),
const SizedBox(height: 5),
const Text(
'Create your first itinerary and it will appear here.',
style: TextStyle(
color: slate500,
fontSize: 13,
height: 1.4,
),
),
],
),
),

const SizedBox(width: 16),

_primaryButton(
label: 'Plan',
icon: Icons.add_rounded,
onPressed: () => _openPlanner(),
height: 44,
horizontalPadding: 15,
),
],
),
);
}

Widget _buildTripError() {
final tripError = _tripError ?? '';

final isAuthError =
tripError.contains('logged in') ||
tripError.contains('session') ||
tripError.contains('log in');

final isNetworkError =
tripError.contains('refused') ||
tripError.contains('not found') ||
tripError.contains('connection');

final Color accent = isAuthError
? blue
    : isNetworkError
? amber
    : const Color(0xFFBA1A1A);

final IconData icon = isAuthError
? Icons.lock_outline_rounded
    : isNetworkError
? Icons.wifi_off_outlined
    : Icons.cloud_off_outlined;

final String message = isAuthError
? 'Sign in to see your saved trips.'
    : isNetworkError
? 'Could not connect to the server. Check your connection.'
    : 'Could not load your trips. Please try again.';

return Container(
padding: const EdgeInsets.all(18),
decoration: BoxDecoration(
color: white,
borderRadius: BorderRadius.circular(16),
border: Border.all(
color: accent.withValues(alpha: 0.25),
),
),
child: Row(
children: [
Container(
width: 42,
height: 42,
decoration: BoxDecoration(
color: accent.withValues(alpha: 0.08),
borderRadius: BorderRadius.circular(10),
),
child: Icon(
icon,
color: accent,
size: 20,
),
),

const SizedBox(width: 14),

Expanded(
child: Text(
message,
style: TextStyle(
color: accent,
fontSize: 13,
height: 1.4,
),
),
),

TextButton(
onPressed: isAuthError
? () => Navigator.pushNamed(
context,
AppRoutes.login,
).then((_) => _loadTrips())
    : _loadTrips,
style: TextButton.styleFrom(
foregroundColor: midnight,
),
child: Text(
isAuthError ? 'Sign in' : 'Retry',
style: const TextStyle(
fontWeight: FontWeight.w800,
),
),
),
],
),
);
}

// ---------------------------------------------------------------------------
// Destinations
// ---------------------------------------------------------------------------

Widget _buildDestinationsHeader(bool isMobile) {
return _sectionHeading(
title: 'Popular destinations',
eyebrow: 'CURATED FOR YOU',
trailing: TextButton(
onPressed: _openExplore,
style: TextButton.styleFrom(
foregroundColor: midnight,
),
child: const Text(
'See all',
style: TextStyle(
fontWeight: FontWeight.w700,
),
),
),
);
}

Widget _buildDestinationStrip(bool isMobile) {
const featuredKeys = {
'Seychelles',
'Paris',
'Cotonou',
'Tokyo',
'Bali',
};

final featured = destinations
    .where((d) => featuredKeys.contains(d.city))
    .toList();

final list = featured.length >= 2
? featured
    : destinations.take(5).toList();

return SizedBox(
height: isMobile ? 330 : 350,
child: ListView.separated(
scrollDirection: Axis.horizontal,
physics: const BouncingScrollPhysics(),
itemCount: list.length,
separatorBuilder: (_, _) => const SizedBox(width: 16),
itemBuilder: (context, index) {
final destination = list[index];

return SizedBox(
width: isMobile ? 280 : 310,
child: _editorialDestinationCard(destination),
);
},
),
);
}

Widget _editorialDestinationCard(dynamic destination) {
return Material(
color: white,
borderRadius: BorderRadius.circular(16),
clipBehavior: Clip.antiAlias,
child: InkWell(
onTap: () => _openPlanner(destination.fullName),
child: Container(
decoration: BoxDecoration(
borderRadius: BorderRadius.circular(16),
border: Border.all(color: slate200),
),
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Expanded(
flex: 6,
child: Stack(
fit: StackFit.expand,
children: [
Image.network(
destination.imageUrl,
fit: BoxFit.cover,
errorBuilder: (context, error, stackTrace) {
return Container(
color: slate100,
child: const Icon(
Icons.image_not_supported_outlined,
color: slate500,
size: 32,
),
);
},
),

Positioned(
left: 0,
right: 0,
bottom: 0,
height: 90,
child: DecoratedBox(
decoration: BoxDecoration(
gradient: LinearGradient(
begin: Alignment.topCenter,
end: Alignment.bottomCenter,
colors: [
Colors.transparent,
midnight.withValues(alpha: 0.72),
],
),
),
),
),

Positioned(
left: 16,
bottom: 14,
right: 16,
child: Row(
children: [
Expanded(
child: Text(
destination.city,
maxLines: 1,
overflow: TextOverflow.ellipsis,
style: GoogleFonts.notoSerif(
color: white,
fontSize: 25,
fontWeight: FontWeight.w600,
),
),
),
const Icon(
Icons.arrow_outward_rounded,
color: white,
size: 19,
),
],
),
),
],
),
),

Expanded(
flex: 4,
child: Padding(
padding: const EdgeInsets.all(16),
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Text(
destination.country.toUpperCase(),
style: const TextStyle(
color: slate500,
fontSize: 9,
fontWeight: FontWeight.w800,
letterSpacing: 1,
),
),

const SizedBox(height: 7),

Expanded(
child: Text(
destination.description,
maxLines: 2,
overflow: TextOverflow.ellipsis,
style: const TextStyle(
color: textSecondary,
fontSize: 12,
height: 1.4,
),
),
),

const SizedBox(height: 8),

Row(
children: [
const Icon(
Icons.schedule_outlined,
size: 14,
color: midnight,
),
const SizedBox(width: 5),
Expanded(
child: Text(
destination.tripLength,
style: const TextStyle(
color: midnight,
fontSize: 11,
fontWeight: FontWeight.w700,
),
),
),
],
),
],
),
),
),
],
),
),
),
);
}

// ---------------------------------------------------------------------------
// Quick actions
// ---------------------------------------------------------------------------

Widget _buildQuickActions(
bool isMobile,
bool isTablet,
) {
final actions = [
_ActionItem(
icon: Icons.search_rounded,
title: 'Find ideas',
subtitle: 'Browse destinations by interest.',
label: 'EXPLORE',
onTap: _openExplore,
),
_ActionItem(
icon: Icons.auto_awesome_rounded,
title: 'Build a trip',
subtitle: 'Create a fresh AI itinerary.',
label: 'AI PLANNER',
onTap: () => _openPlanner(),
),
_ActionItem(
icon: Icons.luggage_outlined,
title: 'Manage trips',
subtitle: 'View and edit saved plans.',
label: 'YOUR TRIPS',
onTap: _openTrips,
),
];

return Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
const Text(
'TRAVEL DESK',
style: TextStyle(
color: slate500,
fontSize: 10,
fontWeight: FontWeight.w800,
letterSpacing: 1.2,
),
),

const SizedBox(height: 8),

Text(
'Everything for your next journey.',
style: GoogleFonts.notoSerif(
color: midnightDark,
fontSize: 26,
fontWeight: FontWeight.w600,
),
),

const SizedBox(height: 18),

LayoutBuilder(
builder: (context, constraints) {
final width = isMobile
? constraints.maxWidth
    : isTablet
? (constraints.maxWidth - 16) / 2
    : (constraints.maxWidth - 32) / 3;

return Wrap(
spacing: 16,
runSpacing: 16,
children: actions.map((action) {
return SizedBox(
width: width,
child: _buildActionCard(action),
);
}).toList(),
);
},
),
],
);
}

Widget _buildActionCard(_ActionItem action) {
return Material(
color: white,
borderRadius: BorderRadius.circular(16),
child: InkWell(
onTap: action.onTap,
borderRadius: BorderRadius.circular(16),
child: Container(
padding: const EdgeInsets.all(20),
decoration: BoxDecoration(
borderRadius: BorderRadius.circular(16),
border: Border.all(color: slate200),
),
child: Row(
children: [
Container(
width: 46,
height: 46,
decoration: BoxDecoration(
color: midnight,
borderRadius: BorderRadius.circular(12),
),
child: Icon(
action.icon,
color: white,
size: 21,
),
),

const SizedBox(width: 14),

Expanded(
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Text(
action.label,
style: const TextStyle(
color: slate500,
fontSize: 9,
fontWeight: FontWeight.w800,
letterSpacing: 0.9,
),
),

const SizedBox(height: 4),

Text(
action.title,
style: const TextStyle(
color: midnightDark,
fontSize: 15,
fontWeight: FontWeight.w800,
),
),

const SizedBox(height: 3),

Text(
action.subtitle,
maxLines: 2,
overflow: TextOverflow.ellipsis,
style: const TextStyle(
color: slate500,
fontSize: 11,
height: 1.35,
),
),
],
),
),

const SizedBox(width: 8),

const Icon(
Icons.arrow_forward_rounded,
size: 17,
color: slate500,
),
],
),
),
),
);
}

// ---------------------------------------------------------------------------
// Shared components
// ---------------------------------------------------------------------------

Widget _sectionHeading({
required String title,
required String eyebrow,
required Widget? trailing,
}) {
return Row(
crossAxisAlignment: CrossAxisAlignment.end,
children: [
Expanded(
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Text(
eyebrow,
style: const TextStyle(
color: slate500,
fontSize: 9,
fontWeight: FontWeight.w800,
letterSpacing: 1.1,
),
),

const SizedBox(height: 6),

Text(
title,
style: GoogleFonts.notoSerif(
color: midnightDark,
fontSize: 27,
height: 1.15,
fontWeight: FontWeight.w600,
letterSpacing: -0.4,
),
),
],
),
),

if (trailing != null) trailing,
],
);
}

Widget _primaryButton({
required String label,
required IconData icon,
required VoidCallback onPressed,
double height = 48,
double horizontalPadding = 22,
}) {
return SizedBox(
height: height,
child: ElevatedButton.icon(
onPressed: onPressed,
icon: Icon(
icon,
size: 17,
),
label: Text(label),
style: ElevatedButton.styleFrom(
backgroundColor: midnight,
foregroundColor: white,
elevation: 0,
padding: EdgeInsets.symmetric(
horizontal: horizontalPadding,
),
shape: RoundedRectangleBorder(
borderRadius: BorderRadius.circular(8),
),
textStyle: const TextStyle(
fontSize: 13,
fontWeight: FontWeight.w700,
letterSpacing: 0.1,
),
),
),
);
}

Widget _secondaryButton({
required String label,
required IconData icon,
required VoidCallback onPressed,
double height = 48,
}) {
return SizedBox(
height: height,
child: OutlinedButton.icon(
onPressed: onPressed,
icon: Icon(
icon,
size: 17,
),
label: Text(label),
style: OutlinedButton.styleFrom(
foregroundColor: midnight,
backgroundColor: Colors.transparent,
side: const BorderSide(color: slate300),
padding: const EdgeInsets.symmetric(horizontal: 20),
shape: RoundedRectangleBorder(
borderRadius: BorderRadius.circular(8),
),
textStyle: const TextStyle(
fontSize: 13,
fontWeight: FontWeight.w700,
),
),
),
);
}
}

// -----------------------------------------------------------------------------
// Hero metadata
// -----------------------------------------------------------------------------

class _HeroMeta extends StatelessWidget {
final IconData icon;
final String label;

const _HeroMeta({
required this.icon,
required this.label,
});

@override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: const Color(0xFF10B981),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.7,
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Action model
// -----------------------------------------------------------------------------

class _ActionItem {
final IconData icon;
final String title;
final String subtitle;
final String label;
final VoidCallback onTap;

const _ActionItem({
required this.icon,
required this.title,
required this.subtitle,
required this.label,
required this.onTap,
});
}