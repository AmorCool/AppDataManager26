#import "IPAValidator.h"
#import "Logger.h"
#import "JailbreakEnvironment.h"

@implementation IPAValidationResult
@end

@interface IPAValidator ()
@end

@implementation IPAValidator

+ (instancetype)sharedValidator {
    static IPAValidator *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ shared = [[self alloc] init]; });
    return shared;
}

- (IPAValidationResult *)validateIPAAtPath:(NSString *)ipaPath {
    IPAValidationResult *result = [[IPAValidationResult alloc] init];
    NSMutableArray<NSString *> *issues = [NSMutableArray array];

    [[Logger sharedLogger] info:[NSString stringWithFormat:@"Validating IPA: %@", ipaPath]];

    // 1. Check file exists
    if (![[NSFileManager defaultManager] fileExistsAtPath:ipaPath]) {
        result.status = IPAValidationStatusInvalidZip;
        result.statusMessage = @"الملف غير موجود";
        result.issues = @[@"لم يتم العثور على ملف IPA في المسار المحدد"];
        result.isReadyForInstall = NO;
        return result;
    }

    // 2. Check it's a valid zip (IPA is a zip)
    NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath:ipaPath];
    if (!fh) {
        result.status = IPAValidationStatusInvalidZip;
        result.statusMessage = @"لا يمكن قراءة الملف";
        result.issues = @[@"فشل في فتح الملف للقراءة"];
        result.isReadyForInstall = NO;
        return result;
    }

    NSData *header = [fh readDataOfLength:4];
    [fh closeFile];

    if (header.length < 4) {
        result.status = IPAValidationStatusInvalidZip;
        result.statusMessage = @"ملف غير صالح";
        result.issues = @[@"الملف فارغ أو تالف"];
        result.isReadyForInstall = NO;
        return result;
    }

    // ZIP magic: 50 4B 03 04
    const unsigned char *bytes = (const unsigned char *)header.bytes;
    if (bytes[0] != 0x50 || bytes[1] != 0x4B || bytes[2] != 0x03 || bytes[3] != 0x04) {
        result.status = IPAValidationStatusInvalidZip;
        result.statusMessage = @"الملف ليس بصيغة ZIP صالحة";
        result.issues = @[@"ملف IPA يجب أن يكون أرشيف ZIP صالح"];
        result.isReadyForInstall = NO;
        return result;
    }

    // 3. Extract and validate deeper
    NSString *tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:tempDir withIntermediateDirectories:YES attributes:nil error:nil];

    // Unzip
    NSTask *unzipTask = [[NSTask alloc] init];
    unzipTask.launchPath = @"/usr/bin/unzip";
    unzipTask.arguments = @[@"-q", @"-o", ipaPath, @"-d", tempDir];
    @try {
        [unzipTask launch];
        [unzipTask waitUntilExit];
    } @catch (NSException *e) {
        [[Logger sharedLogger] error:[NSString stringWithFormat:@"Unzip failed: %@", e.reason]];
        result.status = IPAValidationStatusInvalidZip;
        result.statusMessage = @"فشل في فك الضغط";
        result.issues = @[@"تعذر فك ضغط ملف IPA"];
        result.isReadyForInstall = NO;
        [[NSFileManager defaultManager] removeItemAtPath:tempDir error:nil];
        return result;
    }

    // Check Payload
    NSString *payloadDir = [tempDir stringByAppendingPathComponent:@"Payload"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:payloadDir]) {
        result.status = IPAValidationStatusMissingPayload;
        result.statusMessage = @"الهيكل غير صالح: مجلد Payload مفقود";
        result.issues = @[@"ملف IPA يجب أن يحتوي على مجلد Payload"];
        result.isReadyForInstall = NO;
        [[NSFileManager defaultManager] removeItemAtPath:tempDir error:nil];
        return result;
    }

    // Find .app bundle
    NSArray *payloadContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:payloadDir error:nil];
    NSString *appDir = nil;
    for (NSString *item in payloadContents) {
        if ([item.pathExtension.lowercaseString isEqualToString:@"app"]) {
            appDir = [payloadDir stringByAppendingPathComponent:item];
            break;
        }
    }

    if (!appDir) {
        result.status = IPAValidationStatusMissingAppBundle;
        result.statusMessage = @"لم يتم العثور على حزمة .app";
        result.issues = @[@"مجلد Payload لا يحتوي على حزمة .app"];
        result.isReadyForInstall = NO;
        [[NSFileManager defaultManager] removeItemAtPath:tempDir error:nil];
        return result;
    }

    result = [self validateExtractedAppAtPath:appDir];

    // Cleanup
    [[NSFileManager defaultManager] removeItemAtPath:tempDir error:nil];
    return result;
}

