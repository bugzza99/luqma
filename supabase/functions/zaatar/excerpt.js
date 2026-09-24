/**
 * What «زعتر» is allowed to learn from what a customer typed.
 *
 * The old file here was called `redactor.js` and worked the other way round: it looked
 * for patterns that *are* personal — phone numbers, street words, «اسمي» — removed those,
 * and treated the absence of a match as permission to forward the rest. A denylist cannot
 * make that promise. The structural review of 2026-09-20 sent two ordinary sentences
 * through it and both came out unchanged with `hasPersonalDetails: false`:
 *
 *   «وصل الطلب لمحمد حسن عند مسجد النور»
 *   «deliver to ahmed ali, 12 el bahr, edku»
 *
 * Neither contains the word «شارع» and neither is `Firstname Lastname` in Latin capitals,
 * so both were cleared to leave the country inside a Gemini request. Every new pattern
 * added to a list like that covers the example that prompted it and nothing else.
 *
 * So this file inverts it. Nothing is removed from the customer's words; instead a new
 * string is **built** out of an allowlist. A token survives only if it is one of the
 * roughly ninety words in [INTENT_WORDS] and [CONTEXT_WORDS] below — words about food,
 * time, money and orders. A name, a landmark, a house number, a telephone number and a
 * street are not in that vocabulary and therefore cannot appear in the result, whatever
 * shape they were written in and whether or not anybody anticipated them.
 *
 * The same vocabulary does double duty: [classifyLocally] reads the decisive words
 * straight off it and answers without the model at all, which is what happens for most
 * messages. See `handler.js` for what is actually sent when it does not.
 */

const TASHKEEL = /[ً-ْـ]/g;

/** Eastern Arabic (٠-٩) and Persian (۰-۹) digits to ASCII, so a number is a number. */
export function normalizeDigits(text) {
  if (typeof text !== 'string') return '';
  return text
    .replace(/[٠-٩]/g, (d) => String(d.charCodeAt(0) - 0x0660))
    .replace(/[۰-۹]/g, (d) => String(d.charCodeAt(0) - 0x06f0));
}

/**
 * One spelling per word. Egyptian typing drops hamza, writes ة for ه and ى for ي more or
 * less at random, so «إلغاء», «الغاء» and «الغاء» must all reach the same vocabulary entry
 * or the allowlist silently refuses ordinary Arabic.
 */
export function normalizeArabic(text) {
  if (typeof text !== 'string') return '';
  return normalizeDigits(text)
    .replace(TASHKEEL, '')
    .replace(/[أإآٱ]/g, 'ا')
    .replace(/ى/g, 'ي')
    .replace(/ئ/g, 'ي')
    .replace(/ؤ/g, 'و')
    .replace(/ة/g, 'ه')
    .toLowerCase();
}

/**
 * The words that decide an intent on their own. The five topics are exactly
 * `HelpTopic` in `packages/luqma_core/lib/src/support/order_helper.dart` — there is one
 * answer specification in this product and it lives in Dart.
 *
 * So does the *classification* specification, since 2026-09-20:
 * `packages/luqma_core/lib/src/support/zaatar_classifier.dart`. This file is its port,
 * because the phone has to be able to read a message with no connection at all. The two
 * were written independently once and disagreed — «السعر» was money here and «حاجة
 * تانية» there — so the customer's answer depended on which failure they had hit.
 * `data/zaatar_corpus.json` is the vocabulary and the corpus both sides are run against;
 * a word added here and not there fails this suite and the Dart one.
 */
