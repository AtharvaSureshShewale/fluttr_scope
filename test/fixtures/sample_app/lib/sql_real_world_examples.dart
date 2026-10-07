// sql_injection_risk cases. The 'ok' shapes come from a real app's
// database layer (schema-name constants spliced into queries).
// 'ok ...' must not be flagged, 'bad ...' must.

class Db {
  Future<void> execute(String sql, [List<Object?>? args]) async {}
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? args]) async => [];
}

class TableInfo {
  final String table;
  final String columnLocalID;

  const TableInfo(this.table, this.columnLocalID);
}

const _commentsTable = 'comments';
const _sqlBoolFalse = 0;
const _uploads = TableInfo('uploads', 'local_id');

Future<void> sqlExamples(Db db, String userName, int limit, List<int> ids) async {
  await db.execute('DELETE FROM $_commentsTable'); // 'ok const table name'
  await db.execute('DELETE FROM ${_uploads.table} WHERE ${_uploads.columnLocalID} = ?', [1]); // 'ok schema names'
  await db.execute('UPDATE files SET backed_up = $_sqlBoolFalse'); // 'ok const value'
  await db.rawQuery('SELECT * FROM files LIMIT $limit'); // 'ok int cannot inject'
  await db.rawQuery('SELECT * FROM users WHERE name = ?', [userName]); // 'ok parameterized'
  final placeholders = List.filled(ids.length, '?').join(', ');
  await db.rawQuery('SELECT * FROM files WHERE id IN ($placeholders)', ids); // 'ok placeholder list'
  await db.rawQuery("SELECT * FROM files WHERE id IN (${List.filled(ids.length, '?').join(', ')})", ids); // 'ok inline placeholders'

  await db.rawQuery("SELECT * FROM users WHERE name = '$userName'"); // 'bad user value interpolated'
  await db.rawQuery('SELECT * FROM users WHERE name = ' + userName); // 'bad user value concatenated'
  await db.execute('DELETE FROM files WHERE id IN (${ids.join(',')})'); // 'bad computed list'
}
