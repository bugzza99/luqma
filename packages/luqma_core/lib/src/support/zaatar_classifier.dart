import 'order_helper.dart';

/// What the words in a message say the question is about, and whether they said it
/// plainly enough to be trusted without a model.
class ZaatarReading {
  const ZaatarReading({required this.topic, required this.decisive});

  final HelpTopic topic;

  /// False means «other» is a guess rather than a reading — either nothing in the
  /// message is in the vocabulary, or two different families are, which is the one case
  /// worth spending a model turn on.
  final bool decisive;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ZaatarReading &&
          runtimeType == other.runtimeType &&
          topic == other.topic &&
          decisive == other.decisive;

  @override
  int get hashCode => Object.hash(topic, decisive);

  @override
  String toString() => 'ZaatarReading(topic: $topic, decisive: $decisive)';
}

/// How «زعتر» reads a typed question — the whole specification, in one place.
///
/// It is written twice, because one copy has to run on a phone with no connection and
/// the other inside the Edge Function before anything is sent to a model. It used to be
/// written twice *differently*, which is worse than either: `السعر` was money on the
/// server and «حاجة تانية» on the phone, and `لسه عاوز ألغي` was cancel on the server and
/// «الأوردر اتأخر» on the phone — because the phone's copy searched for substrings in the
/// order somebody happened to write the `if`s, and checked «لسه» before «ألغي». So the
/// answer a customer read depended on *which* failure they had hit, which is the one
/// thing a fallback must never be.
///
/// This file is the specification and `supabase/functions/zaatar/excerpt.js` is its port.
/// Neither is allowed to drift: `data/zaatar_corpus.json` holds the vocabulary and a
/// corpus of messages, and both sides are run against that same file — by
/// `test/zaatar_classifier_test.dart` here and by
/// `supabase/test/local/zaatar_counts_its_words.test.js` there. A word added to one and
/// not the other fails both suites.
abstract final class ZaatarClassifier {
  /// The words that decide a topic on their own, in their normalized spelling.
  static const intentWords = <String, HelpTopic>{
    // late
    'اتاخر': HelpTopic.late,
    'تاخر': HelpTopic.late,
    'متاخر': HelpTopic.late,
    'تاخير': HelpTopic.late,
    'فين': HelpTopic.late,
    'امتي': HelpTopic.late,
    'هيوصل': HelpTopic.late,
    'وصل': HelpTopic.late,
    'يوصل': HelpTopic.late,
    'بطيء': HelpTopic.late,
    'late': HelpTopic.late,
    'delay': HelpTopic.late,
    'delayed': HelpTopic.late,
    'where': HelpTopic.late,
    'مستني': HelpTopic.late,
    'استني': HelpTopic.late,
    'منتظر': HelpTopic.late,
    'جا': HelpTopic.late,
    'جه': HelpTopic.late,
    'جي': HelpTopic.late,
    // wrongItems
    'ناقص': HelpTopic.wrongItems,
    'ناقصه': HelpTopic.wrongItems,
    'غلط': HelpTopic.wrongItems,
    'خطا': HelpTopic.wrongItems,
    'مغلوط': HelpTopic.wrongItems,
    'wrong': HelpTopic.wrongItems,
    'missing': HelpTopic.wrongItems,
    'نسي': HelpTopic.wrongItems,
    'نسيتو': HelpTopic.wrongItems,
    // cancel
    'الغي': HelpTopic.cancel,
    'الغاء': HelpTopic.cancel,
    'يلغي': HelpTopic.cancel,
    'تلغي': HelpTopic.cancel,
    'نلغي': HelpTopic.cancel,
    'ملغي': HelpTopic.cancel,
    'cancel': HelpTopic.cancel,
    // money
    'فلوس': HelpTopic.money,
    'حساب': HelpTopic.money,
    'الحساب': HelpTopic.money,
    'الباقي': HelpTopic.money,
    'فاتوره': HelpTopic.money,
    'سعر': HelpTopic.money,
    'السعر': HelpTopic.money,
    'تمن': HelpTopic.money,
    'كاش': HelpTopic.money,
    'جنيه': HelpTopic.money,
    'money': HelpTopic.money,
    'price': HelpTopic.money,
    'refund': HelpTopic.money,
    'cash': HelpTopic.money,
    'bill': HelpTopic.money,
    // quality
    'بارد': HelpTopic.quality,
    'ساقع': HelpTopic.quality,
    'وحش': HelpTopic.quality,
    'مقرف': HelpTopic.quality,
    'محروق': HelpTopic.quality,
    'ني': HelpTopic.quality,
    'نيء': HelpTopic.quality,
    'بايظ': HelpTopic.quality,
    'بايت': HelpTopic.quality,
    'معفن': HelpTopic.quality,
    'ريحه': HelpTopic.quality,
    'طعم': HelpTopic.quality,
    'مالح': HelpTopic.quality,
    'ملح': HelpTopic.quality,
    'cold': HelpTopic.quality,
    'bad': HelpTopic.quality,
    'burnt': HelpTopic.quality,
    'taste': HelpTopic.quality,
    // change
    'اغير': HelpTopic.change,
    'نغير': HelpTopic.change,
    'تغيير': HelpTopic.change,
    'اعدل': HelpTopic.change,
    'تعديل': HelpTopic.change,
    'ازود': HelpTopic.change,
    'زود': HelpTopic.change,
    'اضيف': HelpTopic.change,
    'اشيل': HelpTopic.change,
    'عنوان': HelpTopic.change,
    'العنوان': HelpTopic.change,
    'change': HelpTopic.change,
    'address': HelpTopic.change,
    // howTo
    'دفع': HelpTopic.howTo,
    'الدفع': HelpTopic.howTo,
    'ادفع': HelpTopic.howTo,
    'فيزا': HelpTopic.howTo,
    'كارت': HelpTopic.howTo,
    'كوبون': HelpTopic.howTo,
    'الكوبون': HelpTopic.howTo,
    'كود': HelpTopic.howTo,
    'خصم': HelpTopic.howTo,
    'رسوم': HelpTopic.howTo,
    'pay': HelpTopic.howTo,
    'coupon': HelpTopic.howTo,
    'visa': HelpTopic.howTo,
    'card': HelpTopic.howTo,
    // thanks
    'شكرا': HelpTopic.thanks,
    'متشكر': HelpTopic.thanks,
    'متشكرين': HelpTopic.thanks,
    'تسلم': HelpTopic.thanks,
    'مرسي': HelpTopic.thanks,
    'thanks': HelpTopic.thanks,
    'thank': HelpTopic.thanks,
    // hello
    'السلام': HelpTopic.hello,
    'اهلا': HelpTopic.hello,
    'ازيك': HelpTopic.hello,
    'هاي': HelpTopic.hello,
    'صباح': HelpTopic.hello,
    'مساء': HelpTopic.hello,
    'hi': HelpTopic.hello,
    'hello': HelpTopic.hello,
  };

