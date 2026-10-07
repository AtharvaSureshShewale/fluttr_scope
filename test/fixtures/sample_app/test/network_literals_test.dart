// Test data: IP addresses and URLs here are inputs to the code under test,
// not endpoints the app connects to. Nothing in this file may be flagged
// by hardcoded_ip_address or insecure_http_url.
void main() {
  const whitelisted = '2.2.2.3';
  const server = 'http://203.0.113.10/api';
  print('$whitelisted $server');
}
