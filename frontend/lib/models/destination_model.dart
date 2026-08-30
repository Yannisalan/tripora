class DestinationModel {
  final String city;
  final String country;
  final String imageUrl;
  final String description;
  final String bestFor;
  final String tripLength;
  final List<String> tags;

  const DestinationModel({
    required this.city,
    required this.country,
    required this.imageUrl,
    required this.description,
    required this.bestFor,
    required this.tripLength,
    required this.tags,
  });

  String get fullName => '$city, $country';
}
