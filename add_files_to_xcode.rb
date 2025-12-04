#!/usr/bin/env ruby

require 'xcodeproj'

project_path = 'iSH.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Find the app group
app_group = project.main_group.children.find { |g| g.display_name == 'app' }

if app_group.nil?
  puts "❌ Could not find 'app' group"
  exit 1
end

# Files to add (relative to app group, not root)
files_to_add = [
  'XREFManager.h',
  'XREFManager.m',
  'SyntaxHighlighter.h',
  'SyntaxHighlighter.m',
  'MachOParser.h',
  'MachOParser.m',
  'SymbolResolver.h',
  'SymbolResolver.m',
  'StackFrameTracker.h',
  'StackFrameTracker.m',
  'BasicBlock.h',
  'BasicBlock.m',
  'CFGBuilder.h',
  'CFGBuilder.m'
]

# Find the iSH target
target = project.targets.find { |t| t.name == 'iSH' }

if target.nil?
  puts "❌ Could not find 'iSH' target"
  exit 1
end

files_to_add.each do |filename|
  # Check if file already exists in project
  existing = app_group.files.find { |f| f.display_name == filename }

  if existing
    puts "⚠️  #{filename} already exists in project"
    next
  end

  # Add file reference (filename only, since app_group already points to 'app' directory)
  file_ref = app_group.new_file(filename)

  # Add to build phase if it's a .m file
  if filename.end_with?('.m')
    target.source_build_phase.add_file_reference(file_ref)
    puts "✅ Added #{filename} to sources"
  else
    puts "✅ Added #{filename} to project"
  end
end

# Save project
project.save

puts "\n🎉 Done! Now run: xcodebuild -project iSH.xcodeproj -scheme iSH build"
