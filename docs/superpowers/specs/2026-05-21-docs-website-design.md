# MeetingScribe Documentation Website — Design

**Date:** 2026-05-21
**Branch:** feat/native-overhaul
**Status:** Approved (in brainstorming session)

## Overview

A user-facing documentation website for MeetingScribe (native-overhaul Swift app), hosted on GitHub Pages with a custom domain. Apple-style visual direction with a landing page that doubles as marketing, plus a structured docs section for tutorial, install, features, troubleshooting, and a short under-the-hood/privacy page.

## Goals

- Help everyday users (lab colleagues, researchers, knowledge workers) install MeetingScribe and record their first meeting in under 5 minutes.
- Document every visible feature with screenshots so users can self-serve.
- Convey privacy/local-first stance clearly (relevant for research audiences).
- Provide a lighter "Under the hood" section for technically curious users and potential contributors.
- Stay maintainable as a single static site that builds in seconds and deploys with one GitHub Action.

## Non-Goals

- Full contributor documentation (API references, code architecture deep dives) — defer to repo READMEs and inline comments.
- Multi-version docs (no version switcher; latest is canonical).
- Internationalization (English only at launch).
- Analytics, comments, or any third-party JS beyond Pagefind for search.
- Marketing video or animated demos in v1 (static screenshots only).
- Migration page (covered adequately in README; can be added later if support volume justifies it).

## Audience

Mixed, users-first:

- **Primary:** End users on macOS who downloaded the DMG. Non-technical to mid-technical. Need install help, recording walkthroughs, troubleshooting.
- **Secondary:** Power users and potential contributors who want to understand what runs on their machine and where data goes.

## Visual Direction

**Style:** Apple-style (selected in brainstorming over Starlight-dev-docs and Mintlify-SaaS directions).

- Light default, dark mode toggle.
- Generous whitespace, large hero typography, screenshots front and center.
- Accent color: Apple blue `#0a84ff` (close to SF system blue).
- Font stack: `-apple-system, BlinkMacSystemFont, 'SF Pro Display', 'SF Pro Text', 'Inter', system-ui, sans-serif`.
- No custom illustrations in v1 — real app screenshots only.
- Visual hierarchy: oversized headlines (~64px on landing hero), comfortable body (16-17px), tight line-height on headings, generous line-height on body.

## Tech Stack

| Concern | Choice | Reason |
|---|---|---|
| Framework | Astro 5 | Static-first, MDX support, content collections, excellent image pipeline. Best fit for marketing+docs hybrid. |
| Styling | Tailwind CSS v4 (CSS-first config via `@import 'tailwindcss'`) | Utility-first, fast iteration. v4 is current as of 2026. |
| Docs content | MDX via `@astrojs/mdx` | Markdown plus components (callouts, screenshots). |
| Search | Pagefind | Static, client-side, no server. Indexes built HTML at build time. |
| Types | TypeScript strict | Catch broken links and missing frontmatter at build time. |
| Node | 20.x LTS | Match what GH Actions ships. |
| Image pipeline | Astro's built-in `<Image />` | Auto-WebP, responsive `srcset`, lazy loading. |

No client-side framework (no React, Vue, Svelte unless a specific component needs it later).

## Repo Placement

```
meeting-scribe/
└── docs/
    └── website/                ← new
        ├── astro.config.mjs
        ├── tailwind.config.ts
        ├── tsconfig.json
        ├── package.json
        ├── README.md            ← contributor notes for editing the docs site
        ├── public/
        │   ├── CNAME            ← custom domain (TBD)
        │   ├── favicon.svg
        │   └── screenshots/     ← user-provided, originals + WebP variants
        └── src/
            ├── pages/
            │   ├── index.astro          ← landing
            │   └── docs/
            │       ├── install.mdx
            │       ├── tutorial.mdx
            │       ├── features.mdx
            │       ├── troubleshooting.mdx
            │       └── under-the-hood.mdx
            ├── layouts/
            │   ├── Landing.astro
            │   └── Doc.astro
            ├── components/
            │   ├── Header.astro
            │   ├── Footer.astro
            │   ├── Hero.astro
            │   ├── HowItWorks.astro
            │   ├── FeatureGrid.astro
            │   ├── FeatureCard.astro
            │   ├── ScreenshotGallery.astro
            │   ├── DownloadCTA.astro
            │   ├── Sidebar.astro
            │   ├── TableOfContents.astro
            │   ├── Callout.astro
            │   ├── Screenshot.astro     ← wrapper around Astro <Image />
            │   └── DarkModeToggle.astro
            └── styles/
                └── global.css
```

Choice of `docs/website/` (rather than repo root `/website/`): keeps the website with sibling `docs/` content, makes path-scoping in CI straightforward, signals to repo visitors that this is documentation infrastructure.

## Information Architecture

