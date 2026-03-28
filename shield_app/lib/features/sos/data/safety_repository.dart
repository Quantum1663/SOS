import '../../../core/storage/app_database.dart';
import 'package:sqflite/sqflite.dart';
import '../domain/incident_log.dart';
import '../domain/journey_plan.dart';
import '../domain/safety_settings.dart';
import '../domain/trusted_contact.dart';

class SafetyRepository {
  SafetyRepository({AppDatabase? database})
      : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;
  static const _activeCheckInDeadlineKey = 'activeCheckInDeadline';
  static const _journeyDestinationKey = 'activeJourneyDestination';
  static const _journeyRouteNoteKey = 'activeJourneyRouteNote';
  static const _journeyVehicleDetailsKey = 'activeJourneyVehicleDetails';
  static const _journeyStartedAtKey = 'activeJourneyStartedAt';
  static const _journeyExpectedArrivalKey = 'activeJourneyExpectedArrival';

  Future<List<TrustedContact>> getContacts() async {
    final db = await _database.database;
    final maps = await db.query(
      'trusted_contacts',
      orderBy: 'priority ASC, id ASC',
    );
    return maps.map(TrustedContact.fromMap).toList();
  }

  Future<TrustedContact> saveContact(TrustedContact contact) async {
    final db = await _database.database;
    if (contact.id == null) {
      final id = await db.insert('trusted_contacts', contact.toMap());
      return contact.copyWith(id: id);
    }

    await db.update(
      'trusted_contacts',
      contact.toMap(),
      where: 'id = ?',
      whereArgs: [contact.id],
    );
    return contact;
  }

  Future<void> deleteContact(int id) async {
    final db = await _database.database;
    await db.delete(
      'trusted_contacts',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<IncidentLog>> getIncidents() async {
    final db = await _database.database;
    final maps = await db.query(
      'incident_logs',
      orderBy: 'created_at DESC',
      limit: 25,
    );
    return maps.map(IncidentLog.fromMap).toList();
  }

  Future<void> saveIncident(IncidentLog incident) async {
    final db = await _database.database;
    await db.insert('incident_logs', incident.toMap());
  }

  Future<void> clearIncidentHistory() async {
    final db = await _database.database;
    await db.delete('incident_logs');
  }

  Future<SafetySettings> getSettings() async {
    final db = await _database.database;
    final maps = await db.query('app_settings');
    final values = <String, String>{};
    for (final row in maps) {
      values[row['key'] as String] = row['value'] as String;
    }
    return SafetySettings.fromStorage(values);
  }

  Future<void> saveSettings(SafetySettings settings) async {
    final db = await _database.database;
    final batch = db.batch();
    for (final entry in settings.toStorage().entries) {
      batch.insert(
        'app_settings',
        {'key': entry.key, 'value': entry.value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<DateTime?> getActiveCheckInDeadline() async {
    final db = await _database.database;
    final maps = await db.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: [_activeCheckInDeadlineKey],
      limit: 1,
    );
    if (maps.isEmpty) {
      return null;
    }

    return DateTime.tryParse(maps.first['value'] as String);
  }

  Future<void> saveActiveCheckInDeadline(DateTime? deadline) async {
    final db = await _database.database;
    if (deadline == null) {
      await db.delete(
        'app_settings',
        where: 'key = ?',
        whereArgs: [_activeCheckInDeadlineKey],
      );
      return;
    }

    await db.insert(
      'app_settings',
      {
        'key': _activeCheckInDeadlineKey,
        'value': deadline.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<JourneyPlan?> getActiveJourney() async {
    final db = await _database.database;
    final maps = await db.query(
      'app_settings',
      where:
          'key IN (?, ?, ?, ?, ?)',
      whereArgs: [
        _journeyDestinationKey,
        _journeyRouteNoteKey,
        _journeyVehicleDetailsKey,
        _journeyStartedAtKey,
        _journeyExpectedArrivalKey,
      ],
    );
    if (maps.isEmpty) {
      return null;
    }

    final values = <String, String>{};
    for (final row in maps) {
      values[row['key'] as String] = row['value'] as String;
    }

    final expectedArrival =
        DateTime.tryParse(values[_journeyExpectedArrivalKey] ?? '');
    final startedAt = DateTime.tryParse(values[_journeyStartedAtKey] ?? '');
    if (expectedArrival == null || startedAt == null) {
      return null;
    }

    final journey = JourneyPlan(
      destination: values[_journeyDestinationKey] ?? '',
      routeNote: values[_journeyRouteNoteKey] ?? '',
      vehicleDetails: values[_journeyVehicleDetailsKey] ?? '',
      startedAt: startedAt,
      expectedArrival: expectedArrival,
    );

    return journey.hasDetails ? journey : null;
  }

  Future<void> saveActiveJourney(JourneyPlan? journey) async {
    final db = await _database.database;
    final keys = [
      _journeyDestinationKey,
      _journeyRouteNoteKey,
      _journeyVehicleDetailsKey,
      _journeyStartedAtKey,
      _journeyExpectedArrivalKey,
    ];

    if (journey == null || !journey.hasDetails) {
      await db.delete(
        'app_settings',
        where: 'key IN (?, ?, ?, ?, ?)',
        whereArgs: keys,
      );
      return;
    }

    final batch = db.batch();
    final values = <String, String>{
      _journeyDestinationKey: journey.destination,
      _journeyRouteNoteKey: journey.routeNote,
      _journeyVehicleDetailsKey: journey.vehicleDetails,
      _journeyStartedAtKey: journey.startedAt.toIso8601String(),
      _journeyExpectedArrivalKey: journey.expectedArrival.toIso8601String(),
    };
    for (final entry in values.entries) {
      batch.insert(
        'app_settings',
        {'key': entry.key, 'value': entry.value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> deleteAllSafetyData() async {
    final db = await _database.database;
    final batch = db.batch();
    batch.delete('trusted_contacts');
    batch.delete('incident_logs');
    batch.delete('app_settings');
    await batch.commit(noResult: true);
  }
}
