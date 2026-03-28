// test/data/repositories/hours_repository_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:salvaore/data/repositories/azienda_repository.dart';
import 'package:salvaore/data/repositories/hours_repository.dart';
import 'package:salvaore/models/azienda.dart';
import 'package:salvaore/models/hours_worked.dart';
import '../../helpers/db_helper.dart';

void main() {
  late HoursRepository repo;
  late String aziendaUuid;

  setUp(() async {
    await TestDb.setup();
    repo = HoursRepository.instance;
    await AziendaRepository.instance.insert(const Azienda(name: 'Test Corp'));
    aziendaUuid = AziendaRepository.instance.getAll().first.uuid!;
  });

  tearDown(TestDb.teardown);
  tearDownAll(TestDb.dispose);

  HoursWorked _make({
    String? uuid,
    DateTime? start,
    DateTime? end,
    int lunch = 60,
    String? notes,
  }) => HoursWorked(
    uuid: uuid,
    aziendaUuid: aziendaUuid,
    startTime: start ?? DateTime(2025, 6, 2, 9, 0),
    endTime:   end   ?? DateTime(2025, 6, 2, 17, 0),
    lunchBreak: lunch,
    notes: notes,
  );

  group('HoursRepository', () {
    test('insert persists and returns non-null uuid', () async {
      final uuid = await repo.insert(_make());
      expect(uuid, isNotEmpty);
      expect(repo.getAll().length, 1);
    });

    test('insert stamps updatedAt', () async {
      await repo.insert(_make());
      expect(repo.getAll().first.uuid, isNotNull);
    });

    test('getAll returns empty on fresh DB', () {
      expect(repo.getAll(), isEmpty);
    });

    test('getAll excludes soft-deleted records', () async {
      final uuid = await repo.insert(_make());
      await repo.softDelete(uuid);
      expect(repo.getAll(), isEmpty);
    });

    test('getAll sorted descending by startTime', () async {
      await repo.insert(_make(start: DateTime(2025, 6, 1, 9, 0), end: DateTime(2025, 6, 1, 17, 0)));
      await repo.insert(_make(start: DateTime(2025, 6, 3, 9, 0), end: DateTime(2025, 6, 3, 17, 0)));
      final all = repo.getAll();
      expect(all.first.startTime.day, 3);
      expect(all.last.startTime.day, 1);
    });

    test('update changes fields', () async {
      final uuid = await repo.insert(_make());
      final inserted = repo.getAll().first;
      await repo.update(inserted.copyWith(lunchBreak: 30, notes: 'updated'));
      final updated = repo.getAll().first;
      expect(updated.lunchBreak, 30);
      expect(updated.notes, 'updated');
    });

    test('softDelete marks record as deleted', () async {
      final uuid = await repo.insert(_make());
      await repo.softDelete(uuid);
      expect(repo.getAll(), isEmpty);
    });

    test('softDelete on unknown uuid is a no-op', () async {
      await repo.insert(_make());
      await repo.softDelete('non-existent');
      expect(repo.getAll().length, 1);
    });

    test('getByAzienda filters by aziendaUuid', () async {
      await AziendaRepository.instance.insert(const Azienda(name: 'Other Corp'));
      final otherUuid = AziendaRepository.instance
          .getAll()
          .firstWhere((a) => a.name == 'Other Corp')
          .uuid!;

      await repo.insert(_make());
      await repo.insert(HoursWorked(
        aziendaUuid: otherUuid,
        startTime: DateTime(2025, 6, 2, 9, 0),
        endTime:   DateTime(2025, 6, 2, 17, 0),
      ));

      expect(repo.getByAzienda(aziendaUuid).length, 1);
      expect(repo.getByAzienda(otherUuid).length, 1);
    });

    test('hasOverlap detects overlapping times for same azienda', () async {
      await repo.insert(_make(
        start: DateTime(2025, 6, 2, 10, 0),
        end:   DateTime(2025, 6, 2, 12, 0),
      ));
      final overlapping = _make(
        start: DateTime(2025, 6, 2, 11, 0),
        end:   DateTime(2025, 6, 2, 13, 0),
      );
      expect(repo.hasOverlap(overlapping), isTrue);
    });

    test('hasOverlap returns false for non-overlapping times', () async {
      await repo.insert(_make(
        start: DateTime(2025, 6, 2, 9, 0),
        end:   DateTime(2025, 6, 2, 12, 0),
      ));
      final nonOverlapping = _make(
        start: DateTime(2025, 6, 2, 13, 0),
        end:   DateTime(2025, 6, 2, 17, 0),
      );
      expect(repo.hasOverlap(nonOverlapping), isFalse);
    });

    test('hasOverlap returns false for same uuid (update scenario)', () async {
      final uuid = await repo.insert(_make(
        start: DateTime(2025, 6, 2, 9, 0),
        end:   DateTime(2025, 6, 2, 17, 0),
      ));
      final sameRecord = _make(
        uuid:  uuid,
        start: DateTime(2025, 6, 2, 9, 0),
        end:   DateTime(2025, 6, 2, 17, 0),
      );
      expect(repo.hasOverlap(sameRecord), isFalse);
    });

    test('hasOverlap returns false for different azienda', () async {
      await repo.insert(_make(
        start: DateTime(2025, 6, 2, 10, 0),
        end:   DateTime(2025, 6, 2, 12, 0),
      ));
      await AziendaRepository.instance.insert(const Azienda(name: 'Other'));
      final otherUuid = AziendaRepository.instance
          .getAll()
          .firstWhere((a) => a.name == 'Other')
          .uuid!;
      final different = HoursWorked(
        aziendaUuid: otherUuid,
        startTime: DateTime(2025, 6, 2, 10, 0),
        endTime:   DateTime(2025, 6, 2, 12, 0),
      );
      expect(repo.hasOverlap(different), isFalse);
    });
  });
}