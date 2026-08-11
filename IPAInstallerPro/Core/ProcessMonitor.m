#import "ProcessMonitor.h"
#import "Logger.h"
#import <sys/sysctl.h>
#import <libproc.h>

@interface ProcessMonitor ()
@property (nonatomic, strong) NSTimer *monitorTimer;
@property (nonatomic, strong) NSMutableDictionary *trackedProcesses;
@property (nonatomic, assign) BOOL monitoring;
@end

@implementation ProcessMonitor

+ (instancetype)sharedMonitor {
    static ProcessMonitor *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ shared = [[self alloc] init]; });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _trackedProcesses = [NSMutableDictionary dictionary];
        _monitoring = NO;
    }
    return self;
}

- (void)startMonitoring {
    if (self.monitoring) return;
    self.monitoring = YES;
    [[Logger sharedLogger] info:@"ProcessMonitor: Started"];
    self.monitorTimer = [NSTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(checkProcesses) userInfo:nil repeats:YES];
}

- (void)stopMonitoring {
    self.monitoring = NO;
    [self.monitorTimer invalidate];
    self.monitorTimer = nil;
}

- (BOOL)isMonitoring { return self.monitoring; }

- (void)checkProcesses {
    NSArray *current = [self runningProcesses];
    NSMutableSet *currentPIDs = [NSMutableSet set];
    for (NSDictionary *proc in current) {
        NSNumber *pid = proc[@"pid"];
        if (pid) [currentPIDs addObject:pid];
    }
    NSMutableArray *exited = [NSMutableArray array];
    @synchronized(self.trackedProcesses) {
        for (NSNumber *pid in [self.trackedProcesses allKeys]) {
            if (![currentPIDs containsObject:pid]) {
                [exited addObject:@{ @"pid": pid, @"info": self.trackedProcesses[pid] }];
                [self.trackedProcesses removeObjectForKey:pid];
            }
        }
    }
    for (NSDictionary *exitInfo in exited) {
        [[NSNotificationCenter defaultCenter] postNotificationName:@"ProcessDidExit" object:nil userInfo:exitInfo[@"info"]];
    }
}

- (NSArray<NSDictionary *> *)runningProcesses {
    NSMutableArray *processes = [NSMutableArray array];
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 };
    size_t size = 0;
    if (sysctl(mib, 4, NULL, &size, NULL, 0) == -1) return processes;
    struct kinfo_proc *procs = malloc(size);
    if (!procs) return processes;
    if (sysctl(mib, 4, procs, &size, NULL, 0) == -1) { free(procs); return processes; }
    int count = (int)(size / sizeof(struct kinfo_proc));
    for (int i = 0; i < count; i++) {
        struct kinfo_proc *p = &procs[i];
        if (p->kp_proc.p_pid <= 0) continue;
        NSString *name = [NSString stringWithUTF8String:p->kp_proc.p_comm];
        NSMutableDictionary *info = [@{ @"pid": @(p->kp_proc.p_pid), @"name": name ?: @"unknown", @"ppid": @(p->kp_eproc.e_ppid), @"uid": @(p->kp_eproc.e_ucred.cr_uid) } mutableCopy];
        NSString *bundleID = [self bundleIDForPID:p->kp_proc.p_pid];
        if (bundleID) info[@"bundleID"] = bundleID;
        NSString *exePath = [self executablePathForPID:p->kp_proc.p_pid];
        if (exePath) info[@"executablePath"] = exePath;
        [processes addObject:info];
    }
    free(procs);
    return processes;
}

- (NSDictionary *)processInfoForPID:(int)pid {
    struct proc_bsdshortinfo info;
    if (proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, &info, sizeof(info)) <= 0) return nil;
    NSMutableDictionary *dict = [@{ @"pid": @(pid), @"name": [NSString stringWithUTF8String:info.pbsi_comm] ?: @"unknown", @"ppid": @(info.pbsi_ppid), @"uid": @(info.pbsi_uid) } mutableCopy];
    NSString *bundleID = [self bundleIDForPID:pid];
    if (bundleID) dict[@"bundleID"] = bundleID;
    NSString *exePath = [self executablePathForPID:pid];
    if (exePath) dict[@"executablePath"] = exePath;
    return dict;
}

- (BOOL)isProcessRunning:(int)pid {
    struct proc_bsdshortinfo info;
    return proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, &info, sizeof(info)) > 0;
}

- (BOOL)isProcessRunningForBundleID:(NSString *)bundleID {
    if (!bundleID) return NO;
    NSArray *processes = [self runningProcesses];
    for (NSDictionary *proc in processes) {
        if ([proc[@"bundleID"] isEqualToString:bundleID]) return YES;
    }
    return NO;
}

- (NSString *)bundleIDForPID:(int)pid {
    char pathbuf[PROC_PIDPATHINFO_MAXSIZE];
    if (proc_pidpath(pid, pathbuf, sizeof(pathbuf)) <= 0) return nil;
    NSString *exePath = [NSString stringWithUTF8String:pathbuf];
    if (!exePath) return nil;
    NSString *appPath = exePath;
    while (appPath && ![appPath hasSuffix:@".app"]) {
        appPath = [appPath stringByDeletingLastPathComponent];
        if ([appPath isEqualToString:@"/"] || appPath.length == 0) break;
    }
    if (appPath && [appPath hasSuffix:@".app"]) {
        NSString *infoPath = [appPath stringByAppendingPathComponent:@"Info.plist"];
        NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPath];
        return info[@"CFBundleIdentifier"];
    }
    return nil;
}

- (NSString *)processNameForPID:(int)pid {
    struct proc_bsdshortinfo info;
    if (proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, &info, sizeof(info)) <= 0) return nil;
    return [NSString stringWithUTF8String:info.pbsi_comm];
}

- (NSString *)executablePathForPID:(int)pid {
    char pathbuf[PROC_PIDPATHINFO_MAXSIZE];
    if (proc_pidpath(pid, pathbuf, sizeof(pathbuf)) <= 0) return nil;
    return [NSString stringWithUTF8String:pathbuf];
}

- (void)trackProcess:(int)pid bundleID:(NSString *)bundleID name:(NSString *)name {
    @synchronized(self.trackedProcesses) {
        self.trackedProcesses[@(pid)] = @{ @"pid": @(pid), @"bundleID": bundleID ?: @"unknown", @"name": name ?: @"unknown", @"launchTime": [NSDate date] };
    }
}

@end
