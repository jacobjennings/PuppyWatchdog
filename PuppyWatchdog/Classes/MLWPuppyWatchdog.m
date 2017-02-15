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

#define PLCF_RELEASE_BUILD

#if __has_include(<PLCrashReporter_DynamicFramework/PLCrashReporter-DynamicFramework-umbrella.h>)
    #import <PLCrashReporter_DynamicFramework/PLCrashReporter-DynamicFramework-umbrella.h>
#elif __has_include(<PLCrashReporter-DynamicFramework/Source/CrashReporter.h>)
    #import <PLCrashReporter-DynamicFramework/Source/CrashReporter.h>
    #import <PLCrashReporter-DynamicFramework/Source/PLCrashLogWriter.h>
#else
    #import <CrashReporter/CrashReporter.h>
    #import <CrashReporter/PLCrashLogWriter.h>
#endif

#if __has_include(<CocoaLumberjack/CocoaLumberjack.h>)
    #import <CocoaLumberjack/CocoaLumberjack.h>
    static const DDLogLevel ddLogLevel = DDLogLevelVerbose;
    #define PWLog DDLogVerbose
#else
    #define PWLog NSLog
#endif

#import <RuntimeRoutines/RuntimeRoutines.h>

#import "MLWPuppyWatchdog.h"

//

static NSTimeInterval const kWatchDogThreshold = 0.1;

static CGFloat const kTreePercentToSkip = 10.0;
static CGFloat const kTreeMaxDeep = 1000;
static CGFloat const kMaxStackFrames = 512;

static NSString *const kTreeTabString = @"| ";

static NSNumber *kTreeCountKey;
__attribute__((constructor))
static void initialize_kTreeCountKey() {
    kTreeCountKey = @(-1);
}

//

static BOOL _allowObjCRuntimeSymbolication;

//

static NSArray<NSNumber *> *GetThreadFrames(thread_t thread, plcrash_async_image_list_t *image_list) {
    NSMutableArray<NSNumber *> *frames = [NSMutableArray arrayWithCapacity:100];
    plframe_cursor_t cursor;
    plframe_error_t ferr;
    
    /* Write out the stack frames. */
    {
        /* Set up the frame cursor. */
        {
            /* Use the provided context if available, otherwise initialize a new thread context
             * from the target thread's state. */
            plcrash_async_thread_state_t cursor_thr_state;
            plcrash_async_thread_state_mach_thread_init(&cursor_thr_state, thread);
            
            /* Initialize the cursor */
            ferr = plframe_cursor_init(&cursor, mach_task_self(), &cursor_thr_state, image_list);
            if (ferr != PLFRAME_ESUCCESS) {
                PLCF_DEBUG("An error occured initializing the frame cursor: %s", plframe_strerror(ferr));
                return nil;
            }
        }
        
        /* Walk the stack, limiting the total number of frames that are output. */
        uint32_t frame_count = 0;
        while ((ferr = plframe_cursor_next(&cursor)) == PLFRAME_ESUCCESS && frame_count < kMaxStackFrames) {
            uint32_t frame_size;
            
            /* Fetch the PC value */
            plcrash_greg_t pc = 0;
            if ((ferr = plframe_cursor_get_reg(&cursor, PLCRASH_REG_IP, &pc)) != PLFRAME_ESUCCESS) {
                PLCF_DEBUG("Could not retrieve frame PC register: %s", plframe_strerror(ferr));
                frames = nil;
                break;
            }
            
            [frames addObject:[NSNumber numberWithUnsignedLongLong:pc]];
            frame_count++;
        }
        
        /* Did we reach the end successfully? */
        if (ferr != PLFRAME_ENOFRAME) {
            /* This is non-fatal, and in some circumstances -could- be caused by reaching the end of the stack if the
             * final frame pointer is not NULL. */
            PLCF_DEBUG("Terminated stack walking early: %s", plframe_strerror(ferr));
        }
    }
    
    plframe_cursor_free(&cursor);
    return frames.reverseObjectEnumerator.allObjects;
}

