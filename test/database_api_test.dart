// test/database_api_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:salvaore/api/database_api.dart';
import 'package:salvaore/models/azienda.dart';
import 'package:salvaore/models/hours_worked.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    DatabaseApi.isForTesting = true;
  });

  group('DatabaseApi Tests', () {
    late DatabaseApi databaseApi;

    setUp(() {
      databaseApi = DatabaseApi();
    });

    tearDown(() async {
      await DatabaseApi.closeDatabase();
    });

    group('Azienda operations', () {
      test('Aggiunge e recupera una Azienda', () async {
        final azienda = Azienda(name: 'Test Company');
        await databaseApi.addAzienda(azienda);
        final aziende = await databaseApi.getAziende();
        expect(aziende.length, 1);
        expect(aziende.first.name, 'Test Company');
        expect(aziende.first.id, isNotNull);
      });

      test('Aggiorna una Azienda esistente', () async {
        final aziendaIniziale = Azienda(name: 'Old Name');
        await databaseApi.addAzienda(aziendaIniziale);
        final primaAzienda = (await databaseApi.getAziende()).first;
        final aziendaAggiornata = Azienda(
          id: primaAzienda.id,
          name: 'New Name',
        );
        await databaseApi.updateAzienda(aziendaAggiornata);
        final aziendeDopoUpdate = await databaseApi.getAziende();
        expect(aziendeDopoUpdate.length, 1);
        expect(aziendeDopoUpdate.first.name, 'New Name');
      });

      test('Elimina una Azienda', () async {
        final azienda = Azienda(name: 'To Be Deleted');
        await databaseApi.addAzienda(azienda);
        var aziende = await databaseApi.getAziende();
        expect(aziende.length, 1);
        await databaseApi.deleteAzienda(aziende.first.id!);
        aziende = await databaseApi.getAziende();
        expect(aziende.isEmpty, isTrue);
      });
    });

    group('HoursWorked operations', () {
      late Azienda aziendaDiTest;

      setUp(() async {
        aziendaDiTest = Azienda(name: 'Hours Test Corp');
        await databaseApi.addAzienda(aziendaDiTest);
        aziendaDiTest = (await databaseApi.getAziende()).first;
      });

      test('Aggiunge e recupera una sessione di ore', () async {
        final hours = HoursWorked(
          aziendaId: aziendaDiTest.id!,
          startTime: DateTime(2025, 10, 10, 8, 0),
          endTime: DateTime(2025, 10, 10, 17, 0),
          lunchBreak: 60,
          notes: 'Test note',
        );

        await databaseApi.addHoursWorked(hours);
        final oreSalvate = await databaseApi.getHoursWorked();
        expect(oreSalvate.length, 1);
        expect(oreSalvate.first.aziendaId, aziendaDiTest.id);
        expect(oreSalvate.first.notes, 'Test note');
        expect(oreSalvate.first.lunchBreak, 60);
      });

      test(
        'Eliminando una azienda, elimina anche le ore associate (ON DELETE CASCADE)',
        () async {
          final hours1 = HoursWorked(
            aziendaId: aziendaDiTest.id!,
            startTime: DateTime.now(),
            endTime: DateTime.now().add(const Duration(hours: 4)),
            lunchBreak: 0,
          );
          final hours2 = HoursWorked(
            aziendaId: aziendaDiTest.id!,
            startTime: DateTime.now().add(const Duration(days: 1)),
            endTime: DateTime.now().add(const Duration(days: 1, hours: 8)),
            lunchBreak: 30,
          );

          await databaseApi.addHoursWorked(hours1);
          await databaseApi.addHoursWorked(hours2);
          var oreSalvate = await databaseApi.getHoursWorked();
          expect(oreSalvate.length, 2);
          await databaseApi.deleteAzienda(aziendaDiTest.id!);
          oreSalvate = await databaseApi.getHoursWorked();
          final aziende = await databaseApi.getAziende();
          expect(oreSalvate.isEmpty, isTrue);
          expect(aziende.isEmpty, isTrue);
        },
      );
    });
  });
}
