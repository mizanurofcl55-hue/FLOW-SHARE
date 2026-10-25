import 'dart:convert';
import 'dart:io';
import 'package:flowshare_core/flowshare_core.dart';
import 'package:sqflite/sqflite.dart' as mobile;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class LocalStore {
  final Database database;
  LocalStore(this.database);
  static Future<LocalStore> open(String path) async {
    if (Platform.isWindows || Platform.isLinux) sqfliteFfiInit();
    final factory = (Platform.isWindows || Platform.isLinux)
        ? databaseFactoryFfi
        : mobile.databaseFactory;
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute(
            'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE trusted (fingerprint TEXT PRIMARY KEY, name TEXT NOT NULL, created TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE history (id TEXT PRIMARY KEY, direction TEXT NOT NULL, peer TEXT NOT NULL, status TEXT NOT NULL, bytes INTEGER NOT NULL, total INTEGER NOT NULL, elapsed INTEGER NOT NULL, destination TEXT, error TEXT, files TEXT NOT NULL, created TEXT NOT NULL)',
          );
        },
      ),
    );
    return LocalStore(db);
  }

  Future<Map<String, String>> settings() async => {
    for (final row in await database.query('settings'))
      row['key'] as String: row['value'] as String,
  };
  Future<void> set(String key, String value) async {
    await database.insert('settings', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> remember(String fp, String name) async {
    await database.insert('trusted', {
      'fingerprint': fp,
      'name': name,
      'created': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, Object?>>> trusted() =>
      database.query('trusted', orderBy: 'created DESC');
  Future<void> forget(String fp) async {
    await database.delete('trusted', where: 'fingerprint=?', whereArgs: [fp]);
  }

  Future<void> record(TransferProgress progress) async {
    await database.insert('history', {
      'id': '${progress.direction}-${progress.manifest.id}',
      'direction': progress.direction,
      'peer': progress.peer,
      'status': progress.status.name,
      'bytes': progress.bytes,
      'total': progress.manifest.total,
      'elapsed': progress.elapsed.inMilliseconds,
      'destination': progress.destination,
      'error': progress.error,
      'files': jsonEncode(
        progress.manifest.files.map((f) => f.toJson()).toList(),
      ),
      'created': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, Object?>>> history() =>
      database.query('history', orderBy: 'created DESC', limit: 500);
  Future<void> clearHistory() async {
    await database.delete('history');
  }

  Future<void> close() => database.close();
}
