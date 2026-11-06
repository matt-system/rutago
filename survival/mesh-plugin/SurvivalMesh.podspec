Pod::Spec.new do |s|
  s.name = 'SurvivalMesh'
  s.version = '0.1.0'
  s.summary = 'Native BLE mesh transport for SURVIVAL'
  s.license = { :type => 'MIT' }
  s.homepage = 'https://github.com/matt-system/rutago'
  s.author = 'SURVIVAL'
  s.source = { :git => 'https://github.com/matt-system/rutago.git', :tag => s.version.to_s }
  s.source_files = 'ios/Sources/SurvivalMeshPlugin/**/*.{swift,h,m}'
  s.ios.deployment_target = '14.0'
  s.dependency 'Capacitor'
  s.swift_version = '5.0'
  s.frameworks = 'CoreBluetooth'
end