import '../models/destination_model.dart';

// Image sources: every photograph is a Wikimedia Commons file that is
// public domain or CC0 (no attribution required, commercial use allowed),
// with its author, description and location documented on its Commons file
// page. Served from upload.wikimedia.org, which the web Content-Security-
// Policy allows (frontend/vercel.json). Verified 2026-11-14; see
// test/phase2_catalogue_test.dart for the file-page reference of each.

const List<DestinationModel> destinations = [
  // --------------------------------------------------------------
  // EUROPE
  // --------------------------------------------------------------
  DestinationModel(
    imageUrl: 'https://upload.wikimedia.org/wikipedia/commons/thumb/f/f6/Paris_skyline_from_the_observation_deck_of_the_Montparnasse_tower%2C_July_2015.jpg/960px-Paris_skyline_from_the_observation_deck_of_the_Montparnasse_tower%2C_July_2015.jpg',
    city: 'Paris',
    country: 'France',
    description:
        'Art museums, walkable neighborhoods, landmark views, markets, and classic cafe culture.',
    bestFor: 'Culture, food, first-time Europe',
    tripLength: '4-6 days',
    tags: ['Culture', 'Food', 'Museums', 'Romance'],
  ),
  DestinationModel(
    imageUrl: 'https://upload.wikimedia.org/wikipedia/commons/thumb/c/c9/Tower_Bridge_in_London_at_night.jpg/960px-Tower_Bridge_in_London_at_night.jpg',
    city: 'London',
    country: 'United Kingdom',
    description:
        'Historic sights, theater, parks, pubs, markets, galleries, and easy day trips.',
    bestFor: 'History, theater, families',
    tripLength: '4-7 days',
    tags: ['Culture', 'Museums', 'Food', 'History'],
  ),
  DestinationModel(
    imageUrl: 'https://upload.wikimedia.org/wikipedia/commons/thumb/5/55/Rialto_Bridge%2C_Venice_Italy.jpg/960px-Rialto_Bridge%2C_Venice_Italy.jpg',
    city: 'Venice',
    country: 'Italy',
    description:
        'Canals, quiet side streets, lagoon islands, churches, seafood, and atmospheric evenings.',
    bestFor: 'Romance, art, slow wandering',
    tripLength: '2-4 days',
    tags: ['Culture', 'Food', 'Romance', 'History'],
  ),
  DestinationModel(
    imageUrl: 'https://upload.wikimedia.org/wikipedia/commons/thumb/5/5b/Colosseum_of_Rome%2C_Italy.jpg/960px-Colosseum_of_Rome%2C_Italy.jpg',
    city: 'Rome',
    country: 'Italy',
    description:
        'Ancient ruins, basilicas, trattorias, piazzas, and layers of history on every corner.',
    bestFor: 'History, food, architecture',
    tripLength: '3-5 days',
    tags: ['History', 'Culture', 'Food', 'Museums'],
  ),
  DestinationModel(
    imageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/thumb/f/f7/Graffiti_%28Unsplash%29.jpg/960px-Graffiti_%28Unsplash%29.jpg',
    city: 'Lisbon',
    country: 'Portugal',
    description:
        'Hilltop viewpoints, vintage trams, tiled facades, riverside Belém, and custard tarts by the Tagus.',
    bestFor: 'Food, culture, city breaks',
    tripLength: '3-5 days',
    tags: ['Culture', 'Food', 'History', 'City'],
  ),
  DestinationModel(
    imageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/thumb/2/25/Acropolis_Parthenon_Athens_Greece.jpg/960px-Acropolis_Parthenon_Athens_Greece.jpg',
    city: 'Athens',
    country: 'Greece',
    description:
        'The Acropolis and ancient agora, neighborhood tavernas, rooftop views, and easy island ferries.',
    bestFor: 'History, food, island hopping',
    tripLength: '3-4 days',
    tags: ['History', 'Museums', 'Food', 'Culture'],
  ),
  // --------------------------------------------------------------
  // ASIA
  // --------------------------------------------------------------
  DestinationModel(
    imageUrl: 'https://upload.wikimedia.org/wikipedia/commons/thumb/5/5d/Shibuya_crossing_seen_from_Shibuya_Stream%2C_2024.jpg/960px-Shibuya_crossing_seen_from_Shibuya_Stream%2C_2024.jpg',
    city: 'Tokyo',
    country: 'Japan',
    description:
        'A high-energy mix of temples, design, shopping districts, gardens, and exceptional food.',
    bestFor: 'Food, city discovery, pop culture',
    tripLength: '5-8 days',
    tags: ['Food', 'Shopping', 'Culture', 'Nightlife'],
  ),
  DestinationModel(
    imageUrl: 'https://upload.wikimedia.org/wikipedia/commons/thumb/e/e1/Dubai_2010.JPG/960px-Dubai_2010.JPG',
    city: 'Dubai',
    country: 'United Arab Emirates',
    description:
        'Architecture, beaches, desert experiences, family attractions, and polished luxury escapes.',
    bestFor: 'Luxury, families, short breaks',
    tripLength: '3-5 days',
    tags: ['Luxury', 'Shopping', 'Adventure', 'Beach'],
  ),
  DestinationModel(
    imageUrl: 'https://upload.wikimedia.org/wikipedia/commons/thumb/a/ac/Rice_Terrace_in_Ubud.jpg/960px-Rice_Terrace_in_Ubud.jpg',
    city: 'Bali',
    country: 'Indonesia',
    description:
        'Beaches, temples, rice terraces, wellness stays, waterfalls, and relaxed island pacing.',
    bestFor: 'Nature, relaxation, couples',
    tripLength: '6-9 days',
    tags: ['Nature', 'Relaxation', 'Adventure', 'Culture'],
  ),
  DestinationModel(
    imageUrl: 'https://upload.wikimedia.org/wikipedia/commons/thumb/8/88/Thai_Grand_Palace%2C_Bangkok_%2831176784107%29.jpg/960px-Thai_Grand_Palace%2C_Bangkok_%2831176784107%29.jpg',
    city: 'Bangkok',
    country: 'Thailand',
    description:
        'Golden temples, neon streets, river boats, street food, and grand palace complexes.',
    bestFor: 'Food, culture, budget travel',
    tripLength: '3-5 days',
    tags: ['Food', 'Culture', 'Shopping', 'Nightlife'],
  ),
  // --------------------------------------------------------------
  // AFRICA
  // --------------------------------------------------------------
  DestinationModel(
    imageUrl: 'https://upload.wikimedia.org/wikipedia/commons/thumb/5/50/La_plage_Fidjross%C3%A8_%C3%A0_Cotonou_au_B%C3%A9nin.jpg/960px-La_plage_Fidjross%C3%A8_%C3%A0_Cotonou_au_B%C3%A9nin.jpg',
    city: 'Cotonou',
    country: 'Benin',
    description:
        'Atlantic beaches, the stilt village of Ganvié, vibrant markets, vodun culture, and warm coastal pace.',
    bestFor: 'Culture, beaches, authentic West Africa',
    tripLength: '3-5 days',
    tags: ['Culture', 'Beach', 'Food', 'History'],
  ),
  DestinationModel(
    imageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/thumb/5/57/Abidjan_Plateau.png/960px-Abidjan_Plateau.png',
    city: 'Abidjan',
    country: 'Côte d\'Ivoire',
    description:
        'A modern lagoon city with a lively music scene, buzzing markets, la Médina-style cuisine, and chic waterfront vibes.',
    bestFor: 'Food, nightlife, city discovery',
    tripLength: '3-5 days',
    tags: ['Culture', 'Food', 'Nightlife', 'City'],
  ),
  DestinationModel(
    imageUrl: 'https://upload.wikimedia.org/wikipedia/commons/thumb/8/82/Takamaka_Beach%2C_Seychelles.jpg/960px-Takamaka_Beach%2C_Seychelles.jpg',
    city: 'Seychelles',
    country: 'Seychelles',
    description:
        'Granite boulders, powder-white beaches, turquoise shallows, and rare island nature on the Indian Ocean.',
    bestFor: 'Honeymoons, relaxation, snorkeling',
    tripLength: '6-9 days',
    tags: ['Beach', 'Nature', 'Relaxation', 'Adventure'],
  ),
  DestinationModel(
    imageUrl: 'https://upload.wikimedia.org/wikipedia/commons/thumb/e/e1/Cape_Town_-_Table_Mountain_seen_from_27th_floor_Southern_Sun_Cape_Sun_hotel_%283%29.jpg/960px-Cape_Town_-_Table_Mountain_seen_from_27th_floor_Southern_Sun_Cape_Sun_hotel_%283%29.jpg',
    city: 'Cape Town',
    country: 'South Africa',
    description:
        'Table Mountain, dramatic coastlines, vineyards, safaris nearby, and a buzzing creative scene.',
    bestFor: 'Nature, wine, adventure',
    tripLength: '4-6 days',
    tags: ['Nature', 'Food', 'Adventure', 'Beach'],
  ),
  DestinationModel(
    imageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/thumb/4/46/Koutoubia_Mosque_%2834383957483%29.jpg/960px-Koutoubia_Mosque_%2834383957483%29.jpg',
    city: 'Marrakech',
    country: 'Morocco',
    description:
        'Red-walled medina, the Jemaa el-Fnaa square, souks, riads, palaces, and gardens near the Atlas.',
    bestFor: 'Culture, food, shopping',
    tripLength: '3-5 days',
    tags: ['Culture', 'Food', 'Shopping', 'History'],
  ),
  DestinationModel(
    imageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/thumb/d/d8/Nairobi_City_09.jpg/960px-Nairobi_City_09.jpg',
    city: 'Nairobi',
    country: 'Kenya',
    description:
        'A lively capital with a national park on its doorstep, giraffe and elephant centers, markets, and a growing food scene.',
    bestFor: 'Wildlife, city discovery, safaris',
    tripLength: '3-4 days',
    tags: ['Nature', 'Adventure', 'Culture', 'City'],
  ),
  DestinationModel(
    imageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/thumb/3/39/ZanzibarBeach.jpg/960px-ZanzibarBeach.jpg',
    city: 'Zanzibar',
    country: 'Tanzania',
    description:
        'Stone Town alleys, spice farms, dhow sailing, and white-sand beaches on the Indian Ocean.',
    bestFor: 'Beaches, history, couples',
    tripLength: '5-7 days',
    tags: ['Beach', 'History', 'Culture', 'Relaxation'],
  ),
  DestinationModel(
    imageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/thumb/b/b2/View_from_Cairo_Tower_31march2007.jpg/960px-View_from_Cairo_Tower_31march2007.jpg',
    city: 'Cairo',
    country: 'Egypt',
    description:
        'The Giza pyramids, the Egyptian Museum, Islamic Cairo mosques and markets, and evenings on the Nile.',
    bestFor: 'History, museums, first-time Egypt',
    tripLength: '3-5 days',
    tags: ['History', 'Museums', 'Culture', 'Food'],
  ),
  // --------------------------------------------------------------
  // NORTH AMERICA
  // --------------------------------------------------------------
  DestinationModel(
    imageUrl: 'https://upload.wikimedia.org/wikipedia/commons/thumb/6/6e/View_from_the_Brooklyn_Bridge_2.jpg/960px-View_from_the_Brooklyn_Bridge_2.jpg',
    city: 'New York',
    country: 'United States',
    description:
        'Iconic skyline, world-class museums, Broadway, neighborhoods, and 24-hour energy.',
    bestFor: 'City breaks, culture, shopping',
    tripLength: '4-7 days',
    tags: ['Culture', 'Museums', 'Food', 'Nightlife'],
  ),
  DestinationModel(
    imageUrl: 'https://upload.wikimedia.org/wikipedia/commons/thumb/e/ed/San_Francisco_Skyline_Feb_2024.jpg/960px-San_Francisco_Skyline_Feb_2024.jpg',
    city: 'San Francisco',
    country: 'United States',
    description:
        'Golden Gate views, cable cars, foggy hills, seafood piers, and bay-side hiking.',
    bestFor: 'City breaks, nature nearby, food',
    tripLength: '3-5 days',
    tags: ['City', 'Nature', 'Food', 'Culture'],
  ),
  // --------------------------------------------------------------
  // SOUTH AMERICA
  // --------------------------------------------------------------
  DestinationModel(
    imageUrl: 'https://upload.wikimedia.org/wikipedia/commons/thumb/0/0d/Sugarloaf_Mountain%2C_Rio_de_Janeiro%2C_Brazil.jpg/960px-Sugarloaf_Mountain%2C_Rio_de_Janeiro%2C_Brazil.jpg',
    city: 'Rio de Janeiro',
    country: 'Brazil',
    description:
        'Sugarloaf and Corcovado views, golden beaches, samba, rainforest, and carnival energy.',
    bestFor: 'Beaches, nightlife, nature',
    tripLength: '4-7 days',
    tags: ['Beach', 'Nature', 'Nightlife', 'Adventure'],
  ),
  DestinationModel(
    imageUrl: 'https://upload.wikimedia.org/wikipedia/commons/thumb/8/82/Fachada_del_Teatro_Col%C3%B3n_en_Buenos_Aires%2C_Argentina.jpg/960px-Fachada_del_Teatro_Col%C3%B3n_en_Buenos_Aires%2C_Argentina.jpg',
    city: 'Buenos Aires',
    country: 'Argentina',
    description:
        'Tango streets, Parisian boulevards, steak houses, bookshops, and café culture.',
    bestFor: 'Culture, food, nightlife',
    tripLength: '3-5 days',
    tags: ['Culture', 'Food', 'Nightlife', 'Shopping'],
  ),
  DestinationModel(
    imageUrl: 'https://upload.wikimedia.org/wikipedia/commons/thumb/d/d2/Cusco_skyline_-_October_2025.jpg/960px-Cusco_skyline_-_October_2025.jpg',
    city: 'Cusco',
    country: 'Peru',
    description:
        'Inca stonework, high-altitude plazas, markets, and the gateway to Machu Picchu.',
    bestFor: 'History, adventure, culture',
    tripLength: '4-6 days',
    tags: ['History', 'Adventure', 'Culture', 'Nature'],
  ),
  DestinationModel(
    imageUrl: 'https://upload.wikimedia.org/wikipedia/commons/thumb/8/84/Calle_de_San_agustin.JPG/960px-Calle_de_San_agustin.JPG',
    city: 'Cartagena',
    country: 'Colombia',
    description:
        'Walled Old Town, colonial balconies, Caribbean beaches, and golden-hour streets.',
    bestFor: 'History, beaches, couples',
    tripLength: '3-5 days',
    tags: ['History', 'Beach', 'Culture', 'Romance'],
  ),
  // --------------------------------------------------------------
  // OCEANIA
  // --------------------------------------------------------------
  DestinationModel(
    imageUrl: 'https://upload.wikimedia.org/wikipedia/commons/thumb/e/ef/Sydney_Opera_House_in_2011.jpg/960px-Sydney_Opera_House_in_2011.jpg',
    city: 'Sydney',
    country: 'Australia',
    description:
        'Harbor icons, surf beaches, coastal walks, markets, and a laid-back outdoor life.',
    bestFor: 'City breaks, beaches, families',
    tripLength: '4-6 days',
    tags: ['Beach', 'City', 'Nature', 'Food'],
  ),
  DestinationModel(
    imageUrl: 'https://upload.wikimedia.org/wikipedia/commons/thumb/3/36/Queenstown._Lake_Wakatipu._%2850854629786%29.jpg/960px-Queenstown._Lake_Wakatipu._%2850854629786%29.jpg',
    city: 'Queenstown',
    country: 'New Zealand',
    description:
        'Alpine lake scenery, bungee and jet-boat thrills, vineyards, and film-set landscapes.',
    bestFor: 'Adventure, nature, couples',
    tripLength: '4-6 days',
    tags: ['Adventure', 'Nature', 'Relaxation', 'Food'],
  ),
  DestinationModel(
    imageUrl: 'https://upload.wikimedia.org/wikipedia/commons/thumb/4/4f/Waya_1.jpg/960px-Waya_1.jpg',
    city: 'Fiji',
    country: 'Fiji',
    description:
        'Blue lagoons, coral reefs, friendly villages, and over-water bungalows in the South Pacific.',
    bestFor: 'Honeymoons, diving, relaxation',
    tripLength: '6-9 days',
    tags: ['Beach', 'Relaxation', 'Nature', 'Adventure'],
  ),
  DestinationModel(
    imageUrl: 'https://upload.wikimedia.org/wikipedia/commons/thumb/6/6f/Borabora3.jpg/960px-Borabora3.jpg',
    city: 'Bora Bora',
    country: 'French Polynesia',
    description:
        'Emerald lagoon, dormant volcano, over-water villas, and postcard island beauty.',
    bestFor: 'Honeymoons, luxury, snorkeling',
    tripLength: '5-7 days',
    tags: ['Beach', 'Luxury', 'Relaxation', 'Romance'],
  ),
  DestinationModel(
    imageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/thumb/3/37/Auckland_CBD_skyline_from_Waitemata_Harbour_entrance.jpg/960px-Auckland_CBD_skyline_from_Waitemata_Harbour_entrance.jpg',
    city: 'Auckland',
    country: 'New Zealand',
    description:
        'Harbor city of sailboats, volcanic cones, island day trips, beaches, and nearby vineyards.',
    bestFor: 'City breaks, nature nearby, families',
    tripLength: '3-5 days',
    tags: ['City', 'Nature', 'Food', 'Adventure'],
  ),
  DestinationModel(
    imageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/thumb/a/a4/Melbourne_and_the_Yarra_River._%2822115562453%29.jpg/960px-Melbourne_and_the_Yarra_River._%2822115562453%29.jpg',
    city: 'Melbourne',
    country: 'Australia',
    description:
        'Laneway cafes, street art, galleries, sport, and a riverside skyline, with coastal drives nearby.',
    bestFor: 'Food, culture, city breaks',
    tripLength: '4-6 days',
    tags: ['Food', 'Culture', 'City', 'Museums'],
  ),
];