  /// Words that carry no topic by themselves but say what kind of message this is.
  ///
  /// They decide nothing. What they do is keep a whole word whole: a word the vocabulary
  /// knows is never cut down to a shorter one, so «مطعم» stays a shop rather than losing
  /// its «م» to become «طعم».
  static const contextWords = <String>{
    'مش', 'عايز', 'عاوز', 'محتاج', 'ممكن', 'لسه', 'خلاص', 'دلوقتي', 'بقالي', 'من',
    'ليه', 'ازاي', 'ايه', 'هو', 'انا', 'حد', 'حاجه', 'تاني', 'كمان', 'برضه',
    'الطلب', 'طلب', 'طلبي', 'الاوردر', 'اوردر', 'الاكل', 'اكل', 'الوجبه', 'وجبه', 'صنف',
    'اصناف', 'كميه', 'حته', 'ساندويتش', 'مشروب', 'المطعم', 'مطعم', 'المحل', 'الشيف', 'المطبخ',
    'المندوب', 'مندوب', 'الدليفري', 'التوصيل', 'توصيل', 'سخن', 'حلو', 'كويس', 'نضيف', 'مقفول',
    'مفتوح', 'مشكله', 'شكوي', 'زعلان', 'اسف', 'ساعه', 'ساعات', 'دقيقه', 'دقايق', 'يوم',
    'النهارده', 'order', 'food', 'driver', 'delivery', 'restaurant', 'shop', 'hot', 'problem', 'help',
    'please', 'still', 'not', 'why', 'when', 'how', 'item', 'items',
  };

