import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import '../core.dart';

/// Minimal synchronous SQLite binding over `dart:ffi`, using the SQLite
/// library that ships with the OS (Windows 10+: winsqlite3.dll; macOS / iOS:
/// libsqlite3.dylib; Linux: libsqlite3.so.0). It lets the importer read
/// chat.db / sms.db / Manifest.db without any package dependency. Memory is
/// allocated with `sqlite3_malloc`, so `package:ffi` isn't needed either.
///
/// Android does not expose its system SQLite to apps, so iPhone/Mac imports
/// are a desktop feature (open() throws an [ImportException] there).
class SqliteException implements Exception {
  SqliteException(this.code, this.message);

  final int code;
  final String message;

  /// SQLITE_NOTADB: encrypted or not a database.
  bool get isNotADatabase => code == 26;

  @override
  String toString() => 'SqliteException($code): $message';
}

class SqliteDb {
  SqliteDb._(this._api, this._db);

  final _SqliteApi _api;
  Pointer<Void> _db;

  static const _openReadOnly = 0x1, _openReadWrite = 0x2, _openCreate = 0x4;

  static SqliteDb open(String path, {bool readOnly = false, bool create = false}) {
    final api = _SqliteApi.instance;
    final ppDb = api.malloc(8).cast<Pointer<Void>>();
    final cPath = api.cString(path);
    try {
      final flags = readOnly ? _openReadOnly : (_openReadWrite | (create ? _openCreate : 0));
      final rc = api.openV2(cPath, ppDb, flags, nullptr);
      final db = ppDb.value;
      if (rc != 0) {
        final msg = db == nullptr ? 'cannot open' : api.errmsgOf(db);
        if (db != nullptr) api.closeV2(db);
        throw SqliteException(rc, msg);
      }
      return SqliteDb._(api, db);
    } finally {
      api.free(cPath.cast());
      api.free(ppDb.cast());
    }
  }

  void close() {
    if (_db == nullptr) return;
    _api.closeV2(_db);
    _db = nullptr;
  }

  /// Runs one statement and returns all rows as column-name -> value maps.
  /// Values are int, double, String, Uint8List or null.
  List<Map<String, Object?>> select(String sql, [List<Object?> params = const []]) {
    final rows = <Map<String, Object?>>[];
    _run(sql, params, (stmt) {
      final n = _api.columnCount(stmt);
      final row = <String, Object?>{};
      for (var i = 0; i < n; i++) {
        row[_api.columnName(stmt, i).toDartUtf8()] = _value(stmt, i);
      }
      rows.add(row);
    });
    return rows;
  }

  /// Runs one parameterised statement, or several `;`-separated statements
  /// when [params] is empty.
  void execute(String sql, [List<Object?> params = const []]) {
    if (params.isNotEmpty) {
      _run(sql, params, (_) {});
      return;
    }
    final cSql = _api.cString(sql);
    final pStmt = _api.malloc(8).cast<Pointer<Void>>();
    final pTail = _api.malloc(8).cast<Pointer<Uint8>>();
    try {
      var cursor = cSql;
      while (cursor.value != 0) {
        _check(_api.prepareV2(_db, cursor, -1, pStmt, pTail));
        final stmt = pStmt.value;
        cursor = pTail.value;
        if (stmt == nullptr) continue; // whitespace / comment
        try {
          int rc;
          do {
            rc = _api.step(stmt);
          } while (rc == 100);
          if (rc != 101) _check(rc);
        } finally {
          _api.finalize(stmt);
        }
      }
    } finally {
      _api.free(cSql.cast());
      _api.free(pStmt.cast());
      _api.free(pTail.cast());
    }
  }

  int? scalarInt(String sql, [List<Object?> params = const []]) {
    final rows = select(sql, params);
    if (rows.isEmpty) return null;
    final v = rows.first.values.first;
    return v is int ? v : (v is num ? v.toInt() : null);
  }

  void _run(String sql, List<Object?> params, void Function(Pointer<Void> stmt) onRow) {
    if (_db == nullptr) throw SqliteException(21, 'database is closed');
    final cSql = _api.cString(sql);
    final pStmt = _api.malloc(8).cast<Pointer<Void>>();
    Pointer<Void> stmt = nullptr;
    try {
      _check(_api.prepareV2(_db, cSql, -1, pStmt, nullptr));
      stmt = pStmt.value;
      for (var i = 0; i < params.length; i++) {
        _bind(stmt, i + 1, params[i]);
      }
      while (true) {
        final rc = _api.step(stmt);
        if (rc == 100) {
          onRow(stmt);
        } else if (rc == 101) {
          break;
        } else {
          _check(rc);
        }
      }
    } finally {
      if (stmt != nullptr) _api.finalize(stmt);
      _api.free(cSql.cast());
      _api.free(pStmt.cast());
    }
  }

