// lib/ui/providers/companies_provider.dart

import 'package:flutter/foundation.dart';
import '../../data/repositories/azienda_repository.dart';
import '../../data/services/auto_shift_service.dart';
import '../../models/azienda.dart';

class CompaniesProvider extends ChangeNotifier {
  List<Azienda> aziende  = [];
  bool          isLoading = false;

  Future<void> load() async {
    isLoading = true;
    notifyListeners();
    aziende = AziendaRepository.instance.getAll();
    isLoading = false;
    notifyListeners();
  }

  Future<void> save(Azienda azienda) async {
    if (azienda.id != null) {
      await AziendaRepository.instance.update(azienda);
    } else {
      await AziendaRepository.instance.insert(azienda);
    }
    await AutoShiftService.instance.run();
    await load();
  }

  Future<void> delete(int id) async {
    await AziendaRepository.instance.delete(id);
    await load();
  }
}
