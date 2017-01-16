//
//  MLWPuppyWatchdog.m
//  PuppyWatchdog
//
//  Copyright (c) 2016 Machine Learning Works
//
//  Licensed under the MIT License (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://opensource.org/licenses/MIT
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#include <dlfcn.h>

#if __has_include(<PLCrashReporter_DynamicFramework/PLCrashReporter-DynamicFramework-umbrella.h>)
#import <PLCrashReporter_DynamicFramework/PLCrashReporter-DynamicFramework-umbrella.h>
#elif __has_include(<PLCrashReporter-DynamicFramework/Source/CrashReporter.h>)
#import <PLCrashReporter-DynamicFramework/Source/CrashReporter.h>
#else
#import <CrashReporter/CrashReporter.h>
#endif

#import "MLWPuppyWatchdog.h"

#if __has_include(<CocoaLumberjack/CocoaLumberjack.h>)
#import <CocoaLumberjack/CocoaLumberjack.h>
static const DDLogLevel ddLogLevel = DDLogLevelVerbose;
#define PWLog DDLogVerbose
#else
#define PWLog NSLog
#endif

//

static NSTimeInterval const kWatchDogThreshold = 0.1;

static CGFloat const kTreePercentToSkip = 10.0;
static CGFloat const kTreeMaxDeep = 1000;

static NSString *const kMainThreadMarkerBegin = @"\n\nThread 0:\n";
static NSString *const kMainThreadMarkerEnd = @"\n\nThread 1";

static NSString *const kTreeCountKey = @"kTreeCountKey";
static NSString *const kTreeTabString = @"| ";

static NSArray<NSString *> *PrintCrashReport(PLCrashReport *report) {
    NSMutableArray *frames = [NSMutableArray array];
    PLCrashReportThreadInfo *thread = [report.threads firstObject];
    for (PLCrashReportStackFrameInfo *stackFrame in thread.stackFrames) {
        void *instructionPointer = stackFrame.instructionPointer;
        Dl_info info;
        dladdr(instructionPointer, &info);
        NSString *module = [@(info.dli_fname ?: "") lastPathComponent];
        NSString *symbol = @(info.dli_sname ?: "");
        if (symbol.length == 0) {
            symbol = [NSString stringWithFormat:@"%p", info.dli_saddr ?: instructionPointer];
        }
        NSString *frame = [NSString stringWithFormat:@"%@ (in %@)", symbol, module];
        [frames addObject:frame];
    }
    return frames;
}

static void TreeAddPath(NSMutableDictionary<NSString *, id> *dict, NSArray<NSString *> *path) {
    for (NSString *step in path) {
        NSMutableDictionary *nextDict = dict[step];
        if (!nextDict) {
            nextDict = [NSMutableDictionary dictionary];
            dict[step] = nextDict;
        }
        dict = nextDict;
        dict[kTreeCountKey] = @([dict[kTreeCountKey] integerValue] + 1);
    }
}

static void TreePrintWithPercents(NSMutableString *log, NSDictionary<NSString *, id> *dict, NSUInteger totalCount, NSString *tab, CGFloat skipLess) {
    if (tab.length / kTreeTabString.length >= kTreeMaxDeep) {
        [log appendFormat:@"%@... Maximal level #%@ reached ...\n", tab, @(kTreeMaxDeep)];
        return;
    }

    NSArray *orderedKeys = [dict.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *obj1, NSString *obj2) {
        NSNumber *count1 = [obj1 isEqualToString:kTreeCountKey] ? @0 : dict[obj1][kTreeCountKey];
        NSNumber *count2 = [obj2 isEqualToString:kTreeCountKey] ? @0 : dict[obj2][kTreeCountKey];
        return [count2 compare:count1];
    }];

    for (NSString *line in orderedKeys) {
        if ([line isEqualToString:kTreeCountKey]) {
            continue;
        }

        CGFloat percent = [dict[line][kTreeCountKey] integerValue] * 100.0 / totalCount;
        if (percent < skipLess) {
            continue;
        }

        [log appendFormat:@"%@%.3f%% %@\n", tab, percent, line];
        TreePrintWithPercents(log, dict[(id)line], totalCount, [tab stringByAppendingString:kTreeTabString], skipLess);
    }
}

