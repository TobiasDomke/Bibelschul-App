# Adds the LesewegWidget extension (home-screen widget + Live Activity) to
# ios/Runner.xcodeproj. Idempotent. Run from bibelschul_app/ios:
#   GEM_HOME=/opt/homebrew/Cellar/cocoapods/<version>/libexec ruby ../tool/add_widget_target.rb
require 'xcodeproj'

project = Xcodeproj::Project.open('Runner.xcodeproj')
runner = project.targets.find { |t| t.name == 'Runner' }
abort 'Runner target missing' unless runner
if project.targets.any? { |t| t.name == 'LesewegWidget' }
  puts 'LesewegWidget already present'
  exit
end

bundle_id = 'de.bibelschulapp.bibelschulApp'
widget = project.new_target(:app_extension, 'LesewegWidget', :ios, '17.0', nil, :swift)

shared_group = project.main_group.new_group('Shared', 'Shared')
shared_file = shared_group.new_file('LesewegShared.swift')
widget_group = project.main_group.new_group('LesewegWidget', 'LesewegWidget')
widget_file = widget_group.new_file('LesewegWidget.swift')
widget_group.new_file('Info.plist')
widget_group.new_file('LesewegWidget.entitlements')
runner_group = project.main_group.children.find { |g| g.respond_to?(:path) && g.path == 'Runner' }
bridge_file = runner_group.new_file('NativeBridge.swift')
runner_group.new_file('Runner.entitlements')

widget.add_file_references([widget_file, shared_file])
runner.add_file_references([bridge_file, shared_file])
%w[WidgetKit SwiftUI].each do |name|
  ref = project.frameworks_group.new_file("System/Library/Frameworks/#{name}.framework", :sdk_root)
  widget.frameworks_build_phase.add_file_reference(ref, true)
end

# Flutter builds Debug, Release and Profile; the extension needs all three.
debug_xcconfig = project.files.find { |f| f.path == 'Flutter/Debug.xcconfig' }
release_xcconfig = project.files.find { |f| f.path == 'Flutter/Release.xcconfig' }
unless widget.build_configurations.any? { |c| c.name == 'Profile' }
  profile = widget.add_build_configuration('Profile', :release)
end
widget.build_configurations.each do |config|
  config.base_configuration_reference = config.name == 'Debug' ? debug_xcconfig : release_xcconfig
  s = config.build_settings
  s['PRODUCT_BUNDLE_IDENTIFIER'] = "#{bundle_id}.LesewegWidget"
  s['PRODUCT_NAME'] = '$(TARGET_NAME)'
  s['INFOPLIST_FILE'] = 'LesewegWidget/Info.plist'
  s['CODE_SIGN_ENTITLEMENTS'] = 'LesewegWidget/LesewegWidget.entitlements'
  s['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
  s['SWIFT_VERSION'] = '5.0'
  s['TARGETED_DEVICE_FAMILY'] = '1,2'
  s['SKIP_INSTALL'] = 'YES'
  s['GENERATE_INFOPLIST_FILE'] = 'NO'
  s['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks']
  s['ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME'] = ''
  s['ASSETCATALOG_COMPILER_WIDGET_BACKGROUND_COLOR_NAME'] = ''
  s['CODE_SIGN_STYLE'] = 'Automatic'
  s['APPLICATION_EXTENSION_API_ONLY'] = 'YES'
end
runner.build_configurations.each do |config|
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Runner/Runner.entitlements'
end

# Embed the extension before Flutter's script phases (avoids a build cycle).
runner.add_dependency(widget)
embed = runner.new_copy_files_build_phase('Embed Foundation Extensions')
embed.symbol_dst_subfolder_spec = :plug_ins
build_file = embed.add_file_reference(widget.product_reference, true)
build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
runner.build_phases.delete(embed)
resources_index = runner.build_phases.index(runner.resources_build_phase)
runner.build_phases.insert(resources_index + 1, embed)

project.save
puts 'LesewegWidget target added'
