// insecure_http_url cases. 'ok ...' must not be flagged, 'bad ...' must.

bool isWebUrl(String raw) => raw.startsWith('http://') || raw.startsWith('https://'); // 'ok scheme prefix check'

const okLan = 'http://192.168.1.7:8000'; // 'ok private LAN dev server'
const okTenNet = 'http://10.0.2.2:8080/api'; // 'ok emulator host alias'
const okMdns = 'http://my-laptop.local:3000'; // 'ok mDNS name'
const okHttps = 'https://api.example.com'; // 'ok https'

const badPublic = 'http://api.example.com/v1'; // 'bad public host'
const badLookalike = 'http://localhost.evil.com/x'; // 'bad lookalike of localhost'
const badPublicIp = 'http://8.8.8.8/dns'; // 'bad public ip'
