# متصفح وهم (WahmCookieBrowser)

متصفح iOS مستقل الأقسام، يدعم تسجيل الدخول عبر لصق الكوكيز/الجلسة لأي موقع.

- اسم العرض: **متصفح وهم**
- المعرّف: `com.wahm.cookiebrowser`
- يتطلب iOS 17 أو أحدث
- بدون مكتبات خارجية

## التحميل

ملف IPA غير موقّع (رابط مباشر):

**https://github.com/wahm8576-glitch/cookie-browser-ios/releases/download/unsigned-latest/WahmCookieBrowser.ipa**

وقّع الملف بنفسك عبر Esign أو Sideloadly أو AltStore ثم ثبّته على جهازك.

## الفكرة

1. افتح قسماً (كل قسم جلسة معزولة بالكامل عن الأقسام الأخرى).
2. اكتب رابط أي موقع في شريط العنوان.
3. اضغط **تسجيل عبر كوكيز**.
4. الصق نص الكوكيز. التطبيق يدعم صيغتين:
   - ترويسة Cookie: `name=value; name2=value2; ...`
   - تصدير متعدد الأسطر:

     ```
     sessionid = ......
         domain=.tiktok.com  path=/  secure=yes  httpOnly=yes  expires=2026-11-22 11:19:32 م +0000
     ```

5. يتم حقن الكوكيز في مخزن `WKWebView` الخاص بذلك القسم ثم يُعاد فتح الموقع وكأنك مسجّل دخولاً عادياً.

الجلسات والكوكيز تُحفظ بعد إغلاق التطبيق: قائمة الأقسام تُحفظ في UserDefaults، وكل قسم يستخدم `WKWebsiteDataStore(forIdentifier:)` بهوية ثابتة.

## البناء محلياً (اختياري)

على جهاز macOS مع Xcode 15+:

```sh
brew install xcodegen   # اختياري إذا أردت إعادة توليد المشروع
xcodegen generate
open WahmCookieBrowser.xcodeproj
```

المشروع معدّ بدون توقيع (`CODE_SIGNING_ALLOWED=NO`) ليوافق بناء IPA غير موقّع. إذا أردت البناء من Xcode على جهازك، اختر فريق التوقيع الخاص بك من إعدادات الهدف.

## الترخيص

استخدام شخصي. أنت مسؤول عن استخدام الكوكيز الخاصة بحساباتك فقط.
