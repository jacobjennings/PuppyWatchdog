Pod::Spec.new do |s|
  s.name             = 'PuppyWatchdog'
  s.version          = '0.1.1'
  s.summary          = 'Main thread performance monitor 🐶'

  s.description      = <<-DESC
                        Main thread performance monitor 🐶. Lives in separate
                        thread and check, that main thread executes small
                        commands in short time. If faces some delays starts
                        grabbing main thread callstacks and then report summary
                        callstacks tree. Need no dSYM files for symbolication.
                       DESC

  s.homepage         = 'https://github.com/ML-Works/PuppyWatchdog'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Anton Bukov' => 'k06aaa@gmail.com' }
  s.source           = { :git => 'https://github.com/ML-Works/PuppyWatchdog.git', :tag => s.version.to_s }

  s.ios.deployment_target = '7.0'
  #s.osx.deployment_target = '10.8'

  s.source_files = 'PuppyWatchdog/Classes/**/*'
  #s.public_header_files = 'PuppyWatchdog/Classes/PuppyWatchdog.h', 'PuppyWatchdog/Classes/MLWPuppyWatchdog.h'

  s.library = 'c++'

  #s.dependency 'PLCrashReporter', '~> 1.2'
  s.dependency 'PLCrashReporter-DynamicFramework', '~> 1.3.0'
  s.dependency 'RuntimeRoutines', '~> 0.3.2'
  s.dependency 'libMachO', '~> 0.1.1'
end
