Pod::Spec.new do |s|
  s.name             = 'AvafliSDK'
  s.version          = '3.1.2'
  s.summary          = 'Sweepstakes-as-a-Service SDK for iOS apps'
  s.description      = <<-DESC
    Avafli SDK enables app publishers to instantly add sweepstakes and prizing
    functionality with a few lines of code. Turnkey solution for daily entries,
    streak rewards, winner announcements, and first-party data capture. The V2
    experience auto-opens once per day and claims entries automatically.
  DESC

  s.homepage         = 'https://avafli.com'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Avafli' => 'team@avafli.com' }
  s.source           = { :git => 'https://github.com/AVAFLI/avafli_ios_sdk.git', :tag => "v#{s.version}" }

  s.ios.deployment_target = '15.0'
  s.swift_version    = '5.9'

  s.source_files     = 'AvafliSDK/**/*.swift'
  s.resources        = 'AvafliSDK/Resources/**/*'
  # NOTE: CommonCrypto is a system MODULE (`import CommonCrypto`), not a
  # linkable framework — declaring it in s.frameworks fails the link step.
  s.frameworks       = 'UIKit', 'SwiftUI', 'Security'
end
