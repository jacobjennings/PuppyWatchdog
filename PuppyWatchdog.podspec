Pod::Spec.new do |s|
  s.name             = 'PuppyWatchdog'
  s.version          = '0.1.6'
  s.summary          = 'Main thread performance monitor 🐶'

  s.description      = <<-DESC
                        Main thread performance monitor 🐶. Lives in a separate 
                        thread and checks, that main thread executes small 
                        commands in a short time. If faces some delays it starts
                        grabbing the main thread callstacks and then reports callstacks 
                        summary tree. It doesn't require dSYM files for symbolication.
                       DESC

  s.homepage         = 'https://github.com/ML-Works/PuppyWatchdog'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Anton Bukov' => 'k06aaa@gmail.com' }
  s.source           = { :git => 'https://github.com/ML-Works/PuppyWatchdog.git', :tag => s.version.to_s }

  s.ios.deployment_target = '7.0'
  s.osx.deployment_target = '10.8'

  s.source_files = 'PuppyWatchdog/Classes/**/*'
  
  s.library = 'c++'

  #s.dependency 'PLCrashReporter', '~> 1.2'
  s.dependency 'PLCrashReporter-DynamicFramework', '~> 1.3.0.1'
end
