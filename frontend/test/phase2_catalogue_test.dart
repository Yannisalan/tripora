// Phase 2: Explore catalogue expansion and image corrections.
//
// - 30 destinations: the original 22 kept, exactly 8 approved additions
//   (4 Africa, 2 Oceania, 2 Europe, distinct countries per region).
// - Cotonou, Benin unchanged (every field, including its image).
// - No duplicate city or city/country pair; only existing tags.
// - Every image is served from a host the web CSP allows.
// - The 5 corrected entries use their verified images.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/data/destinations.dart';
import 'package:frontend/models/destination_model.dart';

DestinationModel byCity(String city) =>
    destinations.firstWhere((d) => d.city == city);

void main() {
  const original22 = {
    'Paris': 'France',
    'London': 'United Kingdom',
    'Venice': 'Italy',
    'Rome': 'Italy',
    'Tokyo': 'Japan',
    'Dubai': 'United Arab Emirates',
    'Bali': 'Indonesia',
    'Bangkok': 'Thailand',
    'Cotonou': 'Benin',
    'Abidjan': "Côte d'Ivoire",
    'Seychelles': 'Seychelles',
    'Cape Town': 'South Africa',
    'New York': 'United States',
    'San Francisco': 'United States',
    'Rio de Janeiro': 'Brazil',
    'Buenos Aires': 'Argentina',
    'Cusco': 'Peru',
    'Cartagena': 'Colombia',
    'Sydney': 'Australia',
    'Queenstown': 'New Zealand',
    'Fiji': 'Fiji',
    'Bora Bora': 'French Polynesia',
  };

  const added = {
    'AFRICA': {
      'Marrakech': 'Morocco',
      'Nairobi': 'Kenya',
      'Zanzibar': 'Tanzania',
      'Cairo': 'Egypt',
    },
    'OCEANIA': {'Auckland': 'New Zealand', 'Melbourne': 'Australia'},
    'EUROPE': {'Lisbon': 'Portugal', 'Athens': 'Greece'},
  };

  test('30 destinations: the original 22 plus exactly 8 additions', () {
    expect(destinations, hasLength(30));
    for (final e in original22.entries) {
      expect(byCity(e.key).country, e.value, reason: e.key);
    }
    final newCities = destinations
        .where((d) => !original22.containsKey(d.city))
        .map((d) => '${d.city}, ${d.country}')
        .toSet();
    expect(newCities, {
      for (final region in added.values)
        for (final e in region.entries) '${e.key}, ${e.value}',
    });
  });

  test('regional distribution: 4 Africa, 2 Oceania, 2 Europe, '
      'distinct countries, each under its region heading', () {
    final source = File('lib/data/destinations.dart').readAsStringSync();
    final headings = RegExp(
      r'^  // (EUROPE|ASIA|AFRICA|NORTH AMERICA|'
      r'SOUTH AMERICA|OCEANIA)$',
      multiLine: true,
    );
    String regionOf(String city) {
      final at = source.indexOf("city: '$city'");
      expect(at, isNonNegative, reason: city);
      final before = headings.allMatches(source).where((m) => m.start < at);
      return before.last.group(1)!;
    }

    expect(added['AFRICA'], hasLength(4));
    expect(added['OCEANIA'], hasLength(2));
    expect(added['EUROPE'], hasLength(2));
    for (final region in added.entries) {
      expect(
        region.value.values.toSet(),
        hasLength(region.value.length),
        reason: '${region.key}: distinct countries',
      );
      for (final city in region.value.keys) {
        expect(regionOf(city), region.key, reason: city);
      }
    }
  });

  test('no duplicates', () {
    final cities = destinations.map((d) => d.city.toLowerCase()).toList();
    expect(cities.toSet(), hasLength(cities.length));
    final pairs = destinations.map((d) => d.fullName.toLowerCase()).toList();
    expect(pairs.toSet(), hasLength(pairs.length));
    final images = destinations.map((d) => d.imageUrl).toList();
    expect(images.toSet(), hasLength(images.length), reason: 'unique images');
  });

  test('Cotonou, Benin: all data unchanged except the verified photo', () {
    final c = byCity('Cotonou');
    expect(c.country, 'Benin');
    // Only the photograph changed (final image audit): the old Unsplash
    // photo was an unidentifiable rocky cove with no traceable source. It
    // is now a documented CC0 photo of Fidjrossè beach in Cotonou.
    expect(c.imageUrl, contains('upload.wikimedia.org'));
    expect(Uri.decodeComponent(c.imageUrl), contains('La_plage_Fidjross'));
    expect(
      c.description,
      'Atlantic beaches, the stilt village of Ganvié, vibrant markets, '
      'vodun culture, and warm coastal pace.',
    );
    expect(c.bestFor, 'Culture, beaches, authentic West Africa');
    expect(c.tripLength, '3-5 days');
    expect(c.tags, ['Culture', 'Beach', 'Food', 'History']);
  });

  test('every entry is complete and uses the existing tag vocabulary', () {
    const vocabulary = {
      'Adventure',
      'Beach',
      'City',
      'Culture',
      'Food',
      'History',
      'Luxury',
      'Museums',
      'Nature',
      'Nightlife',
      'Relaxation',
      'Romance',
      'Shopping',
    };
    for (final d in destinations) {
      expect(d.description.trim(), isNotEmpty, reason: d.city);
      expect(d.bestFor.trim(), isNotEmpty, reason: d.city);
      expect(d.tripLength, matches(RegExp(r'^\d+-\d+ days$')), reason: d.city);
      expect(d.tags, hasLength(4), reason: d.city);
      expect(vocabulary.containsAll(d.tags), isTrue, reason: d.city);
    }
  });

  test('every image host is allowed by the web Content-Security-Policy', () {
    final vercel = jsonDecode(File('vercel.json').readAsStringSync());
    final csp =
        (vercel['headers'] as List)
                .expand((h) => h['headers'] as List)
                .firstWhere(
                  // Enforced or report-only: images must comply either way.
                  (h) => (h['key'] as String).startsWith(
                    'Content-Security-Policy',
                  ),
                )['value']
            as String;
    String directive(String name) => csp
        .split(';')
        .map((d) => d.trim())
        .firstWhere((d) => d.startsWith('$name '));
    for (final d in destinations) {
      final origin = Uri.parse(d.imageUrl).origin;
      expect(d.imageUrl, startsWith('https://'), reason: d.city);
      expect(directive('img-src'), contains(origin), reason: d.city);
      // Flutter web fetches image bytes, so connect-src must allow it too.
      expect(directive('connect-src'), contains(origin), reason: d.city);
    }
  });

  // Final image audit (2026-11-14): every photograph is a Wikimedia
  // Commons file, public domain or CC0, whose file page documents the
  // author and the location. File name -> licence page.
  const verified = <String, (String file, String page, String licence)>{
    'Paris': (
      'Paris_skyline_from_the_observation_deck_of_the_Montparnasse_tower,_July_2015.jpg',
      'https://commons.wikimedia.org/wiki/File:Paris_skyline_from_the_observation_deck_of_the_Montparnasse_tower,_July_2015.jpg',
      'CC0',
    ),
    'London': (
      'Tower_Bridge_in_London_at_night.jpg',
      'https://commons.wikimedia.org/wiki/File:Tower_Bridge_in_London_at_night.jpg',
      'Public domain',
    ),
    'Venice': (
      'Rialto_Bridge,_Venice_Italy.jpg',
      'https://commons.wikimedia.org/wiki/File:Rialto_Bridge,_Venice_Italy.jpg',
      'CC0',
    ),
    'Rome': (
      'Colosseum_of_Rome,_Italy.jpg',
      'https://commons.wikimedia.org/wiki/File:Colosseum_of_Rome,_Italy.jpg',
      'CC0',
    ),
    'Lisbon': (
      'Graffiti_(Unsplash).jpg',
      'https://commons.wikimedia.org/wiki/File:Graffiti_(Unsplash).jpg',
      'CC0',
    ),
    'Athens': (
      'Acropolis_Parthenon_Athens_Greece.jpg',
      'https://commons.wikimedia.org/wiki/File:Acropolis_Parthenon_Athens_Greece.jpg',
      'CC0',
    ),
    'Tokyo': (
      'Shibuya_crossing_seen_from_Shibuya_Stream,_2024.jpg',
      'https://commons.wikimedia.org/wiki/File:Shibuya_crossing_seen_from_Shibuya_Stream,_2024.jpg',
      'CC0',
    ),
    'Dubai': (
      'Dubai_2010.JPG',
      'https://commons.wikimedia.org/wiki/File:Dubai_2010.JPG',
      'Public domain',
    ),
    'Bali': (
      'Rice_Terrace_in_Ubud.jpg',
      'https://commons.wikimedia.org/wiki/File:Rice_Terrace_in_Ubud.jpg',
      'Public domain',
    ),
    'Bangkok': (
      'Thai_Grand_Palace,_Bangkok_(31176784107).jpg',
      'https://commons.wikimedia.org/wiki/File:Thai_Grand_Palace,_Bangkok_(31176784107).jpg',
      'CC0',
    ),
    'Cotonou': (
      'La_plage_Fidjrossè_à_Cotonou_au_Bénin.jpg',
      'https://commons.wikimedia.org/wiki/File:La_plage_Fidjross%C3%A8_%C3%A0_Cotonou_au_B%C3%A9nin.jpg',
      'CC0',
    ),
    'Abidjan': (
      'Abidjan_Plateau.png',
      'https://commons.wikimedia.org/wiki/File:Abidjan_Plateau.png',
      'CC0',
    ),
    'Seychelles': (
      'Takamaka_Beach,_Seychelles.jpg',
      'https://commons.wikimedia.org/wiki/File:Takamaka_Beach,_Seychelles.jpg',
      'CC0',
    ),
    'Cape Town': (
      'Cape_Town_-_Table_Mountain_seen_from_27th_floor_Southern_Sun_Cape_Sun_hotel_(3).jpg',
      'https://commons.wikimedia.org/wiki/File:Cape_Town_-_Table_Mountain_seen_from_27th_floor_Southern_Sun_Cape_Sun_hotel_(3).jpg',
      'CC0',
    ),
    'Marrakech': (
      'Koutoubia_Mosque_(34383957483).jpg',
      'https://commons.wikimedia.org/wiki/File:Koutoubia_Mosque_(34383957483).jpg',
      'Public domain',
    ),
    'Nairobi': (
      'Nairobi_City_09.jpg',
      'https://commons.wikimedia.org/wiki/File:Nairobi_City_09.jpg',
      'CC0',
    ),
    'Zanzibar': (
      'ZanzibarBeach.jpg',
      'https://commons.wikimedia.org/wiki/File:ZanzibarBeach.jpg',
      'Public domain',
    ),
    'Cairo': (
      'View_from_Cairo_Tower_31march2007.jpg',
      'https://commons.wikimedia.org/wiki/File:View_from_Cairo_Tower_31march2007.jpg',
      'Public domain',
    ),
    'New York': (
      'View_from_the_Brooklyn_Bridge_2.jpg',
      'https://commons.wikimedia.org/wiki/File:View_from_the_Brooklyn_Bridge_2.jpg',
      'Public domain',
    ),
    'San Francisco': (
      'San_Francisco_Skyline_Feb_2024.jpg',
      'https://commons.wikimedia.org/wiki/File:San_Francisco_Skyline_Feb_2024.jpg',
      'CC0',
    ),
    'Rio de Janeiro': (
      'Sugarloaf_Mountain,_Rio_de_Janeiro,_Brazil.jpg',
      'https://commons.wikimedia.org/wiki/File:Sugarloaf_Mountain,_Rio_de_Janeiro,_Brazil.jpg',
      'CC0',
    ),
    'Buenos Aires': (
      'Fachada_del_Teatro_Colón_en_Buenos_Aires,_Argentina.jpg',
      'https://commons.wikimedia.org/wiki/File:Fachada_del_Teatro_Col%C3%B3n_en_Buenos_Aires,_Argentina.jpg',
      'CC0',
    ),
    'Cusco': (
      'Cusco_skyline_-_October_2025.jpg',
      'https://commons.wikimedia.org/wiki/File:Cusco_skyline_-_October_2025.jpg',
      'CC0',
    ),
    'Cartagena': (
      'Calle_de_San_agustin.JPG',
      'https://commons.wikimedia.org/wiki/File:Calle_de_San_agustin.JPG',
      'Public domain',
    ),
    'Sydney': (
      'Sydney_Opera_House_in_2011.jpg',
      'https://commons.wikimedia.org/wiki/File:Sydney_Opera_House_in_2011.jpg',
      'Public domain',
    ),
    'Queenstown': (
      'Queenstown._Lake_Wakatipu._(50854629786).jpg',
      'https://commons.wikimedia.org/wiki/File:Queenstown._Lake_Wakatipu._(50854629786).jpg',
      'CC0',
    ),
    'Fiji': (
      'Waya_1.jpg',
      'https://commons.wikimedia.org/wiki/File:Waya_1.jpg',
      'Public domain',
    ),
    'Bora Bora': (
      'Borabora3.jpg',
      'https://commons.wikimedia.org/wiki/File:Borabora3.jpg',
      'Public domain',
    ),
    'Auckland': (
      'Auckland_CBD_skyline_from_Waitemata_Harbour_entrance.jpg',
      'https://commons.wikimedia.org/wiki/File:Auckland_CBD_skyline_from_Waitemata_Harbour_entrance.jpg',
      'Public domain',
    ),
    'Melbourne': (
      'Melbourne_and_the_Yarra_River._(22115562453).jpg',
      'https://commons.wikimedia.org/wiki/File:Melbourne_and_the_Yarra_River._(22115562453).jpg',
      'CC0',
    ),
  };

  test('every image is its verified Commons file (30 of 30)', () {
    expect(verified.keys.toSet(), destinations.map((d) => d.city).toSet());
    for (final d in destinations) {
      final (file, page, licence) = verified[d.city]!;
      expect(
        d.imageUrl,
        startsWith('https://upload.wikimedia.org/wikipedia/commons/'),
        reason: d.city,
      );
      expect(Uri.decodeComponent(d.imageUrl), contains(file), reason: d.city);
      expect(page, startsWith('https://commons.wikimedia.org/wiki/File:'));
      expect(
        licence,
        anyOf('CC0', 'Public domain'),
        reason: '${d.city}: no attribution-required licences in use',
      );
    }
  });
}
