# حزمة نشر Google Play — لقمة

آخر تحديث: ٢٣ أكتوبر ٢٠٢٦  
الفرع: `codex/play-release-readiness`  
حساب Play Console: موجود، وبريد التواصل `ibugza@gmail.com`.

التطبيقات اللي هتنزل على Play:

| التطبيق | Application ID | الحزمة |
|---|---|---|
| لقمة (العميل) | `com.luqma.customer` | `build/aab/luqma-customer.aab` |
| لقمة شريك (المطاعم والمندوبين) | `com.luqma.merchant` | `build/aab/luqma-merchant.aab` |

**AdminApp مش هينزل على Google Play.** ده تطبيق إدارة داخلي، بيتوزع APK مباشر لفريق لقمة بس.

---

## ١. الحالة الحالية

### جاهز

- نسخة `1.0.0+30` للتطبيقين، و AABs موقعة بمفتاح الإصدار.
- `flutter analyze` نضيف للتطبيقات الأربعة.
- آخر تشغيل كامل: كل السويتس المحلية نجحت — **719 اختبار SQL / 166 suite / 0 فشل**، واختبارات السحابة اتخطت.
- سياسة خصوصية العميل: <https://luqma-gules.vercel.app/privacy>
- طلب حذف حساب العميل: <https://luqma-gules.vercel.app/privacy/delete>
- سياسة خصوصية الشريك: <https://luqma-gules.vercel.app/privacy/partner>
- طلب حذف حساب الشريك: <https://luqma-gules.vercel.app/privacy/partner/delete>
- الصفحات الأربعة منشورة ومتاحة بدون تسجيل دخول.
- مسار حذف الحساب داخل التطبيقين موجود، واتضاف لشاشة انتظار تفعيل الشريك وشاشة الدخول كمان.
- `USE_FULL_SCREEN_INTENT` باقي في تطبيق الشريك، وهيتعلن في Play Console كوظيفة أساسية لتنبيه الطلبات.
- أصول المتجر الأساسية جاهزة: `marketing/play/app_icon_512.png`، `feature-customer.png`، `feature-merchant.png`.

### لسه محتاج قرار أو بيانات من صاحب المشروع

