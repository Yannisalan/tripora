import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/l10n/app_localizations.dart';
import '../../core/theme/app_theme.dart';
import '../../data/destinations.dart';
import '../../models/destination_model.dart';
import '../../routes/app_routes.dart';
import '../../widgets/destination_card.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  // Internal value only. Never displayed directly to the user.
  static const String _allTag = '__all__';

  final TextEditingController _searchController =
      TextEditingController();

  String _query = '';
  String _selectedTag = _allTag;

  List<String> get _tags {
    final tags = destinations
        .expand((destination) => destination.tags)
        .toSet()
        .toList()
      ..sort();

    return [_allTag, ...tags];
  }

  List<DestinationModel> get _filteredDestinations {
    return destinations.where((destination) {
      final query = _query.toLowerCase();

      final matchesQuery =
          query.isEmpty ||
          destination.city.toLowerCase().contains(query) ||
          destination.country.toLowerCase().contains(query) ||
          destination.description.toLowerCase().contains(query) ||
          destination.tags.any(
            (tag) => tag.toLowerCase().contains(query),
          );

      final matchesTag =
          _selectedTag == _allTag ||
          destination.tags.contains(_selectedTag);

      return matchesQuery && matchesTag;
    }).toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ============================================================
  // NAVIGATION
  // ============================================================

  void _planDestination(DestinationModel destination) {
    Navigator.pushNamed(
      context,
      AppRoutes.planner,
      arguments: destination.fullName,
    );
  }

  // ============================================================
  // DESTINATION DETAILS
  // ============================================================

  void _showDestinationDetails(
    DestinationModel destination,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final colors = sheetContext.triporaColors;
        final scheme = Theme.of(sheetContext).colorScheme;

        return SafeArea(
          child: Container(
            decoration: BoxDecoration(
              color: colors.backgroundColor,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(
              20,
              10,
              20,
              24,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Bottom sheet handle
                  Center(
                    child: Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: colors.borderStrong,
                        borderRadius: BorderRadius.circular(100),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Destination image
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.network(
                            destination.imageUrl,
                            fit: BoxFit.cover,
                            cacheWidth: 900,
                            errorBuilder: (
                              context,
                              error,
                              stackTrace,
                            ) {
                              return Container(
                                color: colors.surfaceSecondary,
                                child: Icon(
                                  Icons.image_not_supported_outlined,
                                  color: colors.textMuted,
                                  size: 36,
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
                                stops: const [
                                  0.5,
                                  1.0,
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // City
                  Text(
                    destination.city,
                    style: GoogleFonts.notoSerif(
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                      color: sheetContext.headingColor,
                      height: 1.15,
                    ),
                  ),

                  const SizedBox(height: 6),

                  // Country
                  Row(
                    children: [
                      Icon(
                        Icons.location_on_outlined,
                        size: 17,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        destination.country,
                        style: GoogleFonts.manrope(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: sheetContext.headingColor,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Description
                  Text(
                    destination.description,
                    style: GoogleFonts.manrope(
                      fontSize: 14,
                      height: 1.55,
                      color: colors.textSecondary,
                    ),
                  ),

                  const SizedBox(height: 18),

                  _DetailRow(
                    icon: Icons.favorite_outline,
                    label: sheetContext.tr('explore.bestFor'),
                    value: destination.bestFor,
                  ),

                  _DetailRow(
                    icon: Icons.calendar_month_outlined,
                    label: sheetContext.tr('explore.suggestedStay'),
                    value: destination.tripLength,
                  ),

                  const SizedBox(height: 8),

                  // Tags
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: destination.tags.map((tag) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: colors.surfaceSecondary,
                          border: Border.all(
                            color: colors.border,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          tag,
                          style: GoogleFonts.manrope(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: sheetContext.headingColor,
                          ),
                        ),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 22),

                  // Plan trip button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        _planDestination(destination);
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: scheme.primary,
                        foregroundColor: scheme.onPrimary,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: const Icon(
                        Icons.add_location_alt_outlined,
                        size: 18,
                      ),
                      label: Text(
                        sheetContext.tr('explore.planThisTrip'),
                        style: GoogleFonts.manrope(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
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

  // ============================================================
  // REFRESH
  // ============================================================

  Future<void> _refresh() async {
    _searchController.clear();

    setState(() {
      _query = '';
      _selectedTag = _allTag;
    });

    await Future<void>.delayed(
      const Duration(milliseconds: 400),
    );

    if (mounted) {
      setState(() {});
    }
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final colors = context.triporaColors;
    final scheme = Theme.of(context).colorScheme;

    final width = MediaQuery.of(context).size.width;

    final isCompact = width < 760;
    final isTablet = width >= 760 && width < 1200;

    final filtered = _filteredDestinations;

    final horizontalPadding = isCompact
        ? 16.0
        : isTablet
            ? 24.0
            : 40.0;

    return Scaffold(
      backgroundColor: colors.backgroundColor,

      // ========================================================
      // APP BAR
      // ========================================================

      appBar: AppBar(
        backgroundColor: colors.backgroundColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: isCompact ? 16 : 24,
        title: Text(
          context.tr('explore.title'),
          style: GoogleFonts.manrope(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: context.headingColor,
          ),
        ),
      ),

      // ========================================================
      // BODY
      // ========================================================

      body: RefreshIndicator(
        color: scheme.primary,
        backgroundColor: colors.surface,
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: 24,
          ),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 1280,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ==================================================
                    // EDITORIAL HEADER
                    // ==================================================

                    Text(
                      context.tr('explore.discover'),
                      style: GoogleFonts.manrope(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                        color: colors.textMuted,
                      ),
                    ),

                    const SizedBox(height: 8),

                    Text(
                      context.tr('explore.discoverNext'),
                      style: GoogleFonts.notoSerif(
                        fontSize: isCompact ? 28 : 32,
                        fontWeight: FontWeight.w600,
                        height: 1.15,
                        color: context.headingColor,
                      ),
                    ),

                    const SizedBox(height: 8),

                    ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: 700,
                      ),
                      child: Text(
                        context.tr('explore.description'),
                        style: GoogleFonts.manrope(
                          fontSize: 14,
                          height: 1.55,
                          color: colors.textMuted,
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // ==================================================
                    // SEARCH
                    // ==================================================

                    Container(
                      decoration: BoxDecoration(
                        color: colors.surface,
                        border: Border.all(
                          color: colors.border,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x0A1E1B4B),
                            blurRadius: 10,
                            offset: Offset(0, 3),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(14),
                      child: TextField(
                        controller: _searchController,
                        onChanged: (value) {
                          setState(() {
                            _query = value.trim();
                          });
                        },
                        style: GoogleFonts.manrope(
                          fontSize: 14,
                          color: context.headingColor,
                        ),
                        decoration: InputDecoration(
                          hintText: context.tr(
                            'explore.searchHint',
                          ),
                          hintStyle: GoogleFonts.manrope(
                            fontSize: 13,
                            color: colors.textMuted,
                          ),
                          prefixIcon: Icon(
                            Icons.search,
                            color: scheme.primary,
                            size: 21,
                          ),
                          suffixIcon: _query.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: context.tr(
                                    'common.clear',
                                  ),
                                  onPressed: () {
                                    _searchController.clear();

                                    setState(() {
                                      _query = '';
                                    });
                                  },
                                  icon: Icon(
                                    Icons.close,
                                    color: colors.textMuted,
                                    size: 19,
                                  ),
                                ),
                          filled: true,
                          fillColor: colors.backgroundColor,
                          contentPadding:
                              const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 14,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                              color: colors.border,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                              color: colors.border,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                              color: scheme.primary,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ==================================================
                    // FILTERS
                    // ==================================================

                    Text(
                      context.tr('explore.interests'),
                      style: GoogleFonts.manrope(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.3,
                        color: colors.textMuted,
                      ),
                    ),

                    const SizedBox(height: 9),

                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _tags.map((tag) {
                          final selected = _selectedTag == tag;

                          return Padding(
                            padding: const EdgeInsets.only(
                              right: 8,
                            ),
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedTag = tag;
                                });
                              },
                              child: AnimatedContainer(
                                duration: const Duration(
                                  milliseconds: 180,
                                ),
                                padding:
                                    const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 9,
                                ),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? scheme.primary
                                      : colors.surface,
                                  border: Border.all(
                                    color: selected
                                        ? scheme.primary
                                        : colors.borderStrong,
                                  ),
                                  borderRadius:
                                      BorderRadius.circular(8),
                                ),
                                child: Text(
                                  tag == _allTag
                                      ? context.tr('common.all')
                                      : tag,
                                  style: GoogleFonts.manrope(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: selected
                                        ? scheme.onPrimary
                                        : colors.textSecondary,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),

                    const SizedBox(height: 28),

                    // ==================================================
                    // RESULTS HEADER
                    // ==================================================

                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Text(
                            context.tr('explore.destinations'),
                            style: GoogleFonts.notoSerif(
                              fontSize: 24,
                              fontWeight: FontWeight.w600,
                              color: context.headingColor,
                            ),
                          ),
                        ),
                        Text(
                          context.tr(
                            filtered.length == 1
                                ? 'explore.placeCount'
                                : 'explore.placesCount',
                            params: {
                              'n': filtered.length.toString(),
                            },
                          ),
                          style: GoogleFonts.manrope(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: colors.textMuted,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),

                    // ==================================================
                    // DESTINATIONS
                    // ==================================================

                    if (filtered.isEmpty)
                      _buildEmptyState(context)
                    else
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final availableWidth =
                              constraints.maxWidth;

                          final columns = isCompact
                              ? 1
                              : availableWidth >= 1000
                                  ? 3
                                  : 2;

                          const spacing = 16.0;

                          final cardWidth = columns == 1
                              ? availableWidth
                              : (availableWidth -
                                      spacing * (columns - 1)) /
                                  columns;

                          return Wrap(
                            spacing: spacing,
                            runSpacing: spacing,
                            children: filtered.map(
                              (destination) {
                                return SizedBox(
                                  width: cardWidth,
                                  child: DestinationCard(
                                    imageUrl:
                                        destination.imageUrl,
                                    city: destination.city,
                                    country:
                                        destination.country,
                                    description:
                                        destination.description,
                                    footer:
                                        destination.tripLength,
                                    tags: destination.tags,
                                    width: double.infinity,
                                    onTap: () =>
                                        _showDestinationDetails(
                                      destination,
                                    ),
                                    onPlan: () =>
                                        _planDestination(
                                      destination,
                                    ),
                                  ),
                                );
                              },
                            ).toList(),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // EMPTY STATE
  // ============================================================

  Widget _buildEmptyState(BuildContext context) {
    final colors = context.triporaColors;
    final scheme = Theme.of(context).colorScheme;

    final hasActiveSearch = _query.isNotEmpty;
    final hasActiveTag = _selectedTag != _allTag;

    late String headline;
    late String description;

    if (hasActiveSearch && hasActiveTag) {
      headline = context.tr('explore.noMatches');
      description = context.tr(
        'explore.noMatchesDescription',
      );
    } else if (hasActiveSearch) {
      headline = context.tr('explore.noSearchMatches');
      description = context.tr(
        'explore.noSearchMatchesDescription',
      );
    } else if (hasActiveTag) {
      headline = context.tr('explore.noCategory');
      description = context.tr(
        'explore.noCategoryDescription',
      );
    } else {
      headline = context.tr('explore.noDestinations');
      description = context.tr(
        'explore.noDestinationsDescription',
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: 24,
        vertical: 42,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(
          color: colors.border,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: colors.surfaceSecondary,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.travel_explore_outlined,
              size: 28,
              color: scheme.primary,
            ),
          ),

          const SizedBox(height: 18),

          Text(
            headline,
            textAlign: TextAlign.center,
            style: GoogleFonts.notoSerif(
              fontSize: 21,
              fontWeight: FontWeight.w600,
              color: context.headingColor,
            ),
          ),

          const SizedBox(height: 7),

          ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 460,
            ),
            child: Text(
              description,
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                fontSize: 13,
                height: 1.5,
                color: colors.textMuted,
              ),
            ),
          ),

          if (hasActiveSearch || hasActiveTag) ...[
            const SizedBox(height: 18),

            OutlinedButton.icon(
              onPressed: () {
                _searchController.clear();

                setState(() {
                  _query = '';
                  _selectedTag = _allTag;
                });
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: scheme.primary,
                side: BorderSide(
                  color: colors.borderStrong,
                ),
                backgroundColor: colors.backgroundColor,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 11,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: const Icon(
                Icons.refresh,
                size: 17,
              ),
              label: Text(
                context.tr('explore.clearFilters'),
                style: GoogleFonts.manrope(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ================================================================
// DETAIL ROW
// ================================================================

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
    final colors = context.triporaColors;
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(
        bottom: 10,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: colors.surfaceSecondary,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 17,
              color: scheme.primary,
            ),
          ),

          const SizedBox(width: 10),

          Text(
            '$label ',
            style: GoogleFonts.manrope(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: context.headingColor,
            ),
          ),

          Expanded(
            child: Text(
              value,
              style: GoogleFonts.manrope(
                fontSize: 12,
                height: 1.4,
                color: colors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}