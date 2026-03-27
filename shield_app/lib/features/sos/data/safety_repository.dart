import '../../../core/storage/app_database.dart';
import 'package:sqflite/sqflite.dart';
import '../domain/incident_log.dart';
import '../domain/safety_settings.dart';
import '../domain/trusted_contact.dart';

class SafetyRepository {
  SafetyRepository({AppDatabase? database})
      : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;

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
}
