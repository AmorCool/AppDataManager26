# 🔄 AppData Manager - Update & Release Workflow
# دليل تحديث ورفع ومزامنة الأداة

> **للمطورين:** هذا الملف المرجعي يوضح خطوات التحديث من A إلى Z

---

## 📋 ملخص سريع (Quick Reference)

```
1. عدّل الكود ← 2. ارفع commit ← 3. Actions يبني تلقائياً ← 4. حمّل .deb من gh-pages ← 5. زامن repo
```

---

## 🔧 الخطوات بالتفصيل

### الخطوة 1: تعديل الكود المصدري
- عدّل الملفات في هذا المستودع (`AppDataManager`)
- لا تنسَ تحديث `control` (الإصدار الجديد)
- لا تنسَ تحديث `SettingsViewController.m` (رقم الإصدار إن وُجد)

### الخطوة 2: رفع التعديلات
```bash
git add .
git commit -m "vX.Y.Z: وصف التحديث"
git push origin main
```

### الخطوة 3: انتظر البناء التلقائي
- GitHub Actions يشتغل تلقائياً عند كل push
- يبني الـ `.deb` وينشره على فرع `gh-pages`
- مدة البناء: ~2-3 دقائق
- رابط المتابعة: `https://github.com/aosaid3224-ops/AppDataManager/actions`

### الخطوة 4: استخراج الـ .deb
```bash
# من gh-pages branch
wget https://raw.githubusercontent.com/aosaid3224-ops/AppDataManager/gh-pages/pool/main/iphoneos-arm64/com.aosaid.appdatamgr_X.Y.Z_iphoneos-arm64.deb

# أو حمّله يدوياً من صفحة Actions → Artifacts
```

### الخطوة 5: مزامنة الريبو الخارجي (`repo`)
```bash
cd ~/repo  # مسار مستودع الريبو الخارجي

# 1. انسخ الـ .deb الجديد
cp com.aosaid.appdatamgr_X.Y.Z_iphoneos-arm64.deb pool/main/iphoneos-arm64/

# 2. حدّث Packages
dpkg-scanpackages -m pool/main/iphoneos-arm64 > Packages
gzip -k -f Packages
bzip2 -k -f Packages
xz -k -f Packages

# 3. حدّث Release (MD5/SHA256)
# استخدم سكربت update_repo.sh إن وُجد

# 4. ارفع
./update_repo.sh
# أو
```

```bash
git add .
git commit -m "vX.Y.Z: وصف التحديث"
git push origin main
```

### الخطوة 6: اختبر في سيلو
1. افتح **Sileo**
2. اذهب إلى **Sources** → **aosaid3224 Repo**
3. اضغط **Refresh**
4. اضغط **Upgrade**
5. تأكد أن التثبيت يكتمل بدون تعليق

---

## ⚠️ ملاحظات مهمة

| الملاحظة | التوضيح |
|----------|---------|
| **لا تعدّل `repo` يدوياً** | الريبو الخارجي يُحدّث فقط بعد نجاح البناء |
| **تحقق من الإصدار الداخلي** | `dpkg-deb -f file.deb Version` يجب يطابق `control` |
| **لا تحذف إصدارات قديمة** | اتركها في `pool/` للتوافق |
| **الـ Token** | يحتاج `repo` access لرفع الملفات تلقائياً |

---

## 🏗️ هيكل المستودعات

```
AppDataManager/          ← السورس + البناء
├── .github/workflows/   ← GitHub Actions (build.yml)
├── *.m, *.h            ← ملفات Objective-C
├── control              ← إصدار الحزمة
├── Makefile             ← إعدادات Theos
└── gh-pages/           ← الـ .deb المنشأ (تلقائي)

repo/                    ← الريبو الخارجي (ما يشوفه سيلو)
├── pool/main/iphoneos-arm64/  ← ملفات .deb
├── Packages, Packages.gz      ← فهرس الحزم
├── Release                    ← معلومات الريبو
└── index.html                 ← واجهة الويب
```

---

## 🚀 GitHub Actions Workflow

```yaml
# .github/workflows/build.yml
# 1. يثبّت Theos
# 2. يبني التطبيق (make package)
# 3. ينشر الـ .deb إلى gh-pages
# 4. يُنشئ artifact للتحميل
```

---

## 📞 للمساعدة

- **مطور:** ZAIN
- **تويتر:** @Zainqkvd

---

*آخر تحديث: 2026-08-09*
