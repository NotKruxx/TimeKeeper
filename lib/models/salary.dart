class Salary {
  final int? id;
  final int aziendaId;
  final String month;
  final double amount;

  Salary({
    this.id,
    required this.aziendaId,
    required this.month,
    required this.amount,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'azienda_id': aziendaId,
      'month': month,
      'amount': amount,
    };
  }
}
