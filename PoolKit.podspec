Pod::Spec.new do |s|
  s.name             = 'PoolKit'
  s.version          = '0.2.0'
  s.summary          = 'On-device understanding of a photo library, with grants the person controls.'
  s.description      = <<~DESC
    PoolKit reads the photos and screenshots a person allows, on the device, and answers
    searches, questions, interests, places, people and rules for your app under grants the
    person controls. The Swift package is the main route; this pod ships the same SDK as a
    binary XCFramework for CocoaPods and React Native apps.
  DESC
  s.homepage         = 'https://docs.pool.day'
  s.license          = { :type => 'Commercial', :text => 'Copyright Random Access Memories Inc. Use is subject to the PoolKit terms at https://pool.day/developers.' }
  s.author           = { 'Pool' => 'developers@pool.day' }
  s.platform         = :ios, '18.0'
  s.swift_versions   = ['5.10', '6.0']
  # Built by sdk/ios/tools/build-xcframework.sh and attached to the release on the public pool-kit repo.
  s.source           = { :http => "https://github.com/ram-company/pool-kit/releases/download/#{s.version}/PoolKit.xcframework.zip", :flatten => false }
  s.vendored_frameworks = 'PoolKit.xcframework'
  s.frameworks       = 'Photos', 'Vision', 'CoreML', 'NaturalLanguage', 'MapKit', 'CoreLocation', 'Network', 'DeviceCheck', 'BackgroundTasks', 'Accelerate', 'CoreImage'
  s.weak_frameworks  = 'FoundationModels'
  s.libraries        = 'sqlite3', 'c++'
  # The privacy manifest ships inside the framework's resource bundle.
end
