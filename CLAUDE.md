# Claude Code CLI - Operational Context

*Local Claude Code CLI workflow for the Astrid iOS app*

**Repository:** https://github.com/Graceful-Tools/astrid-ios
**Web App:** https://github.com/Graceful-Tools/astrid-web (separate repo)

**Note:** This file is for **Claude Code CLI only** (local development). For shared project context and workflows, see **[ASTRID.md](./ASTRID.md)**.

---

## Quick Start

```bash
# Open in Xcode
open "Astrid App.xcodeproj"

# Run predeploy checks before pushing
npm run predeploy
```

---

## Quality Gates

```bash
# Quick check (localizations + build only)
npm run predeploy:quick

# Standard check (localizations + build + unit tests)
npm run predeploy

# Full check with UI tests (slower)
npm run predeploy:full

# Run specific test suites
npm run test:unit     # Unit tests only
npm run test:ui       # UI tests only
npm run test:all      # Both unit and UI tests

# Localization validation
npm run check:localizations
```

---

## Deployment Workflow

**IMPORTANT: Push to main triggers Xcode Cloud build automatically.**

### Before Pushing

Always run predeploy checks:

```bash
npm run predeploy
```

This validates:
1. All localizations are complete (12 languages)
2. Project builds successfully
3. Unit tests pass

### Deployment Steps

```bash
# 1. Run predeploy checks
npm run predeploy

# 2. Commit changes
git add -A
git commit -m "feat: your changes"

# 3. Push to main (triggers Xcode Cloud)
git push origin main
```

### Xcode Cloud

- Push to main triggers automatic build
- TestFlight builds are distributed automatically
- Check build status in App Store Connect

---

## User Approval Points

### Always Ask Before:

1. **Pushing to main** - Triggers production build
2. **Significant changes** - Architecture, API changes
3. **Deleting files** - Confirm with user first

### Autonomous Actions (No Approval Needed)

- Code analysis and exploration
- Local builds and tests
- Implementation and testing
- Local commits
- Documentation updates

---

## Workflow Trigger: "Let's Fix Stuff"

When user says "let's fix stuff", "just fix stuff", or similar:

```bash
# 1. BASELINE TESTING - Run BEFORE any changes
npm run predeploy
# Document test pass rates before starting work

# 2. Pull tasks from Astrid iOS To-do list
cd ../astrid-web && npx tsx scripts/get-astrid-tasks.ts ios
```

### Coding Workflow

**See [ASTRID.md](./ASTRID.md) > "Coding Workflow"** for the full required workflow including:
- Baseline testing
- Strategy comment posting (Step 3)
- Implementation
- Verification
- Fix summary comment posting (Step 8)

### Task Scripts

**See [ASTRID.md](./ASTRID.md) > "Let's Fix Stuff Workflow"** for task script documentation.

**iOS-specific commands** (run from astrid-web directory):
```bash
# Pull iOS tasks
cd ../astrid-web && npx tsx scripts/get-astrid-tasks.ts ios
```

### Environment Setup

Copy `.env.local` from astrid-web if not present:
```bash
cp ../astrid-web/.env.local .env.local
```

Required variables:
- `ASTRID_OAUTH_CLIENT_ID` - OAuth client ID
- `ASTRID_OAUTH_CLIENT_SECRET` - OAuth client secret
- `ASTRID_IOS_LIST_ID` - iOS task list ID (`aa41c1a3-bd63-4c6d-9b87-42c6e0aafa36`)

---

## Project Structure

```
astrid-ios/
├── Astrid App/
│   ├── Core/             # Core functionality
│   │   ├── Authentication/  # Apple/Google OAuth
│   │   ├── Networking/      # API client
│   │   ├── Persistence/     # CoreData stack
│   │   ├── Services/        # Business logic
│   │   ├── Notifications/   # Push notifications
│   │   └── Sync/            # Data synchronization
│   ├── Models/           # Data models
│   ├── Views/            # SwiftUI views
│   ├── ViewModels/       # View models
│   ├── Extensions/       # Swift extensions
│   ├── Utilities/        # Helpers and constants
│   └── Resources/
│       └── Localizations/ # 12 language translations
├── Astrid/               # Shared code
├── Astrid AppTests/      # Unit tests
│   └── Tests/
│       ├── UnitTests/        # Fast unit tests
│       ├── IntegrationTests/ # Integration tests
│       └── Mocks/            # Test mocks
├── Astrid AppUITests/    # UI tests
├── ShareExtension/       # iOS share extension
├── docs/                 # Project documentation
├── scripts/              # Build and test scripts
└── package.json          # npm scripts for convenience
```

---

## Localization

The app supports 12 languages. **All strings must be localized.**

| Language | Code |
|----------|------|
| English | en (Base) |
| Spanish | es |
| French | fr |
| German | de |
| Italian | it |
| Japanese | ja |
| Korean | ko |
| Dutch | nl |
| Portuguese | pt |
| Russian | ru |
| Simplified Chinese | zh-Hans |
| Traditional Chinese | zh-Hant |

