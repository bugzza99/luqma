# App access — تعليمات مراجعة Google Play

Play Console بيطلب تعليمات بالإنجليزي، وقابلة لإعادة الاستخدام، وبدون OTP أو 2FA. دي المسودات. **الأرقام وكلمات السر لازم تتغير قبل الرفع.**

---

## تطبيق العميل — `com.luqma.customer`

### App access

Select: **All or some functionality is restricted**

### Instructions (English)

```
Most of the app is available without signing in: you can browse the home page, shops, menus, and item details.

To review the signed-in experience, order history, privacy policy, and account deletion, sign in with the demo customer account:

Phone: <CUSTOMER_DEMO_PHONE>
Password: <CUSTOMER_DEMO_PASSWORD>

Sign-in screen: open the app, tap the "حسابي" (Account) tab, enter the phone number and password, then tap "دخول" (Sign in).

Account deletion: "حسابي" (Account) tab → "حذف الحساب نهائيًا" (Delete account permanently) → "احذف حسابي" (Delete my account).

Privacy policy: "حسابي" (Account) tab → "سياسة الخصوصية" (Privacy policy).

The demo account has no real orders and is not linked to a real customer. Please do not place an order at a real shop; it would notify a real merchant. If you need to test the order flow, use the demo shop described below.

Demo shop (if provided): <DEMO_SHOP_NAME>
```

### ملاحظات

- لو مفيش حساب عميل تجريبي، Play هتقدر تتفرج على التطبيق بدون تسجيل، لكن مش هتقدر تجرب حذف الحساب أو سجل الطلبات. ده غالبًا هيأخر المراجعة.
- لو العميل التجريبي عنده أوردرات تجريبية، اذكرها: «The account has two sample orders in the demo shop.»
- **متكتبش** كلمة سر حقيقية في المستند ده. استخدم placeholders، وحط القيم في Play Console بس.

---

## تطبيق الشريك — `com.luqma.merchant`

### App access

Select: **All functionality is restricted**

### Instructions (English)

```
The app requires an account. Use the demo merchant owner account:

Phone or email: <MERCHANT_DEMO_LOGIN>
Password: <MERCHANT_DEMO_PASSWORD>

Sign-in screen: enter the phone/email and password, then tap "دخول" (Sign in).

After sign-in, the app opens the orders inbox ("الطلبات"). Depending on the shop type, the bottom tabs are:
- "الطلبات" (Orders): incoming and live orders.
- "المنيو" (Menu): categories, items, prices, and photos — for a restaurant.
- "الوجبات" (Daily meals): the same idea for a home kitchen.
- "المحل" (Shop): opening hours, busy toggle, subscription, privacy, and account deletion.

Privacy policy and account deletion:
"المحل" (Shop) tab → "الخصوصية والحساب" (Privacy and account) → "سياسة الخصوصية" (Privacy policy) or "طلب حذف الحساب" (Request account deletion).

The demo shop is <DEMO_SHOP_NAME>. It is a review-only shop; orders placed there are not fulfilled by a real merchant.

Courier demo (optional):
Phone or email: <COURIER_DEMO_LOGIN>
Password: <COURIER_DEMO_PASSWORD>
The courier account opens the delivery screen directly.
```

### ملاحظات

- **لازم** يكون فيه محل تجريبي بمنيو. من غير محل، حساب صاحب المطعم هيدخل على شاشة «الحساب لسه مش مفعّل» ومش هتشوف الوظائف.
- لو مش هتقدم حساب مندوب، اكتب: «Courier mode is not included in this review account; the merchant owner account covers the core business features.» لكن الأفضل تقدم مندوب.
- **متكتبش** بيانات حقيقية لمحل شغال. استخدم محل تجريبي.
- الحساب لازم يشتغل من أي دولة، وبدون OTP. الحسابات الحالية phone/password، فده متحقق.

---

## أسئلة Play Console عن الوصول

| السؤال | الإجابة |
|---|---|
| Does your app have any functionality that is restricted? | **Yes** (الشريك) / **Some** (العميل) |
| Do reviewers need a username/password? | **Yes** |
| Are there any other instructions? | الصق النص الإنجليزي فوق |
| Does your app use 2FA/OTP? | **No** |
| Does the account expire? | **No** — الحساب دائم ومخصص للمراجعة |

---

## قبل الرفع

- [ ] الحسابات التجريبية معمولة ومتأكد إنها بتدخل من جهاز نظيف.
- [ ] كلمات السر مش منتهية، ومش محتاجة تغيير إجباري.
- [ ] الحساب مش مربوط برقم حقيقي لعميل، ومفيهوش أوردرات حقيقية.
- [ ] المحل التجريبي ظاهر في تطبيق الشريك، وفيه منيو وأصناف.
- [ ] لو المحل التجريبي هيظهر في تطبيق العميل، اتأكد إنه مش بيقبل أوردرات حقيقية أو إنه في مدينة منفصلة.
- [ ] التعليمات مكتوبة بالإنجليزي، والأسماء العربية بين قوسين.
