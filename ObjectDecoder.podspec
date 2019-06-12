Pod::Spec.new do |s|
  s.name             = 'ObjectDecoder'
  s.version          = '0.3.0'
  s.summary          = 'A Swift Class that decodes basic structures such as Dictionaries and Arrays.'

  s.description      = <<-DESC
ObjectDecoder is a Swift Class that allows for decoding common Swift types such as Dictionary and Array. Use object decoder to convert data models that conform to Decodable from basic structures.
                       DESC

  s.homepage         = 'https://github.com/LucasBest/ObjectDecoder'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Lucas Best' => 'lucas.best.5@gmail.com' }
  s.source           = { :git => 'https://github.com/LucasBest/ObjectDecoder.git', :tag => s.version.to_s }
  s.social_media_url = 'https://twitter.com/thereallu5'

  s.swift_version = '5.0'
  s.ios.deployment_target = '10.0'
  s.watchos.deployment_target = '2.0'

  s.source_files = 'ObjectDecoder/Classes/**/*'
end
