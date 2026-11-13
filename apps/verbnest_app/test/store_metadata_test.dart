import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// App Review rejects a name, subtitle or promotional text that mentions price
/// in any form: free, discounted, no cost, no subscription, "open source" as a
/// price claim (guideline 2.3.7, rejection of 0.64.3 and again after 0.65.x).
/// The text entered in App Store Connect is copied from
/// docs/release/app-store-post.md, so that is what this guards.
final _price = RegExp(
  r'\b(free|gratis|no[- ]cost|zero[- ]cost|cost[- ]free|discount\w*|cheap\w*|'
  r'price\w*|pricing|subscription\w*|paid|premium|pro|lite|trial|'
  r'open[- ]source|\d+\s?%\s?off|on sale|sale)\b|[\$€£]',
  caseSensitive: false,
);

String _section(String text, String start, String end) {
  final a = text.indexOf(start);
  expect(a, greaterThanOrEqualTo(0), reason: 'no "$start" in the listing copy');
  final b = text.indexOf(end, a + start.length);
  return text.substring(a + start.length, b < 0 ? text.length : b);
}

void main() {
  final copy = File('../../docs/release/app-store-post.md').readAsStringSync();

  test('the App Store name and subtitle say nothing about price', () {
    final name = _section(copy, '**Name:**', '\n').trim();
    final subtitle = _section(copy, '**Subtitle:**', '\n').trim();
    expect(name, 'VerbNest');
    expect(subtitle, isNotEmpty);
    expect(subtitle.length, lessThanOrEqualTo(30), reason: 'Apple limit');
    for (final field in [name, subtitle]) {
      expect(_price.firstMatch(field), isNull, reason: 'price wording: $field');
    }
  });

  test('the promotional text and the keywords say nothing about price', () {
    final promo = _section(copy, '## Promotional text', '\n## ');
    final keywords = _section(copy, '## Keywords', '\n## ');
    for (final field in [promo, keywords]) {
      expect(
        _price.firstMatch(field)?.group(0),
        isNull,
        reason: 'price wording in the promotional text or keywords',
      );
    }
  });

  test('the check itself catches price wording', () {
    for (final bad in [
      'Free API client',
      'Open source API client',
      'No cost, no subscription',
      'API client for \$0',
      '50% off today',
    ]) {
      expect(_price.hasMatch(bad), isTrue, reason: bad);
    }
    for (final ok in ['Local-first API client', 'Send requests, keep them']) {
      expect(_price.hasMatch(ok), isFalse, reason: ok);
    }
  });
}
