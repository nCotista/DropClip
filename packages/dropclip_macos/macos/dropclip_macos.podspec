#
# DropClip macOS native layer (T1.6). The Flutter-free core in Classes/Core
# is also built and tested on its own with `swift test` (Package.swift).
#
Pod::Spec.new do |s|
  s.name             = 'dropclip_macos'
  s.version          = '1.0.0'
  s.summary          = 'DropClip macOS pasteboard watcher for the clipboard channels.'
  s.homepage         = 'https://github.com/nCotista/DropClip'
  s.license          = { :type => 'Proprietary', :text => 'DropClip project' }
  s.author           = 'DropClip team'
  s.source           = { :path => '.' }
  s.source_files     = 'dropclip_macos/Sources/dropclip_macos/**/*.swift'
  s.dependency 'FlutterMacOS'
  s.platform         = :osx, '10.15'
  s.swift_version    = '5.0'
end
