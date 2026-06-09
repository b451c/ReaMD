<p align="center">
  <img src="docs/images/hero.png" alt="ReaMD - Markdown Viewer for REAPER" width="800">
</p>

<h1 align="center">ReaMD</h1>

<p align="center">
  <strong>Dockable Markdown Viewer for REAPER DAW</strong><br>
  Scenario linking, teleprompter mode, and AI-powered text formatting
</p>

<p align="center">
  <a href="#features">Features</a> •
  <a href="#installation">Installation</a> •
  <a href="#usage">Usage</a> •
  <a href="#ai-parse">AI Parse</a> •
  <a href="#screenshots">Screenshots</a> •
  <a href="#license">License</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/REAPER-7.0+-green?style=flat-square" alt="REAPER 7.0+">
  <img src="https://img.shields.io/badge/ReaImGui-0.10+-blue?style=flat-square" alt="ReaImGui 0.10+">
  <img src="https://img.shields.io/badge/Platform-Windows%20%7C%20macOS%20%7C%20Linux-lightgrey?style=flat-square" alt="Cross-platform">
  <img src="https://img.shields.io/github/license/b451c/ReaMD?style=flat-square" alt="License">
  <img src="https://img.shields.io/github/v/release/b451c/ReaMD?style=flat-square" alt="Release">
</p>

> [!NOTE]
> **Tested on macOS Tahoe 26.2.** Windows and Linux support is expected but not yet verified. Contributions and feedback from other platforms are welcome!

---

## What is ReaMD?

ReaMD is a **dockable markdown viewer** designed specifically for audio production workflows in REAPER. It bridges the gap between your scripts, notes, and the timeline - allowing you to link text fragments directly to items on your tracks.

Perfect for:
- **Voiceover production** - Link script lines to VO recordings
- **Audio post-production** - Sync scene descriptions with sound design
- **Podcast editing** - Follow show notes while editing
- **Music production** - Keep lyrics and arrangement notes in view

---

## Features

### Core Markdown Support
- Full markdown rendering (headers, lists, tables, code blocks, blockquotes, **strikethrough**)
- **Edit mode** with live split-view preview
- **In-document search** (`Ctrl+F`) with next/prev navigation
- **`time://HH:MM:SS` links** — clicking jumps REAPER's edit cursor to that timestamp
- **Dark & Light themes** matching your REAPER look
- Dockable window

<p align="center">
  <img src="docs/images/editor.gif" alt="Edit Mode Demo" width="600">
</p>

### Scenario Linking
- **Link text fragments to timeline items** — click a paragraph or table row, jump to the items
- **Multi-item per fragment** — one paragraph can reference several items
- **Category colors** — V (Voiceover), M (Music), F (FX), O (Other)
- **Group awareness** — REAPER item groups treated as single units
- **Auto-Link by name** — match headings and table rows against item take names and region names in one click
- **Cue List panel** — sorted overview of every linked fragment, click to jump
- **Export to regions** — turn linked fragments into REAPER regions, colored by category
- **Auto-save** scenario data to a `.reamd` sidecar on every change

### Teleprompter Mode
- **VO-focused display** — voiceover text shown large and centered
- **Auto-scroll** following playback position
- **Progress indicator** — orange (next cue) / green (current item ending)
- **Semi-transparent overlay** — 50% opacity, stays out of the way

### AI Parse (Claude Integration)
- **Paste unformatted text** — meeting notes, raw scripts, brain dumps
- **Model selector** — Haiku 4.5 (default, fast/cheap), Sonnet 4.6, or Opus 4.7
- **Apply to editor** or save as a new file — your call after reviewing the result
- **Customizable prompt** at `prompts/ai_format_prompt.txt`
- **Non-blocking** — async processing, UI stays responsive
- Works on macOS, Linux, **and Windows** (uses `curl`)

### Productivity
- **Keyboard shortcuts** — `Ctrl+F` search, `Ctrl+S` save, `Ctrl+O` open, `Ctrl+E` toggle edit
- **Welcome screen** with recent files and quick-action buttons
- **Unsaved-changes indicator** (`*` in title bar)

---

## Installation

### Requirements

| Component | Version | Required |
|-----------|---------|----------|
| REAPER | 7.0+ | Yes |
| ReaImGui | 0.10+ | Yes |
| js_ReaScriptAPI | Latest | Recommended |
| SWS Extension | Latest | Recommended |

### Method 1: ReaPack (Recommended)

1. **Add ReaMD repository to ReaPack:**
   - Open REAPER → Extensions → ReaPack → Import repositories...
   - Paste: `https://github.com/b451c/ReaMD/raw/main/index.xml`
   - Click OK

2. **Install ReaMD:**
   - Extensions → ReaPack → Browse packages
   - Search for "ReaMD" → Right-click → Install
   - Apply and restart REAPER

3. **Run:**
   - Actions → Show action list
   - Search for "ReaMD"
   - Double-click to run (or assign shortcut)

### Method 2: Manual Install

