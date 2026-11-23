# Generates ios/Polish.xcodeproj from the sources on disk.
# Run from the ios/ folder:  gem install xcodeproj && ruby scripts/generate_project.rb
require 'xcodeproj'
require 'fileutils'

ROOT = File.expand_path('..', __dir__)
PROJECT_PATH = File.join(ROOT, 'Polish.xcodeproj')
BUNDLE_ID = ENV.fetch('BUNDLE_ID', 'com.eitanshay.polish')

FileUtils.rm_rf(PROJECT_PATH)
project = Xcodeproj::Project.new(PROJECT_PATH)
project.root_object.attributes['LastUpgradeCheck'] = '2600'
project.root_object.attributes['LastSwiftUpdateCheck'] = '2600'

target = project.new_target(:application, 'Polish', :ios, '17.0')
# Drop the SDK-pinned Foundation.framework reference the gem adds; Swift links system frameworks automatically.
target.frameworks_build_phase.files.to_a.each do |bf|
  ref = bf.file_ref
  bf.remove_from_project
  ref.remove_from_project if ref
end

def add_group_files(project, target, group_path, disk_dir, resources: false)
  group = project.main_group.find_subpath(group_path, true)
  group.set_source_tree('<group>')
  Dir.glob(File.join(disk_dir, '*')).sort.each do |path|
    name = File.basename(path)
    if File.directory?(path) && !name.end_with?('.xcassets')
      sub = group.new_group(name, name)
      add_children(sub, target, path, resources)
    else
      ref = group.new_reference(path)
      ref.path = name
      ref.source_tree = '<group>'
      attach(target, ref, name, resources)
    end
  end
  group
end

def add_children(group, target, dir, resources)
  Dir.glob(File.join(dir, '*')).sort.each do |path|
    name = File.basename(path)
    if File.directory?(path) && !name.end_with?('.xcassets')
      sub = group.new_group(name, name)
      add_children(sub, target, path, resources)
    else
      ref = group.new_reference(path)
      ref.path = name
      ref.source_tree = '<group>'
      attach(target, ref, name, resources)
    end
  end
end

def attach(target, ref, name, _resources)
  case File.extname(name)
  when '.swift'
    target.source_build_phase.add_file_reference(ref)
  when '.xcassets', '.ttf'
    target.resources_build_phase.add_file_reference(ref)
  end
end

# App sources and resources (Info.plist is referenced by build setting, not copied).
app_group = project.main_group.new_group('Polish', 'Polish')
add_children(app_group, target, File.join(ROOT, 'Polish'), true)

# Core logic, compiled straight into the app. The same files are unit-tested by PolishCore/Package.swift.
core_group = project.main_group.new_group('PolishCore', 'PolishCore/Sources/PolishCore')
add_children(core_group, target, File.join(ROOT, 'PolishCore', 'Sources', 'PolishCore'), false)

target.build_configurations.each do |config|
  s = config.build_settings
  s['PRODUCT_BUNDLE_IDENTIFIER'] = BUNDLE_ID
  s['PRODUCT_NAME'] = 'Polish'
  s['INFOPLIST_FILE'] = 'Polish/Info.plist'
  s['GENERATE_INFOPLIST_FILE'] = 'NO'
  s['SWIFT_VERSION'] = '5.0'
  s['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
  s['TARGETED_DEVICE_FAMILY'] = '1'
  s['SUPPORTS_MACCATALYST'] = 'NO'
  s['SUPPORTED_PLATFORMS'] = 'iphoneos iphonesimulator'
  s['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'AppIcon'
  s['ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME'] = 'AccentColor'
  s['CODE_SIGN_STYLE'] = 'Automatic'
  s['DEVELOPMENT_TEAM'] = ''
  s['CURRENT_PROJECT_VERSION'] = '1'
  s['MARKETING_VERSION'] = '1.0'
  s['VERSIONING_SYSTEM'] = 'apple-generic'
  s['ENABLE_PREVIEWS'] = 'YES'
  s['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks']
  s['SWIFT_EMIT_LOC_STRINGS'] = 'NO'
  s['ENABLE_USER_SCRIPT_SANDBOXING'] = 'YES'
end

project.build_configurations.each do |config|
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['CURRENT_PROJECT_VERSION'] = '1'
  config.build_settings['VERSIONING_SYSTEM'] = 'apple-generic'
end

project.save

# Shared scheme: CI (Codemagic) can only see shared schemes.
scheme = Xcodeproj::XCScheme.new
scheme.configure_with_targets(target, nil, launch_target: true)
scheme.save_as(PROJECT_PATH, 'Polish', true)

puts "Generated #{PROJECT_PATH} (bundle id #{BUNDLE_ID})"
