import 'package:flutter_test/flutter_test.dart';
import 'package:rydago/app/config.dart';
import 'package:rydago/app/strings.dart';
import 'package:rydago/state/share.dart';

void main() {
  test('the live link points at the same server the app talks to', () {
    expect(ShareNotifier.linkFor('abc123'), '$kApiUrl/s/abc123');
  });

  test('share texts mention the destination and the link in both languages', () {
    const link = 'http://x/s/t';
    expect(const S(AppLang.en).liveText('Batu Caves', link), contains('Batu Caves'));
    expect(const S(AppLang.en).liveText('Batu Caves', link), contains(link));
    expect(const S(AppLang.ms).liveText('Batu Caves', link), startsWith('Ikuti perjalanan'));
  });
}
