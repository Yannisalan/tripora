import 'package:flutter/material.dart';

import '../../data/destinations.dart';
import '../../models/destination_model.dart';
import '../../routes/app_routes.dart';
import '../../widgets/destination_card.dart';
import '../../widgets/gradient_button.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final TextEditingController _searchController = TextEditingController();

  String _query = '';
  String _selectedTag = 'All';

  List<String> get _tags {
    final tags = destinations.expand((destination) => destination.tags).toSet()
      ..add('All');
    final sorted = tags.toList()..sort();
    sorted.remove('All');
    return ['All', ...sorted];
  }

  List<DestinationModel> get _filteredDestinations {
    return destinations.where((destination) {
      final query = _query.toLowerCase();
      final matchesQuery =
          query.isEmpty ||
          destination.city.toLowerCase().contains(query) ||
          destination.country.toLowerCase().contains(query) ||
          destination.description.toLowerCase().contains(query) ||
          destination.tags.any((tag) => tag.toLowerCase().contains(query));

      final matchesTag =
          _selectedTag == 'All' || destination.tags.contains(_selectedTag);

      return matchesQuery && matchesTag;
    }).toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _planDestination(DestinationModel destination) {
    Navigator.pushNamed(
      context,
      AppRoutes.planner,
      arguments: destination.fullName,
    );
  }

  void _showDestinationDetails(DestinationModel destination) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE2E8F0),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.network(
                            destination.imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                color: const Color(0xFFE5E7EB),
                                child: const Icon(
                                  Icons.image_not_supported,
                                ),
                              );
                            },
                          ),
                          DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Colors.black.withValues(alpha: 0.55),
                                ],
                                stops: const [0.5, 1.0],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    destination.city,
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        size: 16,
                        color: Color(0xFF2563EB),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        destination.country,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF2563EB),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    destination.description,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.5,
                      color: Color(0xFF475569),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _DetailRow(
                    icon: Icons.favorite_outline,
                    label: 'Best for',
                    value: destination.bestFor,
                  ),
                  _DetailRow(
                    icon: Icons.calendar_month_outlined,
                    label: 'Suggested stay',
                    value: destination.tripLength,
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: destination.tags.map((tag) {
                      return Chip(label: Text(tag));
                    }).toList(),
                  ),
                  const SizedBox(height: 26),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: GradientButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _planDestination(destination);
                      },
                      height: 54,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      icon: const Icon(Icons.add_location_alt_outlined),
                      label: const Text(
                        'Plan This Trip',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isCompact = width < 760;
    final filtered = _filteredDestinations;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Explore',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.symmetric(
          horizontal: isCompact ? 16 : 40,
          vertical: 24,
        ),
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFFEFF6FF),
                      Color(0xFFF5F3FF),
                      Color(0xFFECFEFF),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: const Color(0xFF2563EB).withValues(alpha: 0.18),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.public, size: 16, color: Color(0xFF2563EB)),
                    SizedBox(width: 6),
                    Text(
                      'Add Africa to your travel list',
                      style: TextStyle(
                        color: Color(0xFF1D4ED8),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Text(
            'Discover where to go next',
            style: TextStyle(
              fontSize: 34,
              height: 1.1,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'From Cotonou to Seychelles — search by place or mood, then send the destination straight into Planner.',
            style: TextStyle(
              fontSize: 16,
              height: 1.45,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 22),
          TextField(
            controller: _searchController,
            onChanged: (value) {
              setState(() {
                _query = value.trim();
              });
            },
            decoration: InputDecoration(
              hintText: 'Search destinations, food, nature, culture...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _query = '';
                        });
                      },
                      icon: const Icon(Icons.close),
                    ),
            ),
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _tags.map((tag) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(tag),
                    selected: _selectedTag == tag,
                    onSelected: (_) {
                      setState(() {
                        _selectedTag = tag;
                      });
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 24),
          if (filtered.isEmpty)
            _buildEmptyState()
          else
            Wrap(
              spacing: 18,
              runSpacing: 18,
              children: filtered.map((destination) {
                return SizedBox(
                  width: isCompact ? double.infinity : 320,
                  child: DestinationCard(
                    imageUrl: destination.imageUrl,
                    city: destination.city,
                    country: destination.country,
                    description: destination.description,
                    footer: destination.tripLength,
                    tags: destination.tags,
                    width: double.infinity,
                    onTap: () => _showDestinationDetails(destination),
                    onPlan: () => _planDestination(destination),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final hasActiveSearch = _query.isNotEmpty;
    final hasActiveTag = _selectedTag != 'All';

    String headline, description;

    if (hasActiveSearch && hasActiveTag) {
      headline = 'No matches found';
      description =
          'Try adjusting your search or filter to discover destinations.';
    } else if (hasActiveSearch) {
      headline = 'No destinations match your search';
      description = 'Try different keywords or browse by interest below.';
    } else if (hasActiveTag) {
      headline = 'No destinations in this category';
      description = 'Try a different interest or browse all destinations.';
    } else {
      headline = 'No destinations found';
      description = 'Try a different search or interest filter.';
    }

    return Card(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(
              Icons.travel_explore_outlined,
              size: 46,
              color: Colors.blue.shade700,
            ),
            const SizedBox(height: 12),
            Text(
              headline,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              description,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.blue.shade700),
            ),
            if (hasActiveSearch || hasActiveTag) ...[
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: () {
                  _searchController.clear();
                  setState(() {
                    _query = '';
                    _selectedTag = 'All';
                  });
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Clear Filters'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 20, color: const Color(0xFF2563EB)),
          const SizedBox(width: 10),
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w800)),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
