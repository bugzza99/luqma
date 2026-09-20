import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// The phone's half of one classification specification.
///
/// `supabase/functions/zaatar/excerpt.js` is the other half, and the two were written
/// independently once: «السعر» was money on the server and «حاجة تانية» on the phone,
/// «لسه عاوز ألغي» was cancel on the server and «الأوردر اتأخر» on the phone — so which
/// answer a customer read depended on whether the server had failed or the model was
/// unconfigured, which is the one thing a fallback must never do.
///
/// Both are now run against `data/zaatar_corpus.json`, this file here and
/// `supabase/test/local/zaatar_counts_its_words.test.js` there. A word added to one side
/// and not the other fails both suites.
void main() {
  final corpus = jsonDecode(
    File('../../data/zaatar_corpus.json').readAsStringSync(),
  ) as Map<String, dynamic>;

  HelpTopic topicOf(String name) =>
      HelpTopic.values.firstWhere((t) => t.name == name);

  group('the shared corpus', () {
    test('every message reads the way the corpus says', () {
      for (final entry in (corpus['cases'] as List).cast<Map<String, dynamic>>()) {
        final message = entry['message'] as String;
        final note = entry['note'] as String? ?? '';
        expect(
          ZaatarClassifier.read(message),
          ZaatarReading(
            topic: topicOf(entry['topic'] as String),
            decisive: entry['decisive'] as bool,
          ),
          reason: '«$message»${note.isEmpty ? '' : ' — $note'}',
        );
      }
    });

    test('the vocabulary is exactly the corpus vocabulary', () {
      final expected = (corpus['intentWords'] as Map<String, dynamic>)
          .map((word, topic) => MapEntry(word, topicOf(topic as String)));

      expect(ZaatarClassifier.intentWords, expected);
      expect(
        ZaatarClassifier.contextWords,
        (corpus['contextWords'] as List).cast<String>().toSet(),
      );
    });
  });

  group('reading a message', () {
    test('folds the spellings of one word onto one entry', () {
      for (final spelling in ['ألغي', 'الغي', 'إلغاء', 'الغاء', 'ألغاء']) {
        expect(ZaatarClassifier.read(spelling).topic, HelpTopic.cancel,
            reason: spelling);
      }
    });

    test('reads Arabic-Indic digits as digits, and they decide nothing', () {
      expect(ZaatarClassifier.normalize('٠١٢٣٤٥٦٧٨٩'), '0123456789');
      expect(
        ZaatarClassifier.read('٠١٠١٢٣٤٥٦٧٨'),
        const ZaatarReading(topic: HelpTopic.other, decisive: false),
      );
    });

    test('one family however many times is still decisive', () {
      expect(
        ZaatarClassifier.read('الطلب اتأخر و اتأخر و التأخير مستمر'),
        const ZaatarReading(topic: HelpTopic.late, decisive: true),
      );
    });

    test('two families are a question nobody on the phone can settle', () {
      expect(
        ZaatarClassifier.read('الطلب اتأخر وعاوز ألغي'),
        const ZaatarReading(topic: HelpTopic.other, decisive: false),
      );
    });

    test('matches whole words, not substrings', () {
      // The old phone-side reader searched for «فين» anywhere in the message, so any
      // word containing it — and any word containing «وصل», «حساب» or «غلط» — decided
      // the topic. Tokenising is what stops that.
      expect(
        ZaatarClassifier.read('الشيف محترفين').topic,
        HelpTopic.other,
        reason: '«محترفين» contains «فين» and is not a question about a late order',
      );
    });
  });
}
