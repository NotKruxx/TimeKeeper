// test/data/repositories/hours_repository_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:salvaore/data/repositories/azienda_repository.dart';
import 'package:salvaore/data/repositories/hours_repository.dart';
import 'package:salvaore/models/azienda.dart';
import 'package:salvaore/models/hours_worked.dart';
import '../../helpers/db_helper.dart';

void main() {
  late HoursRepository   hoursRepo;
  late AziendaRepository aziendaRepo;
  late int               aziendaId;

  setUp(() async {
    await TestDb.setup();
    hoursRepo   = HoursRepository.instance;
    aziendaRepo = AziendaRepository.instance;
    await aziendaRepo.insert(const Azienda(name: 'Test Corp'));
    aziendaId = aziendaRepo.getAll().first.id!;
  });

  tearDown(TestDb.teardown);

  HoursWorked _shift({DateTime? start, DateTime? end, int lunch = 60, int? id}) {
    final s = start ?? DateTime(2025, 6, 1, 9, 0);
    final e = end   ?? DateTime(2025, 6, 1, 18, 0);
    return HoursWorked(id: id, aziendaId: aziendaId, startTime: s, endTime: e, lunchBreak: lunch);
  }

  group('HoursRepository', () {
    test('insert persists and assigns id', () async {
      final id   = await hoursRepo.insert(_shift());
      final all  = hoursRepo.getAll();
      expect(all.length, 1);
      expect(all.first.id, id);
    });

    test('getAll excludes soft-deleted rows', () async {
      final id1 = await hoursRepo.insert(_shift(start: DateTime(2025,6,1,9,0), end: DateTime(2025,6,1,17,0)));
      await hoursRepo.insert(_shift(start: DateTime(2025,6,2,9,0), end: DateTime(2025,6,2,17,0)));
      await hoursRepo.softDelete(id1);
      expect(hoursRepo.getAll().length, 1);
    });

    test('getAll sorted by startTime DESC', () async {
      await hoursRepo.insert(_shift(start: DateTime(2025,6,1,9,0), end: DateTime(2025,6,1,17,0)));
      await hoursRepo.insert(_shift(start: DateTime(2025,6,2,9,0), end: DateTime(2025,6,2,17,0)));
      expect(hoursRepo.getAll().first.startTime.day, 2);
    });

    test('hasOverlap — same window', () async {
      await hoursRepo.insert(_shift());
      expect(hoursRepo.hasOverlap(_shift()), isTrue);
    });

    test('hasOverlap — fully inside', () async {
      await hoursRepo.insert(_shift());
      expect(hoursRepo.hasOverlap(_shift(
        start: DateTime(2025,6,1,10,0), end: DateTime(2025,6,1,12,0),
      )), isTrue);
    });

    test('hasOverlap — adjacent no overlap', () async {
      await hoursRepo.insert(_shift());
      expect(hoursRepo.hasOverlap(_shift(
        start: DateTime(2025,6,1,18,0), end: DateTime(2025,6,1,22,0),
      )), isFalse);
    });

    test('hasOverlap — completely after no overlap', () async {
      await hoursRepo.insert(_shift());
      expect(hoursRepo.hasOverlap(_shift(
        start: DateTime(2025,6,1,19,0), end: DateTime(2025,6,1,22,0),
      )), isFalse);
    });

    test('hasOverlap — completely before no overlap', () async {
      await hoursRepo.insert(_shift());
      expect(hoursRepo.hasOverlap(_shift(
        start: DateTime(2025,6,1,6,0), end: DateTime(2025,6,1,8,0),
      )), isFalse);
    });

    test('hasOverlap — editing own record no overlap', () async {
      final id   = await hoursRepo.insert(_shift());
      final saved = hoursRepo.getAll().first;
      expect(hoursRepo.hasOverlap(saved.copyWith(lunchBreak: 30)), isFalse);
    });

    test('hasOverlap — different azienda no overlap', () async {
      await hoursRepo.insert(_shift());
      await aziendaRepo.insert(const Azienda(name: 'Other'));
      final otherId = aziendaRepo.getAll().firstWhere((a) => a.name == 'Other').id!;
      final other = HoursWorked(
        aziendaId: otherId,
        startTime: DateTime(2025,6,1,9,0),
        endTime:   DateTime(2025,6,1,18,0),
        lunchBreak: 60,
      );
      expect(hoursRepo.hasOverlap(other), isFalse);
    });

    test('delete azienda cascades to hours', () async {
      await hoursRepo.insert(_shift());
      await aziendaRepo.delete(aziendaId);
      expect(hoursRepo.getAll(), isEmpty);
    });
  });
}
