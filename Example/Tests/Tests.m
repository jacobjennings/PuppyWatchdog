//
//  PuppyWatchdogTests.m
//  PuppyWatchdogTests
//
//  Created by Anton Bukov on 10/13/2016.
//  Copyright (c) 2016 Anton Bukov. All rights reserved.
//

@import XCTest;

#import <PuppyWatchdog/PuppyWatchdog.h>

@interface Tests : XCTestCase

@property (strong, nonatomic) MLWPuppyWatchdog *watchdog;

@end

@implementation Tests

- (void)setUp {
    [super setUp];
    self.watchdog = [[MLWPuppyWatchdog alloc] init];
}

- (void)tearDown {
    self.watchdog = nil;
    [super tearDown];
}

- (NSUInteger)innerLoop {
    NSUInteger count = 0;
    for (NSUInteger i = 0; i < 100000000; i++) {
        count++;
    }
    return count;
}

- (NSUInteger)innerLoop2 {
    NSUInteger count = 0;
    for (NSUInteger i = 0; i < 50000000; i++) {
        count++;
    }
    return count;
}

- (void)testExample
{
    NSUInteger count = [self innerLoop];
    XCTAssertTrue(count == 100000000);
    
    NSUInteger count2 = [self innerLoop2];
    XCTAssertTrue(count2 == 50000000);
    
    [[NSRunLoop currentRunLoop] acceptInputForMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:2.0]];
    
    [NSThread sleepForTimeInterval:2.0];
}

@end

