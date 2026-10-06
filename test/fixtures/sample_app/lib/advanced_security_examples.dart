import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

// Stand-in for shared_preferences — the fixture app doesn't depend on
// that package, and insecure_storage_of_sensitive_data's check is a type
// name match, so a local type with the same name exercises it without
// the real dependency.
class SharedPreferences {
  Future<void> setString(String key, String value) async {}
}

class AdvancedSecurityExamples extends StatelessWidget {
  const AdvancedSecurityExamples({super.key});

  static const authToken = 'irrelevant-for-this-fixture';

  void logToken() {
    print('token: $authToken');
  }

  Future<void> queryUser(dynamic db, String userId) async {
    await db.rawQuery('SELECT * FROM users WHERE id = $userId');
  }

  Future<void> storeToken(SharedPreferences prefs) async {
    await prefs.setString('auth_token', authToken);
  }

  void hashPassword(String password) {
    md5.convert(utf8.encode(password));
  }

  Future<void> createUnconstrainedTable(dynamic db) async {
    await db.execute('CREATE TABLE notes (id INTEGER, body TEXT)');
  }

  Future<void> createConstrainedTable(dynamic db) async {
    await db.execute(
      'CREATE TABLE users (id INTEGER PRIMARY KEY, email TEXT NOT NULL UNIQUE)',
    );
  }

  void disableCertificateValidation(HttpClient client) {
    client.badCertificateCallback = (cert, host, port) => true;
  }

  void checkCertificatePinning(HttpClient client, String expectedHost) {
    client.badCertificateCallback = (cert, host, port) => host == expectedHost;
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
