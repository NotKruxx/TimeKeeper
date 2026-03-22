// test/ui/providers/companies_provider_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:salvaore/models/azienda.dart';
import 'package:salvaore/ui/providers/companies_provider.dart';
import '../../helpers/db_helper.dart';

void main() {
  late CompaniesProvider provider;

  setUp(() async {
    await TestDb.setup();
    provider = CompaniesProvider();
  });

  tearDown(() async {
    provider.dispose();
    await TestDb.teardown();
  });

  group('CompaniesProvider', () {
    test('load returns empty on fresh DB', () async {
      await provider.load();
      expect(provider.aziende, isEmpty);
    });

    test('save inserts and reloads', () async {
      await provider.save(const Azienda(name: 'New Corp'));
      expect(provider.aziende.length, 1);
      expect(provider.aziende.first.name, 'New Corp');
    });

    test('save updates existing', () async {
      await provider.save(const Azienda(name: 'Original'));
      final original = provider.aziende.first;
      await provider.save(original.copyWith(name: 'Updated'));
      expect(provider.aziende.length, 1);
      expect(provider.aziende.first.name, 'Updated');
    });

    test('delete removes azienda', () async {
      await provider.save(const Azienda(name: 'To Delete'));
      await provider.delete(provider.aziende.first.id!);
      expect(provider.aziende, isEmpty);
    });

    test('notifies listeners after save', () async {
      int count = 0;
      provider.addListener(() => count++);
      await provider.save(const Azienda(name: 'Test'));
      expect(count, greaterThan(0));
    });
  });
}
