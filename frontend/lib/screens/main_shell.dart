import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/l10n/app_localizations.dart';
import '../core/theme/app_theme.dart';
import '../screens/explore/explore_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/travel/flight_search_screen.dart';
import '../screens/trips/trips_screen.dart';

class MainShell extends StatefulWidget {
const MainShell({super.key});

static final ValueNotifier<int> currentIndex = ValueNotifier<int>(0);

@override
State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
static const List<Widget> _pages = [
HomeScreen(),
ExploreScreen(),
FlightSearchScreen(),
TripsScreen(),
ProfileScreen(),
];

@override
Widget build(BuildContext context) {
return ValueListenableBuilder<int>(
valueListenable: MainShell.currentIndex,
builder: (context, currentIndex, _) {
return Scaffold(
body: IndexedStack(
index: currentIndex,
children: _pages,
),
bottomNavigationBar: _TriporaBottomNav(
currentIndex: currentIndex,
onSelected: (index) {
MainShell.currentIndex.value = index;
},
),
);
},
);
}
}

class _TriporaBottomNav extends StatelessWidget {
const _TriporaBottomNav({
required this.currentIndex,
required this.onSelected,
});

final int currentIndex;
final ValueChanged<int> onSelected;

@override
Widget build(BuildContext context) {
final colors = context.triporaColors;

final items = [
_NavItem(
icon: Icons.home_outlined,
selectedIcon: Icons.home,
label: context.tr('nav.home'),
),
_NavItem(
icon: Icons.explore_outlined,
selectedIcon: Icons.explore,
label: context.tr('nav.explore'),
),
_NavItem(
icon: Icons.flight_takeoff_outlined,
selectedIcon: Icons.flight_takeoff,
label: context.tr('nav.flights'),
),
_NavItem(
icon: Icons.card_travel_outlined,
selectedIcon: Icons.card_travel,
label: context.tr('nav.trips'),
),
_NavItem(
icon: Icons.person_outline,
selectedIcon: Icons.person,
label: context.tr('nav.profile'),
),
];

return SafeArea(
top: false,
minimum: const EdgeInsets.fromLTRB(
AppSpacing.sm,
0,
AppSpacing.sm,
AppSpacing.sm,
),
child: ClipRRect(
borderRadius: BorderRadius.circular(26),
child: BackdropFilter(
filter: ImageFilter.blur(
sigmaX: 22,
sigmaY: 22,
),
child: Container(
decoration: BoxDecoration(
color: colors.surface.withValues(alpha: 0.78),
borderRadius: BorderRadius.circular(26),
border: Border.all(
color: Colors.white.withValues(alpha: 0.55),
width: 0.8,
),
boxShadow: [
BoxShadow(
color: AppColors.primary.withValues(alpha: 0.10),
blurRadius: 24,
offset: const Offset(0, 8),
),
BoxShadow(
color: Colors.black.withValues(alpha: 0.04),
blurRadius: 6,
offset: const Offset(0, 2),
),
],
),
child: Padding(
padding: const EdgeInsets.symmetric(
horizontal: 6,
vertical: 6,
),
child: Row(
children: List.generate(
items.length,
(index) {
final item = items[index];

return Expanded(
child: _TriporaNavItem(
item: item,
selected: index == currentIndex,
onTap: () => onSelected(index),
),
);
},
),
),
),
),
),
),
);
}
}

class _TriporaNavItem extends StatelessWidget {
const _TriporaNavItem({
required this.item,
required this.selected,
required this.onTap,
});

final _NavItem item;
final bool selected;
final VoidCallback onTap;

@override
Widget build(BuildContext context) {
final colors = context.triporaColors;

return Semantics(
button: true,
selected: selected,
label: item.label,
child: InkWell(
onTap: onTap,
borderRadius: BorderRadius.circular(20),
child: AnimatedContainer(
duration: const Duration(milliseconds: 180),
curve: Curves.easeOutCubic,
margin: const EdgeInsets.symmetric(horizontal: 2),
padding: const EdgeInsets.symmetric(
vertical: AppSpacing.xs,
),
decoration: BoxDecoration(
color: selected
? AppColors.primary.withValues(alpha: 0.10)
    : Colors.transparent,
borderRadius: BorderRadius.circular(20),
border: selected
? Border.all(
color: AppColors.primary.withValues(alpha: 0.08),
width: 0.8,
)
    : null,
),
child: Column(
mainAxisSize: MainAxisSize.min,
children: [
AnimatedSwitcher(
duration: const Duration(milliseconds: 160),
transitionBuilder: (child, animation) {
return ScaleTransition(
scale: Tween<double>(
begin: 0.88,
end: 1,
).animate(animation),
child: FadeTransition(
opacity: animation,
child: child,
),
);
},
child: Icon(
selected ? item.selectedIcon : item.icon,
key: ValueKey(selected),
size: 22,
color: selected
? AppColors.primary
    : colors.textMuted,
),
),
const SizedBox(height: 3),
AnimatedDefaultTextStyle(
duration: const Duration(milliseconds: 160),
curve: Curves.easeOutCubic,
style: Theme.of(context).textTheme.labelSmall!.copyWith(
color: selected
? AppColors.primary
    : colors.textMuted,
fontWeight:
selected ? FontWeight.w700 : FontWeight.w600,
),
child: Text(
item.label,
maxLines: 1,
overflow: TextOverflow.ellipsis,
),
),
],
),
),
),
);
}
}

class _NavItem {
const _NavItem({
required this.icon,
required this.selectedIcon,
required this.label,
});

final IconData icon;
final IconData selectedIcon;
final String label;
}
