import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend/core/auth/token_store.dart';
import 'package:frontend/core/design/glass/glass_nav.dart';
import 'package:frontend/core/design/glass/glass_surface.dart';
import 'package:frontend/core/design/glass/glass_tokens.dart';
import 'package:frontend/core/preferences/app_preferences.dart';
import 'package:frontend/main.dart';
import 'package:frontend/screens/explore/explore_screen.dart';
import 'package:frontend/screens/home/home_screen.dart';
import 'package:frontend/screens/main_shell.dart';
import 'package:frontend/screens/profile/profile_screen.dart';
import 'package:frontend/screens/travel/flight_search_screen.dart';
import 'package:frontend/screens/trips/trips_screen.dart';

/// Labels of the five destinations (English), in order.
const _labels = ['Home', 'Explore', 'Flights', 'My Trips', 'Profile'];

/// The exact icons the shell used before the responsive pass, in order:
/// (unselected, selected). Index 0 is selected right after launch.
const _icons = <(IconData, IconData)>[
  (Icons.home_outlined, Icons.home),
  (Icons.explore_outlined, Icons.explore),
  (Icons.flight_takeoff_outlined, Icons.flight_takeoff),
  (Icons.card_travel_outlined, Icons.card_travel),
  (Icons.person_outline, Icons.person),
];

Future<void> _pumpApp(
  WidgetTester tester,
  double width, {
  double height = 900,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({'access_token': 'test-token'});
  MainShell.currentIndex.value = 0;

  await tester.pumpWidget(const TriporaApp());
  // Splash: 1100ms delay + 400ms exit fade, then the replaced route
  // needs a frame to build and its transition to finish.
  await tester.pump(const Duration(milliseconds: 1500));
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _resize(
  WidgetTester tester,
  double width, {
  double height = 900,
}) async {
  tester.view.physicalSize = Size(width, height);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 300));
}

/// A destination inside [nav], found by its accessible label (the visible
/// text may be split over two lines on narrow phones).
Finder _item(Finder nav, String label) => find.descendant(
  of: nav,
  matching: find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.label == label,
  ),
);

/// Finder for whichever primary navigation is on screen.
Finder _anyNav() => find.byWidgetPredicate(
  (w) => w is GlassBottomNav || w is GlassNavRail || w is GlassSideNav,
);

