import 'package:sqflite_common_ffi/sqflite_ffi.dart';

bool _ready = false;

void ensureSqlite() {
  if (_ready) return;
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  _ready = true;
}
