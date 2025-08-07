#!/bin/bash

echo "🔧 Fixing TrackIt iOS Build Errors"
echo "=================================="

# Navigate to the project directory
cd "$(dirname "$0")"

echo "📝 Instructions to fix the build errors:"
echo ""
echo "1. Core Data Model Error (HealthMetric.xcdatamodeld):"
echo "   - Open Xcode"
echo "   - In the Project Navigator, look for HealthMetric.xcdatamodeld (it will be red/missing)"
echo "   - Right-click on it and select 'Delete'"
echo "   - Choose 'Remove Reference' when prompted"
echo ""
echo "2. If you still see 'backendIdOptional' errors:"
echo "   - Clean the build folder: Product → Clean Build Folder (⇧⌘K)"
echo "   - Delete Derived Data:"
echo "     • Go to Xcode → Settings → Locations"
echo "     • Click the arrow next to 'Derived Data'"
echo "     • Delete the folder for your project"
echo ""
echo "3. Rebuild the project:"
echo "   - Press ⌘B to build"
echo ""

# Check if there are any old references in the code
echo "🔍 Checking for any remaining issues..."

# Search for backendIdOptional references
if grep -r "backendIdOptional" --include="*.swift" LifeTrackerX/ 2>/dev/null; then
    echo "⚠️  Found references to 'backendIdOptional' - these need to be changed to 'backendId'"
else
    echo "✅ No references to 'backendIdOptional' found"
fi

# Check for old source values
if grep -r 'source == "manual"' --include="*.swift" LifeTrackerX/ 2>/dev/null; then
    echo "⚠️  Found old source value comparisons that might need updating"
fi

echo ""
echo "✨ Script complete!"
echo ""
echo "Note: The Swift concurrency warnings have been fixed in the code."
echo "After removing the Core Data model reference from Xcode, your app should build successfully."