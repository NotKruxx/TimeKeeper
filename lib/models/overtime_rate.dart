class OvertimeRate {
  final int? id;
  final int aziendaId;
  final double rate;
  final String description;

  OvertimeRate({
    this.id,
    required this.aziendaId,
    required this.rate,
    required this.description,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'azienda_id': aziendaId,
      'rate': rate,
      'description': description,
    };
  }
}
