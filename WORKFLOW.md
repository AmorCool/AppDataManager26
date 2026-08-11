# دليل المطور — AppDataManager / IPA Installer Pro

> **الإصدار:** 2.0
> **التاريخ:** 2026-08-11
> **المؤلف:** ZAIN (@Zainqkvd)
> **البيئة:** Dopamine 3.0 (Rootless) | iOS 15.0+ | arm64/arm64e

---

## 📁 هيكل المستودع

يحتوي الريبو على **أداتين منفصلتين** بنفس المستودع:

```
AppDataManager/
├── AppDataManager/ ← الأداة الأولى (مكتملة ومستقرة)
│   ├── Core/
│   ├── UI/
│   ├── Makefile
│   └── control
│
├── IPAInstallerPro/ ← الأداة الثانية (قيد التطوير)
│   ├── Core/ ← محركات التثبيت + التحقق
│   ├── UI/ ← واجهات المستخدم
│   ├── Resources/
│   ├── Makefile
│   ├── control
│   └── entitlements.plist
│
├── scripts/
│   ├── generate-repo.py ← توليد Packages & Release
│   └── validate-repo.py ← التحقق من سلامة الريبو
│
├── .github/workflows/
│   └── sync-to-repo.yml ← CI/CD تلقائي
│
├── Makefile ← بناء الأداتين معاً
├── build.sh ← سكربت البناء المحلي
└── WORKFLOW.md ← هذا الملف
```

---

## 🏛️ نظام الريبو المزدوج (Repo Architecture)

| الريبو | الرابط | الغرض | الجمهور |
|--------|--------|-------|---------|
| **الريبو الرئيسي** | `https://aosaid3224-ops.github.io/repo/` | الإطلاق العام (Production) | **جميع المستخدمين** |
| **ريبو التطوير** | `https://aosaid3224-ops.github.io/repo-dev/` | التطوير والاختبار (Dev) | **المطور فقط** |

### ⚠️ قاعدة ذهبية

> **أثناء التطوير** → ارفع إلى `repo-dev`  
> **عند اكتمال النسخة** → ارفع إلى `repo` الرئيسي  
> **لا ترفع أبداً** نسخ غير مكتملة إلى الريبو الرئيسي.

### 🔧 كيفية التبديل بين الريبوين

#### أثناء التطوير (repo-dev)
```python
# 1. بناء IPA Installer Pro
make clean && make package -C IPAInstallerPro/

# 2. رفع .deb إلى repo-dev
# الملفات تُرفع تلقائياً إلى:
# https://github.com/aosaid3224-ops/repo-dev
```

#### عند الإطلاق (repo)
```python
# 1. تأكد من أن الإصدار نهائي ومستقر
# 2. ارفع .deb إلى repo الرئيسي
# 3. حدث Packages و Release في repo الرئيسي
```

### 📱 في Sileo

**المستخدمون العاديون:**
- يضيفون فقط: `https://aosaid3224-ops.github.io/repo/`
- يرون: AppData Manager فقط ✅

**المطور (أنت):**
- تضيف المصدر الرئيسي: `https://aosaid3224-ops.github.io/repo/`
- **وتضيف أيضاً:** `https://aosaid3224-ops.github.io/repo-dev/`
- ترى: AppData Manager + IPA Installer Pro ✅

---

## ⚙️ مبدأ العمل (CI/CD Pipeline)

```
[تعديل الكود] → [Commit] → [GitHub Actions] → [.deb] → [Repo] → [Sileo]
```

### 1. GitHub Actions Workflow (`sync-to-repo.yml`)

```yaml
name: Build & Sync to Repo
on:
  workflow_dispatch: ← يدوي فقط
jobs:
  build-and-sync:
    runs-on: macos-latest
    steps:
      - Checkout
      - Setup Theos
      - Build AppDataManager
      - Build IPAInstallerPro
      - Copy .deb → repo/pool/ (للريبو الرئيسي)
      - Copy .deb → repo-dev/pool/ (للريبو التطويري)
      - Run generate-repo.py
      - Push إلى repo + repo-dev
```

### 2. المزامنة التلقائية

عندما ينجح البناء:
1. ينسخ الـ `.deb` الجديد إلى `repo/pool/main/iphoneos-arm64/` (للإطلاق)
2. ينسخ الـ `.deb` الجديد إلى `repo-dev/pool/main/iphoneos-arm64/` (للتطوير)
3. يشغل `generate-repo.py` لتحديث `Packages` و `Release` في كلا الريبوين
4. **GitHub Pages** ينشر التغييرات خلال 30-60 ثانية
5. **Sileo** يكتشف الترقية فور **Refresh**

---

## 🔧 كيفية إصلاح خطأ بناء (Build Fix)

### الخطوة 1: قراءة اللوغات

افتح الرابط:
```
https://github.com/aosaid3224-ops/AppDataManager/actions
```

اضغط على الـ Run الفاشل → **"Build IPA Installer Pro"** → ابحث عن `error:`

### الخطوة 2: التعديل عبر GitHub API (Python)

