import 'package:fluttr_scope/src/static/rules/hardcoded_secret.dart';
import 'package:test/test.dart';

void main() {
  test('matches well-known secret shapes', () {
    expect(matchSecretPattern('AKIAABCDEFGHIJKLMNOP'), 'AWS access key');
    expect(
      matchSecretPattern('AIza${'x' * 35}'),
      'Google API key',
    );
    expect(
      matchSecretPattern('sk_live_${'a' * 24}'),
      'Stripe live key',
    );
    expect(matchSecretPattern('ghp_${'a' * 36}'), 'GitHub token');
    expect(matchSecretPattern('xoxb-1234567890-abcdefg'), 'Slack token');
  });

  test('does not match ordinary strings or placeholders', () {
    expect(matchSecretPattern('hello world'), isNull);
    expect(matchSecretPattern('YOUR_API_KEY_HERE'), isNull);
    expect(matchSecretPattern(''), isNull);
    expect(matchSecretPattern('X-Api-Key'), isNull);
  });
}