- (IPAValidationResult *)validateExtractedAppAtPath:(NSString *)appPath {
    IPAValidationResult *result = [[IPAValidationResult alloc] init];
    NSMutableArray<NSString *> *issues = [NSMutableArray array];

    // Info.plist
    NSString *infoPlistPath = [appPath stringByAppendingPathComponent:@"Info.plist"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:infoPlistPath]) {
        result.status = IPAValidationStatusMissingInfoPlist;
        result.statusMessage = @"معلومات التطبيق مفقودة";
        result.issues = @[@"ملف Info.plist غير موجود داخل الحزمة"];
        result.isReadyForInstall = NO;
        return result;
    }

    NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:infoPlistPath];
    if (!plist) {
        result.status = IPAValidationStatusMissingInfoPlist;
        result.statusMessage = @"معلومات التطبيق تالفة";
        result.issues = @[@"ملف Info.plist موجود لكنه تالف أو غير قابل للقراءة"];
        result.isReadyForInstall = NO;
        return result;
    }

    // Bundle ID
    NSString *bundleID = plist[@"CFBundleIdentifier"];
    if (!bundleID || bundleID.length == 0) {
        [issues addObject:@"معرّف الحزمة (Bundle ID) غير موجود"];
        result.status = IPAValidationStatusInvalidBundleID;
        result.isReadyForInstall = NO;
    }

    // Executable
    NSString *executable = plist[@"CFBundleExecutable"];
    if (!executable || executable.length == 0) {
        [issues addObject:@"اسم الملف التنفيذي مفقود"];
        result.status = IPAValidationStatusMissingExecutable;
        result.isReadyForInstall = NO;
    } else {
        NSString *execPath = [appPath stringByAppendingPathComponent:executable];
        if (![[NSFileManager defaultManager] fileExistsAtPath:execPath]) {
            [issues addObject:@"الملف التنفيذي غير موجود داخل الحزمة"];
            result.status = IPAValidationStatusMissingExecutable;
            result.isReadyForInstall = NO;
        }
    }

    // Minimum iOS version
    NSString *minOS = plist[@"MinimumOSVersion"];
    if (minOS && minOS.length > 0) {
        NSString *currentOS = [[JailbreakEnvironment sharedEnvironment] osVersion];
        if ([self compareVersion:currentOS withVersion:minOS] < 0) {
            [issues addObject:[NSString stringWithFormat:@"التطبيق يتطلب iOS %@ لكن جهازك يعمل على iOS %@", minOS, currentOS]];
            result.status = IPAValidationStatusIncompatibleOS;
            result.isReadyForInstall = NO;
        }
    }

    // Architecture check (basic)
    NSString *execPath = [appPath stringByAppendingPathComponent:executable];
    if ([[NSFileManager defaultManager] fileExistsAtPath:execPath]) {
        NSFileHandle *execFh = [NSFileHandle fileHandleForReadingAtPath:execPath];
        if (execFh) {
            NSData *magic = [execFh readDataOfLength:4];
            [execFh closeFile];
            if (magic.length >= 4) {
                const unsigned char *m = (const unsigned char *)magic.bytes;
                uint32_t magicNum = *(uint32_t *)m;
                // MH_MAGIC_64 = 0xfeedfacf
                if (magicNum != 0xfeedfacf) {
                    [issues addObject:@"البنية المعمارية للملف التنفيذي غير مدعومة"];
                    result.status = IPAValidationStatusIncompatibleArchitecture;
                    result.isReadyForInstall = NO;
                }
            }
        }
    }

    if (issues.count == 0) {
        result.status = IPAValidationStatusValid;
        result.statusMessage = @"جاهز للتثبيت ✓";
        result.isReadyForInstall = YES;
    } else {
        if (result.status == IPAValidationStatusUnknown) {
            result.status = IPAValidationStatusInvalidZip;
        }
        if (result.statusMessage.length == 0) {
            result.statusMessage = @"تم اكتشاف مشاكل في ملف IPA";
        }
        result.isReadyForInstall = NO;
    }

    result.issues = [issues copy];
    return result;
}

- (NSInteger)compareVersion:(NSString *)v1 withVersion:(NSString *)v2 {
    NSArray *c1 = [v1 componentsSeparatedByString:@"."];
    NSArray *c2 = [v2 componentsSeparatedByString:@"."];
    NSUInteger max = MAX(c1.count, c2.count);
    for (NSUInteger i = 0; i < max; i++) {
        NSInteger n1 = (i < c1.count) ? [c1[i] integerValue] : 0;
        NSInteger n2 = (i < c2.count) ? [c2[i] integerValue] : 0;
        if (n1 < n2) return -1;
        if (n1 > n2) return 1;
    }
    return 0;
}

@end