```python
import requests, base64

TOKEN = "ghp_..."
HEADERS = {"Authorization": f"token {TOKEN}"}
REPO = "aosaid3224-ops/AppDataManager"

# 1. احصل على SHA الحالي
r = requests.get(
    f"https://api.github.com/repos/{REPO}/contents/{path}?ref=main",
    headers=HEADERS
)
sha = r.json()['sha']

# 2. ارسل التعديل
payload = {
    "message": message,
    "content": base64.b64encode(content.encode()).decode(),
    "sha": sha,
    "branch": "main"
}
requests.put(
    f"https://api.github.com/repos/{REPO}/contents/{path}",
    headers=HEADERS,
    json=payload
)
```

### الخطوة 3: تشغيل البناء

```python
# تشغيل Workflow يدوياً
requests.post(
    f"https://api.github.com/repos/{REPO}/actions/workflows/sync-to-repo.yml/dispatches",
    headers=HEADERS,
    json={"ref": "main"}
)
```

### الخطوة 4: التحقق من النجاح

```python
import time
time.sleep(60)

r = requests.get(
    f"https://api.github.com/repos/{REPO}/actions/runs?per_page=1",
    headers=HEADERS
)
run = r.json()['workflow_runs'][0]
print(run['conclusion'])  # "success" أو "failure"
```

---

## 📦 كيفية رفع إصدار جديد (Version Bump)

### أثناء التطوير (repo-dev)

```python
# 1. تعديل control
update_file(
    "IPAInstallerPro/control",
    new_control_content,
    "Bump IPA Installer Pro dev version to 1.0.5"
)

# 2. رفع إلى repo-dev
# يدوياً أو عبر CI/CD
```

### عند الإطلاق (repo)

```python
# 1. تأكد من الاستقرار
# 2. تعديل control
update_file(
    "IPAInstallerPro/control",
    new_control_content,
    "Release IPA Installer Pro v1.0.5"
)

# 3. شغل Workflow للريبو الرئيسي
requests.post(
    f"https://api.github.com/repos/{REPO}/actions/workflows/sync-to-repo.yml/dispatches",
    headers=HEADERS,
    json={"ref": "main"}
)
```

### النتيجة في Sileo

بعد 2-3 دقائق:
```
IPA Installer Pro
الإصدار المثبت: 1.0.4
الإصدار الجديد: 1.0.5
زر: ⬆️ Upgrade
```

---

## 🐛 قائمة الأخطاء الشائعة وحلولها

| الخطأ | السبب | الحل |
|-------|-------|------|
| `no known class method for selector 'successResult:bundleID:'` | Method غير موجود | استخدم `successResult:` ثم `result.bundleID = ...` |
| `use of undeclared identifier 'NSTask'` | NSTask غير موجود في iOS | استبدل بـ `posix_spawn()` |
| `ld: symbol(s) not found` | ملف `.m` ناقص من Makefile | أضف الملف لـ `*_FILES` |
| `implicit declaration of function 'objc_getClass'` | ناقص `#import <objc/runtime.h>` | أضف الـ import |
| `variable 'x' set but not used` | متغير غير مستخدم | احذف المتغير أو استخدمه |
| الملف ليس بصيغة ZIP صالحة | نسخ الملف فاشل (security-scoped) | استخدم `NSFileCoordinator` |
| لا يوجد ملفات IPA بعد الاستيراد | المجلد `IPAInstaller` غير موجود في `loadIPAFiles` | أضف `/var/mobile/Documents/IPAInstaller` للبحث |

---

## 🏗️ قواعد التطوير

### 1. Rootless Support

**دائماً** استخدم `RootlessManager` للمسارات:

```objc
// ❌ خطأ:
const char *path = "/usr/bin/uicache";

// ✅ صح:
NSString *pathStr = [[RootlessManager sharedManager] resolvePath:@"/usr/bin/uicache"];
const char *path = [pathStr UTF8String];
```

### 2. Private APIs (LSApplicationWorkspace)

استخدم `objc_msgSend` مع cast:

```objc
#import <objc/runtime.h>
#import <objc/message.h>

SEL installSel = NSSelectorFromString(@"installApplication:withOptions:error:");
typedef BOOL (*InstallMethod)(id, SEL, NSURL *, NSDictionary *, NSError **);
InstallMethod method = (InstallMethod)objc_msgSend;
BOOL installed = method(workspace, installSel, ipaURL, options, &error);
```

### 3. File Import (Files App)

استخدم `NSFileCoordinator` دائماً:

```objc
NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
[coordinator coordinateReadingItemAtURL:url
                                options:NSFileCoordinatorReadingForUploading
                                  error:nil
                             byAccessor:^(NSURL *newURL) {
    [fm copyItemAtPath:newURL.path toPath:destPath error:&error];
}];
```

### 4. Null Safety

```objc
// ❌ خطأ:
cell.textLabel.text = info.displayName ?: info.name;

// ✅ صح:
cell.textLabel.text = info.displayName ?: info.name ?: [info.filePath lastPathComponent];
```

---

## 📞 دعم

- **GitHub Issues:** [github.com/aosaid3224-ops/AppDataManager/issues](https://github.com/aosaid3224-ops/AppDataManager/issues)
- **X:** @Zainqkvd

---

**تم التطوير بـ ❤️ لمجتمع Jailbreak العربي**