### Adding New Strings

1. Add to `en.lproj/Localizable.strings`
2. Add translations to ALL other language files
3. Run `npm run check:localizations` to verify

### Localization Check

```bash
npm run check:localizations
```

This validates all languages have matching keys.

---

## Testing

### Test Commands

| Command | Description |
|---------|-------------|
| `npm run test` | Run unit tests |
| `npm run test:unit` | Run unit tests |
| `npm run test:ui` | Run UI tests only |
| `npm run test:all` | Run both unit and UI tests |

### Test File Locations

| Test Type | Location |
|-----------|----------|
| Unit tests | `Astrid AppTests/Tests/UnitTests/` |
| Integration tests | `Astrid AppTests/Tests/IntegrationTests/` |
| Test mocks | `Astrid AppTests/Tests/Mocks/` |
| UI tests | `Astrid AppUITests/` |

### Xcode Commands (Alternative)

```bash
# Build
xcodebuild build -scheme "Astrid App" -destination "platform=iOS Simulator,name=iPhone 17" -quiet

# Run unit tests
xcodebuild test -scheme "Astrid App" -destination "platform=iOS Simulator,name=iPhone 17" -only-testing:"Astrid AppTests" -quiet

# Run UI tests
xcodebuild test -scheme "Astrid App" -destination "platform=iOS Simulator,name=iPhone 17" -only-testing:"Astrid AppUITests" -quiet
```

---

## API Integration

The app connects to the Astrid backend at `https://astrid.cc`.

### Key Endpoints

- **Authentication**: `/api/auth/apple`, `/api/auth/google`, `/api/auth/mobile-*`
- **Tasks**: `/api/tasks` (CRUD)
- **Lists**: `/api/lists` (CRUD)
- **Comments**: `/api/tasks/{id}/comments`
- **Real-time**: `/api/sse` (Server-Sent Events)

### API Contract

See `docs/API_CONTRACT.md` for the full API specification.

### Changing Backend URL

Edit `Astrid App/Utilities/Constants.swift`:

```swift
enum API {
    static let baseURL = "https://astrid.cc"
}
```

---

## Architecture Patterns

### Local-First Pattern

The app implements local-first architecture:

1. **Write Local, Sync Background** - All mutations save to Core Data immediately
2. **Read from Cache First** - UI reads Core Data, never waits for network
3. **Optimistic Updates** - Show changes instantly
4. **Background Sync** - 60-second sync timer + network restoration triggers

See `docs/LOCAL_FIRST_PATTERN.md` for implementation details.

### Code Style

- **SwiftUI** for all views
- **Async/await** for asynchronous operations
- **MVVM-like** architecture (Views + Services)
- **No external dependencies** (system frameworks only)

---

## Quick Reference

| Command | Purpose |
|---------|---------|
| `npm run predeploy:quick` | Quick check (build only) |
| `npm run predeploy` | Standard check (build + unit tests) |
| `npm run predeploy:full` | Full check (includes UI tests) |
| `npm run test` | Run unit tests |
| `npm run test:all` | Run all tests |
| `npm run check:localizations` | Validate translations |
| `npm run build` | Build app (quiet mode) |

### Common Workflows

| Scenario | Action |
|----------|--------|
| Before pushing | `npm run predeploy` |
| After localization changes | `npm run check:localizations` |
| Full validation | `npm run predeploy:full` |
| Debug build issues | `npm run build:verbose` |

---

## Documentation

### Root Files

- `ASTRID.md` - Project context and workflows (symlink to astrid-web)
- `CLAUDE.md` - Claude Code CLI context (this file)
- `README.md` - Project overview
- `CONTRIBUTING.md` - Contribution guidelines
- `SECURITY.md` - Security policy
- `CODE_OF_CONDUCT.md` - Community standards

### Setup Guides

- `GOOGLE_OAUTH_SETUP.md` - Google OAuth configuration
- `SHARE_EXTENSION_SETUP.md` - Share extension setup
- `README_XCODE_SETUP.md` - Complete Xcode setup

### Technical Docs (in `/docs/`)

- `API_CONTRACT.md` - Backend API specification
- `LOCAL_FIRST_PATTERN.md` - Offline-first architecture

---

## See Also

- **[ASTRID.md](./ASTRID.md)** - Project context, coding workflow, task management
- **[README.md](./README.md)** - Project overview and setup
- **[docs/API_CONTRACT.md](./docs/API_CONTRACT.md)** - API specification
- **[docs/LOCAL_FIRST_PATTERN.md](./docs/LOCAL_FIRST_PATTERN.md)** - Offline architecture
- **[CONTRIBUTING.md](./CONTRIBUTING.md)** - How to contribute

---

*This file is for Claude Code CLI. For project context and workflows, see ASTRID.md.*