export const INTENT_WORDS = Object.freeze({
  // late
  اتاخر: 'late',
  تاخر: 'late',
  متاخر: 'late',
  تاخير: 'late',
  فين: 'late',
  امتي: 'late',
  هيوصل: 'late',
  وصل: 'late',
  يوصل: 'late',
  بطيء: 'late',
  late: 'late',
  delay: 'late',
  delayed: 'late',
  where: 'late',
  مستني: 'late',
  استني: 'late',
  منتظر: 'late',
  جا: 'late',
  جه: 'late',
  جي: 'late',
  // wrongItems
  ناقص: 'wrongItems',
  ناقصه: 'wrongItems',
  غلط: 'wrongItems',
  خطا: 'wrongItems',
  مغلوط: 'wrongItems',
  wrong: 'wrongItems',
  missing: 'wrongItems',
  نسي: 'wrongItems',
  نسيتو: 'wrongItems',
  // cancel
  الغي: 'cancel',
  الغاء: 'cancel',
  يلغي: 'cancel',
  تلغي: 'cancel',
  نلغي: 'cancel',
  ملغي: 'cancel',
  cancel: 'cancel',
  // money
  فلوس: 'money',
  حساب: 'money',
  الحساب: 'money',
  الباقي: 'money',
  فاتوره: 'money',
  سعر: 'money',
  السعر: 'money',
  تمن: 'money',
  كاش: 'money',
  جنيه: 'money',
  money: 'money',
  price: 'money',
  refund: 'money',
  cash: 'money',
  bill: 'money',
  // quality
  بارد: 'quality',
  ساقع: 'quality',
  وحش: 'quality',
  مقرف: 'quality',
  محروق: 'quality',
  ني: 'quality',
  نيء: 'quality',
  بايظ: 'quality',
  بايت: 'quality',
  معفن: 'quality',
  ريحه: 'quality',
  طعم: 'quality',
  مالح: 'quality',
  ملح: 'quality',
  cold: 'quality',
  bad: 'quality',
  burnt: 'quality',
  taste: 'quality',
  // change
  اغير: 'change',
  نغير: 'change',
  تغيير: 'change',
  اعدل: 'change',
  تعديل: 'change',
  ازود: 'change',
  زود: 'change',
  اضيف: 'change',
  اشيل: 'change',
  عنوان: 'change',
  العنوان: 'change',
  change: 'change',
  address: 'change',
  // howTo
  دفع: 'howTo',
  الدفع: 'howTo',
  ادفع: 'howTo',
  فيزا: 'howTo',
  كارت: 'howTo',
  كوبون: 'howTo',
  الكوبون: 'howTo',
  كود: 'howTo',
  خصم: 'howTo',
  رسوم: 'howTo',
  pay: 'howTo',
  coupon: 'howTo',
  visa: 'howTo',
  card: 'howTo',
  // thanks
  شكرا: 'thanks',
  متشكر: 'thanks',
  متشكرين: 'thanks',
  تسلم: 'thanks',
  مرسي: 'thanks',
  thanks: 'thanks',
  thank: 'thanks',
  // hello
  السلام: 'hello',
  اهلا: 'hello',
  ازيك: 'hello',
  هاي: 'hello',
  صباح: 'hello',
  مساء: 'hello',
  hi: 'hello',
  hello: 'hello',
});

/**
 * Words that carry no intent by themselves but say what kind of message this is. They are
 * what the model gets to see; none of them can identify anybody.
 */
export const CONTEXT_WORDS = Object.freeze(new Set([
  'مش', 'عايز', 'عاوز', 'محتاج', 'ممكن', 'لسه', 'خلاص', 'دلوقتي', 'بقالي', 'من',
  'ليه', 'ازاي', 'ايه', 'هو', 'انا', 'حد', 'حاجه', 'تاني', 'كمان', 'برضه',
  'الطلب', 'طلب', 'طلبي', 'الاوردر', 'اوردر', 'الاكل', 'اكل', 'الوجبه', 'وجبه', 'صنف',
  'اصناف', 'كميه', 'حته', 'ساندويتش', 'مشروب', 'المطعم', 'مطعم', 'المحل', 'الشيف', 'المطبخ',
  'المندوب', 'مندوب', 'الدليفري', 'التوصيل', 'توصيل', 'سخن', 'حلو', 'كويس', 'نضيف', 'مقفول',
  'مفتوح', 'مشكله', 'شكوي', 'زعلان', 'اسف', 'ساعه', 'ساعات', 'دقيقه', 'دقايق', 'يوم',
  'النهارده', 'order', 'food', 'driver', 'delivery', 'restaurant', 'shop', 'hot', 'problem', 'help',
  'please', 'still', 'not', 'why', 'when', 'how', 'item', 'items',
]));

/**
 * What may come off the front and the back of a word the vocabulary does not know, once
 * each — the port of `ZaatarClassifier.prefixes`/`suffixes`. «موصلش» is «وصل» under «م…ش»,
 * «هيتأخر» is «تاخر» after «هي»; a vocabulary of whole words refused both. The whole word
 * is always tried first, so «مطعم» stays a shop and never becomes «طعم».
 */
