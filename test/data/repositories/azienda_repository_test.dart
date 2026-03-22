// test/data/repositories/azienda_repository_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:salvaore/data/repositories/azienda_repository.dart';
import 'package:salvaore/models/azienda.dart';
import '../../helpers/db_helper.dart';

void main() {
  late AziendaRepository repo;

  setUp(() async {
    await TestDb.setup();
    repo = AziendaRepository.instance;
  });

  tearDown(TestDb.teardown);

  Future<Azienda> _insert(String name, {double rate = 0}) async {
    await repo.insert(Azienda(name: name, hourlyRate: rate));
    return repo.getAll().firstWhere((a) => a.name == name);
  }

  group('AziendaRepository', () {
    test('insert persists and returns non-null id', () async {
      final az = await _insert('ACME');
      expect(az.id, isNotNull);
      expect(az.name, 'ACME');
    });

    test('duplicate name is ignored', () async {
      await repo.insert(const Azienda(name: 'Dup'));
      await repo.insert(const Azienda(name: 'Dup'));
      expect(repo.getAll().length, 1);
    });

    test('getAll returns empty when no rows', () {
      expect(repo.getAll(), isEmpty);
    });

    test('getAll sorted alphabetically', () async {
      await repo.insert(const Azienda(name: 'Zebra'));
      await repo.insert(const Azienda(name: 'Alpha'));
      final names = repo.getAll().map((a) => a.name).toList();
      expect(names, ['Alpha', 'Zebra']);
    });

    test('getById returns correct azienda', () async {
      final inserted = await _insert('By-ID Corp');
      final found    = repo.getById(inserted.id!);
      expect(found?.name, 'By-ID Corp');
    });

    test('getById returns null for unknown id', () {
      expect(repo.getById(99999), isNull);
    });

    test('update changes name and rate', () async {
      final az      = await _insert('Old', rate: 10);
      final updated = az.copyWith(name: 'New', hourlyRate: 20);
      await repo.update(updated);
      expect(repo.getById(az.id!)?.name, 'New');
      expect(repo.getById(az.id!)?.hourlyRate, 20.0);
    });

    test('delete removes the row', () async {
      final az = await _insert('To Delete');
      await repo.delete(az.id!);
      expect(repo.getAll(), isEmpty);
    });

    test('delete unknown id is a no-op', () async {
      await _insert('Safe');
      await repo.delete(99999);
      expect(repo.getAll().length, 1);
    });
  });
}
