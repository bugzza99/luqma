# Data safety — إجابات Play Console

دي الإجابات المقترحة، مبنية على الكود والسياسات المنشورة. أي تغيير في الكود أو في مزودي الخدمة لازم يتنعكس هنا قبل الرفع.

## قواعد عامة

- **Collected** = البيانات بتطلع من الجهاز. كل حاجة بتتبعت لـ Supabase أو Sentry أو Google بتتحسب Collected.
- **Shared** = البيانات بتتنقل لطرف تالت مش Service Provider. Supabase وSentry وFirebase بيعالجوا البيانات نيابة عننا، فمش بنعلنهم كـ Sharing. Google Gemini بياخد رسايل «زعتر» وممكن يستخدمها لتحسين خدماته حسب سياسة الخصوصية، فبنعلنها Shared.
- **Service providers**: Supabase (قاعدة البيانات والتخزين)، Sentry (الأعطال)، Firebase Cloud Messaging (الإشعارات). كلهم معالجين بالنيابة عن لقمة.
- **مفيش**: إعلانات، تتبع عبر التطبيقات، بيع بيانات، جمع جهات اتصال، موقع GPS، كاميرا/صور للعميل، دفع إلكتروني.

---

## تطبيق العميل — `com.luqma.customer`

### الإجابات العامة

| السؤال | الإجابة |
|---|---|
| Does your app collect or share any of the required user data types? | **Yes** |
| Is all of the user data collected by your app encrypted in transit? | **Yes** |
| Do you provide a way for users to request that their data be deleted? | **Yes** |
| Do you delete all user data upon request? | **No** — راجع الشرح تحت |
| Data deletion URL | `https://luqma-gules.vercel.app/privacy/delete` |
| Does your app allow users to create an account? | **Yes** |
| Account creation method | Phone number + password (the app maps the phone to an internal account address; the user never sees an email) |

**شرح «Do you delete all user data upon request?»:**

> بنحذف الحساب والبروفايل والعناوين والتقييمات والتعليقات والشكاوى ورموز الأجهزة وبيانات الدخول. سجلات الأوردرات والمدفوعات بتفضل بدون الاسم أو رقم الموبايل أو العنوان، لأغراض المحاسبة والالتزامات القانونية. التفاصيل في صفحة الحذف.

### البيانات

| Data type | Collected | Shared | Purpose | Required / Optional | Notes |
|---|---|---|---|---|---|
| Personal info → Name | Yes | Yes | App functionality, Account management | Required | الاسم بيظهر للمطعم/المندوب عشان يعرفوا الأوردر لمين. |
| Personal info → Phone number | Yes | Yes | App functionality, Account management | Required | رقم الدخول، ورقم التواصل مع المندوب. |
| Personal info → Address | Yes | Yes | App functionality | Required | عنوان التوصيل بيتبعت للمطعم/المندوب. |
| Personal info → User IDs | Yes | No | Account management, App functionality | Required | معرّف الحساب الداخلي. |
| Personal info → Email address | No | — | — | — | العميل مش بيدخل إيميل. |
| Financial info → Purchase history | Yes | Yes | App functionality | Required | الأوردرات والأصناف والإجمالي. المطعم/المندوب بيشوفوا تفاصيل الأوردر. |
| Financial info → User payment info | No | — | — | — | الدفع كاش عند الاستلام، مفيش كارت أو محفظة. |
| Financial info → Other financial info | No | — | — | — | — |
| Messages → Other in-app messages | Yes | Yes | App functionality | Optional | رسايل «زعتر» بتتبعت لـ Supabase، ورسايل مش مفهومة محليًا بتتبعت لـ Google Gemini بعد حذف الأرقام والروابط والإيميلات. مش بتتخزن إلا لو اتحولت لشكوى. |
| Photos and videos → Photos | No | — | — | — | العميل مش بيرفع صور. |
| App activity → App interactions | Yes | No | Analytics, App functionality | Required | فتح التطبيق وأحداث الأوردر. |
| App activity → Other user-generated content | Yes | Yes | App functionality | Optional | التقييمات والتعليقات والشكاوى. المطعم/الإدارة بيشوفوها. |
| App info and performance → Crash logs | Yes | No | Analytics, App functionality | Required | Sentry. |
| App info and performance → Diagnostics | Yes | No | Analytics, App functionality | Required | Sentry performance traces بنسبة ١٠٪. |
| Device or other IDs → Device or other IDs | Yes | No | App functionality | Required | FCM token ومعرّف جهاز عشوائي ثابت. |
| Location | No | — | — | — | مفيش GPS ولا تحديد موقع. |
| Contacts | No | — | — | — | — |
| Health and fitness | No | — | — | — | — |
| Web browsing | No | — | — | — | — |
| Files and docs | No | — | — | — | — |
| Calendar | No | — | — | — | — |
| Audio | No | — | — | — | — |
| SMS / MMS | No | — | — | — | — |

---

## تطبيق الشريك — `com.luqma.merchant`

### الإجابات العامة

