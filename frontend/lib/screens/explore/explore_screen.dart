import 'package:flutter/material.dart';
import '../../data/destinations.dart';
import '../../core/theme/app_theme.dart';
import '../../models/destination_model.dart';
import '../../routes/app_routes.dart';
import '../../widgets/destination_card.dart';

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
    final textTheme = Theme.of(context).textTheme;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          child: Container(
            decoration: BoxDecoration(
              color: context.triporaColors.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppRadius.xl),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.xs,
              AppSpacing.lg,
              AppSpacing.xl,
            ),
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
                        color: context.triporaColors.border,
                        borderRadius: BorderRadius.circular(AppRadius.full),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.network(
                            destination.imageUrl,
                            fit: BoxFit.cover,
                            cacheWidth: 900,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                color: context.triporaColors.border,
                                child: const Icon(Icons.image_not_supported),
                              );
                            },
                          ),
                          // Photo scrim for text legibility — not a brand
                          // gradient, so it stays even though the design
                          // system otherwise avoids gradients on UI chrome.
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
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    destination.city,
                    style: textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      ExcludeSemantics(
                        child: Icon(
                          Icons.location_on_outlined,
                          size: 16,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        destination.country,
                        style: textTheme.labelLarge?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    destination.description,
                    style: textTheme.bodyLarge?.copyWith(
                      color: context.triporaColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
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
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: destination.tags.map((tag) {
                      return Chip(label: Text(tag));
                    }).toList(),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _planDestination(destination);
                      },
                      icon: const Icon(Icons.add_location_alt_outlined),
                      label: const Text('Plan this trip'),
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

  Future<void> _refresh() async {
    _searchController.clear();

    setState(() {
      _query = '';
      _selectedTag = 'All';
    });

    await Future<void>.delayed(const Duration(milliseconds: 400));

    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isCompact = width < 760;
    final filtered = _filteredDestinations;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('Explore', style: textTheme.headlineSmall),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.symmetric(
            horizontal: isCompact ? AppSpacing.md : AppSpacing.xl2,
            vertical: AppSpacing.lg,
          ),
          children: [
            Text(
              'Discover where to go next',
              style: isCompact ? textTheme.headlineLarge : textTheme.displayLarge,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'From Cotonou to Seychelles — search by place or mood, then '
                  'send the destination straight into Planner.',
              style: textTheme.bodyLarge?.copyWith(
                color: context.triporaColors.textMuted,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _searchController,
              onChanged: (value) {
                setState(() {
                  _query = value.trim();
                });
              },
              decoration: InputDecoration(
                hintText: 'Search destinations, food, nature, culture...',
                prefixIcon: const ExcludeSemantics(child: Icon(Icons.search)),
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
            const SizedBox(height: AppSpacing.md),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _tags.map((tag) {
                  return Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.xs),
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
            const SizedBox(height: AppSpacing.lg),
            if (filtered.isEmpty)
              _buildEmptyState(context)
            else
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
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
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final hasActiveSearch = _query.isNotEmpty;
    final hasActiveTag = _selectedTag != 'All';
    final textTheme = Theme.of(context).textTheme;

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
      color: context.triporaColors.surfaceInfo,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: [
            ExcludeSemantics(
              child: Icon(
                Icons.travel_explore_outlined,
                size: 46,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(headline, style: textTheme.headlineSmall),
            const SizedBox(height: 6),
            Text(
              description,
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: context.triporaColors.textSecondary,
              ),
            ),
            if (hasActiveSearch || hasActiveTag) ...[
              const SizedBox(height: AppSpacing.md),
              TextButton.icon(
                onPressed: () {
                  _searchController.clear();
                  setState(() {
                    _query = '';
                    _selectedTag = 'All';
                  });
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Clear filters'),
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
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 10),
          Text('$label: ', style: textTheme.labelLarge),
          Expanded(
            child: Text(
              value,
              style: textTheme.bodyMedium?.copyWith(
                color: context.triporaColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}