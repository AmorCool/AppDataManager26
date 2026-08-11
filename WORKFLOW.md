# دليل المطور — AppDataManager / IPA Installer Pro

> **الإصدار:** 2.1
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
│   ├── sync-to-repo.yml ← CI/CD تلقائي → repo-dev
│   └── release-to-production.yml ← CI/CD يدوي → repo
│
├── Makefile ← بناء الأداتين معاً
├── build.sh ← سكربت البناء المحلي
└── WORKFLOW.md ← هذا الملف
```

---

## 🏛️ نظام الريبو المزدوج (Repo Architecture)

| الريبو | الرابط | الغرض | الجمهور | طريقة الرفع |
|--------|--------|-------|---------|-------------|
| **الريبو الرئيسي** | `https://aosaid3224-ops.github.io/repo/` | الإطلاق العام (Production) | **جميع المستخدمين** | **يدوي فقط** |
| **ريبو التطوير** | `https://aosaid3224-ops.github.io/repo-dev/` | التطوير والاختبار (Dev) | **المطور فقط** | **تلقائي** |

### ⚠️ قاعدة ذهبية

> **أثناء التطوير** → ارفع إلى `repo-dev` (تلقائي)  
> **عند اكتمال النسخة** → ارفع إلى `repo` الرئيسي (يدوي)  
> **لا ترفع أبداً** نسخ غير مكتملة إلى الريبو الرئيسي.

### 🔧 كيفية التبديل بين الريبوين

#### أثناء التطوير (repo-dev) — تلقائي
```
[Commit] → [GitHub Actions: sync-to-repo.yml] → [repo-dev] → [Sileo]
```

#### عند الإطلاق (repo) — يدوي
```
[GitHub Actions: release-to-production.yml] → [YES] → [repo] → [Sileo]
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

## ⚙️ CI/CD Pipeline

### 1. البناء التلقائي → repo-dev (التطوير)

**Workflow:** `sync-to-repo.yml`

```yaml
Trigger: workflow_dispatch (يدوي من GitHub Actions)
Target:  aosaid3224-ops/repo-dev
Result:  IPA Installer Pro يظهر فقط في repo-dev
```

**الخطوات:**
1. Checkout AppDataManager + repo-dev
2. Setup Theos + dependencies
3. Build IPA Installer Pro
4. Copy .deb → repo-dev/pool/
5. Run `generate-repo.py . --dev`
6. Push to repo-dev

**كيفية التشغيل:**
```
GitHub → Actions → "Build IPA Installer Pro and Sync to Dev Repo" → Run workflow
```

### 2. الإطلاق اليدوي → repo (الإنتاج)

**Workflow:** `release-to-production.yml`

```yaml
Trigger: workflow_dispatch + confirmation YES
Target:  aosaid3224-ops/repo
Result:  IPA Installer Pro يظهر في الريبو الرئيسي
```

**الخطوات:**
1. يطلب إدخال: `version` + `confirm: YES`
2. Checkout AppDataManager + repo
3. Build IPA Installer Pro
4. Copy .deb → repo/pool/
5. Run `generate-repo.py . --prod`
6. Push to repo

**كيفية التشغيل:**
```
GitHub → Actions → "Release to Production Repo" → Run workflow
→ أدخل الإصدار (مثلاً: 1.0.5)
→ اكتب YES في حقل التأكيد
→ Run
```

### 3. generate-repo.py — التوليد الذكي

```bash
# للتطوير (repo-dev)
python3 scripts/generate-repo.py . --dev
# ينشئ Packages + Release مع بيانات "A-ZAIN Dev Repo"

# للإنتاج (repo)
python3 scripts/generate-repo.py . --prod
# ينشئ Packages + Release مع بيانات "A-ZAIN Repo"
```

---

## 🔧 كيفية إصلاح خطأ بناء (Build Fix)

### الخطوة 1: قراءة اللوغات

افتح الرابط:
```
https://github.com/aosaid3224-ops/AppDataManager/actions
```

اضغط على الـ Run الفاشل → **"Build IPA Installer Pro and Sync to Dev Repo"** → ابحث عن `error:`

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

### الخطوة 3: تشغيل البناء التلقائي (repo-dev)

```python
# تشغيل Workflow التلقائي (repo-dev)
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

### أثناء التطوير (repo-dev) — تلقائي

```python
# 1. تعديل control
update_file(
    "IPAInstallerPro/control",
    new_control_content,
    "Bump IPA Installer Pro dev version to 1.0.5"
)

# 2. شغل Workflow التلقائي (repo-dev)
requests.post(
    f"https://api.github.com/repos/{REPO}/actions/workflows/sync-to-repo.yml/dispatches",
    headers=HEADERS,
    json={"ref": "main"}
)
```

### عند الإطلاق (repo) — يدوي

```python
# 1. تأكد من الاستقرار والاختبار في repo-dev
# 2. اذهب إلى GitHub Actions → "Release to Production Repo"
# 3. اضغط "Run workflow"
# 4. أدخل الإصدار (مثلاً: 1.0.5)
# 5. اكتب YES في حقل التأكيد
# 6. اضغط Run
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
