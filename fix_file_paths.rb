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

# Files to fix
files_to_fix = [
  'XREFManager.h',
  'XREFManager.m',
  'SyntaxHighlighter.h',
  'SyntaxHighlighter.m'
]

files_to_fix.each do |filename|
  file_ref = app_group.files.find { |f| f.display_name == filename }

  if file_ref
    # Fix the path - should be just the filename relative to app group
    old_path = file_ref.path
    file_ref.path = filename
    puts "✅ Fixed #{filename}: #{old_path} → #{filename}"
  else
    puts "⚠️  #{filename} not found in project"
  end
end

# Save project
project.save

puts "\n🎉 Fixed! Now build again."
