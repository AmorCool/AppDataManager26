//
//  IPAValidator.m
//  IPAInstallerPro
//
//  Enhanced version - checks dylib permissions and @rpath dependencies
//

#import "IPAValidator.h"
#import "RootlessManager.h"
#import <Foundation/Foundation.h>

@interface IPAValidator ()
@property (nonatomic, strong) NSString *ldidPath;
@property (nonatomic, strong) NSString *otoolPath;
@property (nonatomic, strong) NSString *lipoPath;
@property (nonatomic, strong) NSString *filePath;
@end

@implementation IPAValidator

- (instancetype)init {
    self = [super init];
    if (self) {
        RootlessManager *rm = [RootlessManager sharedManager];
        self.ldidPath  = [rm resolvePath:@"/usr/bin/ldid"];
        self.otoolPath = [rm resolvePath:@"/usr/bin/otool"];
        self.lipoPath  = [rm resolvePath:@"/usr/bin/lipo"];
        self.filePath  = [rm resolvePath:@"/usr/bin/file"];
    }
    return self;
}

- (ValidationResult *)validateIPA:(NSString *)ipaPath {
    NSMutableArray *errors = [NSMutableArray array];
    NSMutableArray *warnings = [NSMutableArray array];

    NSFileManager *fm = [NSFileManager defaultManager];

    // 1. Check file exists and is readable
    if (![fm fileExistsAtPath:ipaPath]) {
        [errors addObject:@"ملف IPA غير موجود"];
        return [ValidationResult resultWithValid:NO errors:errors warnings:warnings info:nil];
    }
    if (![fm isReadableFileAtPath:ipaPath]) {
        [errors addObject:@"لا يمكن قراءة ملف IPA (صلاحيات غير كافية)"];
        return [ValidationResult resultWithValid:NO errors:errors warnings:warnings info:nil];
    }

    // 2. Check ZIP magic number
    NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath:ipaPath];
    if (!fh) {
        [errors addObject:@"لا يمكن فتح ملف IPA للقراءة"];
        return [ValidationResult resultWithValid:NO errors:errors warnings:warnings info:nil];
    }
    NSData *header = [fh readDataOfLength:4];
    [fh closeFile];
    if (header.length < 4) {
        [errors addObject:@"ملف IPA فارغ أو تالف"];
        return [ValidationResult resultWithValid:NO errors:errors warnings:warnings info:nil];
    }
    const unsigned char *bytes = (const unsigned char *)header.bytes;
    if (bytes[0] != 0x50 || bytes[1] != 0x4B || bytes[2] != 0x03 || bytes[3] != 0x04) {
        [errors addObject:@"ملف IPA ليس ملف ZIP صالح"];
        return [ValidationResult resultWithValid:NO errors:errors warnings:warnings info:nil];
    }

    // 3. Extract to temp and validate structure
    NSString *tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [fm createDirectoryAtPath:tempDir withIntermediateDirectories:YES attributes:nil error:nil];

    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/usr/bin/unzip";
    task.arguments = @[@"-o", ipaPath, @"-d", tempDir];
    [task launch];
    [task waitUntilExit];

    NSString *payloadPath = [tempDir stringByAppendingPathComponent:@"Payload"];
    if (![fm fileExistsAtPath:payloadPath]) {
        [errors addObject:@"لا يوجد مجلد Payload داخل IPA"];
        [fm removeItemAtPath:tempDir error:nil];
        return [ValidationResult resultWithValid:NO errors:errors warnings:warnings info:nil];
    }

    NSArray *payloadItems = [fm contentsOfDirectoryAtPath:payloadPath error:nil];
    NSString *appFolder = nil;
    for (NSString *item in payloadItems) {
        if ([item hasSuffix:@".app"]) {
            appFolder = item;
            break;
        }
    }
    if (!appFolder) {
        [errors addObject:@"لا يوجد ملف .app داخل Payload"];
        [fm removeItemAtPath:tempDir error:nil];
        return [ValidationResult resultWithValid:NO errors:errors warnings:warnings info:nil];
    }

    NSString *appPath = [payloadPath stringByAppendingPathComponent:appFolder];

    // 4. Check Info.plist
    NSString *infoPath = [appPath stringByAppendingPathComponent:@"Info.plist"];
    if (![fm fileExistsAtPath:infoPath]) {
        [errors addObject:@"لا يوجد Info.plist داخل التطبيق"];
        [fm removeItemAtPath:tempDir error:nil];
        return [ValidationResult resultWithValid:NO errors:errors warnings:warnings info:nil];
    }

    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPath];
    if (!info) {
        [errors addObject:@"Info.plist تالف أو غير قابل للقراءة"];
        [fm removeItemAtPath:tempDir error:nil];
        return [ValidationResult resultWithValid:NO errors:errors warnings:warnings info:nil];
    }

    NSString *bundleID = info[@"CFBundleIdentifier"];
    NSString *bundleName = info[@"CFBundleName"];
    NSString *displayName = info[@"CFBundleDisplayName"];
    NSString *version = info[@"CFBundleShortVersionString"];
    NSString *build = info[@"CFBundleVersion"];
    NSString *exeName = info[@"CFBundleExecutable"];
    NSNumber *minOS = info[@"MinimumOSVersion"];
    NSArray *supportedDevices = info[@"UISupportedDevices"];

    if (!bundleID || bundleID.length == 0) {
        [errors addObject:@"CFBundleIdentifier مفقود في Info.plist"];
    }
    if (!exeName || exeName.length == 0) {
        [errors addObject:@"CFBundleExecutable مفقود في Info.plist"];
    }

    // 5. Check executable exists
    NSString *exePath = [appPath stringByAppendingPathComponent:exeName];
    if (![fm fileExistsAtPath:exePath]) {
        [errors addObject:[NSString stringWithFormat:@"الملف التنفيذي %@ غير موجود", exeName]];
    } else if (![fm isReadableFileAtPath:exePath]) {
        [errors addObject:[NSString stringWithFormat:@"الملف التنفيذي %@ غير قابل للقراءة", exeName]];
    }

    // 6. Check architectures
    if ([fm fileExistsAtPath:exePath]) {
        NSArray *archs = [self architecturesForBinary:exePath];
        if (archs.count == 0) {
            [warnings addObject:@"لا يمكن تحديد معمارية التطبيق"];
        } else {
            BOOL hasArm64 = NO;
            for (NSString *arch in archs) {
                if ([arch containsString:@"arm64"]) hasArm64 = YES;
            }
            if (!hasArm64) {
                [warnings addObject:@"التطبيق لا يدعم arm64 - قد لا يعمل على أجهزة حديثة"];
            }
        }
    }

    // 7. Check iOS version compatibility
    if (minOS) {
        NSString *minOSStr = [minOS isKindOfClass:[NSString class]] ? (NSString *)minOS : [minOS stringValue];
        NSArray *parts = [minOSStr componentsSeparatedByString:@"."];
        if (parts.count >= 1) {
            NSInteger minMajor = [parts[0] integerValue];
            if (minMajor > 15) {
                [warnings addObject:[NSString stringWithFormat:@"يتطلب iOS %@ أو أحدث", minOSStr]];
            }
        }
    }

    // 8. Check signing status
    if ([fm fileExistsAtPath:self.ldidPath]) {
        BOOL isSigned = [self checkCodeSignature:exePath];
        if (!isSigned) {
            [warnings addObject:@"التطبيق غير موقع - سيتم إعادة توقيعه أثناء التثبيت"];
        }
    }

    // 9. Check embedded.mobileprovision
    NSString *provPath = [appPath stringByAppendingPathComponent:@"embedded.mobileprovision"];
    if ([fm fileExistsAtPath:provPath]) {
        [warnings addObject:@"يحتوي على ملف توقيع Apple - سيتم إزالته وإعادة التوقيع"];
    }

    // 10. Check device support
    if (supportedDevices && supportedDevices.count > 0) {
        [warnings addObject:@"يحتوي على قيود أجهزة محددة"];
    }

    // 11. Check entitlements
    if ([fm fileExistsAtPath:self.ldidPath]) {
        NSDictionary *ents = [self extractEntitlements:exePath];
        if (ents && ents.count > 0) {
            // Check for problematic entitlements
            if (ents[@"com.apple.private.security.container-required"] &&
                [ents[@"com.apple.private.security.container-required"] boolValue]) {
                [warnings addObject:@"يتطلب حاوية أمان خاصة - قد يحتاج تعديل"];
            }
        }
    }

    // 12. CRITICAL: Check Frameworks dylibs permissions and dependencies
    NSString *frameworksPath = [appPath stringByAppendingPathComponent:@"Frameworks"];
    if ([fm fileExistsAtPath:frameworksPath]) {
        NSArray *fwItems = [fm contentsOfDirectoryAtPath:frameworksPath error:nil];

        for (NSString *item in fwItems) {
            NSString *itemPath = [frameworksPath stringByAppendingPathComponent:item];
            BOOL isDir = NO;
            [fm fileExistsAtPath:itemPath isDirectory:&isDir];

            if ([item hasSuffix:@".dylib"] || [item hasSuffix:@".so"]) {
                // Check if dylib is readable
                if (![fm isReadableFileAtPath:itemPath]) {
                    [errors addObject:[NSString stringWithFormat:@"Frameworks/%@ غير قابل للقراءة - سيؤدي لفشل التشغيل", item]];
                } else {
                    // Check if dylib is signed
                    if ([fm fileExistsAtPath:self.ldidPath]) {
                        BOOL dylibSigned = [self checkCodeSignature:itemPath];
                        if (!dylibSigned) {
                            [warnings addObject:[NSString stringWithFormat:@"Frameworks/%@ غير موقع - سيتم توقيعه أثناء التثبيت", item]];
                        }
                    }
                }
            }
            else if (isDir && [item hasSuffix:@".framework"]) {
                // Check framework executable
                NSString *fwName = [item stringByDeletingPathExtension];
                NSString *fwExe = [itemPath stringByAppendingPathComponent:fwName];
                if ([fm fileExistsAtPath:fwExe] && ![fm isReadableFileAtPath:fwExe]) {
                    [errors addObject:[NSString stringWithFormat:@"Frameworks/%@/%@ غير قابل للقراءة", item, fwName]];
                }
            }
        }
    }

    // 13. Check @rpath dependencies
    if ([fm fileExistsAtPath:exePath] && [fm fileExistsAtPath:self.otoolPath]) {
        NSArray *deps = [self checkDependenciesAtAppPath:appPath executable:exePath];
        for (NSString *dep in deps) {
            if ([dep hasPrefix:@"@rpath/"] || [dep hasPrefix:@"@executable_path/"]) {
                // These should be bundled - already checked above
            } else if ([dep hasPrefix:@"/usr/lib/"] || [dep hasPrefix:@"/System/Library/"]) {
                // System libraries - should be fine
            } else {
                [warnings addObject:[NSString stringWithFormat:@"يعتمد على مكتبة خارجية: %@ - قد لا تكون متوفرة", dep]];
            }
        }
    }

    // 14. Check PlugIns
    NSString *pluginsPath = [appPath stringByAppendingPathComponent:@"PlugIns"];
    if ([fm fileExistsAtPath:pluginsPath]) {
        [warnings addObject:@"يحتوي على PlugIns - قد تحتاج توقيع إضافي"];
    }

    // Cleanup
    [fm removeItemAtPath:tempDir error:nil];

    // Build info dictionary
    NSMutableDictionary *infoDict = [NSMutableDictionary dictionary];
    if (bundleID) infoDict[@"bundleID"] = bundleID;
    if (bundleName) infoDict[@"bundleName"] = bundleName;
    if (displayName) infoDict[@"displayName"] = displayName;
    if (version) infoDict[@"version"] = version;
    if (build) infoDict[@"build"] = build;
    if (exeName) infoDict[@"executable"] = exeName;
    if (minOS) infoDict[@"minOS"] = minOS;

    BOOL isValid = (errors.count == 0);
    return [ValidationResult resultWithValid:isValid errors:errors warnings:warnings info:infoDict];
}

