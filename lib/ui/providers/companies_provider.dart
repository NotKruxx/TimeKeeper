// lib/ui/providers/companies_provider.dart

import 'package:flutter/foundation.dart';
import '../../data/models/azienda_model.dart';
import 'data_cache_provider.dart';

class CompaniesProvider extends ChangeNotifier {
  List<AziendaModel> aziende  = [];
  bool               isLoading = false;

  void updateFromCache(DataCacheProvider cache) {
    aziende = cache.aziende;
    isLoading = cache.isLoading;
    notifyListeners();
  }
}
