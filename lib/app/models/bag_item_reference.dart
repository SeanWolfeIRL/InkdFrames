class BagItemReference {
  const BagItemReference({
    required this.id,
    required this.name,
    required this.assetType,
    required this.createdAt,
    this.imagePath,
  });

  final String id;
  final String name;
  final String assetType;
  final DateTime createdAt;
  final String? imagePath;

  factory BagItemReference.fromJson(Map<String, dynamic> json) {
    return BagItemReference(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Bag Item',
      assetType: json['assetType'] as String? ?? 'vector',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      imagePath: json['imagePath'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'assetType': assetType,
    'createdAt': createdAt.toIso8601String(),
    if (imagePath != null) 'imagePath': imagePath,
  };
}
