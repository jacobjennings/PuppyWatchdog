# PuppyWatchdog

[![CI Status](http://img.shields.io/travis/ML-Works/PuppyWatchdog.svg?style=flat)](https://travis-ci.org/ML-Works/PuppyWatchdog)
[![Version](https://img.shields.io/cocoapods/v/PuppyWatchdog.svg?style=flat)](http://cocoapods.org/pods/PuppyWatchdog)
[![License](https://img.shields.io/cocoapods/l/PuppyWatchdog.svg?style=flat)](http://cocoapods.org/pods/PuppyWatchdog)
[![Platform](https://img.shields.io/cocoapods/p/PuppyWatchdog.svg?style=flat)](http://cocoapods.org/pods/PuppyWatchdog)

Main thread performance monitor 🐶. Lives in a separate thread and checks, that main thread executes small commands in a short time. If faces some delays it starts grabbing the main thread callstacks and then reports callstacks summary tree. It doesn't require dSYM files for symbolication.

Please use it only in `DEBUG`:
```objective-c
#ifdef DEBUG
#import <PuppyWatchdog/PuppyWatchdog.h>
#endif

@interface AppDelegate ()

#ifdef DEBUG
@property (strong, nonatomic) MLWPuppyWatchdog *watchdog;
#endif

@end

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {

#ifdef DEBUG
    self.watchdog = [[MLWPuppyWatchdog alloc] init];
#endif

}
```

## Example

Test code:
```objective-c
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
```

Test output:
```
2017-01-16 23:27:11.100 xctest[79336:418608] 🐶 Main thread was blocked for 0.10 sec
2017-01-16 23:27:11.200 xctest[79336:418608] 🐶 Main thread is still blocked for 0.20 sec
2017-01-16 23:27:11.301 xctest[79336:418608] 🐶 Main thread is still blocked for 0.30 sec
2017-01-16 23:27:11.401 xctest[79336:418608] 🐶 Main thread is still blocked for 0.40 sec
2017-01-16 23:27:11.502 xctest[79336:418608] 
🐶🐶🐶🐶🐶🐶🐶🐶🐶🐶 Collected 730 reports for 0.49 sec processed for 0.02 sec:
99.863% start (in libdyld.dylib)
| 99.863% <Unknown> (in <Unknown>)
| | 99.863% _XCTestMain (in XCTest)
| | | 99.863% -[XCTestDriver _checkForTestManager] (in XCTest)
| | | | 99.863% -[XCTestDriver _runSuite] (in XCTest)
| | | | | 99.863% -[XCTestObservationCenter _observeTestExecutionForBlock:] (in XCTest)
| | | | | | 99.863% __25-[XCTestDriver _runSuite]_block_invoke (in XCTest)
| | | | | | | 99.863% -[XCTestSuite performTest:] (in XCTest)
| | | | | | | | 99.863% -[XCTestSuite performTest:] (in XCTest)
| | | | | | | | | 99.863% -[XCTestSuite performTest:] (in XCTest)
| | | | | | | | | | 99.863% -[XCTestCase performTest:] (in XCTest)
| | | | | | | | | | | 99.863% -[XCTestCase invokeTest] (in XCTest)
| | | | | | | | | | | | 99.863% -[XCTestContext performInScope:] (in XCTest)
| | | | | | | | | | | | | 99.863% __24-[XCTestCase invokeTest]_block_invoke_2 (in XCTest)
| | | | | | | | | | | | | | 99.863% -[NSInvocation invoke] (in CoreFoundation)
| | | | | | | | | | | | | | | 99.863% __invoking___ (in CoreFoundation)
| | | | | | | | | | | | | | | | 99.863% -[Tests testExample] (in PuppyWatchdog_Tests)
| | | | | | | | | | | | | | | | | 56.521% -[Tests innerLoop] (in PuppyWatchdog_Tests)
| | | | | | | | | | | | | | | | | 43.342% -[Tests innerLoop2] (in PuppyWatchdog_Tests)
🐶🐶🐶🐶🐶🐶🐶🐶🐶🐶
```

## Requirements

Both iOS and macOS platforms are supported, watchOS and tvOS support can be achieved only after PLCrashReporter will support them.

## Installation

PuppyWatchdog is available through [CocoaPods](http://cocoapods.org). To install
it, simply add the following line to your Podfile:

```ruby
pod 'PuppyWatchdog', :configurations => ['Debug']
```

If you are using `use_frameworks!` you may be needed this code in your Podfile:
```ruby
pre_install do |installer|
    def installer.verify_no_static_framework_transitive_dependencies; end
end

post_install do |installer|
    installer.pods_project.targets.flat_map(&:build_configurations).each { |bc|
        bc.build_settings['CLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES'] = 'Yes'
    }
end
```

If you are using Carthage, please report any problems you faced. **Will add Carthage instruction soon.**

## Author

Anton Bukov, k06a@mlworks.com

## License

PuppyWatchdog is available under the MIT license. See the LICENSE file for more info.
