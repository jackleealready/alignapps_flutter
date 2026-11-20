Pod::Spec.new do |s|
  s.name             = 'alignapps_flutter'
  s.version          = '0.3.1'
  s.summary          = 'AlignApps attribution bridge for Flutter.'
  s.description      = 'Flutter bridge for the AlignApps attribution SDK.'
  s.homepage         = 'https://github.com/alignapps/alignapps-sdk-android'
  s.license          = { :type => 'Proprietary' }
  s.author           = { 'AlignApps' => 'support@alignapps.example' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*.{swift,h,m}'
  s.public_header_files = 'Classes/**/*.h'
  s.dependency 'Flutter'
  s.dependency 'GoogleAdsOnDeviceConversion', '3.0.0'
  s.platform         = :ios, '14.5'
  s.static_framework = true
  s.swift_version    = '5.0'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'OTHER_LDFLAGS' => '-ObjC -lc++'
  }
  s.resource_bundles = {
    'alignapps_flutter_privacy' => ['Classes/PrivacyInfo.xcprivacy']
  }
end
