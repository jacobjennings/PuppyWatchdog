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
#include <mach-o/dyld.h>
#include <mach-o/dyld_images.h>

#if __has_include(<PLCrashReporter_DynamicFramework/PLCrashReporter-DynamicFramework-umbrella.h>)
#import <PLCrashReporter_DynamicFramework/PLCrashReporter-DynamicFramework-umbrella.h>
#else
#import <PLCrashReporter-DynamicFramework/Source/CrashReporter.h>
#endif

#import <RuntimeRoutines/RuntimeRoutines.h>
#import <libMachO/macho.h>

#if __has_include(<CocoaLumberjack/CocoaLumberjack.h>)
#import <CocoaLumberjack/CocoaLumberjack.h>
#define PWLog DDLogVerbose
#else
#define PWLog NSLog
#endif

#import "STDMap.h"

#import "MLWPuppyWatchdog.h"

//

static NSTimeInterval const kWatchDogThreshold = 0.1;

static CGFloat const kTreePercentToSkip = 10.0;
static CGFloat const kTreeMaxDeep = 1000;

static NSString *const kMainThreadMarkerBegin = @"\n\nThread 0:\n";
static NSString *const kMainThreadMarkerEnd = @"\n\nThread 1";

static NSString *const kTreeCountKey = @"kTreeCountKey";
static NSString *const kTreeTabString = @"| ";

static NSString *ClassAndSelectorForIMP(IMP imp, IMP *outImp) {
    static STDMap *dict;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dict = [STDMap new];
        RRClassEnumerateAllClasses(YES, ^(Class klass) {
            RRClassEnumerateMethods(klass, ^(Method method) {
                IMP imp = method_getImplementation(method);
                SEL sel = method_getName(method);
                NSString *value = [NSString stringWithFormat:@"%c[%s %@]", class_isMetaClass(klass) ? '+' : '-', object_getClassName(klass), NSStringFromSelector(sel)];
                STDMapInsert(dict, (void *)imp, value);
            });
        });

        __block mk_memory_map_self_t memory_map;
        mk_error_t err = mk_memory_map_self_init(NULL, &memory_map);
        if (err != MK_ESUCCESS) {
            return;
        }

        for (uint32_t i = 0; i < _dyld_image_count(); i++) {
            const char *image_name = _dyld_get_image_name(i);
            if ([[NSString stringWithCString:image_name encoding:NSUTF8StringEncoding] hasSuffix:@"/dyld_sim"]) {
                continue;
            }

            __block mk_macho_t macho;
            mk_vm_address_t headerAddress = (mk_vm_address_t)_dyld_get_image_header(i);
            intptr_t slide = _dyld_get_image_vmaddr_slide(i);
            mk_error_t err = mk_macho_init(NULL, image_name, slide, headerAddress, &memory_map, &macho);
            if (err != MK_ESUCCESS) {
                NSLog(@"Error parsiong MachO of %s", image_name);
                continue;
            }

            mk_macho_enumerate_commands(&macho, ^(struct load_command *load_command, uint32_t index, mk_vm_address_t host_address) {
                if (load_command->cmd != LC_SEGMENT_64 && load_command->cmd != LC_SEGMENT) {
                    return;
                }

                struct segment_command_64 *segment_command = (typeof(segment_command))load_command; // The choice between casting to segment_command_64 vs segment_command does not matter here

                if (strncmp(segment_command->segname, SEG_LINKEDIT, 16) != 0) {
                    return;
                }

                mk_segment_t segment;
                mk_error_t err = mk_segment_init_with_mach_load_command(&macho, segment_command, &segment);
                if (err != MK_ESUCCESS) {
                    NSLog(@"Error creating MachO segment");
                    return;
                }

                mk_symbol_table_t symbol_table;
                err = mk_symbol_table_init_with_segment(&segment, &symbol_table);
                if (err != MK_ESUCCESS) {
                    NSLog(@"Error creating MachO symbol table");
                    return;
                }

                __block mk_string_table_t string_table;
                err = mk_string_table_init_with_segment(&segment, &string_table);
                if (err != MK_ESUCCESS) {
                    NSLog(@"Error creating MachO string table");
                    return;
                }

                mk_symbol_table_enumerate_mach_symbols(&symbol_table, 0, ^(const mk_mach_nlist symbol, uint32_t index, mk_vm_address_t host_address) {
                    uint32_t string_index = symbol.nlist_64->n_un.n_strx;
#ifdef __LP64__
                    uint64_t address = symbol.nlist_64->n_value + (uint64_t)slide;
#else
                    uint64_t address = symbol.nlist->n_value + (uint64_t)slide;
#endif
                    const char *str = mk_string_table_get_string_at_offset(&string_table, string_index, &host_address);
                    NSString *value = [[NSString alloc] initWithBytesNoCopy:(void *)str length:strlen(str) encoding:NSUTF8StringEncoding freeWhenDone:NO];
                    if (value.length) {
                        STDMapInsert(dict, (void *)address, value);
                    }
                });
            });

            mk_macho_free(&macho);
        }
    });

    return STDMapGetLessOrEqual(dict, (void *)imp, (void **)outImp);
}

static void TreeAddPath(NSMutableDictionary<NSString *, id> *dict, NSArray<NSString *> *path) {
    for (NSString *stepWithIndex in path) {
        char imageName[64];
        uint64_t index, imp, base, offset;
        sscanf(stepWithIndex.UTF8String, "%lld %s 0x%llx %llx + %lld", &index, imageName, &imp, &base, &offset);
        IMP outImp;
        ClassAndSelectorForIMP((IMP)imp, &outImp);
        NSString *step = [NSString stringWithFormat:@"%s %@", imageName, @((uint64_t)outImp)];

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

        NSArray<NSString *> *tokens = [line componentsSeparatedByString:@" "];

        CGFloat percent = [dict[line][kTreeCountKey] integerValue] * 100.0 / totalCount;
        if (percent < skipLess) {
            continue;
        }

        IMP result = (IMP)[tokens.lastObject integerValue];
        NSString *module = tokens.firstObject;

        IMP outImp;
        NSString *klassAndSelector = ClassAndSelectorForIMP((IMP)result, &outImp);
        [log appendFormat:@"%@%.3f%% %@ (in %@)\n", tab, percent, klassAndSelector, module];
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

                    NSString *report = [PLCrashReportTextFormatter stringValueForCrashReport:crashLog withTextFormat:PLCrashReportTextFormatiOS];

                    NSRange range;
                    range.location = [report rangeOfString:kMainThreadMarkerBegin].location + kMainThreadMarkerBegin.length;
                    range.length = [report rangeOfString:kMainThreadMarkerEnd].location - range.location;
                    NSString *callstack = [report substringWithRange:range];

                    TreeAddPath(tree, [callstack componentsSeparatedByString:@"\n"].reverseObjectEnumerator.allObjects);
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

- (instancetype)initWithThreshold:(NSTimeInterval)thresold {
    self = [super init];
    if (self) {
        _pingThread = [[MLWPingThread alloc] initWithThreshold:thresold handler:^(CGFloat blockTime, BOOL firstTime) {
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
