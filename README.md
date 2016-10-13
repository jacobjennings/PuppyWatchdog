# PuppyWatchdog

[![CI Status](http://img.shields.io/travis/Anton Bukov/PuppyWatchdog.svg?style=flat)](https://travis-ci.org/Anton Bukov/PuppyWatchdog)
[![Version](https://img.shields.io/cocoapods/v/PuppyWatchdog.svg?style=flat)](http://cocoapods.org/pods/PuppyWatchdog)
[![License](https://img.shields.io/cocoapods/l/PuppyWatchdog.svg?style=flat)](http://cocoapods.org/pods/PuppyWatchdog)
[![Platform](https://img.shields.io/cocoapods/p/PuppyWatchdog.svg?style=flat)](http://cocoapods.org/pods/PuppyWatchdog)

Main thread performance monitor 🐶. Lives in separate thread and check, that main thread executes small commands in short time. If faces some delays starts grabbing main thread callstacks and then report summary callstacks tree. Need no dSYM files for symbolication.

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
2016-10-24 00:46:46.721 xctest[18048:6230312] 🐶 Main thread was blocked for 0.17 sec
2016-10-24 00:46:46.824 xctest[18048:6230312] 🐶 Main thread is still blocked for 0.27 sec
2016-10-24 00:46:46.929 xctest[18048:6230312] 🐶 Main thread is still blocked for 0.37 sec
2016-10-24 00:46:47.039 xctest[18048:6230312] 🐶 Main thread is still blocked for 0.48 sec
2016-10-24 00:46:47.150 xctest[18048:6230312] 🐶 Main thread is still blocked for 0.60 sec
2016-10-24 00:46:47.263 xctest[18048:6230312] 🐶 Main thread is still blocked for 0.71 sec
2016-10-24 00:46:48.379 xctest[18048:6230312] 
🐶🐶🐶🐶🐶🐶🐶🐶🐶🐶 Collected 39 reports for 1.82 sec:
100.000% _start (in libdyld.dylib)
| 100.000% __mh_execute_header (in xctest)
| | 100.000% __XCTestMain (in XCTest)
| | | 100.000% -[XCTestDriver _checkForTestManager] (in XCTest)
| | | | 100.000% -[XCTestDriver _runSuite] (in XCTest)
| | | | | 100.000% -[XCTestObservationCenter _observeTestExecutionForBlock:] (in XCTest)
| | | | | | 100.000% ___25-[XCTestDriver _runSuite]_block_invoke (in XCTest)
| | | | | | | 100.000% -[XCTestSuite performTest:] (in XCTest)
| | | | | | | | 100.000% -[XCTestSuite performTest:] (in XCTest)
| | | | | | | | | 100.000% -[XCTestSuite performTest:] (in XCTest)
| | | | | | | | | | 100.000% -[XCTestCase performTest:] (in XCTest)
| | | | | | | | | | | 100.000% -[XCTestCase invokeTest] (in XCTest)
| | | | | | | | | | | | 100.000% -[XCTestContext performInScope:] (in XCTest)
| | | | | | | | | | | | | 100.000% ___24-[XCTestCase invokeTest]_block_invoke_2 (in XCTest)
| | | | | | | | | | | | | | 100.000% -[NSInvocation invoke] (in CoreFoundation)
| | | | | | | | | | | | | | | 100.000% ___invoking___ (in CoreFoundation)
| | | | | | | | | | | | | | | | 100.000% -[Tests testExample] (in PuppyWatchdog_Tests)
| | | | | | | | | | | | | | | | | 63.282% -[Tests innerLoop] (in PuppyWatchdog_Tests)
| | | | | | | | | | | | | | | | | 34.154% -[Tests innerLoop2] (in PuppyWatchdog_Tests)
🐶🐶🐶🐶🐶🐶🐶🐶🐶🐶
```

## Requirements

Right now only iOS platform supported, but you can help to make it work on macOS: https://github.com/CocoaPods/CocoaPods/issues/6070

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

## Author

Anton Bukov, k06a@mlworks.com

## License

PuppyWatchdog is available under the MIT license. See the LICENSE file for more info.
