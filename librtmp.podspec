Pod::Spec.new do |s|
  s.name         = "librtmp"
  s.version      = "0.0.1"
  s.summary      = "librtmp"
  s.description  = <<-DESC
                   this pod downloads librtmp source code (under LGPL v2.1).
                   please check the license when you distribute your code or binary.
                   DESC

  s.homepage     = "http://github.com/banjun/librtmp"
  s.license      = {:type => 'GNU LGPL 2.1', :file => 'librtmp/COPYING'}
  s.author             = { "banjun" => "banjun@gmail.com" }
  s.ios.deployment_target = '7.0'
  s.osx.deployment_target = '10.9'
  s.source       = { :git => "git://git.ffmpeg.org/rtmpdump", :commit => "dc76f0a8461e6c8f1277eba58eae201b2dc1d06a" }
  s.source_files  = 'librtmp/*.{h,m}'
  s.exclude_files = 'Classes/Exclude'
  s.preserve_paths = 'librtmp/COPYING'


  # ――― Project Linking ―――――――――――――――――――――――――――――――――――――――――――――――――――――――――― #
  #
  #  Link your library with frameworks, or libraries. Libraries do not include
  #  the lib prefix of their name.
  #

  # s.framework  = 'SomeFramework'
  # s.frameworks = 'SomeFramework', 'AnotherFramework'

  # s.library   = 'iconv'
  # s.libraries = 'iconv', 'xml2'


  # ――― Project Settings ――――――――――――――――――――――――――――――――――――――――――――――――――――――――― #
  #
  #  If your library depends on compiler flags you can set them in the xcconfig hash
  #  where they will only apply to your library. If you depend on other Podspecs
  #  you can include multiple dependencies to ensure it works.

  # s.requires_arc = true

  # s.xcconfig = { 'HEADER_SEARCH_PATHS' => '$(SDKROOT)/usr/include/libxml2' }
  # s.dependency 'JSONKit', '~> 1.4'
end
