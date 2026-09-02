import '../models/destination_model.dart';

const List<DestinationModel> destinations = [
  // --------------------------------------------------------------
  // EUROPE
  // --------------------------------------------------------------
  DestinationModel(
    imageUrl: 'https://images.unsplash.com/photo-1502602898657-3e91760cbb34',
    city: 'Paris',
    country: 'France',
    description:
        'Art museums, walkable neighborhoods, landmark views, markets, and classic cafe culture.',
    bestFor: 'Culture, food, first-time Europe',
    tripLength: '4-6 days',
    tags: ['Culture', 'Food', 'Museums', 'Romance'],
  ),
  DestinationModel(
    imageUrl: 'https://images.unsplash.com/photo-1533929736458-ca588d08c8be',
    city: 'London',
    country: 'United Kingdom',
    description:
        'Historic sights, theater, parks, pubs, markets, galleries, and easy day trips.',
    bestFor: 'History, theater, families',
    tripLength: '4-7 days',
    tags: ['Culture', 'Museums', 'Food', 'History'],
  ),
  DestinationModel(
    imageUrl: 'https://images.unsplash.com/photo-1523906834658-6e24ef2386f9',
    city: 'Venice',
    country: 'Italy',
    description:
        'Canals, quiet side streets, lagoon islands, churches, seafood, and atmospheric evenings.',
    bestFor: 'Romance, art, slow wandering',
    tripLength: '2-4 days',
    tags: ['Culture', 'Food', 'Romance', 'History'],
  ),
  DestinationModel(
    imageUrl: 'https://images.unsplash.com/photo-1552832230-c0197dd311b5',
    city: 'Rome',
    country: 'Italy',
    description:
        'Ancient ruins, basilicas, trattorias, piazzas, and layers of history on every corner.',
    bestFor: 'History, food, architecture',
    tripLength: '3-5 days',
    tags: ['History', 'Culture', 'Food', 'Museums'],
  ),
  // --------------------------------------------------------------
  // ASIA
  // --------------------------------------------------------------
  DestinationModel(
    imageUrl: 'https://images.unsplash.com/photo-1540959733332-eab4deabeeaf',
    city: 'Tokyo',
    country: 'Japan',
    description:
        'A high-energy mix of temples, design, shopping districts, gardens, and exceptional food.',
    bestFor: 'Food, city discovery, pop culture',
    tripLength: '5-8 days',
    tags: ['Food', 'Shopping', 'Culture', 'Nightlife'],
  ),
  DestinationModel(
    imageUrl: 'https://images.unsplash.com/photo-1512453979798-5ea266f8880c',
    city: 'Dubai',
    country: 'United Arab Emirates',
    description:
        'Architecture, beaches, desert experiences, family attractions, and polished luxury escapes.',
    bestFor: 'Luxury, families, short breaks',
    tripLength: '3-5 days',
    tags: ['Luxury', 'Shopping', 'Adventure', 'Beach'],
  ),
  DestinationModel(
    imageUrl: 'https://images.unsplash.com/photo-1537996194471-e657df975ab4',
    city: 'Bali',
    country: 'Indonesia',
    description:
        'Beaches, temples, rice terraces, wellness stays, waterfalls, and relaxed island pacing.',
    bestFor: 'Nature, relaxation, couples',
    tripLength: '6-9 days',
    tags: ['Nature', 'Relaxation', 'Adventure', 'Culture'],
  ),
  DestinationModel(
    imageUrl: 'https://images.unsplash.com/photo-1563492065599-3520f775eeed',
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
    imageUrl:
        'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcQe0isWFKceZEmYNzyrsWXShp8me_WAPq_tm_aloGRJ489yvbQ7cofoEcs&s=10',
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
        'https://upload.wikimedia.org/wikipedia/commons/5/57/Abidjan_Plateau.png',
    city: 'Abidjan',
    country: 'Côte d\'Ivoire',
    description:
        'A modern lagoon city with a lively music scene, buzzing markets, la Médina-style cuisine, and chic waterfront vibes.',
    bestFor: 'Food, nightlife, city discovery',
    tripLength: '3-5 days',
    tags: ['Culture', 'Food', 'Nightlife', 'City'],
  ),
  DestinationModel(
    imageUrl: 'https://images.unsplash.com/photo-1636110026885-8950fbdd3e74',
    city: 'Seychelles',
    country: 'Seychelles',
    description:
        'Granite boulders, powder-white beaches, turquoise shallows, and rare island nature on the Indian Ocean.',
    bestFor: 'Honeymoons, relaxation, snorkeling',
    tripLength: '6-9 days',
    tags: ['Beach', 'Nature', 'Relaxation', 'Adventure'],
  ),
  DestinationModel(
    imageUrl: 'https://images.unsplash.com/photo-1580060839134-75a5edca2e99',
    city: 'Cape Town',
    country: 'South Africa',
    description:
        'Table Mountain, dramatic coastlines, vineyards, safaris nearby, and a buzzing creative scene.',
    bestFor: 'Nature, wine, adventure',
    tripLength: '4-6 days',
    tags: ['Nature', 'Food', 'Adventure', 'Beach'],
  ),
  // --------------------------------------------------------------
  // NORTH AMERICA
  // --------------------------------------------------------------
  DestinationModel(
    imageUrl: 'https://images.unsplash.com/photo-1496442226666-8d4d0e62e6e9',
    city: 'New York',
    country: 'United States',
    description:
        'Iconic skyline, world-class museums, Broadway, neighborhoods, and 24-hour energy.',
    bestFor: 'City breaks, culture, shopping',
    tripLength: '4-7 days',
    tags: ['Culture', 'Museums', 'Food', 'Nightlife'],
  ),
  DestinationModel(
    imageUrl: 'https://images.unsplash.com/photo-1572536147248-ac59a8abfa4b',
    city: 'Cancún',
    country: 'Mexico',
    description:
        'Caribbean beaches, Mayan ruins, cenotes, coral reefs, and all-inclusive ease.',
    bestFor: 'Beaches, families, nightlife',
    tripLength: '4-7 days',
    tags: ['Beach', 'History', 'Adventure', 'Relaxation'],
  ),
  DestinationModel(
    imageUrl: 'https://images.unsplash.com/photo-1558002038-1055907df827',
    city: 'Toronto',
    country: 'Canada',
    description:
        'Lakefront skyline, multicultural food, galleries, islands, and nearby Niagara Falls.',
    bestFor: 'City breaks, food, families',
    tripLength: '3-5 days',
    tags: ['Food', 'Culture', 'City', 'Museums'],
  ),
  DestinationModel(
    imageUrl: 'https://images.unsplash.com/photo-1449034446853-66c86144b0ad',
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
    imageUrl: 'https://images.unsplash.com/photo-1483729558449-99ef09a8c325',
    city: 'Rio de Janeiro',
    country: 'Brazil',
    description:
        'Sugarloaf and Corcovado views, golden beaches, samba, rainforest, and carnival energy.',
    bestFor: 'Beaches, nightlife, nature',
    tripLength: '4-7 days',
    tags: ['Beach', 'Nature', 'Nightlife', 'Adventure'],
  ),
  DestinationModel(
    imageUrl: 'https://images.unsplash.com/photo-1518391846015-55a9cc003b25',
    city: 'Buenos Aires',
    country: 'Argentina',
    description:
        'Tango streets, Parisian boulevards, steak houses, bookshops, and café culture.',
    bestFor: 'Culture, food, nightlife',
    tripLength: '3-5 days',
    tags: ['Culture', 'Food', 'Nightlife', 'Shopping'],
  ),
  DestinationModel(
    imageUrl: 'https://images.unsplash.com/photo-1526392060635-9d6019884377',
    city: 'Cusco',
    country: 'Peru',
    description:
        'Inca stonework, high-altitude plazas, markets, and the gateway to Machu Picchu.',
    bestFor: 'History, adventure, culture',
    tripLength: '4-6 days',
    tags: ['History', 'Adventure', 'Culture', 'Nature'],
  ),
  DestinationModel(
    imageUrl: 'https://images.unsplash.com/photo-1596422846543-75c6fc197f07',
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
    imageUrl: 'https://images.unsplash.com/photo-1508739773434-c26b3d09e071',
    city: 'Sydney',
    country: 'Australia',
    description:
        'Harbor icons, surf beaches, coastal walks, markets, and a laid-back outdoor life.',
    bestFor: 'City breaks, beaches, families',
    tripLength: '4-6 days',
    tags: ['Beach', 'City', 'Nature', 'Food'],
  ),
  DestinationModel(
    imageUrl: 'https://images.unsplash.com/photo-1546971587-02375cbbdade',
    city: 'Queenstown',
    country: 'New Zealand',
    description:
        'Alpine lake scenery, bungee and jet-boat thrills, vineyards, and film-set landscapes.',
    bestFor: 'Adventure, nature, couples',
    tripLength: '4-6 days',
    tags: ['Adventure', 'Nature', 'Relaxation', 'Food'],
  ),
  DestinationModel(
    imageUrl: 'https://images.unsplash.com/photo-1573790387438-4da905039392',
    city: 'Fiji',
    country: 'Fiji',
    description:
        'Blue lagoons, coral reefs, friendly villages, and over-water bungalows in the South Pacific.',
    bestFor: 'Honeymoons, diving, relaxation',
    tripLength: '6-9 days',
    tags: ['Beach', 'Relaxation', 'Nature', 'Adventure'],
  ),
  DestinationModel(
    imageUrl: 'https://images.unsplash.com/photo-1602002418082-a4443e081dd1',
    city: 'Bora Bora',
    country: 'French Polynesia',
    description:
        'Emerald lagoon, dormant volcano, over-water villas, and postcard island beauty.',
    bestFor: 'Honeymoons, luxury, snorkeling',
    tripLength: '5-7 days',
    tags: ['Beach', 'Luxury', 'Relaxation', 'Romance'],
  ),
];
