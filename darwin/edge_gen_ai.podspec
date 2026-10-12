Pod::Spec.new do |s|
  s.name = 'edge_gen_ai'
  s.version = '0.4.0'
  s.summary = 'On-device generative AI using Apple Foundation Models.'
  s.description = s.summary
  s.homepage = 'https://github.com/manukj/EdgeAi'
  s.license = { :file => '../LICENSE' }
  s.author = { 'Manu' => 'https://github.com/manukj' }
  s.source = { :path => '.' }
  s.source_files = 'edge_gen_ai/Sources/edge_gen_ai/**/*.swift'
  s.ios.deployment_target = '13.0'
  s.osx.deployment_target = '12.0'
  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'
  s.swift_version = '5.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.resource_bundles = {
    'edge_gen_ai_privacy' => ['edge_gen_ai/Sources/edge_gen_ai/PrivacyInfo.xcprivacy']
  }
end
