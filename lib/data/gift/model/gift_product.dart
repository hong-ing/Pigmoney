class GiftProduct {
  final String code;
  final String brand;
  final int money;
  final String name;

  GiftProduct({
    required this.code,
    required this.brand,
    required this.money,
    required this.name,
  });

  factory GiftProduct.fromJson(Map<String, dynamic> json) {
    return GiftProduct(
      code: json['code'] as String,
      brand: json['brand'] as String,
      money: (json['money'] as num).toInt(),
      name: json['name'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'brand': brand,
      'money': money,
      'name': name,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GiftProduct && other.code == code && other.brand == brand && other.money == money && other.name == name;
  }

  @override
  int get hashCode => code.hashCode ^ brand.hashCode ^ money.hashCode ^ name.hashCode;
}