```
/                          Landing (marketing + product overview)
└── /docs/
    ├── install            Download DMG, Gatekeeper, permissions
    ├── tutorial           Record your first meeting
    ├── features           Feature-by-feature reference
    ├── troubleshooting    FAQ for common issues
    └── under-the-hood     Architecture + privacy combined
```

Header nav exposes: Home · Docs (dropdown or first-page link) · GitHub · Download
Footer exposes: secondary nav, version, repo link, license, "Made by …" line.

## Page Layouts

### Landing (`/`)

Single-column, full-bleed sections stacked vertically. Each section is self-contained vertically rhythmed.

1. **Header** — slim, sticky on scroll. Logo + nav + Download button.
2. **Hero** — large headline (e.g., "Meetings, captured."), sub-headline (1 sentence), primary "Download for Mac" CTA, secondary "View on GitHub" link, app screenshot floating below (drop-shadow, slight tilt or straight).
3. **How it works** — 3 numbered cards (Record → Transcribe → Summarize), each with one-line description and a mini-screenshot.
4. **Feature grid** — 6 cards in 3×2 grid (mic+system audio, on-device whisper, calendar integration, claude-code/ollama summary, organized file storage, menu-bar control). Each card: small icon, title, 1-2 sentences.
5. **Screenshots gallery** — 3-4 large screenshots showing the menu bar, the recording panel, the dashboard, the summary view.
6. **Privacy callout** — single short section: "Everything runs locally."
7. **Download CTA (repeat)** — large band, single CTA, requirements line below ("Apple Silicon · macOS 14+").
8. **Footer** — secondary nav, copyright, repo link.

### Doc page (`/docs/*`)

Three-column on desktop, collapsing on mobile.

```
┌────────────────────────────────────────────────────────────┐
│ Header (Home · Docs · GitHub · Download · ⌘K search)       │
├──────────┬──────────────────────────────────┬──────────────┤
│ Sidebar  │                                  │ On this page │
│          │   # Page title                   │              │
│ Start    │                                  │ - Heading 1  │
│  Install │   Body content with MDX,         │ - Heading 2  │
│  Tutorial│   callouts, code blocks,         │ - Heading 3  │
│          │   screenshots.                   │              │
│ Reference│                                  │              │
│  Features│                                  │              │
│  Trouble.│                                  │              │
│  Under   │                                  │              │
│   Hood   │                                  │              │
│          │   ← Prev    Next →               │              │
└──────────┴──────────────────────────────────┴──────────────┘
```

- Sidebar: collapsible groups ("Start here", "Reference"). Active page highlighted with accent color.
- Right TOC: auto-generated from H2/H3 headings in the page.
- Prev/next footer-of-page navigation within docs.
- Mobile: sidebar becomes a top hamburger sheet; right TOC hides.

## Page Content Outlines

### `/` Landing

(See Layout above. Copy will be drafted during implementation but follow this skeleton.)

### `/docs/install`

1. Requirements — Apple Silicon, macOS 14+, ~500MB disk for whisper model
2. Download the DMG (link to GitHub Releases latest)
3. First launch — Gatekeeper "developer cannot be verified" walkthrough (right-click → Open, or `xattr` command)
4. Grant permissions — Microphone, Screen Recording, Calendar (with System Settings screenshots)
5. Install whisper.cpp — `brew install whisper-cpp` and model download script
6. Verify install — launch app, look for menu-bar icon

### `/docs/tutorial`

"Record your first meeting in 2 minutes."

1. Click the menu-bar icon
2. Enter a meeting title (or use calendar suggestion)
3. Choose meeting type tag
4. Start Session
5. Watch live transcription preview
6. Stop the session
7. Wait for whisper transcription (progress bar)
8. View transcript and click "Open in Claude Code" or wait for Ollama auto-summary
9. Find your meeting under `~/MeetingScribe/YYYY/MM-Month/DD-slug/`

Each step has a screenshot. Pull quotes for callouts ("Tip: Auto-detected calendar meetings appear in the title field").

### `/docs/features`

Long-page reference, organized by capability:

- Menu bar app — every UI element documented
- Live transcription preview (SFSpeechRecognizer, auto-disables after 60s)
- Recording — mic + system audio capture details
- Calendar integration
- Meeting type tags
- Notes
- On-device transcription (whisper.cpp)
- File storage layout
- Post-recording panel
- Summarization — Claude Code vs Ollama (when to use which)
- Settings — mic selection, output directory, summarization provider
- `meetingctl list` CLI

Each subsection: 1-2 paragraphs + screenshot.

### `/docs/troubleshooting`

FAQ format, each issue is an H2 anchor:

