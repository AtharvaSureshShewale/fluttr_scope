import 'package:flutter/material.dart';

// hardcoded_ip_address / insecure_http_url cases. Text shown to the user
// (shape taken from a real app's settings screen) isn't an endpoint.
// 'ok ...' must not be flagged, 'bad ...' must.

Widget networkHelp() => Column(children: [
      Text('123.123.123.123'), // 'ok example ip shown to the user'
      const TextField(decoration: InputDecoration(hintText: 'http://my-server.example.com')), // 'ok hint text'
    ]);

const apiHost = '203.0.113.10'; // 'bad hardcoded endpoint ip'
const apiBase = 'http://api.example.com/v1'; // 'bad cleartext endpoint'
