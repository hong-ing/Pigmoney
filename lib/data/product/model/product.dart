class Product {
  final String imagePath;
  final String name;
  final int price;

  Product({
    required this.imagePath,
    required this.name,
    required this.price,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      name: json['name'] ?? '',
      price: json['price'] ?? 0,
      imagePath: json['imagePath'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'price': price,
      'imagePath': imagePath,
    };
  }
}
