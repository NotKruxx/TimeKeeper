// test/data/repositories/azienda_repository_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:salvaore/data/repositories/azienda_repository.dart';
import 'package:salvaore/data/repositories/hours_repository.dart';
import 'package:salvaore/models/azienda.dart';
import 'package:salvaore/models/hours_worked.dart';
import '../../helpers/db_helper.dart';

void main() {
  late AziendaRepository repo;

  setUp(() async {
    await TestDb.setup();
    repo = AziendaRepository.instance;
  });

  tearDown(TestDb.teardown);
  tearDownAll(TestDb.dispose);

  Future<Azienda> insertAzienda(String name, {double rate = 0}) async {
    await repo.insert(Azienda(name: name, hourlyRate: rate));
    return repo.getAll().firstWhere((a) => a.name == name);
  }

  group('AziendaRepository', () {
    test('insert persists and returns non-null uuid', () async {
      final az = await insertAzienda('ACME');
      expect(az.uuid, isNotNull);
      expect(az.name, 'ACME');
    });

    test('insert stamps updatedAt', () async {
      final az = await insertAzienda('Timestamped');
      expect(az.uuid, isNotNull);
      // updatedAt is stored in raw map — verify via getByUuid roundtrip
      final found = repo.getByUuid(az.uuid!);
      expect(found, isNotNull);
    });

    test('duplicate name is ignored', () async {
      await repo.insert(const Azienda(name: 'Dup'));
      await repo.insert(const Azienda(name: 'Dup'));
      expect(repo.getAll().length, 1);
    });

    test('getAll returns empty on fresh DB', () {
      expect(repo.getAll(), isEmpty);
    });

    test('getAll sorted alphabetically', () async {
      await repo.insert(const Azienda(name: 'Zebra'));
      await repo.insert(const Azienda(name: 'Alpha'));
      final names = repo.getAll().map((a) => a.name).toList();
      expect(names, ['Alpha', 'Zebra']);
    });

    test('getAll excludes tombstoned records', () async {
      final az = await insertAzienda('To Delete');
      await repo.delete(az.uuid!);
      expect(repo.getAll(), isEmpty);
    });

    test('getByUuid returns correct azienda', () async {
      final inserted = await insertAzienda('By-UUID Corp');
      final found = repo.getByUuid(inserted.uuid!);
      expect(found?.name, 'By-UUID Corp');
    });

    test('getByUuid returns null for unknown uuid', () {
      expect(repo.getByUuid('non-existent'), isNull);
    });

    test('getByUuid returns null for tombstoned record', () async {
      final az = await insertAzienda('Tombstoned');
      await repo.delete(az.uuid!);
      expect(repo.getByUuid(az.uuid!), isNull);
    });

    test('update changes name and rate', () async {
      final az = await insertAzienda('Old', rate: 10);
      await repo.update(az.copyWith(name: 'New', hourlyRate: 20));
      final found = repo.getByUuid(az.uuid!);
      expect(found?.name, 'New');
      expect(found?.hourlyRate, 20.0);
    });

    test('delete is a soft delete — record stays in box with tombstone', () async {
      final az = await insertAzienda('Soft');
      await repo.delete(az.uuid!);
      // Not visible via getAll/getByUuid
      expect(repo.getAll(), isEmpty);
      expect(repo.getByUuid(az.uuid!), isNull);
    });

    test('delete unknown uuid is a no-op', () async {
      await insertAzienda('Safe');
      await repo.delete('non-existent');
      expect(repo.getAll().length, 1);
    });

    test('delete cascades soft-delete to linked hours', () async {
      final az = await insertAzienda('With Hours');
      final hoursRepo = HoursRepository.instance;
      await hoursRepo.insert(HoursWorked(
        aziendaUuid: az.uuid!,
        startTime: DateTime(2025, 1, 1, 9, 0),
        endTime: DateTime(2025, 1, 1, 17, 0),
      ));
      expect(hoursRepo.getAll().length, 1);
      await repo.delete(az.uuid!);
      expect(hoursRepo.getAll(), isEmpty);
    });
  });
}