1. **Download** the [latest release](https://github.com/b451c/ReaMD/releases/latest) or clone:
   ```bash
   git clone https://github.com/b451c/ReaMD.git
   ```

2. **Copy to REAPER Scripts folder:**
   ```
   Windows: %APPDATA%\REAPER\Scripts\ReaMD\
   macOS:   ~/Library/Application Support/REAPER/Scripts/ReaMD/
   Linux:   ~/.config/REAPER/Scripts/ReaMD/
   ```

3. **Load the script:**
   - REAPER → Actions → Load ReaScript
   - Select `Main/ReaMD.lua`

> **Tip:** For full functionality, install [ReaImGui](https://github.com/cfillion/reaimgui), [js_ReaScriptAPI](https://forum.cockos.com/showthread.php?t=212174), and [SWS Extension](https://www.sws-extension.org/).

---

## Usage

### Basic Workflow

1. **Open a markdown file** - Click "Open..." or drag & drop
2. **Dock the window** - Right-click title bar → Dock
3. **Browse your script** - Scroll, search, navigate headings

### Scenario Linking

1. **Enter Scenario Mode** - Toggle "Scenario" in toolbar
2. **Select items on timeline** - The items you want to link
3. **Click [+] on a text fragment** - Links selected items to that text
4. **Click linked text** - Jumps to and selects the items
5. **Play** - Text highlights follow playback position

<p align="center">
  <img src="docs/images/scenario-demo.gif" alt="Scenario Linking Demo" width="600">
</p>

### Teleprompter

1. **Set up scenario links** - At least link your VO items
2. **Click "Teleprompter"** - Opens focused display window
3. **Start playback** - Text auto-scrolls with timeline

<p align="center">
  <img src="docs/images/teleprompter-demo.gif" alt="Teleprompter Demo" width="600">
</p>

---

## AI Parse

Transform unstructured text into clean markdown using Claude AI.

### Setup

1. Get an API key from [Anthropic Console](https://console.anthropic.com/)
2. In ReaMD, open **Settings** (gear icon)
3. Paste your API key in the "AI Parser Settings" section

### Usage

1. Click **New → AI Parse...**
2. Paste your unformatted text
3. Click **Parse with AI**
4. Review the result → **Save As...**

### Customize the Prompt

Click **Edit Prompt** in settings to modify `prompts/ai_format_prompt.txt`. Tailor it for your specific use case (voiceover scripts, technical docs, meeting notes, etc.).

<p align="center">
  <img src="docs/images/ai-parse-demo.gif" alt="AI Parse Demo" width="600">
</p>

> **Note:** AI Parse requires an internet connection and uses the Claude Haiku model for fast, cost-effective processing.

---

## Screenshots

<details>
<summary><strong>Dark & Light Themes</strong></summary>
<p align="center">
  <img src="docs/images/themes.png" alt="Dark and Light Themes" width="700">
</p>
</details>

<details>
<summary><strong>Settings Panel</strong></summary>
<p align="center">
  <img src="docs/images/settings.png" alt="Settings" width="400">
</p>
</details>

<details>
<summary><strong>Edit Mode</strong></summary>
<p align="center">
  <img src="docs/images/editor.png" alt="Edit Mode" width="600">
</p>
</details>

<details>
<summary><strong>AI Parse Window</strong></summary>
<p align="center">
  <img src="docs/images/ai-parse-window.png" alt="AI Parse Window" width="500">
</p>
</details>

---

## File Structure

```
ReaMD/
├── Main/
│   └── ReaMD.lua           # Main script (run this)
├── Libs/
│   ├── ai_parser.lua       # AI integration module
│   ├── config.lua          # Settings management
│   ├── cue_list.lua        # Cue List floating panel
│   ├── json.lua            # JSON encoder/decoder
│   ├── md_parser.lua       # Markdown parser
│   ├── md_renderer.lua     # ReaImGui renderer
│   ├── scenario_engine.lua # Timeline linking engine
│   ├── teleprompter.lua    # Teleprompter mode
│   └── utils.lua           # Utility functions
└── prompts/
    └── ai_format_prompt.txt # Customizable AI prompt
```

---

## Troubleshooting

### "ReaImGui not found"
Install ReaImGui via ReaPack: Extensions → ReaPack → Browse packages → Search "ReaImGui"

### AI Parse not working
- Verify your API key is correct in Settings
- Check internet connection
- On Windows, ensure `curl` is available (comes with Windows 10+)

### Teleprompter not following playback
- Ensure scenario links are set up (fragments linked to timeline items)
- Check that linked items exist on the timeline

---

## Contributing

Contributions are welcome! Please feel free to submit issues and pull requests.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## Acknowledgments

- [ReaImGui](https://github.com/cfillion/reaimgui) by cfillion - Amazing ImGui bindings for REAPER
- [REAPER](https://www.reaper.fm/) by Cockos - The best DAW for scripting
- [Anthropic](https://www.anthropic.com/) - Claude AI for text formatting

---

<p align="center">
  Made with ❤️ for the REAPER community

<p align="center">
  <a href="https://ko-fi.com/quickmd"><img src="https://img.shields.io/badge/Ko--fi-support-ff5e5b?style=flat-square&logo=ko-fi" alt="Ko-fi"></a>
  <a href="https://buymeacoffee.com/bsroczynskh"><img src="https://img.shields.io/badge/Buy%20Me%20a%20Coffee-support-yellow?style=flat-square&logo=buy-me-a-coffee" alt="Buy Me a Coffee"></a>
</p>
</p>


---

Made by [falami.studio](https://falami.studio/lab/reamd/) — audio production & engineering studio.
