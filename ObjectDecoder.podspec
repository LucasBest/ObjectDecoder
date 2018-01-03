#
# Be sure to run `pod lib lint ObjectDecoder.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'ObjectDecoder'
  s.version          = '0.1.0'
  s.summary          = 'A Swift Class that decodes basic structures such as Dictionaries and Arrays.'

# This description is used to generate tags and improve search results.
#   * Think: What does it do? Why did you write it? What is the focus?
#   * Try to keep it short, snappy and to the point.
#   * Write the description between the DESC delimiters below.
#   * Finally, don't worry about the indent, CocoaPods strips it!

  s.description      = <<-DESC
ObjectDecoder is a Swift Class that allows for decoding common Swift types such as Dictionary and Array. Use object decoder to convert data models that conform to Decodable from basic structures.
                       DESC

  s.homepage         = 'https://github.com/LucasBest/ObjectDecoder'
  # s.screenshots     = 'www.example.com/screenshots_1', 'www.example.com/screenshots_2'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Lucas Best' => 'lucas.best.5@gmail.com' }
  s.source           = { :git => 'https://github.com/LucasBest/ObjectDecoder.git', :tag => s.version.to_s }
  # s.social_media_url = 'https://twitter.com/<TWITTER_USERNAME>'

  s.ios.deployment_target = '8.0'

  s.source_files = 'ObjectDecoder/Classes/**/*'
  
  # s.resource_bundles = {
  #   'ObjectDecoder' => ['ObjectDecoder/Assets/*.png']
  # }

  # s.public_header_files = 'Pod/Classes/**/*.h'
  # s.frameworks = 'UIKit', 'MapKit'
  # s.dependency 'AFNetworking', '~> 2.3'
end