export const PREFIXES = Object.freeze(["", "و", "ف", "ب", "ل", "ال", "وال", "بال", "فال", "لل", "ه", "ح", "هي", "هت", "حي", "حت", "بي", "بت", "م", "ما", "ي", "ت", "ن", "ا"]);
export const SUFFIXES = Object.freeze(["", "ش", "ت", "و", "ي", "ه", "ها", "هم", "ك", "كم", "نا", "لي", "لك", "ين", "وا", "تش", "وش", "يش", "ته", "تو", "وه"]);

/** Which family answers a message that has more than one. */
export const PRECEDENCE = Object.freeze(["cancel", "change", "wrongItems", "quality", "money", "howTo", "late", "thanks", "hello"]);

function known(word) {
  // Own properties only: `in` walks the prototype chain (see [reduceToExcerpt]).
  return Object.hasOwn(INTENT_WORDS, word) || CONTEXT_WORDS.has(word);
}

/**
 * The vocabulary word [token] is, whole or with one prefix and one suffix taken off —
 * fewest letters first, prefixes and suffixes in their listed order — or null. A core
 * under two letters never counts. What it returns is always a vocabulary word, so the
 * excerpt built from it is still built out of the allowlist alone.
 */
export function vocabularyWord(token) {
  if (!token) return null;
  if (known(token)) return token;
  for (let removed = 1; removed < token.length - 1; removed++) {
    for (const p of PREFIXES) {
      for (const s of SUFFIXES) {
        if (p.length + s.length !== removed) continue;
        if (!token.startsWith(p) || !token.endsWith(s)) continue;
        const core = token.slice(p.length, token.length - s.length);
        if (core.length >= 2 && known(core)) return core;
      }
    }
  }
  return null;
}

/** How many allowlisted words may leave. Enough to tell «مش وصل» from «وصل بارد». */
export const MAX_EXCERPT_WORDS = 12;

/**
 * What a customer typed, reduced to the allowlisted words in it, in order, deduplicated.
 *
 * Returns `''` when nothing in the message is in the vocabulary — which is the answer for
 * a message that is only a name and an address. The caller must not call the model then.
 */
export function reduceToExcerpt(text) {
  if (typeof text !== 'string') return '';
  const kept = [];
  const seen = new Set();
  for (const token of normalizeArabic(text).split(/[^\p{L}\p{N}]+/u)) {
    if (!token) continue;
    // `Object.hasOwn`, never `in`: `in` walks the prototype chain, so «constructor»,
    // «toString» and «hasOwnProperty» are all "in" any object literal and were being
    // forwarded to Google as though they were words about food. [vocabularyWord] asks
    // the same way, and hands back the vocabulary's own spelling — never the token.
    const word = vocabularyWord(token);
    if (word === null) continue;
    if (seen.has(word)) continue;
    seen.add(word);
    kept.push(word);
    if (kept.length === MAX_EXCERPT_WORDS) break;
  }
  return kept.join(' ');
}

/**
 * The topic a message decides on its own, and whether it decided one.
 *
 * `decisive` false means «other» is a guess rather than a reading — that is the only case
 * worth spending a model turn on, and [reduceToExcerpt] is what the model is given.
 */
export function classifyLocally(text) {
  const found = new Set();
  for (const token of normalizeArabic(text).split(/[^\p{L}\p{N}]+/u)) {
    const word = vocabularyWord(token);
    // Own properties only. A bare «constructor» used to read `Object` off the prototype
    // chain and return it as the topic — truthy, so «decisive», and a function, so
    // `JSON.stringify` dropped the key entirely and the phone got a reply with no intent
    // in it at all.
    if (word === null || !Object.hasOwn(INTENT_WORDS, word)) continue;
    found.add(INTENT_WORDS[word]);
  }
  if (found.size === 0) return { topic: 'other', decisive: false };

  // Two different families in one message is the ambiguity a model is for, so it is not
  // decisive — but it is not «حاجة تانية» either: without a model it reads as the family
  // that comes first in [PRECEDENCE].
  if (found.size > 1) {
    return { topic: PRECEDENCE.find((t) => found.has(t)) ?? 'other', decisive: false };
  }

  const topic = [...found][0];
  // Belt and braces: whatever the vocabulary comes to hold, nothing but a topic leaves
  // this function under the name of one.
  return TOPICS.includes(topic)
    ? { topic, decisive: true }
    : { topic: 'other', decisive: false };
}

/** The topics — exactly `HelpTopic` — and the only values the handler returns as one. */
export const TOPICS = Object.freeze([
  'late', 'wrongItems', 'cancel', 'money', 'other',
  'quality', 'change', 'howTo', 'thanks', 'hello',
]);
