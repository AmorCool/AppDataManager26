# AppData Manager - Update & Release Workflow

## دليل تحديث ورفع ومزامنة الأداة

### ملخص سريع
```
1. عدّل الكود ← 2. ارفع commit ← 3. Actions يبني تلقائياً ← 4. تحقق من gh-pages ← 5. اختبر في سيلو
```

### الخطوات بالتفصيل

**1. تعديل الكود المصدري**
- عدّل الملفات في المستودع
- لا تنسَ تحديث `control` (الإصدار الجديد)
- لا تنسَ تحديث `SettingsViewController.m` (رقم الإصدار)
- لا تنسَ تحديث `postinst` (رقم الإصدار)

**2. رفع التعديلات**
```bash
git add .
git commit -m "vX.Y.Z: وصف التحديث"
git push origin main
```

**3. انتظر البناء التلقائي**
- GitHub Actions يشتغل تلقائياً عند كل push
- مدة البناء: ~2-3 دقائق
- رابط المتابعة: `https://github.com/aosaid3224-ops/AppDataManager/actions`

**4. اختبر في سيلو**
1. افتح Sileo
2. اذهب إلى Sources → aosaid3224 Repo
3. اضغط Refresh
4. اضغط Upgrade

### هيكل المستودعات
```
AppDataManager/          ← السورس + البناء
├── .github/workflows/   ← GitHub Actions
├── *.m, *.h            ← ملفات Objective-C
├── control              ← إصدار الحزمة
├── Makefile             ← إعدادات Theos
└── gh-pages/           ← الـ .deb المنشأ (تلقائي)
```

---

*آخر تحديث: 2026-08-10 | الإصدار: 1.0.0*
