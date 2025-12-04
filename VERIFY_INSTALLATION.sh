#!/bin/bash
# Verify XSH new features installation

echo "🔍 Verifying XSH Installation..."
echo ""

# Check if files exist
echo "📁 Checking files..."
FILES=(
    "app/SSHConnectionManager.h"
    "app/SSHConnectionManager.m"
    "app/SSHManagerViewController.h"
    "app/SSHManagerViewController.m"
    "app/SplitTerminalViewController.h"
    "app/SplitTerminalViewController.m"
    "app/CodeEditorViewController.h"
    "app/CodeEditorViewController.m"
)

ALL_EXIST=true
for file in "${FILES[@]}"; do
    if [ -f "$file" ]; then
        echo "✅ $file"
    else
        echo "❌ $file - MISSING!"
        ALL_EXIST=false
    fi
done

echo ""

# Check if files are in project
echo "🔨 Checking Xcode project..."
if grep -q "SSHManagerViewController.m" iSH.xcodeproj/project.pbxproj; then
    echo "✅ SSHManagerViewController.m in project"
else
    echo "⚠️  SSHManagerViewController.m NOT in project - Add it manually!"
fi

if grep -q "SplitTerminalViewController.m" iSH.xcodeproj/project.pbxproj; then
    echo "✅ SplitTerminalViewController.m in project"
else
    echo "⚠️  SplitTerminalViewController.m NOT in project - Add it manually!"
fi

if grep -q "CodeEditorViewController.m" iSH.xcodeproj/project.pbxproj; then
    echo "✅ CodeEditorViewController.m in project"
else
    echo "⚠️  CodeEditorViewController.m NOT in project - Add it manually!"
fi

if grep -q "SSHConnectionManager.m" iSH.xcodeproj/project.pbxproj; then
    echo "✅ SSHConnectionManager.m in project"
else
    echo "⚠️  SSHConnectionManager.m NOT in project - Add it manually!"
fi

echo ""
echo "📋 Summary:"
if [ "$ALL_EXIST" = true ]; then
    echo "✅ All files exist"
else
    echo "❌ Some files are missing"
fi

echo ""
echo "Next steps:"
echo "1. Open Xcode: iSH.xcodeproj"
echo "2. Add missing .m files to Build Phases → Compile Sources"
echo "3. Clean Build Folder (Cmd+Shift+K)"
echo "4. Build (Cmd+B)"