| # | المطلوب | ليه | الاقتراح |
|---|---|---|---|
| ١ | **نوع حساب Play Console: فردي (Personal) ولا مؤسسة (Organization)؟** | الحسابات الفردية اللي اتعملت بعد ١٣ نوفمبر ٢٠٢٣ لازم ١٢ تستر مسجلين ومستمرين ١٤ يوم قبل الإنتاج. حسابات المؤسسات معفية. | من Play Console: **Settings ← Developer account ← Account type**. ابعتلي اللي مكتوب. |
| ٢ | **بيانات دخول تجريبية للمراجعين**: عميل، صاحب مطعم، ومندوب (اختياري بس مفضل). | Google لازم تقدر تدخل وتجرب التطبيق كله، بما فيه حذف الحساب. | الأفضل حسابات تجريبية مخصصة، مش حسابات حقيقية. ابعت رقم/إيميل + كلمة سر لكل حساب، أو وافق إن أنا أنشئ حسابات تجريبية في الإنتاج (ده كتابة إنتاج، مش هعملها غير بموافقة صريحة). |
| ٣ | **١٢ بريد Google تستر** (لو الحساب فردي). | شرط Play للحسابات الفردية: ١٢ تستر مسجلين، التطبيق متثبت، لمدة ١٤ يوم متواصلة. | ابعت ١٢ إيميل Google. لو الحساب مؤسسة، الخطوة دي مش مطلوبة. |
| ٤ | **الفئة المستهدفة**: ١٨+ ولا ١٣+؟ | بتحدد استبيان Target audience وهل تطبق سياسة Families. | **١٨+** للتطبيقين. التطبيق مش موجه للأطفال، وفيه دفع كاش ورقم موبايل. |
| ٥ | **اسم المطور الظاهر على Play**. | اسم عام بيظهر للناس. لو الحساب فردي، Google ممكن تطلب الاسم القانوني. | `لقمة` لو الحساب مؤسسة، أو `محمد رمضان — Mohamed Ramadan` لو فردي. |
| ٦ | **اعتماد اسم التطبيق والوصف القصير**. | لازم يكونوا نهائيين قبل الرفع. | drafts في `listing-copy.md`: اسم العميل ٢٧ حرف، اسم الشريك ٢٤ حرف، الوصف القصير ٥٦ حرف. |
| ٧ | **اختيار مفتاح التوقيع**: نستخدم `signing/luqma-release.jks` ولا مفتاح من Google؟ | Play App Signing بيحدد مفتاح التوقيع النهائي. لو اخترنا مفتاح Google، التحديثات المباشرة القديمة مش هتترقى لنفس التطبيق. | **استخدام المفتاح الحالي** عشان التطبيقات المثبتة عند التجار والعملاء تتحدث عادي. المفتاح هيتحمل في Play Console، مش هيتبعت في الشات. |
| ٨ | **أصول المتجر**: أيقونة ٥١٢، صورة ١٠٢٤×٥٠٠، ولقطات شاشة. | Play مش بيقبل نشر بدون أيقونة وفيتشر جرافيك، ولقطتين على الأقل. | الأيقونة والفيتشر جرافيك جاهزين في `marketing/play/`. اللقطات محتاجة جهاز/محاكي شغال وحساب تاجر تجريبي. |
| ٩ | **رقم واتساب الدعم**. | طلبات حذف الحساب بتوصل عليه، وهو منشور في سياسة الخصوصية. | `01032210681` شغال كـ fallback. تأكد إنه الرقم الصح أو ابعت رقم تاني. |
| ١٠ | **تأكيد بيانات المسؤول في سياسة الخصوصية**. | مكتوب: محمد رمضان — Mohamed Ramadan، إدكو، البحيرة، مصر. | أكد إن ده الاسم والعنوان الصح. |
| ١١ | **تأكيد إن application IDs نهائية**. | بعد أول نشر مش ينفع تتغير. | `com.luqma.customer` و `com.luqma.merchant`. |
| ١٢ | **حساب تاجر تجريبي**: نستخدم مطعم حقيقي موجود ولا ننشئ محل تجريبي؟ | لقطات الشريك ومراجعة Google محتاجة محل بمنيو. استخدام محل حقيقي بيعرض بياناته وأرقامه للمراجع. | **محل تجريبي** في مدينة منفصلة أو مقفول، عشان ميظهرش لعملاء إدكو. ده برضه كتابة إنتاج ومحتاج موافقة. |

---

## ٢. خطوات الرفع في Play Console

### أ. إنشاء التطبيقين

1. **Create app**.
2. App name: من `listing-copy.md`.
3. Default language: **Arabic**.
4. App or game: **App**.
5. Free or paid: **Free**.
6. Accept the declarations.

### ب. Store listing — العميل

- **App name**: `لقمة — أكل البلد وأكل البيت`
- **Short description**: `اطلب من مطاعم إدكو وأكل البيت، وتابع طلبك لحد باب البيت.`
- **Full description**: من `listing-copy.md`.
- **App icon**: `marketing/play/app_icon_512.png` (512×512 RGBA، جاهزة).
- **Feature graphic**: `marketing/play/feature-customer.png` (١٠٢٤×٥٠٠).
- **Phone screenshots**: ٢–٨ لقطات، ١٠٨٠×١٩٢٠ مستحسن.
- **Category**: Food & Drink.
- **Contact email**: `ibugza@gmail.com`.
- **Website**: `https://luqma-gules.vercel.app` (بيحوّل لصفحة الخصوصية).
- **Privacy policy**: `https://luqma-gules.vercel.app/privacy`.
- **Data deletion**: `https://luqma-gules.vercel.app/privacy/delete`.

### ج. Store listing — الشريك

