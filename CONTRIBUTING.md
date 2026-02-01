# Contributing to RetroVision Cabs Converter

Thank you for your interest in contributing! This document provides guidelines and instructions for contributing.

## Code of Conduct

By participating in this project, you agree to abide by our [Code of Conduct](CODE_OF_CONDUCT.md).

## How to Contribute

### Reporting Bugs

Before creating a bug report, please check existing issues to avoid duplicates.

**When reporting a bug, include:**
- macOS version
- App version (from About menu)
- Steps to reproduce
- Expected vs actual behavior
- Screenshots if applicable
- Console logs if relevant

### Suggesting Features

We welcome feature suggestions! Please:
1. Check if the feature has already been requested
2. Clearly describe the use case
3. Explain why this would benefit other users

### Pull Requests

#### Before You Start

1. **Open an issue first** - Discuss your proposed changes before investing time
2. **Fork the repository** - Work on your own copy
3. **Create a feature branch** - Never work directly on `main`

#### Development Setup

1. **Requirements:**
   - Xcode 15.0+
   - macOS 14.0+
   - Blender 3.6+ (for testing conversions)
   - Python 3.9+ (for Blender scripts)

2. **Clone your fork:**
   ```bash
   git clone https://github.com/YOUR_USERNAME/RetroVisionCabsConverter.git
   cd RetroVisionCabsConverter
   ```

3. **Create a branch:**
   ```bash
   git checkout -b feature/your-feature-name
   # or
   git checkout -b fix/issue-number-description
   ```

#### Coding Standards

- **Swift Style:** Follow [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/)
- **SwiftUI:** Use declarative patterns, avoid UIKit unless necessary
- **Comments:** Document complex logic, not obvious code
- **Naming:** Use descriptive names; avoid abbreviations

#### Commit Messages

Follow conventional commits format:

```
type(scope): brief description

[optional body with more details]

[optional footer with issue references]
```

**Types:**
- `feat:` New feature
- `fix:` Bug fix
- `docs:` Documentation only
- `style:` Code style (formatting, no logic change)
- `refactor:` Code refactoring
- `test:` Adding/updating tests
- `chore:` Maintenance tasks

**Examples:**
```
feat(gallery): add batch export for cabinets
fix(converter): handle special characters in filenames
docs: update installation instructions
```

#### Pull Request Process

1. **Update your branch:**
   ```bash
   git fetch upstream
   git rebase upstream/main
   ```

2. **Test your changes:**
   - Build successfully in Xcode
   - Test affected features manually
   - Ensure no regressions in existing functionality

3. **Submit PR:**
   - Fill out the PR template completely
   - Link related issues
   - Add screenshots for UI changes
   - Request review when ready

4. **Address feedback:**
   - Respond to all review comments
   - Push fixes as new commits (don't force push during review)
   - Re-request review after addressing feedback

### What We're Looking For

**High Priority:**
- Bug fixes
- Performance improvements
- Accessibility improvements
- Documentation improvements

**Welcome:**
- New cabinet/prop templates
- UI/UX enhancements
- Code quality improvements

**Please Discuss First:**
- Major architectural changes
- New external dependencies
- Changes to core conversion logic

## Project Structure

```
RetroVisionCabsConverter/
├── RetroVisionCabsConverter/     # Main app source
│   ├── CabinetGallery/           # Cabinet browsing & management
│   ├── PropsGallery/             # Props browsing & management
│   ├── Resources/                # Templates, assets, scripts
│   └── *.swift                   # Core app files
├── Scripts/                      # Build & release scripts
├── docs/                         # Additional documentation
└── .github/                      # GitHub templates & workflows
```

## Getting Help

- **Questions:** Open a [Discussion](https://github.com/britxpatusa/RetroVisionCabsConverter/discussions)
- **Bugs:** Open an [Issue](https://github.com/britxpatusa/RetroVisionCabsConverter/issues)
- **Contact:** support@RetroVision.pro

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).

---

Thank you for helping make RetroVision Cabs Converter better!