void main() {
  setUp(() {
    TokenStore.debugForceSecureStorage = false;
    TokenStore.instance.resetForTesting();
  });
  tearDown(() {
    TokenStore.debugForceSecureStorage = null;
    TokenStore.instance.resetForTesting();
    MainShell.currentIndex.value = 0;
  });

  test('breakpoints follow width only', () {
    expect(TriporaBreakpoints.sizeFor(360), TriporaLayoutSize.compact);
    expect(TriporaBreakpoints.sizeFor(767.9), TriporaLayoutSize.compact);
    expect(TriporaBreakpoints.sizeFor(768), TriporaLayoutSize.medium);
    expect(TriporaBreakpoints.sizeFor(1279.9), TriporaLayoutSize.medium);
    expect(TriporaBreakpoints.sizeFor(1280), TriporaLayoutSize.expanded);
    expect(TriporaBreakpoints.navFor(767), TriporaNavMode.bottomBar);
    expect(TriporaBreakpoints.navFor(768), TriporaNavMode.rail);
    expect(TriporaBreakpoints.navFor(1279), TriporaNavMode.rail);
    expect(TriporaBreakpoints.navFor(1280), TriporaNavMode.sidebar);
    expect(TriporaBreakpoints.usesSidebar(1279), isFalse);
    expect(TriporaBreakpoints.usesSidebar(1280), isTrue);
  });

  for (final width in const <double>[360, 390, 767, 768, 1024, 1279, 1280, 1440]) {
    final mode = TriporaBreakpoints.navFor(width);
    final sidebar = mode == TriporaNavMode.sidebar;
    final rail = mode == TriporaNavMode.rail;
    final vertical = sidebar || rail;

    testWidgets(
      'width $width: exactly one ${mode.name} '
      'with the original five icons',
      (tester) async {
        await _pumpApp(tester, width);

        expect(
          _anyNav(),
          findsOneWidget,
          reason: 'exactly one primary navigation must be rendered',
        );
        expect(
          find.byType(GlassSideNav),
          sidebar ? findsOneWidget : findsNothing,
        );
        expect(
          find.byType(GlassNavRail),
          rail ? findsOneWidget : findsNothing,
        );
        expect(
          find.byType(GlassBottomNav),
          vertical ? findsNothing : findsOneWidget,
        );

        // Same order, labels and icons in either presentation.
        final nav = _anyNav();
        for (var i = 0; i < _labels.length; i++) {
          expect(
            _item(nav, _labels[i]),
            findsOneWidget,
            reason: 'nav label ${_labels[i]}',
          );
          final icon = i == 0 ? _icons[i].$2 : _icons[i].$1;
          expect(
            find.descendant(of: nav, matching: find.byIcon(icon)),
            findsOneWidget,
            reason: 'nav icon for ${_labels[i]}',
          );
        }

        // Item order on screen matches the destination order.
        final positions = [
          for (final label in _labels) tester.getCenter(_item(nav, label)),
        ];
        for (var i = 1; i < positions.length; i++) {
          if (vertical) {
            expect(positions[i].dy, greaterThan(positions[i - 1].dy));
          } else {
            expect(positions[i].dx, greaterThan(positions[i - 1].dx));
          }
        }

        // One Plan a Trip CTA: Home's app bar on compact, an icon button
        // (with tooltip) in the rail, a labelled button in the sidebar.
        if (rail) {
          expect(find.text('Plan a Trip'), findsNothing);
          expect(
            find.descendant(
              of: find.byType(GlassNavRail),
              matching: find.byTooltip('Plan a Trip'),
            ),
            findsOneWidget,
          );
          // Every rail destination has a tooltip with its label.
          for (final label in _labels) {
            expect(
              find.descendant(
                of: find.byType(GlassNavRail),
                matching: find.byTooltip(label),
              ),
              findsOneWidget,
              reason: 'rail tooltip $label',
            );
          }
        } else {
          expect(find.text('Plan a Trip'), findsOneWidget);
        }
        if (sidebar) {
          expect(
            find.descendant(
              of: find.byType(GlassSideNav),
              matching: find.text('Plan a Trip'),
            ),
            findsOneWidget,
          );
        }

        // Selecting the selected icon variant follows the current tab.
        MainShell.currentIndex.value = 2;
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          find.descendant(of: nav, matching: find.byIcon(Icons.flight_takeoff)),
          findsOneWidget,
        );
        expect(
          find.descendant(of: nav, matching: find.byIcon(Icons.home_outlined)),
          findsOneWidget,
        );

        final exception = tester.takeException();
        expect(
          exception,
          isNull,
          reason: 'layout exception at $width: $exception',
        );
      },
    );
  }

  testWidgets('tapping a destination switches tabs', (tester) async {
    for (final width in const <double>[390, 1024, 1440]) {
      await _pumpApp(tester, width);
      final nav = _anyNav();
      await tester.tap(_item(nav, 'Explore'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(MainShell.currentIndex.value, 1, reason: 'width $width');
      await tester.tap(_item(nav, 'Flights'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(MainShell.currentIndex.value, 2, reason: 'width $width');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('bottom bar items are at least 48x48 at 360 px', (tester) async {
    await _pumpApp(tester, 360);
    final items = find.descendant(
      of: find.byType(GlassBottomNav),
      matching: find.byType(InkWell),
    );
    expect(items, findsNWidgets(5));
    for (final element in items.evaluate()) {
      final size = tester.getSize(find.byWidget(element.widget));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    }
  });

  testWidgets('rail items are at least 48x48 at 1024 px', (tester) async {
    await _pumpApp(tester, 1024);
    final railRect = tester.getRect(find.byType(GlassNavRail));
    expect(railRect.width, GlassNavMetrics.railWidth);
    for (final label in _labels) {
      final item = find
          .descendant(
            of: _item(find.byType(GlassNavRail), label),
            matching: find.byType(InkWell),
          )
          .first;
      final size = tester.getSize(item);
      expect(size.height, greaterThanOrEqualTo(48), reason: label);
      expect(size.width, greaterThanOrEqualTo(48), reason: label);
    }
  });

  testWidgets('sidebar items are at least 48 px tall at 1280 px', (
    tester,
  ) async {
    await _pumpApp(tester, 1280);
    expect(
      tester.getRect(find.byType(GlassSideNav)).width,
      GlassNavMetrics.sidebarWidth,
    );
    // One InkWell per destination (the CTA button is not a destination).
    for (final label in _labels) {
      final item = find
          .ancestor(
            of: find.descendant(
              of: find.byType(GlassSideNav),
              matching: find.text(label),
            ),
            matching: find.byType(InkWell),
          )
          .first;
      expect(
        tester.getSize(item).height,
        greaterThanOrEqualTo(48),
        reason: label,
      );
    }
  });

  testWidgets('bottom bar is a centered capsule below 768 px', (tester) async {
    await _pumpApp(tester, 700);
    final surface = find
        .descendant(
          of: find.byType(GlassBottomNav),
          matching: find.byType(GlassSurface),
        )
        .first;
    final rect = tester.getRect(surface);
    expect(rect.width, lessThanOrEqualTo(GlassNavMetrics.bottomBarMaxWidth));
    expect(rect.center.dx, moreOrLessEquals(350, epsilon: 0.5));
  });

  testWidgets('bottom bar collapses while the keyboard is open', (
    tester,
  ) async {
    await _pumpApp(tester, 390, height: 844);
    expect(find.byType(GlassBottomNav), findsOneWidget);

    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(GlassBottomNav), findsNothing);
    expect(find.byType(GlassSideNav), findsNothing);

    tester.view.resetViewInsets();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(GlassBottomNav), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'last item clears the bar with a three-button nav inset (48 px)',
    (tester) async {
      tester.view.padding = const FakeViewPadding(bottom: 48);
      tester.view.viewPadding = const FakeViewPadding(bottom: 48);
      await _pumpApp(tester, 360, height: 780);

      // Visible top edge of the floating capsule.
      final barTop = tester
          .getRect(
            find
                .descendant(
                  of: find.byType(GlassBottomNav),
                  matching: find.byType(GlassSurface),
                )
                .first,
          )
          .top;
      final screenBottom = tester.view.physicalSize.height;

      // Home's list extends under the bar (extendBody); its bottom padding
      // must cover everything from the bar's top edge to the screen bottom.
      final list = tester.widget<ListView>(
        find
            .descendant(
              of: find.byType(HomeScreen, skipOffstage: false),
              matching: find.byType(ListView),
              skipOffstage: false,
            )
            .first,
      );
      final padding = list.padding!.resolve(TextDirection.ltr);
      expect(
        padding.bottom,
        greaterThan(screenBottom - barTop),
        reason:
            'bar covers ${screenBottom - barTop}px, '
            'list clears ${padding.bottom}px',
      );
    },
  );

  testWidgets('crossing breakpoints keeps tab, page state, scroll and form', (
    tester,
  ) async {
    await _pumpApp(tester, 390);

    // Scroll Home.
    final homeScrollable = find
        .descendant(
          of: find.byType(HomeScreen, skipOffstage: false),
          matching: find.byType(Scrollable),
          skipOffstage: false,
        )
        .first;
    final homePosition = tester.state<ScrollableState>(homeScrollable).position;
    homePosition.jumpTo(120);
    await tester.pump();
    expect(homePosition.pixels, 120);

    // Type into the Flights form.
    MainShell.currentIndex.value = 2;
    await tester.pump(const Duration(milliseconds: 300));
    final field = find
        .descendant(
          of: find.byType(FlightSearchScreen, skipOffstage: false),
          matching: find.byType(EditableText),
          skipOffstage: false,
        )
        .first;
    await tester.enterText(field, 'Lisbon');
    await tester.pump();

    // Keep a handle on every page's State.
    final before = <State>[
      tester.state(find.byType(HomeScreen, skipOffstage: false)),
      tester.state(find.byType(ExploreScreen, skipOffstage: false)),
      tester.state(find.byType(FlightSearchScreen, skipOffstage: false)),
      tester.state(find.byType(TripsScreen, skipOffstage: false)),
      tester.state(find.byType(ProfileScreen, skipOffstage: false)),
    ];

    for (final width in const <double>[
      768,
      1024,
      1280,
      1440,
      600,
      360,
      1279,
      767,
      390,
    ]) {
      await _resize(tester, width);
      expect(MainShell.currentIndex.value, 2, reason: 'tab at $width');
      expect(_anyNav(), findsOneWidget, reason: 'one nav at $width');

      final after = <State>[
        tester.state(find.byType(HomeScreen, skipOffstage: false)),
        tester.state(find.byType(ExploreScreen, skipOffstage: false)),
        tester.state(find.byType(FlightSearchScreen, skipOffstage: false)),
        tester.state(find.byType(TripsScreen, skipOffstage: false)),
        tester.state(find.byType(ProfileScreen, skipOffstage: false)),
      ];
      for (var i = 0; i < before.length; i++) {
        expect(
          identical(before[i], after[i]),
          isTrue,
          reason: '${before[i].runtimeType} State recreated at $width',
        );
      }

      final text = tester.widget<EditableText>(
        find
            .descendant(
              of: find.byType(FlightSearchScreen, skipOffstage: false),
              matching: find.byType(EditableText),
              skipOffstage: false,
            )
            .first,
      );
      expect(text.controller.text, 'Lisbon', reason: 'form value at $width');
    }

    // Home's scroll offset survived every layout change.
    MainShell.currentIndex.value = 0;
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byType(HomeScreen, skipOffstage: false),
                  matching: find.byType(Scrollable),
                  skipOffstage: false,
                )
                .first,
          )
          .position
          .pixels,
      120,
    );

    expect(tester.takeException(), isNull);
  });

  for (final lang in const ['en', 'es', 'fr', 'de', 'it', 'pt']) {
    for (final scale in const [1.0, 1.3]) {
      testWidgets(
        'tablet bottom-bar labels are never cut off ($lang, ${scale}x)',
        (tester) async {
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await _pumpApp(tester, 600, height: 900);
          await AppPreferences.instance.setLanguage(lang);
          await tester.pump(const Duration(milliseconds: 300));

          // Every label line is a single-line text in a scale-down
          // FittedBox: it may shrink, but never below 70% (legibility) and
          // never truncate.
          final lines = find.descendant(
            of: find.byType(GlassBottomNav),
            matching: find.byType(FittedBox),
          );
          expect(lines.evaluate().length, greaterThanOrEqualTo(5));
          for (final e in lines.evaluate()) {
            final box = e.renderObject! as RenderBox;
            final paragraph =
                find
                        .descendant(
                          of: find.byWidget(e.widget),
                          matching: find.byType(RichText),
                        )
                        .evaluate()
                        .single
                        .renderObject!
                    as RenderParagraph;
            final text = paragraph.text.toPlainText();
            expect(
              paragraph.didExceedMaxLines,
              isFalse,
              reason: '"$text" truncated ($lang ${scale}x)',
            );
            final shown = box.size.width / paragraph.size.width;
            expect(
              shown,
              greaterThanOrEqualTo(0.7),
              reason:
                  '"$text" shrunk to ${shown.toStringAsFixed(2)} '
                  '($lang ${scale}x)',
            );
          }
          expect(tester.takeException(), isNull);

          await AppPreferences.instance.setLanguage('en');
          await tester.pump(const Duration(milliseconds: 300));
        },
      );
    }
  }
}
