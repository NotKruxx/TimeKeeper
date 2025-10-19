// lib/models/azienda.dart

class Azienda {
  final int? id;
  final String name;
  final double hourlyRate;
  final double overtimeRate;

  Azienda({
    this.id,
    required this.name,
    this.hourlyRate = 0.0,
    this.overtimeRate = 0.0,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'hourly_rate': hourlyRate,
      'overtime_rate': overtimeRate,
    };
  }

  factory Azienda.fromMap(Map<String, dynamic> map) {
    return Azienda(
      id: map['id'],
      name: map['name'],
      hourlyRate: (map['hourly_rate'] as num?)?.toDouble() ?? 0.0,
      overtimeRate: (map['overtime_rate'] as num?)?.toDouble() ?? 0.0,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Azienda && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
