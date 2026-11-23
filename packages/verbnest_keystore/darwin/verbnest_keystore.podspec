Pod::Spec.new do |s|
  s.name             = 'verbnest_keystore'
  s.version          = '0.70.0'
  s.summary          = 'System keystore bridge for VerbNest client certificates.'
  s.description      = 'Opens TLS connections with an identity held by the Keychain, through a loopback relay.'
  s.homepage         = 'https://github.com/Omni-Technical-Solutions/VerbNest'
  s.license          = { :type => 'BUSL-1.1' }
  s.author           = { 'Omni Technical Solutions' => 'noreply@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'verbnest_keystore/Sources/verbnest_keystore/**/*.swift'
  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'
  s.ios.deployment_target = '15.0'
  s.osx.deployment_target = '12.0'
  s.swift_version = '5.0'
end