static NSArray<NSNumber *> *GetThreadSnapshot(thread_t thread) {
    __block plcrash_error_t err = PLCRASH_ESUCCESS;
    
    static plcrash_async_allocator_t *allocator = NULL;
    {
        static dispatch_once_t onceTokenForAllocator;
        dispatch_once(&onceTokenForAllocator, ^{
            plcrash_async_allocator_create(&allocator, 100000);
        });
        if (err != PLCRASH_ESUCCESS) {
            plcrash_async_allocator_free(allocator);
            return nil;
        }
    }
    
    static plcrash_async_dynloader_t *loader = NULL;
    {
        static dispatch_once_t onceTokenForLoader;
        dispatch_once(&onceTokenForLoader, ^{
            err = plcrash_nasync_dynloader_new(&loader, allocator, mach_task_self());
        });
        if (err != PLCRASH_ESUCCESS) {
            plcrash_async_dynloader_free(loader);
            return nil;
        }
    }
    
    static plcrash_async_image_list_t *image_list;
    {
        static dispatch_once_t onceTokenForImageList;
        dispatch_once(&onceTokenForImageList, ^{
            err = plcrash_async_dynloader_read_image_list(loader, allocator, &image_list);
            if (err != PLCRASH_ESUCCESS) {
                PLCF_DEBUG("Fetching image list failed, proceeding with an empty image list: %d", err);
                
                /* Allocate an empty image list; outside of a compile-time configuration error, this should never fail. If it does
                 * fail, our environment is messed up enough that terminating without writing a report is likely justified */
                image_list = plcrash_async_image_list_new_empty(allocator);
                if (image_list == NULL) {
                    PLCF_DEBUG("Allocation of our empty image list failed unexpectedly");
                }
            }
        });
        if (image_list == NULL) {
            return nil;
        }
    }
    
    //thread_suspend(thread);
    NSArray<NSNumber *> *frames = GetThreadFrames(thread, image_list);
    //thread_resume(thread);
    //usleep(150); // Need to sleep a litle bit to avoid main thread freeze
    
    return frames;
}

static NSString *SymbolicateFast(NSNumber *address) {
    Dl_info info;
    if (dladdr(address.unsignedLongLongValue, &info) && info.dli_sname) {
        NSString *module = [@(info.dli_fname ?: "") lastPathComponent];
        NSString *symbol = @(info.dli_sname ?: "");
        if (symbol.length) {
            return [NSString stringWithFormat:@"%@ (in %@)", symbol, module];
        }
    }
    return [NSString stringWithFormat:@"<%p> (in <unknown>)", address.unsignedLongLongValue];;
}

static NSString *SymbolicateRuntime(NSNumber *address) {
    static NSArray<NSNumber *> *keys;
    static NSArray<NSNumber *> *klasses;
    static NSArray<NSNumber *> *methods;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableDictionary<NSNumber *, NSNumber *> *dictKlasses = [NSMutableDictionary dictionaryWithCapacity:1000000];
        NSMutableDictionary<NSNumber *, NSNumber *> *dictMethods = [NSMutableDictionary dictionaryWithCapacity:1000000];
        RRClassEnumerateAllClasses(YES, ^(Class klass) {
            RRClassEnumerateMethods(klass, ^(Method method) {
                NSNumber *key = @((uint64_t)method_getImplementation(method));
                dictKlasses[key] = @((uint64_t)(__bridge void *)klass);
                dictMethods[key] = @((uint64_t)(void *)method);
            });
        });
        keys = [[dictKlasses allKeys] sortedArrayUsingSelector:@selector(compare:)];
        klasses = [dictKlasses objectsForKeys:keys notFoundMarker:[NSNull null]];
        methods = [dictMethods objectsForKeys:keys notFoundMarker:[NSNull null]];
    });
    
    NSUInteger index = [keys indexOfObject:address inSortedRange:NSMakeRange(0, keys.count) options:NSBinarySearchingInsertionIndex usingComparator:^NSComparisonResult(NSNumber *obj1, NSNumber *obj2) {
        return [obj1 compare:obj2];
    }];
    
    if (index == 0) {
        return @"<unknown> (in <unknown>)";
    }
    index--;
    
    Class klass = (__bridge Class)(void *)klasses[index].unsignedLongLongValue;
    Method method = (Method)methods[index].unsignedLongLongValue;
    NSString *imageName = @(class_getImageName(klass) ?: "");
    return [NSString stringWithFormat:@"%c[%@ %@] (in %@)",
            class_isMetaClass(klass) ? '+' : '-',
            NSStringFromClass(klass),
            NSStringFromSelector(method_getName(method)),
            imageName.lastPathComponent];
}

static NSString *SymbolicateStackFrame(NSNumber *stackFrame) {
    NSString *symbol = SymbolicateFast(stackFrame);
    if (_allowObjCRuntimeSymbolication && [symbol hasPrefix:@"<"]) {
        symbol = SymbolicateRuntime(stackFrame);
    }
    return symbol;
}

static NSString *SymbolicateStackFrameCached(NSNumber *stackFrame) {
    static NSMutableDictionary<NSNumber *, NSString *> *cache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [NSMutableDictionary dictionaryWithCapacity:1000000];
    });
    
    NSString *frame = cache[@(stackFrame.unsignedLongLongValue)];
    if (frame == nil) {
        frame = SymbolicateStackFrame(stackFrame);
        cache[stackFrame] = frame;
    }
    
    return frame;
}

