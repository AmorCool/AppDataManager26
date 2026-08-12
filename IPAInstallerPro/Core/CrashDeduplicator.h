//
// CrashDeduplicator.h
// IPAInstallerPro
//
// Prevents duplicate incidents using fingerprint + incident_id.
//

#import <Foundation/Foundation.h>
#import "CrashIncident.h"

@interface CrashDeduplicator : NSObject
+ (instancetype)sharedDeduplicator;

// Check if this incident is a duplicate of a previously seen one
- (BOOL)isDuplicate:(CrashIncident *)incident;

// Record an incident as seen
- (void)recordIncident:(CrashIncident *)incident;

// Get all recorded fingerprints
- (NSArray<NSString *> *)allFingerprints;

// Clear all recorded fingerprints
- (void)clearAll;

// Persistence
- (void)saveState;
- (void)loadState;

@property (nonatomic, readonly) NSUInteger totalDedupedCount;
@end
