// hardcoded_secret cases (all values fake). 'ok ...' must not be flagged,
// 'bad ...' must -- on the literal's line.

class SetuLikeService {
  static const _clientId = '292c6e76-dabf-49c4-8e48-90fba2916673'; // 'ok an id, not a secret'
  static const _clientSecret = 'Qz7Lm2Xp9Rt4Vb8Nw3Kd6Hs1'; // 'bad client secret'
}

const tokenKey = 'access_token'; // 'ok prefs key name'
const passwordLabel = 'Enter your password'; // 'ok label'
const serviceRoleKey = 'YOUR_SERVICE_ROLE_KEY_HERE'; // 'ok placeholder'
const apiKeyDocs = 'https://example.com/docs/api-key'; // 'ok url'
const secretShort = 'abc123'; // 'ok too short'
const accessToken = 'aaaaaaaaaaaaaaaa1111111111'; // 'ok low entropy'

void configure({String? apiKey}) {}

void setup() {
  configure(apiKey: 'k9Fq2Wz7Lp4Xr8Tm3Vn6Bc5D'); // 'bad named argument'
}
