import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../routes/app_routes.dart';

/// Hub for the premium travel-search features.
///
/// Free users are routed through [PremiumGate] which shows the paywall;
/// premium users see the three search categories (Flights / Stays / Cars).
class PremiumTravelScreen extends StatelessWidget {
  const PremiumTravelScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Premium Travel')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: const [
          _Header(),
          SizedBox(height: 20),
          _TravelTile(
            icon: Icons.flight_takeoff,
            title: 'Flights',
            subtitle: 'Search live fares on routes around the world.',
            color: Color(0xFF2563EB),
            route: AppRoutes.travelFlights,
          ),
          SizedBox(height: 14),
          _TravelTile(
            icon: Icons.hotel_outlined,
            title: 'Hotels',
            subtitle: 'Find stays near your destination.',
            color: Color(0xFF7C3AED),
            route: AppRoutes.travelStays,
          ),
          SizedBox(height: 14),
          _TravelTile(
            icon: Icons.directions_car_outlined,
            title: 'Cars',
            subtitle: 'Compare rental cars at pickup and drop-off.',
            color: Color(0xFFEA580C),
            route: AppRoutes.travelCars,
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.travel_explore, color: Colors.white, size: 28),
              SizedBox(width: 10),
              Text(
                'Search the world',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          SizedBox(height: 10),
          Text(
            'Live travel search, powered for Tripora Premium. '
            'Results are for display only — Tripora doesn\'t book or charge '
            'for travel.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _TravelTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final String route;

  const _TravelTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.route,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: const Color(0xFFE5E7EB)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          Navigator.pushNamed(context, route);
        },
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
