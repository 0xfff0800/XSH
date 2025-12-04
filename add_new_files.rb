#!/usr/bin/env ruby
require 'xcodeproj'

project_path = 'iSH.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Find the app group
app_group = project.main_group['app'] || project.main_group.new_group('app')

# Create subgroups if they don't exist
disassembler_group = app_group['Disassembler'] || app_group.new_group('Disassembler')
analysis_group = app_group['Analysis'] || app_group.new_group('Analysis')

# Files to add
disassembler_files = [
  'app/MachOParser.h',
  'app/MachOParser.m',
  'app/SymbolResolver.h',
  'app/SymbolResolver.m',
  'app/StackFrameTracker.h',
  'app/StackFrameTracker.m'
]

analysis_files = [
  'app/BasicBlock.h',
  'app/BasicBlock.m',
  'app/CFGBuilder.h',
  'app/CFGBuilder.m'
]

# Find the iSH target
target = project.targets.find { |t| t.name == 'iSH' }

unless target
  puts "Error: Could not find iSH target"
  exit 1
end

# Add disassembler files
disassembler_files.each do |file_path|
  file_ref = disassembler_group.new_file(file_path)

  # Add .m files to compile sources
  if file_path.end_with?('.m')
    target.source_build_phase.add_file_reference(file_ref)
  end

  puts "Added #{file_path}"
end

# Add analysis files
analysis_files.each do |file_path|
  file_ref = analysis_group.new_file(file_path)

  # Add .m files to compile sources
  if file_path.end_with?('.m')
    target.source_build_phase.add_file_reference(file_ref)
  end

  puts "Added #{file_path}"
end

# Save the project
project.save

puts "\n✅ Successfully added all files to Xcode project!"
puts "Files added to compile sources: #{disassembler_files.count + analysis_files.count}"