| السؤال | الإجابة |
|---|---|
| Does your app collect or share any of the required user data types? | **Yes** |
| Is all of the user data collected by your app encrypted in transit? | **Yes** |
| Do you provide a way for users to request that their data be deleted? | **Yes** |
| Do you delete all user data upon request? | **No** — راجع الشرح تحت |
| Data deletion URL | `https://luqma-gules.vercel.app/privacy/partner/delete` |
| Does your app allow users to create an account? | **Yes** — المتقدم بيعمل حساب قبل ما الإدارة توافق، والحساب مالوش صلاحيات لحد الموافقة. |
| Account creation method | Phone number + password (the app maps the phone to an internal account address; some staff accounts also sign in with an email) |

**شرح «Do you delete all user data upon request?»:**

> بنحذف حساب الدخول والبيانات الشخصية بعد مراجعة صاحب الحساب. سجلات الأوردرات والعمولة والتحصيل والمدفوعات بتفضل بدون الاسم أو رقم الموبايل، لأغراض المحاسبة والالتزامات القانونية. صور بطاقة المندوب بتتحذف بعد انتهاء مدة التحقق. التفاصيل في صفحة حذف حساب الشريك.

### البيانات

| Data type | Collected | Shared | Purpose | Required / Optional | Notes |
|---|---|---|---|---|---|
| Personal info → Name | Yes | Yes | App functionality, Account management | Required | اسم صاحب المحل/المندوب/العميل بيظهر للأطراف اللي ليها علاقة بالأوردر. |
| Personal info → Phone number | Yes | Yes | App functionality, Account management | Required | رقم دخول الشريك، ورقم المحل/المندوب/العميل في الأوردر. |
| Personal info → Email address | Yes | No | Account management | Optional | بعض حسابات الفريق بتدخل بالإيميل؛ مش كل الشراكات عندها إيميل. |
| Personal info → Address | Yes | Yes | App functionality | Required | عنوان المحل بيظهر للعملاء، وعنوان العميل بيظهر للمندوب/المحل. |
| Personal info → User IDs | Yes | No | Account management, App functionality | Required | معرّف الحساب الداخلي. |
| Financial info → Purchase history | Yes | No | App functionality, Account management | Required | أوردرات المحل ومبيعاته. |
| Financial info → Other financial info | Yes | No | App functionality, Account management | Required | التحصيل النقدي، العمولة، كشف الحساب، المدفوعات. مفيش بيانات كارت أو حساب بنكي. |
| Messages → Other in-app messages | Yes | Yes | App functionality | Optional | شكاوى العملاء ورسايل الدعم. |
| Photos and videos → Photos | Yes | Yes | App functionality | Required | صور المحل/المنيو (اختيارية) وصور بطاقة المندوب (مطلوبة للمندوبين). صور المحل/المنيو بتظهر للعملاء؛ صور البطاقة للإدارة فقط. |
| App activity → App interactions | Yes | No | Analytics, App functionality | Required | فتح التطبيق وأحداث الأوردر. |
| App activity → Other user-generated content | Yes | Yes | App functionality | Optional | التقييمات والتعليقات والشكاوى. |
| App info and performance → Crash logs | Yes | No | Analytics, App functionality | Required | Sentry. |
| App info and performance → Diagnostics | Yes | No | Analytics, App functionality | Required | Sentry performance traces بنسبة ١٠٪. |
| Device or other IDs → Device or other IDs | Yes | No | App functionality | Required | FCM token ومعرّف جهاز عشوائي ثابت. |
| Location | No | — | — | — | مفيش GPS ولا تحديد موقع. |
| Contacts | No | — | — | — | — |
| Health and fitness | No | — | — | — | — |
| Web browsing | No | — | — | — | — |
| Files and docs | No | — | — | — | — |
| Calendar | No | — | — | — | — |
| Audio | No | — | — | — | — |
| SMS / MMS | No | — | — | — | — |

---

## حاجات لازم تتأكد منها قبل ما تدوس Submit

- [ ] **Google Gemini**: سياسة الخصوصية بتقول إن جوجل ممكن تستخدم الرسايل لتحسين خدماتها. لو ده مش صحيح في خطتك المدفوعة، اشيل الجملة من السياسة ومن إجابة «Shared» أو عدّلها.
- [ ] **Sentry**: لو الـ DSN مش متظبط في build الإنتاج، مش بيتبعت أي حاجة. الـ AABs الحالية مبنية بـ DSN، فالإجابة «Yes» صح.
- [ ] **Firebase**: لو FCM مش شغال في build معين، برضه بنعلن Device IDs لأن الكود بيحاول يسجل التوكن. الأفضل نعلنها على مستوى التطبيق كله.
- [ ] **حذف الحساب**: صفحة العميل وصفحة الشريك شغالين بدون تسجيل دخول. راجعهم قبل Submit.
- [ ] **الاحتفاظ**: لو القانون المصري أو المحاسبة بتطلب مدة مختلفة عن ٣٠ يوم، عدّل النص في الصفحتين وفي الشرح هنا.
