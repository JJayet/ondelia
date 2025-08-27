# AudiobookReader - Suggested Development Commands

## Project Management Commands

### Xcode Operations
```bash
# Open project in Xcode
open AudiobookReader.xcodeproj

# Build the project
xcodebuild -project AudiobookReader.xcodeproj -scheme AudiobookReader -destination 'platform=iOS Simulator,name=iPhone 15' build

# Clean build folder
xcodebuild clean -project AudiobookReader.xcodeproj -scheme AudiobookReader
```

### File and Code Search
```bash
# Find Swift files (using fd if available, otherwise find)
fd -e swift
find . -name "*.swift" -type f

# Search for text in codebase (using rg if available, otherwise grep)
rg "AudioEngine" --type swift
grep -r "AudioEngine" --include="*.swift" .

# Search for code patterns (using ast-grep if available)
ast-grep --pattern 'class $NAME: ObservableObject { $$$ }'
```

### Git Operations
```bash
# Check project status
git status

# View recent commits
git log --oneline -10

# Create feature branch
git checkout -b feature/reorganization

# Stage and commit changes
git add .
git commit -m "Implement project reorganization"
```

### File Structure Analysis
```bash
# List project structure
find AudiobookReader -type f -name "*.swift" | sort

# Count Swift files by type
find AudiobookReader -name "*.swift" -exec basename {} \; | sort | uniq -c

# Find large files
find AudiobookReader -name "*.swift" -exec wc -l {} + | sort -n
```

## Development Workflow Commands

### Testing
```bash
# Run unit tests
xcodebuild test -project AudiobookReader.xcodeproj -scheme AudiobookReader -destination 'platform=iOS Simulator,name=iPhone 15'

# Run UI tests
xcodebuild test -project AudiobookReader.xcodeproj -scheme AudiobookReader -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:AudiobookReaderUITests
```

### Code Analysis
```bash
# Check for TODO/FIXME comments
rg "TODO|FIXME|HACK" --type swift || grep -r "TODO\|FIXME\|HACK" --include="*.swift" .

# Find unused imports (requires additional tools)
# Manual review recommended for SwiftUI projects
```

### Project Reorganization Specific
```bash
# Create directory structure
mkdir -p AudiobookReader/{App,Features/{Home,Library,Player,Bookmarks,Settings},Core/{Models,Services,Managers},Shared,Resources}

# Move files systematically (example)
mv AudiobookReader/AudiobookReaderApp.swift AudiobookReader/App/
mv AudiobookReader/MainTabView.swift AudiobookReader/App/

# Verify file moves don't break builds
xcodebuild build -project AudiobookReader.xcodeproj -scheme AudiobookReader -destination 'platform=iOS Simulator,name=iPhone 15'
```

## System Utilities (macOS)
```bash
# File operations
ls -la
cp source destination
mv source destination
mkdir -p path/to/directory

# Text processing
cat filename
head -n 20 filename
tail -n 20 filename
grep -n "pattern" filename
```