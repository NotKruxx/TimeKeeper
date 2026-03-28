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
  tearDownAll(TestDb.dispose);

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

    test('delete soft-deletes and removes from list', () async {
      await provider.save(const Azienda(name: 'To Delete'));
      final uuid = provider.aziende.first.uuid!;
      await provider.delete(uuid);
      expect(provider.aziende, isEmpty);
    });

    test('notifies listeners after save', () async {
      int count = 0;
      provider.addListener(() => count++);
      await provider.save(const Azienda(name: 'Test'));
      expect(count, greaterThan(0));
    });

    test('notifies listeners after delete', () async {
      await provider.save(const Azienda(name: 'To Delete'));
      final uuid = provider.aziende.first.uuid!;
      int count = 0;
      provider.addListener(() => count++);
      await provider.delete(uuid);
      expect(count, greaterThan(0));
    });
  });
}