  void _bind(Pointer<Void> stmt, int index, Object? value) {
    int rc;
    switch (value) {
      case null:
        rc = _api.bindNull(stmt, index);
      case bool b:
        rc = _api.bindInt64(stmt, index, b ? 1 : 0);
      case int v:
        rc = _api.bindInt64(stmt, index, v);
      case double v:
        rc = _api.bindDouble(stmt, index, v);
      case String s:
        final bytes = utf8.encode(s);
        final p = _api.bytes(bytes);
        rc = _api.bindText(stmt, index, p, bytes.length, _transient);
        _api.free(p.cast());
      case List<int> blob:
        final p = _api.bytes(blob);
        rc = _api.bindBlob(stmt, index, p.cast(), blob.length, _transient);
        _api.free(p.cast());
      default:
        throw ArgumentError('Unsupported SQLite parameter type: ${value.runtimeType}');
    }
    _check(rc);
  }

  static final _transient = Pointer<NativeFunction<Void Function(Pointer<Void>)>>.fromAddress(-1);

  Object? _value(Pointer<Void> stmt, int i) {
    switch (_api.columnType(stmt, i)) {
      case 1:
        return _api.columnInt64(stmt, i);
      case 2:
        return _api.columnDouble(stmt, i);
      case 3:
        final p = _api.columnText(stmt, i);
        final n = _api.columnBytes(stmt, i);
        return p == nullptr ? '' : utf8.decode(p.asTypedList(n), allowMalformed: true);
      case 4:
        final p = _api.columnBlob(stmt, i);
        final n = _api.columnBytes(stmt, i);
        return p == nullptr ? Uint8List(0) : Uint8List.fromList(p.cast<Uint8>().asTypedList(n));
      default:
        return null;
    }
  }

  void _check(int rc) {
    if (rc != 0) throw SqliteException(rc, _api.errmsgOf(_db));
  }
}

extension on Pointer<Uint8> {
  String toDartUtf8() {
    var len = 0;
    while (this[len] != 0) {
      len++;
    }
    return utf8.decode(asTypedList(len), allowMalformed: true);
  }
}

typedef _OpenN = Int32 Function(Pointer<Uint8>, Pointer<Pointer<Void>>, Int32, Pointer<Uint8>);
typedef _OpenD = int Function(Pointer<Uint8>, Pointer<Pointer<Void>>, int, Pointer<Uint8>);
typedef _PtrIntN = Int32 Function(Pointer<Void>);
typedef _PtrIntD = int Function(Pointer<Void>);
typedef _PrepN = Int32 Function(Pointer<Void>, Pointer<Uint8>, Int32, Pointer<Pointer<Void>>, Pointer<Pointer<Uint8>>);
typedef _PrepD = int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Pointer<Void>>, Pointer<Pointer<Uint8>>);
typedef _ColIntN = Int32 Function(Pointer<Void>, Int32);
typedef _ColIntD = int Function(Pointer<Void>, int);
typedef _ColI64N = Int64 Function(Pointer<Void>, Int32);
typedef _ColDblN = Double Function(Pointer<Void>, Int32);
typedef _ColDblD = double Function(Pointer<Void>, int);
typedef _ColPtrN = Pointer<Uint8> Function(Pointer<Void>, Int32);
typedef _ColPtrD = Pointer<Uint8> Function(Pointer<Void>, int);
typedef _ColVoidN = Pointer<Void> Function(Pointer<Void>, Int32);
typedef _ColVoidD = Pointer<Void> Function(Pointer<Void>, int);
typedef _BindI64N = Int32 Function(Pointer<Void>, Int32, Int64);
typedef _BindDblN = Int32 Function(Pointer<Void>, Int32, Double);
typedef _BindDblD = int Function(Pointer<Void>, int, double);
typedef _Dtor = Pointer<NativeFunction<Void Function(Pointer<Void>)>>;
typedef _BindTextN = Int32 Function(Pointer<Void>, Int32, Pointer<Uint8>, Int32, _Dtor);
typedef _BindTextD = int Function(Pointer<Void>, int, Pointer<Uint8>, int, _Dtor);
typedef _BindBlobN = Int32 Function(Pointer<Void>, Int32, Pointer<Void>, Int32, _Dtor);
typedef _BindBlobD = int Function(Pointer<Void>, int, Pointer<Void>, int, _Dtor);
typedef _ErrN = Pointer<Uint8> Function(Pointer<Void>);
typedef _MallocN = Pointer<Void> Function(Int32);
typedef _MallocD = Pointer<Void> Function(int);
typedef _FreeN = Void Function(Pointer<Void>);
typedef _FreeD = void Function(Pointer<Void>);

