# Changelog

All notable changes to ReaMD will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2026-05-27

### Added

#### New features
- **Search in document** (`Ctrl+F`) with match counter and prev/next navigation
  (`Enter`/`F3` next, `Shift+F3` prev, `Esc` close).
- **Cue List panel** — floating window listing every linked fragment sorted by
  earliest item time. Click a row to jump to the item and scroll the markdown.
  Filter box lets you narrow the list. Toolbar toggle button "Cue".
- **Export to regions** — `Scenario → Tools → Export linked fragments to regions`
  creates a REAPER region for each linked fragment, named with the identifier
  and colored by category.
- **Auto-Link by name** — `Scenario → Tools → Auto-Link by name` now matches
  both **headings** and **table rows** against **item take names** as well as
  region names. Lines that already have links are skipped.
- **`time://HH:MM:SS` link scheme** — clicking a markdown link like
  `[Intro](time://1:23)` sets the REAPER edit cursor to that timestamp. Accepts
  `HH:MM:SS`, `MM:SS`, and bare-seconds (`12.5`).
- **Strikethrough** (`~~text~~`) is now parsed and rendered with a line through
  the text, including inside table cells.
- **Keyboard shortcuts**: `Ctrl+F` search, `Ctrl+S` save, `Ctrl+O` open,
  `Ctrl+E` toggle edit mode.

#### AI Parse improvements
- **Model selector** in settings: Haiku 4.5 (default, cheap), Sonnet 4.6
  (balanced), Opus 4.7 (best quality).
- **Windows support**: AI Parse now writes a `.bat` launcher on Windows
  (previously bash-only, broken on Win).
- **Editable result preview** — the parsed markdown is shown in a text area
  before Save As, so you can tweak it without re-running the parse.
- **Better error messages**: API errors expose the error type and full message;
  invalid API keys are caught before the call; first 200 bytes of unparseable
  responses are shown for diagnosis.

#### UX polish
- Window title shows an asterisk (`*`) when there are unsaved changes.
- Toolbar file name also shows the asterisk and tooltips the full path on hover.
- New welcome screen with action buttons (Open / New / AI Parse) and a clickable
  recent-files list — replaces the plain text instructions.
- Link hover now shows the URL as a tooltip.
- Font size slider in settings.
- Scenario `.reamd` file now auto-saves on every change (the "Save Map" button
  is still available for explicit saves).

### Fixed
- **Table cells overflow** — long content in markdown tables now wraps to the
  cell width instead of running past it. This was the most visible rendering
  glitch in earlier versions.
- **Table parsing**: escaped `\|` is now treated as a literal pipe inside cell
  content; phantom empty cells from consecutive pipes are no longer emitted.
- **Code blocks**: long single lines now scroll horizontally inside the block
  instead of bleeding into surrounding content.
- **Heading highlight height**: the highlight bar now scales with the actual
  heading font size (was hard-coded 24px, too short for H1/H2 at large font).
- **Table cells**: italic and inline code inside cells were silently dropped by
  the renderer. They're now rendered correctly.
- Cleaned up a stray empty `TextColored("")` call before every link.

## [1.0.3] - 2026-01-11

### Fixed
- ImGui ID conflict when recent files have the same filename (from different folders)
- Settings (theme, scroll options) not persisting after restart - `Config.load()` was missing

### Changed
- Light theme redesigned for better contrast and professional appearance
  - Blue accent buttons instead of gray (matches dark theme style)
  - Alternating table row backgrounds for better readability
  - Cleaner off-white background with proper borders
  - Improved visual hierarchy
  - Lighter scenario [+] buttons for better text visibility

## [1.0.2] - 2026-01-11

### Changed
- Updated welcome message to reflect current features (Scenario linking, Teleprompter, AI Parse)

## [1.0.1] - 2026-01-10

### Fixed
- ReaPack installation now includes all required files
  - Added missing `ai_parser.lua` (AI Parse feature)
  - Added missing `teleprompter.lua` (Teleprompter mode)
  - Added missing `ai_format_prompt.txt` (AI prompt template)

## [1.0.0] - 2026-01-08

### Added

#### Core Features
- **Markdown Viewer** - Full markdown rendering with ReaImGui
  - Headers (H1-H6), paragraphs, bold, italic, strikethrough
  - Bullet lists, numbered lists, nested lists
  - Tables with proper column alignment
  - Code blocks with syntax highlighting style
  - Blockquotes and horizontal rules
  - Links (clickable, opens in browser)

- **Edit Mode** - Create and modify markdown directly in REAPER
  - Toggle between view and edit modes
  - Auto-save on mode switch
  - "New" menu for creating fresh documents

- **Themes** - Dark and Light themes
  - Matches common REAPER color schemes
  - Unified background colors for clean appearance
  - Full style customization (14 color variables)

#### Scenario Mode
- **Fragment-to-Item Linking** - Connect text to timeline
  - Link multiple items to a single text fragment
  - Click text to jump to linked items on timeline
  - Visual highlighting of linked fragments
  - Playback position tracking

- **Category System** - Organize linked items
  - V (Voiceover) - Blue
  - M (Music) - Green
  - F (FX/Sound Effects) - Orange
  - O (Other) - Gray

- **Group Support** - REAPER groups handled as units
  - Grouped items linked/selected together
  - Progress calculation spans entire group

#### Teleprompter Mode
- **VO-Focused Display** - Large, centered text
  - Shows only voiceover-linked fragments
  - 48px font size for readability
  - Semi-transparent background (50% opacity)

- **Auto-Scroll** - Follows playback
  - Smooth transitions between cues
  - 2-second hold prevents flashing
  - Progress bar indicator (orange→green)

#### AI Parse Feature
- **Claude Integration** - AI-powered text formatting
  - Paste unformatted text, get clean markdown
  - Async processing (non-blocking UI)
  - Uses Claude Haiku for speed and cost efficiency

- **Customizable Prompt** - Tailor AI behavior
  - Edit prompt template in `prompts/ai_format_prompt.txt`
  - Default prompt optimized for AV production scripts

- **Settings Panel** - API key management
  - Masked input for security
  - Show/Hide toggle
  - Edit Prompt button (opens in system editor)

### Technical
- ReaImGui 0.10+ compatibility
- Cross-platform support (Windows, macOS, Linux)
- Modular architecture (9 Lua modules)
- JSON-based scenario file format (.reamd)

---

## [Unreleased]

### Planned
- Rate limiting for AI Parse calls
- `ImGui_ListClipper` virtualization for very large documents
- Submission to ReaTeam/ReaScripts for wider ReaPack distribution
- Drag & drop file open (via JS_Window_OnFileDrop)

[1.1.0]: https://github.com/b451c/ReaMD/releases/tag/v1.1.0
[1.0.3]: https://github.com/b451c/ReaMD/releases/tag/v1.0.3
[1.0.1]: https://github.com/b451c/ReaMD/releases/tag/v1.0.1
[1.0.0]: https://github.com/b451c/ReaMD/releases/tag/v1.0.0
[Unreleased]: https://github.com/b451c/ReaMD/compare/v1.1.0...HEAD