- (NSArray *)architecturesForBinary:(NSString *)path {
    NSMutableArray *archs = [NSMutableArray array];
    if (![[NSFileManager defaultManager] fileExistsAtPath:self.lipoPath]) return archs;

    NSTask *task = [[NSTask alloc] init];
    task.launchPath = self.lipoPath;
    task.arguments = @[@"-info", path];
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    [task launch];
    [task waitUntilExit];

    NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
    NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (output) {
        // Parse output for architectures
        if ([output containsString:@"arm64e"]) [archs addObject:@"arm64e"];
        if ([output containsString:@"arm64"] && ![output containsString:@"arm64e"]) [archs addObject:@"arm64"];
        if ([output containsString:@"armv7s"]) [archs addObject:@"armv7s"];
        if ([output containsString:@"armv7"]) [archs addObject:@"armv7"];
    }
    return archs;
}

- (BOOL)checkCodeSignature:(NSString *)path {
    if (![[NSFileManager defaultManager] fileExistsAtPath:self.ldidPath]) return YES; // Can't check, assume OK

    NSTask *task = [[NSTask alloc] init];
    task.launchPath = self.ldidPath;
    task.arguments = @[@"-e", path];
    [task launch];
    [task waitUntilExit];
    return (task.terminationStatus == 0);
}