class _SqliteApi {
  _SqliteApi(DynamicLibrary lib)
      : openV2 = lib.lookupFunction<_OpenN, _OpenD>('sqlite3_open_v2'),
        closeV2 = lib.lookupFunction<_PtrIntN, _PtrIntD>('sqlite3_close_v2'),
        prepareV2 = lib.lookupFunction<_PrepN, _PrepD>('sqlite3_prepare_v2'),
        step = lib.lookupFunction<_PtrIntN, _PtrIntD>('sqlite3_step'),
        finalize = lib.lookupFunction<_PtrIntN, _PtrIntD>('sqlite3_finalize'),
        columnCount = lib.lookupFunction<_PtrIntN, _PtrIntD>('sqlite3_column_count'),
        columnName = lib.lookupFunction<_ColPtrN, _ColPtrD>('sqlite3_column_name'),
        columnType = lib.lookupFunction<_ColIntN, _ColIntD>('sqlite3_column_type'),
        columnInt64 = lib.lookupFunction<_ColI64N, _ColIntD>('sqlite3_column_int64'),
        columnDouble = lib.lookupFunction<_ColDblN, _ColDblD>('sqlite3_column_double'),
        columnText = lib.lookupFunction<_ColPtrN, _ColPtrD>('sqlite3_column_text'),
        columnBlob = lib.lookupFunction<_ColVoidN, _ColVoidD>('sqlite3_column_blob'),
        columnBytes = lib.lookupFunction<_ColIntN, _ColIntD>('sqlite3_column_bytes'),
        bindNull = lib.lookupFunction<_ColIntN, _ColIntD>('sqlite3_bind_null'),
        bindInt64 = lib.lookupFunction<_BindI64N, int Function(Pointer<Void>, int, int)>('sqlite3_bind_int64'),
        bindDouble = lib.lookupFunction<_BindDblN, _BindDblD>('sqlite3_bind_double'),
        bindText = lib.lookupFunction<_BindTextN, _BindTextD>('sqlite3_bind_text'),
        bindBlob = lib.lookupFunction<_BindBlobN, _BindBlobD>('sqlite3_bind_blob'),
        errmsg = lib.lookupFunction<_ErrN, _ErrN>('sqlite3_errmsg'),
        malloc = lib.lookupFunction<_MallocN, _MallocD>('sqlite3_malloc'),
        free = lib.lookupFunction<_FreeN, _FreeD>('sqlite3_free');

  static _SqliteApi? _instance;

  static _SqliteApi get instance => _instance ??= _SqliteApi(_load());

  static DynamicLibrary _load() {
    final candidates = Platform.isWindows
        ? ['winsqlite3.dll', 'sqlite3.dll']
        : Platform.isMacOS || Platform.isIOS
            ? ['/usr/lib/libsqlite3.dylib', 'libsqlite3.dylib']
            : Platform.isLinux
                ? ['libsqlite3.so.0', 'libsqlite3.so']
                : <String>[];
    for (final name in candidates) {
      try {
        return DynamicLibrary.open(name);
      } catch (_) {}
    }
    if (Platform.isIOS || Platform.isMacOS) {
      try {
        final process = DynamicLibrary.process();
        process.lookup('sqlite3_open_v2');
        return process;
      } catch (_) {}
    }
    throw const ImportException(
      'Reading iPhone/Mac message databases is not available on this device.',
      hint: 'Run the import from the Orbit app on a Windows PC or Mac.',
    );
  }

  final _OpenD openV2;
  final _PtrIntD closeV2;
  final _PrepD prepareV2;
  final _PtrIntD step;
  final _PtrIntD finalize;
  final _PtrIntD columnCount;
  final _ColPtrD columnName;
  final _ColIntD columnType;
  final _ColIntD columnInt64;
  final _ColDblD columnDouble;
  final _ColPtrD columnText;
  final _ColVoidD columnBlob;
  final _ColIntD columnBytes;
  final _ColIntD bindNull;
  final int Function(Pointer<Void>, int, int) bindInt64;
  final _BindDblD bindDouble;
  final _BindTextD bindText;
  final _BindBlobD bindBlob;
  final _ErrN errmsg;
  final _MallocD malloc;
  final _FreeD free;

  String errmsgOf(Pointer<Void> db) => errmsg(db).toDartUtf8();

  Pointer<Uint8> bytes(List<int> data) {
    final p = malloc(data.length + 1).cast<Uint8>();
    p.asTypedList(data.length + 1)
      ..setRange(0, data.length, data)
      ..[data.length] = 0;
    return p;
  }

  Pointer<Uint8> cString(String s) => bytes(utf8.encode(s));
}

/// True when the OS SQLite library can be loaded on this device.
bool sqliteAvailable() {
  try {
    _SqliteApi.instance;
    return true;
  } catch (_) {
    return false;
  }
}

List<String> tableColumns(SqliteDb db, String table) =>
    [for (final r in db.select('PRAGMA table_info($table)')) (r['name'] as String).toLowerCase()];

bool tableExists(SqliteDb db, String table) =>
    db.select("SELECT name FROM sqlite_master WHERE type='table' AND name=?", [table]).isNotEmpty;

/// Copies a SQLite file plus its -wal/-shm siblings into [dir], so we never
/// open (or lock, or modify) the user's original database.
Future<String> copySqliteForReading(String source, String dir, {String? name}) async {
  await Directory(dir).create(recursive: true);
  final target = '$dir${Platform.pathSeparator}${name ?? File(source).uri.pathSegments.last}';
  await File(source).copy(target);
  for (final suffix in const ['-wal', '-shm']) {
    final side = File('$source$suffix');
    if (await side.exists()) await side.copy('$target$suffix');
  }
  return target;
}