  /// What may come off the front and the back of a word the vocabulary does not know,
  /// once each. Egyptian Arabic wraps a verb in its tense and its negation — «موصلش» is
  /// «وصل» under «م…ش», «هيتأخر» is «تاخر» after the future «هي», «اتأخرت» is «اتاخر» with
  /// its «ت» — and a vocabulary of whole words refused every one of them, which is most of
  /// how people actually write. The whole word is always tried first, so «مطعم» stays a
  /// shop and never loses its «م» to become «طعم».
  static const prefixes = <String>[
    '', 'و', 'ف', 'ب', 'ل', 'ال', 'وال', 'بال', 'فال', 'لل', 'ه', 'ح', 'هي', 'هت', 'حي', 'حت', 'بي', 'بت', 'م', 'ما', 'ي', 'ت', 'ن', 'ا',
  ];

  static const suffixes = <String>[
    '', 'ش', 'ت', 'و', 'ي', 'ه', 'ها', 'هم', 'ك', 'كم', 'نا', 'لي', 'لك', 'ين', 'وا', 'تش', 'وش', 'يش', 'ته', 'تو', 'وه',
  ];

  /// Which family answers a message that has more than one. «الأكل وصل بارد» is about
  /// the food, not the clock; «اتأخر وعاوز ألغي» wants the way out. It used to read as
  /// «حاجة تانية», and «حاجة تانية» sent every one of them to a person.
  static const precedence = <HelpTopic>[
    HelpTopic.cancel, HelpTopic.change, HelpTopic.wrongItems, HelpTopic.quality, HelpTopic.money, HelpTopic.howTo, HelpTopic.late, HelpTopic.thanks, HelpTopic.hello,
  ];

  static final RegExp _tashkeel = RegExp('[ً-ْـ]');
  static final RegExp _separator = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

  /// Eastern Arabic (٠-٩) and Persian (۰-۹) digits to ASCII, so a number is a number.
  static String normalizeDigits(String text) {
    final out = StringBuffer();
    for (final unit in text.runes) {
      if (unit >= 0x0660 && unit <= 0x0669) {
        out.write(unit - 0x0660);
      } else if (unit >= 0x06f0 && unit <= 0x06f9) {
        out.write(unit - 0x06f0);
      } else {
        out.writeCharCode(unit);
      }
    }
    return out.toString();
  }

  /// One spelling per word. Egyptian typing drops hamza, writes ة for ه and ى for ي more
  /// or less at random, so «إلغاء», «الغاء» and «ألغاء» must all reach the same entry or
  /// the vocabulary silently refuses ordinary Arabic.
  static String normalize(String text) => normalizeDigits(text)
      .replaceAll(_tashkeel, '')
      .replaceAll(RegExp('[أإآٱ]'), 'ا')
      .replaceAll('ى', 'ي')
      .replaceAll('ئ', 'ي')
      .replaceAll('ؤ', 'و')
      .replaceAll('ة', 'ه')
      .toLowerCase();

  /// The normalized words in a message, in order, splitting on anything that is neither
  /// a letter nor a digit.
  static List<String> tokens(String text) =>
      normalize(text).split(_separator).where((t) => t.isNotEmpty).toList();

  /// The vocabulary word [token] is, whole or with one prefix and one suffix taken off —
  /// fewest letters first, prefixes and suffixes in their listed order — or null. A core
  /// under two letters never counts.
  static String? vocabularyWord(String token) {
    bool known(String w) => intentWords.containsKey(w) || contextWords.contains(w);
    if (known(token)) return token;
    for (var removed = 1; removed < token.length - 1; removed++) {
      for (final p in prefixes) {
        for (final s in suffixes) {
          if (p.length + s.length != removed) continue;
          if (!token.startsWith(p) || !token.endsWith(s)) continue;
          final core = token.substring(p.length, token.length - s.length);
          if (core.length >= 2 && known(core)) return core;
        }
      }
    }
    return null;
  }

  /// The topic these words decide, and whether they decided one.
  static ZaatarReading read(String message) {
    final found = <HelpTopic>{};
    for (final token in tokens(message)) {
      final word = vocabularyWord(token);
      final topic = word == null ? null : intentWords[word];
      if (topic != null) found.add(topic);
    }

    if (found.isEmpty) {
      return const ZaatarReading(topic: HelpTopic.other, decisive: false);
    }
    // Two different families in one message — «الطلب اتأخر وعاوز ألغي» — is the ambiguity
    // a model is for, so it is not decisive; but it is not «حاجة تانية» either. Without a
    // model it is answered as the family that comes first in [precedence].
    if (found.length > 1) {
      return ZaatarReading(
        topic: precedence.firstWhere(found.contains),
        decisive: false,
      );
    }
    return ZaatarReading(topic: found.single, decisive: true);
  }
}