//

@interface MLWPingThread : NSThread

@property (strong, nonatomic) dispatch_semaphore_t semaphore;
@property (assign, nonatomic) NSTimeInterval threshold;
@property (copy, nonatomic) void (^handler)(CGFloat blockTime, BOOL firstTime);
@property (strong, nonatomic) PLCrashReporter *reporter;
@property (strong, nonatomic) NSMutableArray<NSData *> *datas;

@end

@implementation MLWPingThread

- (instancetype)initWithThreshold:(NSTimeInterval)threshold handler:(void (^)(CGFloat blockTime, BOOL firstTime))handler {
    self = [super init];
    if (self) {
        _semaphore = dispatch_semaphore_create(0);
        _threshold = threshold;
        _handler = handler;
        _reporter = [PLCrashReporter new];
    }
    return self;
}

- (void)main {
    while (!self.cancelled) {
        @autoreleasepool {
            __block BOOL done = NO;
            __block NSDate *lastTimestamp = [NSDate date];
            dispatch_async(dispatch_get_main_queue(), ^{
                done = YES;
            });
            [NSThread sleepForTimeInterval:self.threshold];

            self.datas = [NSMutableArray array];
            NSDate *localLastTimestamp = lastTimestamp;
            while (!done && !self.cancelled) {
                @autoreleasepool {
                    if (-[localLastTimestamp timeIntervalSinceNow] > self.threshold) {
                        if (localLastTimestamp == lastTimestamp) {
                            self.handler(-[lastTimestamp timeIntervalSinceNow], YES);
                        }
                        else {
                            self.handler(-[lastTimestamp timeIntervalSinceNow], NO);
                        }
                        localLastTimestamp = [NSDate date];
                    }

                    [self.datas addObject:[self.reporter generateLiveReport]];
                    //[NSThread sleepForTimeInterval:0.01];
                }
            }

            NSMutableDictionary *tree = [NSMutableDictionary dictionary];
            for (NSData *data in self.datas) {
                @autoreleasepool {
                    NSError *error;
                    PLCrashReport *crashLog = [[PLCrashReport alloc] initWithData:data error:&error];
                    if (error) {
                        continue;
                    }

                    NSArray<NSString *> *report = PrintCrashReport(crashLog);
                    TreeAddPath(tree, report.reverseObjectEnumerator.allObjects);
                }
            }

            if (self.datas.count) {
                NSMutableString *log = [NSMutableString string];
                [log appendFormat:@"\n🐶🐶🐶🐶🐶🐶🐶🐶🐶🐶 Collected %@ reports for %.2f sec:\n", @(self.datas.count), -[lastTimestamp timeIntervalSinceNow]];
                TreePrintWithPercents(log, tree, self.datas.count, @"", kTreePercentToSkip);
                [log appendString:@"🐶🐶🐶🐶🐶🐶🐶🐶🐶🐶"];
                PWLog(@"%@", log);
            }
        }
    }
}

@end

#pragma mark -

@interface MLWPuppyWatchdog ()

@property (strong, nonatomic) MLWPingThread *pingThread;

@end

@implementation MLWPuppyWatchdog

- (instancetype)init {
    return [self initWithThreshold:kWatchDogThreshold];
}

- (instancetype)initWithThreshold:(NSTimeInterval)threshold {
    self = [super init];
    if (self) {
        _pingThread = [[MLWPingThread alloc] initWithThreshold:threshold handler:^(CGFloat blockTime, BOOL firstTime) {
            if (firstTime) {
                PWLog(@"🐶 Main thread was blocked for %.2f sec", blockTime);
            }
            else {
                PWLog(@"🐶 Main thread is still blocked for %.2f sec", blockTime);
            }
        }];
        [_pingThread start];
    }
    return self;
}

- (void)dealloc {
    [self.pingThread cancel];
}

@end