- (NSDictionary *)extractEntitlements:(NSString *)path {
    if (![[NSFileManager defaultManager] fileExistsAtPath:self.ldidPath]) return nil;

    NSTask *task = [[NSTask alloc] init];
    task.launchPath = self.ldidPath;
    task.arguments = @[@"-e", path];
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    [task launch];
    [task waitUntilExit];

    NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
    if (data.length > 10) {
        id obj = [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:nil];
        if ([obj isKindOfClass:[NSDictionary class]]) return obj;
    }
    return nil;
}

- (NSArray *)checkDependenciesAtAppPath:(NSString *)appPath executable:(NSString *)exePath {
    NSMutableArray *deps = [NSMutableArray array];
    if (![[NSFileManager defaultManager] fileExistsAtPath:self.otoolPath]) return deps;

    NSTask *task = [[NSTask alloc] init];
    task.launchPath = self.otoolPath;
    task.arguments = @[@"-L", exePath];
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    [task launch];
    [task waitUntilExit];

    NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
    NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!output) return deps;

    NSArray *lines = [output componentsSeparatedByString:@"\n"];
    for (NSString *line in lines) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([trimmed hasPrefix:@"\t"]) {
            NSRange range = [trimmed rangeOfString:@" ("];
            if (range.location != NSNotFound) {
                NSString *lib = [trimmed substringWithRange:NSMakeRange(1, range.location - 1)];
                [deps addObject:lib];
            }
        }
    }
    return deps;
}

@end