- No audio captured / silent recording
- "whisper.cpp not found"
- Live transcription preview never appears
- Summary didn't generate
- How to switch Claude Code ↔ Ollama
- Permissions denied / how to re-grant
- App won't open after download (Gatekeeper recap)
- Where to find my recordings
- How to delete a recording cleanly
- How to file a bug

### `/docs/under-the-hood`

Short. Two parts.

**How it works (architecture overview)**
- 1 paragraph + diagram: ScreenCaptureKit + AVAudioEngine capture → ffmpeg merge → whisper.cpp transcribe → markdown output → Claude Code or Ollama summarize.

**Privacy (what stays local, what leaves)**
- Recording, audio, transcription, file storage: 100% local.
- Summarization with Ollama: 100% local.
- Summarization with Claude Code: text-only transcript sent to Anthropic via Claude Code CLI; audio never leaves the machine.
- No telemetry, no analytics, no auto-update phone-home.

## Asset Strategy

- **Origin:** user provides screenshots; they live in `public/screenshots/originals/`.
- **Build:** Astro's `<Image />` component generates responsive WebP variants at build time.
- **Naming convention:** `<area>-<state>.png` — e.g., `menu-bar-idle.png`, `menu-bar-recording.png`, `dashboard-meeting-list.png`, `recording-panel-live-transcript.png`, `summary-view-claude.png`.
- **Placeholders during dev:** a `Screenshot` component renders a labeled gray box when the named file is missing, so layout work can proceed without all screenshots.
- **Optimization targets:** original PNG, 2x WebP (~1600px wide), 1x WebP (~800px wide), AVIF optional.
- **Alt text:** every screenshot has descriptive alt text (required by the component).

## Build & Deploy

### Local development

```bash
cd docs/website
npm install
npm run dev    # http://localhost:4321
```

### Production build

```bash
npm run build
npm run preview   # smoke-test the built site locally
```

### GitHub Pages deploy

`.github/workflows/docs.yml`:

- Triggers: `push` to `main` with paths under `docs/website/**`; also `workflow_dispatch`.
- Steps: checkout → setup-node → install → build → upload artifact → deploy to `gh-pages` branch via `actions/deploy-pages`.
- Permissions: `pages: write`, `id-token: write`.
- Custom domain: `public/CNAME` with the chosen domain (TBD before first deploy).

### Per-user constraint

Per project preference, this workflow ships only after explicit user approval — no auto-push, no tagging, no CI release trigger on initiative. The implementation work stays on a local branch and the user decides when to merge to `main`.

## Component Inventory

| Component | Purpose | Used by |
|---|---|---|
| `Header.astro` | Site-wide top nav, search trigger | All pages |
| `Footer.astro` | Site-wide footer | All pages |
| `Hero.astro` | Landing hero section | Landing |
| `HowItWorks.astro` | 3-step section | Landing |
| `FeatureGrid.astro` + `FeatureCard.astro` | Feature highlights | Landing |
| `ScreenshotGallery.astro` | Landing gallery | Landing |
| `DownloadCTA.astro` | Download band | Landing (×2) |
| `Sidebar.astro` | Docs left nav | All docs pages |
| `TableOfContents.astro` | Right-side in-page TOC | All docs pages |
| `Callout.astro` | Note/Warning/Tip boxes | Docs (MDX) |
| `Screenshot.astro` | Image wrapper with placeholder fallback | Docs + landing |
| `DarkModeToggle.astro` | Light/dark switch in header | Header |
| `Search.astro` | Pagefind UI mount point | Header |

## Testing

- **Build check:** `npm run build` must succeed (covered by CI).
- **Link check:** an Astro plugin or a `lychee` post-build step verifies no broken internal links.
- **Lighthouse smoke:** target 95+ on Performance, Accessibility, Best Practices, SEO on the landing page.
- **Visual check:** before pushing, run the dev server and walk every page in light and dark mode.
- **No automated unit tests in v1** — content site, low logic surface.

## Open Items (deferred, not blocking implementation)

- **Custom domain name** — `public/CNAME` will contain a placeholder string until the user supplies the real domain.
- **Real screenshots** — the implementation uses labeled placeholders. User supplies screenshots after layout is approved.
- **Demo video / animated walkthrough** — explicitly out of scope for v1.
- **Migration-from-old-install page** — explicitly out of scope for v1.
- **Changelog page** — out of scope for v1 (GitHub Releases is canonical).

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| User domain not chosen at deploy time | `CNAME` is a single-line file, can be added later without rebuild. Workflow tolerates its presence/absence. |
| Screenshots not provided in time | Placeholder component renders labeled gray boxes; layout proceeds without blocking. |
| Astro 5 churn | Pin a minor version (`astro@^5.x`) and dependabot quietly. |
| GH Pages caching | Cache-bust via Astro's content-hashed asset filenames; no manual purge needed. |
| Bundled JS too large | Astro ships zero JS by default. Audit any added React/Svelte islands before merging. |
