Pod::Spec.new do |s|
  s.name             = 'flutter_eml_msg_viewer'
  s.version          = '1.1.0'
  s.summary          = 'In-app previewer and parser for .eml and .msg email files on Android and iOS.'
  s.description      = <<-DESC
An in-app previewer and parser for .eml and .msg email files on Android and iOS with zero external dependencies.
                       DESC
  s.homepage         = 'https://github.com/amidelu/Flutter-Eml-Msg-Viewer'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'amidelu' => 'email@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'flutter_eml_msg_viewer/Sources/flutter_eml_msg_viewer/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '12.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