static NSArray<NSString *> *SymbolicateCallstack(NSArray<NSNumber *> *callstack) {
    NSMutableArray *symbolicated = [NSMutableArray array];
    for (NSNumber *stackFrame in callstack) {
        [symbolicated addObject:SymbolicateStackFrameCached(stackFrame)];
    }
    return symbolicated;
}

static void TreeAddCallstack(NSMutableDictionary<NSNumber *, id> *tree, NSArray<NSNumber *> *callstack) {
    for (NSNumber *stackFrame in callstack) {
        NSMutableDictionary *nextTree = tree[stackFrame];
        if (!nextTree) {
            nextTree = [NSMutableDictionary dictionary];
            tree[stackFrame] = nextTree;
        }
        tree = nextTree;
        tree[kTreeCountKey] = @([tree[kTreeCountKey] integerValue] + 1);
    }
}

static void TreePrintWithPercents(NSMutableString *log, NSDictionary<NSNumber *, id> *tree, NSUInteger totalCount, NSString *tab, CGFloat skipLess) {
    if (tab.length / kTreeTabString.length >= kTreeMaxDeep) {
        [log appendFormat:@"%@... Maximal level #%@ reached ...\n", tab, @(kTreeMaxDeep)];
        return;
    }

    NSArray *orderedKeys = [tree.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *obj1, NSString *obj2) {
        NSNumber *count1 = [obj1 isEqual:kTreeCountKey] ? @0 : tree[obj1][kTreeCountKey];
        NSNumber *count2 = [obj2 isEqual:kTreeCountKey] ? @0 : tree[obj2][kTreeCountKey];
        return [count2 compare:count1];
    }];

    for (NSNumber *stackFrame in orderedKeys) {
        if ([stackFrame isEqual:kTreeCountKey]) {
            continue;
        }

        CGFloat percent = [tree[stackFrame][kTreeCountKey] integerValue] * 100.0 / totalCount;
        if (percent < skipLess) {
            continue;
        }

        [log appendFormat:@"%@%.3f%% %@\n", tab, percent, SymbolicateStackFrameCached(stackFrame)];
        TreePrintWithPercents(log, tree[stackFrame], totalCount, [tab stringByAppendingString:kTreeTabString], skipLess);
    }
}

//

@interface MLWPingThread : NSThread

@property (assign, nonatomic) NSTimeInterval threshold;
@property (copy, nonatomic) void (^handler)(CGFloat blockTime, BOOL firstTime);
@property (assign, nonatomic) thread_t mainThread;

@end

@implementation MLWPingThread

- (instancetype)initWithThreshold:(NSTimeInterval)threshold handler:(void (^)(CGFloat blockTime, BOOL firstTime))handler {
    self = [super init];
    if (self) {
        _threshold = threshold;
        _handler = handler;
        if ([NSThread isMainThread]) {
            _mainThread = mach_thread_self();
        }
        else {
            dispatch_sync(dispatch_get_main_queue(), ^{
                _mainThread = mach_thread_self();
            });
        }
    }
    return self;
}

- (void)dealloc {
    mach_port_deallocate(mach_task_self(), self.mainThread);
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

            NSMutableArray<NSArray<NSNumber *> *> *snapshots = [NSMutableArray array];
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
                    
                    NSArray<NSNumber *> *snapshot = GetThreadSnapshot(self.mainThread);
                    if (snapshot) {
                        [snapshots addObject:snapshot];
                    }
                    //[NSThread sleepForTimeInterval:0.01];
                }
            }

            NSDate *collected = [NSDate date];
            
            NSMutableDictionary<NSNumber *, id> *tree = [NSMutableDictionary dictionary];
            for (NSArray<NSNumber *> *snapshot in snapshots) {
                @autoreleasepool {
                    TreeAddCallstack(tree, snapshot);
                }
            }
            
            if (snapshots.count) {
                NSMutableString *log = [NSMutableString string];
                [log appendFormat:@"\n🐶🐶🐶🐶🐶🐶🐶🐶🐶🐶 Collected %@ reports for %.2f sec and processed for %.2f sec:\n", @(snapshots.count), -[lastTimestamp timeIntervalSinceDate:collected], -[collected timeIntervalSinceNow]];
                TreePrintWithPercents(log, tree, snapshots.count, @"", kTreePercentToSkip);
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

+ (void)setAllowObjCRuntimeSymbolication:(BOOL)allowObjCRuntimeSymbolication {
    _allowObjCRuntimeSymbolication = allowObjCRuntimeSymbolication;
}

+ (BOOL)allowObjCRuntimeSymbolication {
    return _allowObjCRuntimeSymbolication;
}

@end