- **App name**: `لقمة شريك — إدارة المطعم`
- **Short description**: `استقبل طلبات مطعمك، حدّث المنيو، وتابع التحصيل والأرباح.`
- **Full description**: من `listing-copy.md`.
- **App icon**: نفس الأيقونة.
- **Feature graphic**: `marketing/play/feature-merchant.png`.
- **Phone screenshots**: ٢–٨ لقطات.
- **Category**: Business.
- **Contact email**: `ibugza@gmail.com`.
- **Website**: `https://luqma-gules.vercel.app`.
- **Privacy policy**: `https://luqma-gules.vercel.app/privacy/partner`.
- **Data deletion**: `https://luqma-gules.vercel.app/privacy/partner/delete`.

### د. App content (لكل تطبيق)

- **Privacy policy**: الرابط الخاص بكل تطبيق.
- **Ads**: No.
- **App access**: من `review-access.md`، وبيحتاج بيانات الدخول التجريبية.
- **Content rating**: من `content-rating.md`.
- **Target audience**: ١٨+ (مقترح).
- **News app**: No.
- **COVID-19 contact tracing**: No.
- **Government app**: No.
- **Financial features**: No (تطبيق الشريك بيسجل تحصيل كاش، لكنه مش خدمة مالية).
- **Health**: No.
- **Data safety**: من `data-safety.md`.
- **Data deletion**: Yes، والرابط العام موجود.
- **Play App Signing**: استخدم المفتاح الحالي، وارفع `signing/luqma-release.jks` مع alias وpasswords من `signing/key.properties` في شاشة Play Console. متبعتهمش في الشات.

### هـ. الاختبار المغلق والإنتاج

1. **Closed testing ← Create track**.
2. ارفع `build/aab/luqma-customer.aab` و `build/aab/luqma-merchant.aab`.
3. أضف ١٢ تستر لو الحساب فردي (شرط Play)، أو ٢ على الأقل لو الحساب مؤسسة.
4. ابعت رابط الاختبار للتسترين.
5. خلي التطبيق متثبت ١٤ يوم متواصلة (شرط الحساب الفردي).
6. بعد ١٤ يوم: **Production ← Apply for production access**.
7. جاوب على أسئلة Play عن التسترات والتغذية الراجعة، واذكر إن التطبيق بيخدم مطاعم ومطابخ إدكو.

---

## ٣. ملفات الحزمة

| الملف | المحتوى |
|---|---|
| `listing-copy.md` | اسم التطبيق، الوصف القصير والطويل، release notes، الحقول. |
| `data-safety.md` | إجابات Data safety لكل تطبيق، وشرح الاحتفاظ. |
| `review-access.md` | تعليمات المراجعة بالإنجليزي، وplaceholders للحسابات. |
| `content-rating.md` | استبيان IARC والفئة المستهدفة. |
| `screenshots.md` | قائمة اللقطات المطلوبة وطريقة التقاطها. |
| `marketing/play/` | الأيقونة والفيتشر جرافيك. |

---

## ٤. ملاحظات حرجة

- **مفيش نشر إنتاج ولا كتابة على قاعدة بيانات الإنتاج قبل موافقة صريحة.** الحسابات التجريبية والمحل التجريبي بيتعملوا بموافقة منفصلة.
- **AAB الشريك اتبنى من جديد** بعد إصلاح مسار حذف الحساب في شاشة الانتظار: النسخة `1.0.0+30`، arm64-v8a، وموقعة بنفس مفتاح الإصدار. باقي تشغيل CI على آخر commit.
- **CI artifacts مش صالحة للنشر** لأنها debug-signed. اللي بيترفع هو AABs الموقعة محليًا.
- **`support_whatsapp` فاضي حاليًا**، والكود بيرجع لـ `01032210681`. لو عايز رقم تاني، قوله قبل النشر.
- **كل حسابات المراجعة لازم تكون phone/email + password**، بدون OTP أو 2FA، وتشتغل من أي مكان.
- **AdminApp مش هيتحط في Play Console** ولا هيتم رفعه.
