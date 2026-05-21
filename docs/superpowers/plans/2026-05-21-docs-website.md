# Documentation Website Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a static documentation + marketing website for MeetingScribe at `docs/website/` — Apple-style landing page plus five doc pages (install, tutorial, features, troubleshooting, under-the-hood). Builds to `docs/website/dist/`, deploys to GitHub Pages via a path-scoped Action. No data layer, no client framework.

**Architecture:** Single Astro 5 project. File-based routing under `src/pages/`. Shared layouts in `src/layouts/`. Static assets in `public/`. Tailwind v4 via the Vite plugin with a CSS-first `@theme` config. MDX for docs content. Pagefind generates a search index from the built HTML in a `npm run build` post-step. Output is plain HTML+CSS with islands only where genuinely needed (theme toggle, search trigger).

**Tech Stack:** Astro 5, TypeScript strict, Tailwind v4, `@astrojs/mdx`, `@astrojs/check`, Pagefind, Node 20 LTS, GitHub Actions (`actions/deploy-pages`).

**Reference spec:** `docs/superpowers/specs/2026-05-21-docs-website-design.md`

**Branch policy:** Implementation work stays on a local branch off `feat/native-overhaul` (or worktree). No push, no tag, no CI release on initiative — the user merges to `main` when ready.

**Verification model for content sites:** TDD-style unit tests don't fit a static MDX site. Instead, each implementation task is gated on three checks: (1) `npm run build` exits 0 with no warnings about the touched file, (2) dev server renders the page at the expected URL, (3) where the task changes structure, the link checker (`lychee` post-build) passes. Visual correctness is confirmed by the user via dev-server preview before any commit that touches layout.

---

## Phase 1 — Scaffold

### Task 1: Create the Astro project skeleton

**Files:**
- Create: `docs/website/package.json`
- Create: `docs/website/tsconfig.json`
- Create: `docs/website/astro.config.mjs`
- Create: `docs/website/.gitignore`
- Create: `docs/website/README.md`

- [ ] **Step 1: Create the project directory and package.json**

```bash
mkdir -p docs/website
```

Write `docs/website/package.json`:

```json
{
  "name": "meetingscribe-website",
  "version": "0.0.1",
  "type": "module",
  "private": true,
  "scripts": {
    "dev": "astro dev",
    "build": "astro check && astro build && pagefind --site dist",
    "preview": "astro preview",
    "astro": "astro"
  },
  "dependencies": {
    "astro": "^5.0.0",
    "@astrojs/mdx": "^4.0.0",
    "@astrojs/check": "^0.9.0",
    "typescript": "^5.5.0",
    "tailwindcss": "^4.0.0",
    "@tailwindcss/vite": "^4.0.0",
    "pagefind": "^1.3.0"
  }
}
```

- [ ] **Step 2: Create tsconfig.json**

Write `docs/website/tsconfig.json`:

```json
{
  "extends": "astro/tsconfigs/strict",
  "include": [".astro/types.d.ts", "**/*"],
  "exclude": ["dist"]
}
```

- [ ] **Step 3: Create astro.config.mjs**

Write `docs/website/astro.config.mjs`:

```js
// @ts-check
import { defineConfig } from 'astro/config';
import mdx from '@astrojs/mdx';
import tailwindcss from '@tailwindcss/vite';

// NOTE: replace `site` with the real custom domain before first deploy.
export default defineConfig({
  site: 'https://meetingscribe.example.com',
  base: '/',
  trailingSlash: 'never',
  integrations: [mdx()],
  vite: {
    plugins: [tailwindcss()],
  },
});
```

- [ ] **Step 4: Create .gitignore**

Write `docs/website/.gitignore`:

```
node_modules/
dist/
.astro/
.DS_Store
```

- [ ] **Step 5: Create README.md**

Write `docs/website/README.md`:

```markdown
# MeetingScribe Documentation Website

Static site for [MeetingScribe](../../README.md). Built with Astro 5.

## Local development

```bash
cd docs/website
npm install
npm run dev    # http://localhost:4321
```

## Production build

```bash
npm run build      # outputs to dist/
npm run preview    # smoke-test built output
```

The build runs `astro check`, then `astro build`, then `pagefind` to
generate the static search index over the built HTML.

## Editing content

- Landing page: `src/pages/index.astro`
- Doc pages: `src/pages/docs/*.mdx`
- Shared layout: `src/layouts/`
- Components: `src/components/`
- Screenshots: `public/screenshots/`

## Deploy

Pushed via `.github/workflows/docs.yml` on changes under
`docs/website/**` on the `main` branch. Custom domain set in
`public/CNAME`.
```

- [ ] **Step 6: Install dependencies**

```bash
cd docs/website && npm install
```

Expected: dependencies install without errors. `node_modules/` populated.

- [ ] **Step 7: Commit**

```bash
git add docs/website/package.json docs/website/package-lock.json docs/website/tsconfig.json docs/website/astro.config.mjs docs/website/.gitignore docs/website/README.md
git commit -m "scaffold(docs-website): initialize Astro 5 project skeleton"
```

---

### Task 2: Set up base styles and design tokens

**Files:**
- Create: `docs/website/src/styles/global.css`

- [ ] **Step 1: Write the base CSS with Tailwind v4 import and design tokens**

Write `docs/website/src/styles/global.css`:

```css
@import 'tailwindcss';

@theme {
  /* Color palette — Apple-style with #0a84ff accent */
  --color-accent: #0a84ff;
  --color-accent-hover: #0066cc;
  --color-ink: #0b0d10;
  --color-ink-muted: #4b5563;
  --color-bg: #ffffff;
  --color-bg-alt: #f7f8fa;
  --color-border: #e6e8eb;

  /* Dark mode */
  --color-ink-dark: #f5f7fa;
  --color-ink-muted-dark: #9aa3b2;
  --color-bg-dark: #0b0d10;
  --color-bg-alt-dark: #161a1f;
  --color-border-dark: #2a2f37;

  /* Typography */
  --font-display: -apple-system, BlinkMacSystemFont, 'SF Pro Display', 'Inter', system-ui, sans-serif;
  --font-text: -apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Inter', system-ui, sans-serif;
  --font-mono: 'SF Mono', ui-monospace, 'JetBrains Mono', Menlo, monospace;
}

:root {
  color-scheme: light dark;
}

html {
  font-family: var(--font-text);
  font-feature-settings: 'cv11', 'ss01';
  -webkit-font-smoothing: antialiased;
  background: var(--color-bg);
  color: var(--color-ink);
}

html.dark {
  background: var(--color-bg-dark);
  color: var(--color-ink-dark);
}

body {
  margin: 0;
  line-height: 1.55;
}

h1, h2, h3, h4 {
  font-family: var(--font-display);
  letter-spacing: -0.02em;
  line-height: 1.15;
  margin: 0;
}

/* Avoid Tailwind preflight removing list styles inside .prose-ish blocks */
.doc-content ul { list-style: disc; padding-left: 1.25rem; }
.doc-content ol { list-style: decimal; padding-left: 1.25rem; }
.doc-content code:not(pre code) {
  font-family: var(--font-mono);
  font-size: 0.875em;
  background: var(--color-bg-alt);
  padding: 0.1em 0.35em;
  border-radius: 4px;
}
html.dark .doc-content code:not(pre code) {
  background: var(--color-bg-alt-dark);
}
```

- [ ] **Step 2: Commit**

```bash
git add docs/website/src/styles/global.css
git commit -m "scaffold(docs-website): base CSS with Tailwind v4 + design tokens"
```

---

### Task 3: Render a minimal landing placeholder and verify dev server

**Files:**
- Create: `docs/website/src/pages/index.astro`

- [ ] **Step 1: Write a placeholder landing that loads global CSS**

Write `docs/website/src/pages/index.astro`:

```astro
---
import '../styles/global.css';
---

<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width" />
    <title>MeetingScribe — Local-first meeting transcription for macOS</title>
    <meta name="description" content="Record, transcribe, and summarize meetings locally on macOS." />
  </head>
  <body class="min-h-screen flex items-center justify-center">
    <main class="text-center">
      <h1 class="text-5xl font-semibold tracking-tight">MeetingScribe</h1>
      <p class="mt-3 text-lg opacity-70">Scaffold up. Replacing this with the real landing in Phase 3.</p>
    </main>
  </body>
</html>
```

- [ ] **Step 2: Start dev server and verify**

```bash
cd docs/website && npm run dev
```

Expected: server starts on `http://localhost:4321`. Open in browser. See the heading, no console errors. Stop the server (Ctrl+C).

- [ ] **Step 3: Run build to confirm production pipeline**

```bash
cd docs/website && npm run build
```

Expected: `astro check` reports 0 errors, `astro build` succeeds, `pagefind` runs (it will warn that no `data-pagefind-body` elements are tagged yet — fine for now). `dist/index.html` exists.

- [ ] **Step 4: Commit**

```bash
git add docs/website/src/pages/index.astro
git commit -m "scaffold(docs-website): placeholder landing page renders"
```

---

## Phase 2 — Shared layout primitives

### Task 4: Site-wide Header component

**Files:**
- Create: `docs/website/src/components/Header.astro`

- [ ] **Step 1: Write the header**

Write `docs/website/src/components/Header.astro`:

```astro
---
const navItems = [
  { href: '/docs/install', label: 'Install' },
  { href: '/docs/tutorial', label: 'Tutorial' },
  { href: '/docs/features', label: 'Features' },
  { href: '/docs/troubleshooting', label: 'Troubleshooting' },
];
const downloadHref = 'https://github.com/scott-yj-yang/meeting-scribe/releases/latest';
const repoHref = 'https://github.com/scott-yj-yang/meeting-scribe';
---

<header class="sticky top-0 z-50 backdrop-blur bg-white/80 dark:bg-[#0b0d10]/80 border-b border-[var(--color-border)] dark:border-[var(--color-border-dark)]">
  <div class="max-w-6xl mx-auto px-6 h-14 flex items-center justify-between">
    <a href="/" class="font-semibold tracking-tight text-base">
      <span aria-hidden="true">◐</span> MeetingScribe
    </a>
    <nav class="hidden md:flex items-center gap-6 text-sm">
      {navItems.map((item) => (
        <a href={item.href} class="opacity-70 hover:opacity-100 transition">{item.label}</a>
      ))}
      <a href={repoHref} class="opacity-70 hover:opacity-100 transition">GitHub</a>
    </nav>
    <div class="flex items-center gap-3">
      <button id="theme-toggle" aria-label="Toggle theme" class="opacity-70 hover:opacity-100 transition text-sm">
        <span class="hidden dark:inline">☀</span>
        <span class="inline dark:hidden">☾</span>
      </button>
      <a href={downloadHref} class="rounded-full bg-[var(--color-accent)] text-white text-sm font-medium px-4 py-1.5 hover:bg-[var(--color-accent-hover)] transition">
        Download
      </a>
    </div>
  </div>
</header>

<script>
  // Dark-mode toggle persists across loads via localStorage.
  const root = document.documentElement;
  const stored = localStorage.getItem('mscribe-theme');
  if (stored === 'dark' || (!stored && matchMedia('(prefers-color-scheme: dark)').matches)) {
    root.classList.add('dark');
  }
  document.getElementById('theme-toggle')?.addEventListener('click', () => {
    root.classList.toggle('dark');
    localStorage.setItem('mscribe-theme', root.classList.contains('dark') ? 'dark' : 'light');
  });
</script>
```

- [ ] **Step 2: Commit**

```bash
git add docs/website/src/components/Header.astro
git commit -m "feat(docs-website): site-wide header with nav + theme toggle"
```

---

### Task 5: Site-wide Footer component

**Files:**
- Create: `docs/website/src/components/Footer.astro`

- [ ] **Step 1: Write the footer**

Write `docs/website/src/components/Footer.astro`:

```astro
---
const year = new Date().getFullYear();
const repoHref = 'https://github.com/scott-yj-yang/meeting-scribe';
---

<footer class="border-t border-[var(--color-border)] dark:border-[var(--color-border-dark)] mt-24">
  <div class="max-w-6xl mx-auto px-6 py-10 flex flex-col md:flex-row md:items-center md:justify-between gap-4 text-sm opacity-70">
    <div>
      <span class="font-semibold opacity-100">MeetingScribe</span>
      &nbsp;· Local-first meeting transcription for macOS
    </div>
    <nav class="flex gap-5">
      <a href="/docs/install" class="hover:opacity-100">Install</a>
      <a href="/docs/under-the-hood" class="hover:opacity-100">Privacy</a>
      <a href={repoHref} class="hover:opacity-100">GitHub</a>
    </nav>
    <div>© {year} · MIT License</div>
  </div>
</footer>
```

- [ ] **Step 2: Commit**

```bash
git add docs/website/src/components/Footer.astro
git commit -m "feat(docs-website): site-wide footer"
```

---

### Task 6: Screenshot component with placeholder fallback

**Files:**
- Create: `docs/website/src/components/Screenshot.astro`
- Create: `docs/website/public/screenshots/.gitkeep`

- [ ] **Step 1: Create the screenshots folder placeholder**

```bash
mkdir -p docs/website/public/screenshots
touch docs/website/public/screenshots/.gitkeep
```

- [ ] **Step 2: Write the component**

Write `docs/website/src/components/Screenshot.astro`:

```astro
---
import fs from 'node:fs';
import path from 'node:path';

interface Props {
  src: string;          // e.g. "menu-bar-recording.png" (relative to public/screenshots/)
  alt: string;          // required descriptive alt text
  caption?: string;     // optional caption below the image
  width?: number;       // intrinsic width, defaults to 1600
  height?: number;      // intrinsic height, defaults to 1000
}

const { src, alt, caption, width = 1600, height = 1000 } = Astro.props;
const publicPath = path.resolve(process.cwd(), 'public', 'screenshots', src);
const exists = fs.existsSync(publicPath);
const url = `/screenshots/${src}`;
const aspect = `${width} / ${height}`;
---

<figure class="my-6">
  {exists ? (
    <img
      src={url}
      alt={alt}
      width={width}
      height={height}
      loading="lazy"
      decoding="async"
      class="rounded-lg shadow-[0_10px_30px_rgba(0,0,0,0.08)] border border-[var(--color-border)] dark:border-[var(--color-border-dark)] w-full h-auto"
    />
  ) : (
    <div
      role="img"
      aria-label={alt}
      style={`aspect-ratio: ${aspect};`}
      class="rounded-lg border-2 border-dashed border-[var(--color-border)] dark:border-[var(--color-border-dark)] bg-[var(--color-bg-alt)] dark:bg-[var(--color-bg-alt-dark)] flex items-center justify-center text-xs opacity-60 px-4 text-center"
    >
      Placeholder for <code class="mx-1">{src}</code> — {alt}
    </div>
  )}
  {caption && (
    <figcaption class="mt-2 text-sm opacity-60 text-center">{caption}</figcaption>
  )}
</figure>
```

- [ ] **Step 3: Commit**

```bash
git add docs/website/src/components/Screenshot.astro docs/website/public/screenshots/.gitkeep
git commit -m "feat(docs-website): Screenshot component with placeholder fallback"
```

---

### Task 7: Callout component for MDX

**Files:**
- Create: `docs/website/src/components/Callout.astro`

- [ ] **Step 1: Write the callout**

Write `docs/website/src/components/Callout.astro`:

```astro
---
interface Props {
  type?: 'note' | 'tip' | 'warning';
  title?: string;
}
const { type = 'note', title } = Astro.props;
const palette = {
  note:    { bar: 'border-l-[var(--color-accent)]', label: 'Note',    icon: 'ⓘ' },
  tip:     { bar: 'border-l-emerald-500',           label: 'Tip',     icon: '★' },
  warning: { bar: 'border-l-amber-500',             label: 'Warning', icon: '⚠' },
}[type];
---

<aside class={`my-5 border-l-4 ${palette.bar} bg-[var(--color-bg-alt)] dark:bg-[var(--color-bg-alt-dark)] rounded-r-md px-4 py-3`}>
  <div class="text-xs uppercase tracking-wide opacity-70 font-semibold mb-1">
    <span aria-hidden="true">{palette.icon}</span> {title ?? palette.label}
  </div>
  <div class="text-[15px] leading-relaxed">
    <slot />
  </div>
</aside>
```

- [ ] **Step 2: Commit**

```bash
git add docs/website/src/components/Callout.astro
git commit -m "feat(docs-website): Callout component (note/tip/warning)"
```

---

### Task 8: Landing layout

**Files:**
- Create: `docs/website/src/layouts/Landing.astro`

- [ ] **Step 1: Write the landing layout**

Write `docs/website/src/layouts/Landing.astro`:

```astro
---
import '../styles/global.css';
import Header from '../components/Header.astro';
import Footer from '../components/Footer.astro';

interface Props {
  title: string;
  description: string;
}
const { title, description } = Astro.props;
---

<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>{title}</title>
    <meta name="description" content={description} />
    <meta property="og:title" content={title} />
    <meta property="og:description" content={description} />
    <link rel="icon" type="image/svg+xml" href="/favicon.svg" />
  </head>
  <body class="min-h-screen">
    <Header />
    <main>
      <slot />
    </main>
    <Footer />
  </body>
</html>
```

- [ ] **Step 2: Commit**

```bash
git add docs/website/src/layouts/Landing.astro
git commit -m "feat(docs-website): Landing layout with header + footer + slots"
```

---

### Task 9: Sidebar component for doc pages

**Files:**
- Create: `docs/website/src/components/Sidebar.astro`

- [ ] **Step 1: Write the sidebar**

Write `docs/website/src/components/Sidebar.astro`:

```astro
---
interface Props {
  currentPath: string;
}
const { currentPath } = Astro.props;

const groups = [
  {
    title: 'Get started',
    items: [
      { href: '/docs/install', label: 'Install' },
      { href: '/docs/tutorial', label: 'Tutorial' },
    ],
  },
  {
    title: 'Reference',
    items: [
      { href: '/docs/features', label: 'Features' },
      { href: '/docs/troubleshooting', label: 'Troubleshooting' },
      { href: '/docs/under-the-hood', label: 'Under the hood' },
    ],
  },
];

const isActive = (href: string) => currentPath === href || currentPath === href + '/';
---

<nav aria-label="Docs navigation" class="text-sm">
  {groups.map((group) => (
    <div class="mb-6">
      <div class="text-[11px] uppercase tracking-wider opacity-50 font-semibold mb-2">
        {group.title}
      </div>
      <ul class="space-y-1">
        {group.items.map((item) => (
          <li>
            <a
              href={item.href}
              class={`block px-3 py-1.5 rounded-md transition ${
                isActive(item.href)
                  ? 'bg-[var(--color-accent)]/10 text-[var(--color-accent)] font-medium'
                  : 'opacity-75 hover:opacity-100 hover:bg-[var(--color-bg-alt)] dark:hover:bg-[var(--color-bg-alt-dark)]'
              }`}
            >
              {item.label}
            </a>
          </li>
        ))}
      </ul>
    </div>
  ))}
</nav>
```

- [ ] **Step 2: Commit**

```bash
git add docs/website/src/components/Sidebar.astro
git commit -m "feat(docs-website): Sidebar nav with active-state highlighting"
```

---

### Task 10: TableOfContents component (auto-extracts from headings)

**Files:**
- Create: `docs/website/src/components/TableOfContents.astro`

- [ ] **Step 1: Write the TOC**

Write `docs/website/src/components/TableOfContents.astro`:

```astro
---
import type { MarkdownHeading } from 'astro';
interface Props {
  headings: MarkdownHeading[];
}
const { headings } = Astro.props;
// Only H2 and H3 in the TOC — H1 is the page title.
const filtered = headings.filter((h) => h.depth === 2 || h.depth === 3);
---

{filtered.length > 0 && (
  <aside class="text-sm sticky top-20" aria-label="On this page">
    <div class="text-[11px] uppercase tracking-wider opacity-50 font-semibold mb-2">
      On this page
    </div>
    <ul class="space-y-1.5">
      {filtered.map((h) => (
        <li class={h.depth === 3 ? 'ml-3' : ''}>
          <a href={`#${h.slug}`} class="opacity-70 hover:opacity-100 transition">
            {h.text}
          </a>
        </li>
      ))}
    </ul>
  </aside>
)}
```

- [ ] **Step 2: Commit**

```bash
git add docs/website/src/components/TableOfContents.astro
git commit -m "feat(docs-website): TableOfContents auto-extracts H2/H3"
```

---

### Task 11: Doc layout

**Files:**
- Create: `docs/website/src/layouts/Doc.astro`

- [ ] **Step 1: Write the doc layout**

Write `docs/website/src/layouts/Doc.astro`:

```astro
---
import '../styles/global.css';
import Header from '../components/Header.astro';
import Footer from '../components/Footer.astro';
import Sidebar from '../components/Sidebar.astro';
import TableOfContents from '../components/TableOfContents.astro';
import type { MarkdownHeading } from 'astro';

interface Props {
  frontmatter: { title: string; description?: string };
  headings: MarkdownHeading[];
}

const { frontmatter, headings } = Astro.props;
const currentPath = Astro.url.pathname.replace(/\/$/, '');
const pageTitle = `${frontmatter.title} · MeetingScribe`;
---

<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>{pageTitle}</title>
    {frontmatter.description && <meta name="description" content={frontmatter.description} />}
    <link rel="icon" type="image/svg+xml" href="/favicon.svg" />
  </head>
  <body class="min-h-screen">
    <Header />
    <div class="max-w-6xl mx-auto px-6 grid grid-cols-1 md:grid-cols-[200px_minmax(0,1fr)] lg:grid-cols-[200px_minmax(0,1fr)_180px] gap-10 pt-10">
      <aside class="hidden md:block">
        <Sidebar currentPath={currentPath} />
      </aside>
      <article class="doc-content min-w-0 pb-20" data-pagefind-body>
        <h1 class="text-4xl font-semibold tracking-tight mb-4">{frontmatter.title}</h1>
        {frontmatter.description && (
          <p class="text-lg opacity-70 mb-8">{frontmatter.description}</p>
        )}
        <slot />
      </article>
      <div class="hidden lg:block">
        <TableOfContents headings={headings} />
      </div>
    </div>
    <Footer />
  </body>
</html>
```

- [ ] **Step 2: Commit**

```bash
git add docs/website/src/layouts/Doc.astro
git commit -m "feat(docs-website): Doc layout with sidebar + TOC + pagefind body marker"
```

---

## Phase 3 — Landing page sections

### Task 12: Hero section

**Files:**
- Create: `docs/website/src/components/Hero.astro`

- [ ] **Step 1: Write the hero**

Write `docs/website/src/components/Hero.astro`:

```astro
---
import Screenshot from './Screenshot.astro';
const downloadHref = 'https://github.com/scott-yj-yang/meeting-scribe/releases/latest';
const repoHref = 'https://github.com/scott-yj-yang/meeting-scribe';
---

<section class="pt-16 pb-20 md:pt-24 md:pb-28 text-center px-6">
  <div class="max-w-3xl mx-auto">
    <h1 class="text-5xl md:text-7xl font-semibold tracking-tight leading-[1.05]">
      Meetings,<br /><span class="text-[var(--color-accent)]">captured.</span>
    </h1>
    <p class="mt-6 text-lg md:text-xl opacity-70 leading-relaxed">
      Local-first meeting transcription and summaries for macOS.<br />
      Record system audio + mic, transcribe on-device, summarize with your tools.
    </p>
    <div class="mt-10 flex items-center justify-center gap-3">
      <a href={downloadHref} class="rounded-full bg-[var(--color-accent)] text-white text-base font-medium px-6 py-3 hover:bg-[var(--color-accent-hover)] transition">
        Download for Mac
      </a>
      <a href={repoHref} class="rounded-full border border-[var(--color-border)] dark:border-[var(--color-border-dark)] text-base px-6 py-3 hover:bg-[var(--color-bg-alt)] dark:hover:bg-[var(--color-bg-alt-dark)] transition">
        View on GitHub
      </a>
    </div>
    <p class="mt-4 text-sm opacity-50">Apple Silicon · macOS 14+</p>
  </div>
  <div class="max-w-4xl mx-auto mt-16 px-4">
    <Screenshot src="hero-app-shot.png" alt="MeetingScribe dashboard showing a meeting in progress with live transcription preview" />
  </div>
</section>
```

- [ ] **Step 2: Commit**

```bash
git add docs/website/src/components/Hero.astro
git commit -m "feat(docs-website): Hero section with headline + CTAs + app shot"
```

---

### Task 13: HowItWorks 3-step section

**Files:**
- Create: `docs/website/src/components/HowItWorks.astro`

- [ ] **Step 1: Write the section**

Write `docs/website/src/components/HowItWorks.astro`:

```astro
---
import Screenshot from './Screenshot.astro';

const steps = [
  {
    n: '01',
    title: 'Record',
    body: 'One click from the menu bar captures system audio + your microphone, with live transcription preview to confirm audio is working.',
    shot: 'how-record.png',
    alt: 'Recording panel showing live transcription text appearing as audio is captured',
  },
  {
    n: '02',
    title: 'Transcribe',
    body: 'whisper.cpp runs locally on your machine. No audio ever leaves the device. Progress bar with ETA so you know what is happening.',
    shot: 'how-transcribe.png',
    alt: 'Transcription progress bar with estimated time remaining',
  },
  {
    n: '03',
    title: 'Summarize',
    body: 'Hand off the transcript to Claude Code in your terminal, or run Ollama locally for an automatic summary. Your choice.',
    shot: 'how-summarize.png',
    alt: 'Summary view showing structured meeting summary with action items',
  },
];
---

<section class="py-20 md:py-28 px-6 bg-[var(--color-bg-alt)] dark:bg-[var(--color-bg-alt-dark)]">
  <div class="max-w-6xl mx-auto">
    <div class="text-center mb-14">
      <h2 class="text-4xl md:text-5xl font-semibold tracking-tight">How it works</h2>
      <p class="mt-3 text-lg opacity-70">Three steps. Two minutes from click to transcript.</p>
    </div>
    <div class="grid grid-cols-1 md:grid-cols-3 gap-8">
      {steps.map((step) => (
        <div class="flex flex-col">
          <div class="text-sm font-mono opacity-50">{step.n}</div>
          <h3 class="mt-2 text-2xl font-semibold tracking-tight">{step.title}</h3>
          <p class="mt-3 opacity-75 leading-relaxed">{step.body}</p>
          <div class="mt-6">
            <Screenshot src={step.shot} alt={step.alt} width={800} height={500} />
          </div>
        </div>
      ))}
    </div>
  </div>
</section>
```

- [ ] **Step 2: Commit**

```bash
git add docs/website/src/components/HowItWorks.astro
git commit -m "feat(docs-website): How it works 3-step section"
```

---

### Task 14: FeatureGrid + FeatureCard

**Files:**
- Create: `docs/website/src/components/FeatureCard.astro`
- Create: `docs/website/src/components/FeatureGrid.astro`

- [ ] **Step 1: Write FeatureCard**

Write `docs/website/src/components/FeatureCard.astro`:

```astro
---
interface Props {
  icon: string;     // emoji or single glyph for v1
  title: string;
  body: string;
}
const { icon, title, body } = Astro.props;
---

<div class="rounded-2xl border border-[var(--color-border)] dark:border-[var(--color-border-dark)] p-6 hover:border-[var(--color-accent)] transition">
  <div class="text-3xl mb-3" aria-hidden="true">{icon}</div>
  <h3 class="text-lg font-semibold tracking-tight">{title}</h3>
  <p class="mt-2 text-[15px] opacity-70 leading-relaxed">{body}</p>
</div>
```

- [ ] **Step 2: Write FeatureGrid**

Write `docs/website/src/components/FeatureGrid.astro`:

```astro
---
import FeatureCard from './FeatureCard.astro';

const features = [
  { icon: '🎙', title: 'Mic + system audio', body: 'Captures both streams separately, ffmpeg merges with alignment correction so the transcript reads correctly.' },
  { icon: '🔒', title: 'On-device transcription', body: 'whisper.cpp runs locally. Audio never leaves your Mac. Works offline.' },
  { icon: '📅', title: 'Calendar integration', body: 'Auto-suggests meeting titles from your calendar events so you spend less time naming things.' },
  { icon: '🧠', title: 'Claude Code or Ollama', body: 'Summarize via the Claude Code CLI in your terminal, or run a local LLM with Ollama. Toggle in Settings.' },
  { icon: '🗂', title: 'Organized files', body: 'Recordings land in ~/MeetingScribe/YYYY/MM-Month/DD-slug/ — easy to find, easy to back up.' },
  { icon: '🎛', title: 'Menu-bar control', body: 'No window in the way. Start, stop, and check status from the menu bar.' },
];
---

<section class="py-20 md:py-28 px-6">
  <div class="max-w-6xl mx-auto">
    <div class="text-center mb-14">
      <h2 class="text-4xl md:text-5xl font-semibold tracking-tight">Built for focus.</h2>
      <p class="mt-3 text-lg opacity-70">Everything you need. Nothing you don't.</p>
    </div>
    <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-5">
      {features.map((f) => <FeatureCard icon={f.icon} title={f.title} body={f.body} />)}
    </div>
  </div>
</section>
```

- [ ] **Step 3: Commit**

```bash
git add docs/website/src/components/FeatureCard.astro docs/website/src/components/FeatureGrid.astro
git commit -m "feat(docs-website): FeatureGrid with six feature cards"
```

---

### Task 15: PrivacyCallout + DownloadCTA

**Files:**
- Create: `docs/website/src/components/PrivacyCallout.astro`
- Create: `docs/website/src/components/DownloadCTA.astro`

- [ ] **Step 1: Write PrivacyCallout**

Write `docs/website/src/components/PrivacyCallout.astro`:

```astro
---
const docHref = '/docs/under-the-hood';
---

<section class="py-16 px-6 border-y border-[var(--color-border)] dark:border-[var(--color-border-dark)] bg-[var(--color-bg-alt)] dark:bg-[var(--color-bg-alt-dark)]">
  <div class="max-w-3xl mx-auto text-center">
    <h2 class="text-3xl md:text-4xl font-semibold tracking-tight">Everything runs locally.</h2>
    <p class="mt-4 text-lg opacity-75 leading-relaxed">
      Recording, transcription, file storage — all on your Mac.
      Summaries can stay local too via Ollama, or you can hand the transcript
      to Claude Code if you want.
    </p>
    <a href={docHref} class="inline-block mt-6 text-[var(--color-accent)] hover:underline">
      What stays local, what leaves →
    </a>
  </div>
</section>
```

- [ ] **Step 2: Write DownloadCTA**

Write `docs/website/src/components/DownloadCTA.astro`:

```astro
---
const downloadHref = 'https://github.com/scott-yj-yang/meeting-scribe/releases/latest';
---

<section class="py-20 md:py-28 px-6 text-center">
  <div class="max-w-2xl mx-auto">
    <h2 class="text-4xl md:text-5xl font-semibold tracking-tight">Try it.</h2>
    <p class="mt-4 text-lg opacity-70">Free. Local. No account.</p>
    <a href={downloadHref} class="inline-block mt-8 rounded-full bg-[var(--color-accent)] text-white text-base font-medium px-7 py-3.5 hover:bg-[var(--color-accent-hover)] transition">
      Download for Mac
    </a>
    <p class="mt-4 text-sm opacity-50">Apple Silicon · macOS 14+ · ~25 MB DMG</p>
  </div>
</section>
```

- [ ] **Step 3: Commit**

```bash
git add docs/website/src/components/PrivacyCallout.astro docs/website/src/components/DownloadCTA.astro
git commit -m "feat(docs-website): PrivacyCallout + bottom DownloadCTA"
```

---

### Task 16: Assemble the landing page

**Files:**
- Modify: `docs/website/src/pages/index.astro`

- [ ] **Step 1: Replace the placeholder with the real landing**

Overwrite `docs/website/src/pages/index.astro` with:

```astro
---
import Landing from '../layouts/Landing.astro';
import Hero from '../components/Hero.astro';
import HowItWorks from '../components/HowItWorks.astro';
import FeatureGrid from '../components/FeatureGrid.astro';
import PrivacyCallout from '../components/PrivacyCallout.astro';
import DownloadCTA from '../components/DownloadCTA.astro';
---

<Landing
  title="MeetingScribe — Local-first meeting transcription for macOS"
  description="Record system audio + mic, transcribe on-device with whisper.cpp, summarize with Claude Code or Ollama. Everything runs on your Mac."
>
  <Hero />
  <HowItWorks />
  <FeatureGrid />
  <PrivacyCallout />
  <DownloadCTA />
</Landing>
```

- [ ] **Step 2: Run dev server and verify the landing renders end-to-end**

```bash
cd docs/website && npm run dev
```

Visit `http://localhost:4321/`. Expected:
- Hero loads with headline "Meetings, captured."
- "How it works" shows 3 steps with placeholder gray boxes (no real screenshots yet).
- Feature grid shows 6 cards.
- Privacy callout renders.
- Download CTA at bottom.
- Theme toggle (☾/☀) in header flips light/dark.

Stop server (Ctrl+C).

- [ ] **Step 3: Build to verify no production errors**

```bash
cd docs/website && npm run build
```

Expected: `astro check` clean, build succeeds, pagefind generates indexes in `dist/pagefind/`.

- [ ] **Step 4: Commit**

```bash
git add docs/website/src/pages/index.astro
git commit -m "feat(docs-website): assemble full landing page"
```

---

## Phase 4 — Documentation pages

### Task 17: Install page

**Files:**
- Create: `docs/website/src/pages/docs/install.mdx`

- [ ] **Step 1: Write the install page**

Write `docs/website/src/pages/docs/install.mdx`:

````mdx
---
layout: ../../layouts/Doc.astro
title: Install MeetingScribe
description: Download the DMG, get past Gatekeeper, grant permissions, and verify the install.
---

import Callout from '../../components/Callout.astro';
import Screenshot from '../../components/Screenshot.astro';

## Requirements

- **Mac:** Apple Silicon (M1 or later). Intel Macs are not supported.
- **macOS:** 14 (Sonoma) or newer.
- **Disk:** ~500 MB total — about 150 MB for the app, the rest for the whisper model you choose.

## Download the DMG

Grab the latest release from [GitHub Releases](https://github.com/scott-yj-yang/meeting-scribe/releases/latest).

Double-click `MeetingScribe-X.Y.Z.dmg`, then drag **MeetingScribe.app** into your Applications folder.

## First launch — get past Gatekeeper

Current builds are ad-hoc signed (not yet notarized), so the first launch will show:

> "MeetingScribe.app cannot be opened because the developer cannot be verified."

<Callout type="note" title="This is expected">
Apple shows this dialog for any app that hasn't gone through Apple's notarization service. It does not mean the app is unsafe.
</Callout>

Two ways past it:

**Option 1 — Right-click open**

1. Open `/Applications/` in Finder.
2. Right-click `MeetingScribe.app` → **Open**.
3. Click **Open** in the confirmation dialog.

**Option 2 — Terminal**

```bash
xattr -dr com.apple.quarantine /Applications/MeetingScribe.app
```

Then double-click the app normally.

## Grant permissions

MeetingScribe needs three system permissions. macOS prompts for each the first time it's needed; you can also grant them up front in **System Settings → Privacy & Security**.

<Screenshot src="permissions-system-settings.png" alt="macOS System Settings showing the Privacy & Security pane with Microphone, Screen Recording, and Calendar entries" />

| Permission | Why |
|---|---|
| **Microphone** | Capture your voice during meetings. |
| **Screen Recording** | Capture system audio (Zoom, Meet, etc.) via ScreenCaptureKit. The camera and screen are not recorded. |
| **Calendar** | Suggest meeting titles from your upcoming events. |

<Callout type="warning" title="If you deny a permission">
You can re-grant any of these later in **System Settings → Privacy & Security**. After flipping a switch, fully quit MeetingScribe and relaunch.
</Callout>

## Install whisper.cpp

Transcription runs locally via [whisper.cpp](https://github.com/ggerganov/whisper.cpp).

```bash
brew install whisper-cpp
```

Then download a model — `base.en` is a good default (English, ~150 MB, fast):

```bash
bash scripts/download-model.sh base.en
```

The model file goes wherever MeetingScribe expects it (the app's Settings → Transcription pane shows the resolved path).

## Verify the install

1. Launch MeetingScribe.
2. Look for the **◐** icon in the menu bar.
3. Click it. You should see the recording panel.

If you don't see the menu-bar icon, check **System Settings → Login Items & Extensions** to make sure MeetingScribe isn't blocked from running.

Ready to record? Head to the [tutorial](/docs/tutorial).
````

- [ ] **Step 2: Verify the page renders**

```bash
cd docs/website && npm run dev
```

Visit `http://localhost:4321/docs/install`. Expected: page renders with sidebar (Install highlighted), right-side TOC populated from H2s, callouts styled, screenshot placeholder visible.

- [ ] **Step 3: Commit**

```bash
git add docs/website/src/pages/docs/install.mdx
git commit -m "docs(docs-website): install page (DMG, Gatekeeper, permissions, whisper)"
```

---

### Task 18: Tutorial page

**Files:**
- Create: `docs/website/src/pages/docs/tutorial.mdx`

- [ ] **Step 1: Write the tutorial**

Write `docs/website/src/pages/docs/tutorial.mdx`:

````mdx
---
layout: ../../layouts/Doc.astro
title: Record your first meeting
description: A two-minute walkthrough from menu bar click to finished transcript.
---

import Callout from '../../components/Callout.astro';
import Screenshot from '../../components/Screenshot.astro';

This walkthrough takes about two minutes once MeetingScribe is [installed](/docs/install) and permissions are granted.

## 1. Open the recording panel

Click the **◐** icon in the menu bar.

<Screenshot src="tutorial-menu-bar-icon.png" alt="The MeetingScribe menu bar icon expanded into the recording panel" />

## 2. Title your meeting

If you have a calendar event happening right now, MeetingScribe pre-fills the title. Otherwise type one yourself — anything human-readable works (it ends up in the folder name).

<Callout type="tip">
MeetingScribe sanitizes the title into a URL-safe slug. "Q2 Planning · Subgroup" becomes `q2-planning-subgroup` on disk.
</Callout>

## 3. Pick a meeting type tag

The dropdown offers: **1:1**, **Subgroup**, **Lab Meeting**, **Casual**, **Standup**. The tag is saved with the meeting and shows up in the dashboard later — useful when you have hundreds of recordings and want to filter.

## 4. Start the session

Click **Start Session**.

<Screenshot src="tutorial-start-session.png" alt="Recording panel with the Start Session button highlighted" />

You'll see the live transcription preview begin within a few seconds. This is `SFSpeechRecognizer` running locally, just so you can confirm audio is being captured. It auto-disables after 60 seconds to save battery — the final transcript comes from whisper.cpp.

<Callout type="note" title="No words appearing?">
If the live preview stays blank after 10 seconds of speaking, your microphone or screen-recording permission probably isn't granted. See [Troubleshooting](/docs/troubleshooting#no-audio-captured).
</Callout>

## 5. Take notes (optional)

The notes field stays open during the meeting. Anything you type is saved as `notes.md` alongside the transcript.

## 6. Stop the session

Click **Stop**. A confirmation gives you a chance to cancel if you stopped by accident.

<Screenshot src="tutorial-stop-button.png" alt="Floating two-click Stop button at the bottom of the recording panel" />

## 7. Wait for transcription

whisper.cpp processes the merged audio. The progress bar shows percent complete and ETA. A typical 30-minute meeting takes 1–2 minutes to transcribe on M2.

<Screenshot src="tutorial-transcription-progress.png" alt="Transcription progress bar showing 42% complete with 47s remaining" />

## 8. Read the transcript or summarize

When transcription finishes, the post-recording panel shows up.

- **Open in Claude Code** — launches your terminal at the meeting folder and runs `/summarize`. Requires the Claude Code CLI to be installed.
- **Ollama summary** — if you've selected Ollama in Settings, the summary generates automatically.
- **Open in Finder** — jump to the meeting folder.
- **Delete** — remove the recording cleanly.
- **Start new session** — begin recording the next meeting.

## 9. Find your files

Your meeting lives at:

```
~/MeetingScribe/2026/05-May/21-q2-planning-subgroup/
├── audio.m4a
├── transcript.md
├── notes.md          (if you took notes)
└── summary.md        (after summarization)
```

That's it. Everything else in the app is variations on this loop — see [Features](/docs/features) for the full reference.
````

- [ ] **Step 2: Commit**

```bash
git add docs/website/src/pages/docs/tutorial.mdx
git commit -m "docs(docs-website): tutorial page (record first meeting in 2 min)"
```

---

### Task 19: Features reference page

**Files:**
- Create: `docs/website/src/pages/docs/features.mdx`

- [ ] **Step 1: Write the features reference**

Write `docs/website/src/pages/docs/features.mdx`. Follow the outline in
`docs/superpowers/specs/2026-05-21-docs-website-design.md` § "`/docs/features`".
Use this skeleton; expand each section with 1–3 paragraphs grounded in the
existing repo `README.md` and the app's actual UI:

````mdx
---
layout: ../../layouts/Doc.astro
title: Features
description: Reference for every visible feature of MeetingScribe.
---

import Callout from '../../components/Callout.astro';
import Screenshot from '../../components/Screenshot.astro';

This page documents every visible feature. For an opinionated walkthrough, see the [tutorial](/docs/tutorial) instead.

## Menu bar app

The MeetingScribe menu bar item is the only UI in your way. Clicking it expands the recording panel; clicking anywhere outside dismisses it.

<Screenshot src="features-menu-bar.png" alt="MeetingScribe menu bar item with the recording panel expanded" />

## Live transcription preview

While recording, the first 60 seconds show real-time text via Apple's `SFSpeechRecognizer`. This is a confidence check — it lets you confirm audio is being captured. The preview disables automatically to save battery; the real transcript comes from whisper.cpp post-recording.

<Callout type="note" title="Why two transcription engines?">
SFSpeechRecognizer is fast but lower quality. whisper.cpp is slower but produces the final, accurate transcript. Using both gives you instant feedback and high accuracy.
</Callout>

## Recording

System audio is captured via ScreenCaptureKit; the mic is captured via AVAudioEngine. The two streams are written to separate temporary files and merged with ffmpeg after you stop — with alignment correction so participants don't appear to talk over themselves.

## Calendar integration

If you have a calendar event happening within ±15 minutes of clicking Start, its title is offered as the meeting title. You can always override it.

## Meeting type tags

Five tags: 1:1, Subgroup, Lab Meeting, Casual, Standup. The tag is stored in the meeting's metadata and shows up in the dashboard for filtering.

## Notes

A free-text field that opens with the recording panel. Saved as `notes.md` in the meeting folder. Markdown is rendered when you view it in the dashboard.

## On-device transcription (whisper.cpp)

After you stop, whisper.cpp transcribes the merged audio file. Progress bar shows percent + ETA. The model used is configurable in Settings — `base.en` is the default; `small.en` is more accurate but slower.

## File storage layout

```
~/MeetingScribe/
└── 2026/
    └── 05-May/
        └── 21-q2-planning-subgroup/
            ├── audio.m4a
            ├── transcript.md
            ├── notes.md
            └── summary.md
```

Year/month/day folder structure makes it natural to back up by date range.

## Post-recording panel

When transcription finishes, you get five actions: Open in Claude Code, Open in Finder, View Summary, Delete, Start New Session. The panel stays open until you dismiss it.

## Summarization — Claude Code vs Ollama

Two providers, selectable in Settings.

| Provider | Where it runs | Cost | Privacy |
|---|---|---|---|
| **Claude Code CLI** | Anthropic's cloud, via the Claude Code CLI on your Mac | Anthropic API token (your account) | Transcript text is sent. Audio is not. |
| **Ollama** | Locally on your Mac | None (compute is yours) | 100% local. Nothing leaves the machine. |

Use Claude Code for higher-quality summaries on important meetings. Use Ollama when you want zero data leaving your machine.

## Settings

- **Microphone** — pick from available input devices.
- **Output directory** — default `~/MeetingScribe/`. You can move it (e.g., to an external drive).
- **Summarization provider** — Claude Code or Ollama.
- **Whisper model** — `base.en`, `small.en`, `medium.en`, etc.

## meetingctl CLI

The `meetingctl` command lists your meetings from the terminal:

```bash
npx tsx bin/meetingctl.ts list
```

It's deliberately not globally installed in the native build — most operations live in the GUI. The CLI is there for scripting and search.
````

- [ ] **Step 2: Commit**

```bash
git add docs/website/src/pages/docs/features.mdx
git commit -m "docs(docs-website): features reference page"
```

---

### Task 20: Troubleshooting page

**Files:**
- Create: `docs/website/src/pages/docs/troubleshooting.mdx`

- [ ] **Step 1: Write the troubleshooting page**

Write `docs/website/src/pages/docs/troubleshooting.mdx`:

````mdx
---
layout: ../../layouts/Doc.astro
title: Troubleshooting
description: Common issues and how to fix them.
---

import Callout from '../../components/Callout.astro';

## No audio captured

**Symptom:** The recording finishes but the transcript is empty, or only your voice (not the meeting audio) is transcribed.

1. Check **System Settings → Privacy & Security → Microphone** — MeetingScribe is on.
2. Check **System Settings → Privacy & Security → Screen Recording** — MeetingScribe is on. *This is the most common cause of missing system audio.*
3. Fully quit MeetingScribe and relaunch after toggling either permission.
4. If you're using a virtual audio device (Loopback, BlackHole, etc.), make sure it's selected as your system output during the call.

## "whisper.cpp not found"

**Symptom:** Transcription fails immediately with a "whisper.cpp executable not found" message.

```bash
brew install whisper-cpp
which whisper-cli  # should print a path
```

If `which` returns nothing, Homebrew isn't on your `PATH` for GUI apps. Open Terminal, run `brew --prefix`, and put that bin folder on the PATH MeetingScribe sees — easiest fix is to relaunch the app from Terminal once:

```bash
open /Applications/MeetingScribe.app
```

## Live transcription preview never appears

**Symptom:** Recording works but the live preview text box stays blank.

The live preview uses Apple's `SFSpeechRecognizer`, which requires the **Speech Recognition** permission *and* an internet connection on first use (Apple downloads a language model). Grant it in System Settings; subsequent recordings work offline.

This does not affect the final transcript — whisper.cpp runs after you stop and is fully offline.

## Summary didn't generate

**For Claude Code:**

- Claude Code CLI is installed (`which claude`) and you've authenticated.
- The meeting folder opened in your terminal — if not, the launch step failed; open the folder manually and run `claude` there.

**For Ollama:**

- Ollama is running (`ollama list` succeeds).
- The model picked in Settings is pulled (`ollama pull llama3.1` or similar).
- Check the app's log pane for the actual error.

## Switching Claude Code ↔ Ollama

Open MeetingScribe → click the menu bar icon → **Settings → Summarization provider**. Pick the other one. New recordings use the new provider; existing recordings keep whatever summary they already have.

## Permissions denied / how to re-grant

Open **System Settings → Privacy & Security**. Find the relevant pane (Microphone, Screen Recording, Calendar). Toggle MeetingScribe off, then on. Fully quit MeetingScribe (⌘Q) and relaunch.

<Callout type="warning" title="macOS quirk">
Toggling a permission while the app is running often doesn't take effect until restart.
</Callout>

## App won't open after download

You're seeing "developer cannot be verified." Right-click `MeetingScribe.app` in Applications → **Open** → click **Open** in the dialog. Or run:

```bash
xattr -dr com.apple.quarantine /Applications/MeetingScribe.app
```

Then double-click normally. See the [install page](/docs/install#first-launch-get-past-gatekeeper) for more.

## Where are my recordings?

Default location:

```
~/MeetingScribe/YYYY/MM-Month/DD-slug/
```

If you changed the output directory in Settings, look there instead. The path is shown at the top of Settings → Storage.

## How to delete a recording cleanly

In the dashboard, right-click the meeting → **Delete**. This removes the entire folder including audio, transcript, notes, and summary.

To delete from the terminal:

```bash
rm -rf ~/MeetingScribe/2026/05-May/21-q2-planning-subgroup/
```

## How to file a bug

Open an issue at [github.com/scott-yj-yang/meeting-scribe/issues](https://github.com/scott-yj-yang/meeting-scribe/issues). Include: macOS version, MeetingScribe version (Settings → About), what you were doing, what happened, what you expected. If transcription failed, the app's log pane content is gold.
````

- [ ] **Step 2: Commit**

```bash
git add docs/website/src/pages/docs/troubleshooting.mdx
git commit -m "docs(docs-website): troubleshooting page (9 common issues)"
```

---

### Task 21: Under-the-hood + privacy page

**Files:**
- Create: `docs/website/src/pages/docs/under-the-hood.mdx`

- [ ] **Step 1: Write the page**

Write `docs/website/src/pages/docs/under-the-hood.mdx`:

````mdx
---
layout: ../../layouts/Doc.astro
title: Under the hood
description: How MeetingScribe works and what stays on your machine.
---

import Callout from '../../components/Callout.astro';

## How it works

```
┌──────────────────────────────────────────────┐
│   macOS App (Menu Bar + Window)              │
│   Swift 6 / SwiftUI                          │
│                                              │
│   ScreenCaptureKit (system audio)            │
│   AVAudioEngine (mic)                        │
│   SFSpeechRecognizer (live preview, 60s)     │
│   whisper.cpp (final transcription)          │
│   Claude Code CLI or Ollama (summarization)  │
└──────────────────────────────────────────────┘
                      │
                      ▼
            ~/MeetingScribe/
            (local markdown + audio + metadata)
                      │
                      ▼
              meetingctl list
              (optional CLI)
```

The pipeline:

1. **Capture** — ScreenCaptureKit gets system audio (Zoom, Meet, FaceTime, anything coming out of your speakers). AVAudioEngine gets your microphone. The two streams write to separate temp files.
2. **Live preview** — `SFSpeechRecognizer` runs on the mic stream for the first 60 seconds so you can confirm audio is working.
3. **Stop** — ffmpeg merges the two streams with timestamp alignment so speakers don't overlap incorrectly.
4. **Transcribe** — whisper.cpp processes the merged audio. Output is markdown with speaker turn-taking.
5. **Save** — markdown + audio + metadata land under `~/MeetingScribe/YYYY/MM-Month/DD-slug/`.
6. **Summarize (optional)** — either the Claude Code CLI is invoked at the meeting folder (you click "Open in Claude Code"), or Ollama runs locally if you've selected it.

## Privacy

MeetingScribe is built local-first. The table below is the complete story of what data goes where.

| Data | Where it lives | Leaves your Mac? |
|---|---|---|
| Recorded audio (`audio.m4a`) | `~/MeetingScribe/.../audio.m4a` | **Never.** |
| Live transcription preview | In-memory only, discarded after 60s | **Never.** |
| Final transcript (`transcript.md`) | `~/MeetingScribe/.../transcript.md` | Depends on summarization choice — see below. |
| Your notes (`notes.md`) | `~/MeetingScribe/.../notes.md` | Depends on summarization choice — see below. |
| Meeting metadata (title, tag, timestamps) | `~/MeetingScribe/.../meeting.json` | **Never** automatically. |
| Calendar event titles | Read locally via EventKit | **Never.** |
| Whisper model file | `~/.../ggml-base.en.bin` (or your chosen path) | **Never.** |

### Summarization — the only thing that might leave

Two providers. You pick in Settings.

- **Ollama** — 100% local. The model runs on your Mac. Nothing leaves.
- **Claude Code CLI** — you click "Open in Claude Code" and run `/summarize` in your terminal. The transcript text (and your notes if you include them) is sent to Anthropic via the Claude Code CLI. The audio file is never sent.

<Callout type="note" title="No telemetry">
MeetingScribe does not send analytics, crash reports, telemetry, or update checks. The only network calls are the ones you explicitly trigger by choosing Claude Code as your summarization provider.
</Callout>

## Source code

Everything is open source: [github.com/scott-yj-yang/meeting-scribe](https://github.com/scott-yj-yang/meeting-scribe). You can audit the capture pipeline, the file paths, and the summarization integration yourself.
````

- [ ] **Step 2: Build the whole site to verify all pages and links**

```bash
cd docs/website && npm run build
```

Expected: build succeeds; `dist/` contains `index.html`, `docs/install/index.html`, `docs/tutorial/index.html`, `docs/features/index.html`, `docs/troubleshooting/index.html`, `docs/under-the-hood/index.html`, and a `pagefind/` directory with the search index.

- [ ] **Step 3: Commit**

```bash
git add docs/website/src/pages/docs/under-the-hood.mdx
git commit -m "docs(docs-website): under-the-hood + privacy page"
```

---

## Phase 5 — Search, link check, deploy

### Task 22: Add Pagefind search UI to the header

**Files:**
- Modify: `docs/website/src/components/Header.astro`
- Create: `docs/website/src/components/SearchModal.astro`

- [ ] **Step 1: Create the search modal**

Write `docs/website/src/components/SearchModal.astro`:

```astro
---
// Pagefind UI mounts client-side. The CSS comes from /pagefind/pagefind-ui.css
// which exists only after `pagefind` runs (post-build step in `npm run build`).
// In dev (`npm run dev`), the import will 404 — that's fine, search is a build-time feature.
---

<dialog id="search-modal" class="rounded-2xl shadow-2xl border border-[var(--color-border)] dark:border-[var(--color-border-dark)] p-0 w-[min(92vw,640px)] backdrop:bg-black/40 backdrop:backdrop-blur-sm">
  <div class="p-5">
    <div id="search-mount"></div>
    <button id="search-close" class="absolute top-3 right-3 opacity-50 hover:opacity-100 text-sm" aria-label="Close search">✕</button>
  </div>
</dialog>

<link rel="stylesheet" href="/pagefind/pagefind-ui.css" />
<script>
  (async () => {
    const modal = document.getElementById('search-modal') as HTMLDialogElement | null;
    const closeBtn = document.getElementById('search-close');
    const trigger = document.getElementById('search-trigger');
    if (!modal || !trigger) return;

    let loaded = false;
    async function ensureLoaded() {
      if (loaded) return;
      try {
        // @ts-ignore — pagefind-ui is loaded from /pagefind/ at runtime
        await import('/pagefind/pagefind-ui.js');
        // @ts-ignore — PagefindUI is exposed on window after the script loads
        new window.PagefindUI({ element: '#search-mount', showSubResults: true });
        loaded = true;
      } catch (err) {
        document.getElementById('search-mount')!.innerHTML =
          '<p style="opacity:.7">Search index unavailable in dev mode. Run <code>npm run build &amp;&amp; npm run preview</code>.</p>';
        loaded = true;
      }
    }

    trigger.addEventListener('click', async () => {
      await ensureLoaded();
      modal.showModal();
    });
    closeBtn?.addEventListener('click', () => modal.close());

    document.addEventListener('keydown', (e) => {
      if ((e.metaKey || e.ctrlKey) && e.key === 'k') {
        e.preventDefault();
        trigger.click();
      }
    });
  })();
</script>
```

- [ ] **Step 2: Add the search trigger to the header**

Edit `docs/website/src/components/Header.astro`. Replace the existing block:

```astro
    <div class="flex items-center gap-3">
      <button id="theme-toggle" aria-label="Toggle theme" class="opacity-70 hover:opacity-100 transition text-sm">
        <span class="hidden dark:inline">☀</span>
        <span class="inline dark:hidden">☾</span>
      </button>
      <a href={downloadHref} class="rounded-full bg-[var(--color-accent)] text-white text-sm font-medium px-4 py-1.5 hover:bg-[var(--color-accent-hover)] transition">
        Download
      </a>
    </div>
```

with:

```astro
    <div class="flex items-center gap-3">
      <button id="search-trigger" aria-label="Open search (⌘K)" class="hidden md:flex items-center gap-2 text-xs opacity-60 hover:opacity-100 border border-[var(--color-border)] dark:border-[var(--color-border-dark)] rounded-md px-2 py-1">
        <span>Search</span>
        <kbd class="font-mono text-[10px] opacity-70">⌘K</kbd>
      </button>
      <button id="theme-toggle" aria-label="Toggle theme" class="opacity-70 hover:opacity-100 transition text-sm">
        <span class="hidden dark:inline">☀</span>
        <span class="inline dark:hidden">☾</span>
      </button>
      <a href={downloadHref} class="rounded-full bg-[var(--color-accent)] text-white text-sm font-medium px-4 py-1.5 hover:bg-[var(--color-accent-hover)] transition">
        Download
      </a>
    </div>
```

Then add at the very bottom of the file (after the existing `<script>` block):

```astro
<SearchModal />
```

And at the top of the frontmatter (the `---` block), add:

```astro
import SearchModal from './SearchModal.astro';
```

- [ ] **Step 3: Build and preview to verify search**

```bash
cd docs/website && npm run build && npm run preview
```

Open `http://localhost:4321/`. Press ⌘K. Search modal opens. Type "install" — results appear linking to `/docs/install`. Press Esc or click ✕ to close.

- [ ] **Step 4: Commit**

```bash
git add docs/website/src/components/Header.astro docs/website/src/components/SearchModal.astro
git commit -m "feat(docs-website): Pagefind search modal with ⌘K shortcut"
```

---

### Task 23: Add an internal link checker to the build

**Files:**
- Modify: `docs/website/package.json`

- [ ] **Step 1: Add a link-check script**

Edit `docs/website/package.json`. Change the `scripts` block from:

```json
  "scripts": {
    "dev": "astro dev",
    "build": "astro check && astro build && pagefind --site dist",
    "preview": "astro preview",
    "astro": "astro"
  },
```

to:

```json
  "scripts": {
    "dev": "astro dev",
    "build": "astro check && astro build && pagefind --site dist",
    "link-check": "npx --yes linkinator dist --recurse --skip 'https?://(github.com|raw.githubusercontent.com)'",
    "preview": "astro preview",
    "astro": "astro"
  },
```

- [ ] **Step 2: Run the link checker against the build**

```bash
cd docs/website && npm run build && npm run link-check
```

Expected: linkinator scans every page in `dist/`, reports 0 broken internal links. External GitHub links are skipped (they require auth headers in some CI environments). If a broken link is reported, fix it in the source file and rebuild.

- [ ] **Step 3: Commit**

```bash
git add docs/website/package.json
git commit -m "build(docs-website): linkinator script for internal link check"
```

---

### Task 24: Add a favicon

**Files:**
- Create: `docs/website/public/favicon.svg`

- [ ] **Step 1: Write the favicon SVG**

Write `docs/website/public/favicon.svg`:

```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32">
  <circle cx="16" cy="16" r="14" fill="#0a84ff"/>
  <path d="M16 4 a12 12 0 1 0 0 24 z" fill="#ffffff" opacity="0.95"/>
</svg>
```

- [ ] **Step 2: Verify it loads**

```bash
cd docs/website && npm run dev
```

Inspect the tab favicon at `http://localhost:4321/`. Expect a blue/white half-moon (matches the `◐` glyph used in the wordmark).

- [ ] **Step 3: Commit**

```bash
git add docs/website/public/favicon.svg
git commit -m "feat(docs-website): favicon (half-moon, matches wordmark)"
```

---

### Task 25: CNAME placeholder for custom domain

**Files:**
- Create: `docs/website/public/CNAME`

- [ ] **Step 1: Write a placeholder CNAME**

This file will be overwritten by the user with the real domain before first deploy. The placeholder ensures the deploy workflow has something to copy into the published artifact.

Write `docs/website/public/CNAME`:

```
meetingscribe.example.com
```

- [ ] **Step 2: Commit**

```bash
git add docs/website/public/CNAME
git commit -m "build(docs-website): CNAME placeholder for custom domain (TBD)"
```

---

### Task 26: GitHub Actions workflow (path-scoped, not yet enabled)

**Files:**
- Create: `.github/workflows/docs.yml`

- [ ] **Step 1: Write the workflow**

Write `.github/workflows/docs.yml` (relative to repo root, NOT inside `docs/website/`):

```yaml
name: Deploy docs website

on:
  push:
    branches: [main]
    paths:
      - 'docs/website/**'
      - '.github/workflows/docs.yml'
  workflow_dispatch:

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: pages
  cancel-in-progress: true

jobs:
  build:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: docs/website
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'
          cache-dependency-path: docs/website/package-lock.json
      - run: npm ci
      - run: npm run build
      - uses: actions/upload-pages-artifact@v3
        with:
          path: docs/website/dist

  deploy:
    needs: build
    runs-on: ubuntu-latest
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    steps:
      - id: deployment
        uses: actions/deploy-pages@v4
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/docs.yml
git commit -m "ci(docs-website): GH Actions workflow for path-scoped Pages deploy"
```

<Callout type="warning" title="Workflow is committed but inert until merged">
The workflow only fires on pushes to `main` matching `docs/website/**`. Until the user merges this branch into `main` and enables GitHub Pages in repo settings (Source: GitHub Actions), no deploy happens. This is intentional — the user controls when the site goes live.
</Callout>

---

### Task 27: Final smoke test — build, preview, walk every page

**Files:** (no file changes — verification only)

- [ ] **Step 1: Clean build**

```bash
cd docs/website && rm -rf dist .astro && npm run build
```

Expected: `astro check` reports 0 errors, build succeeds, pagefind generates the index.

- [ ] **Step 2: Link check**

```bash
cd docs/website && npm run link-check
```

Expected: 0 broken internal links.

- [ ] **Step 3: Preview and walk every URL**

```bash
cd docs/website && npm run preview
```

Open `http://localhost:4321/` and verify:

1. **Landing** — hero, how-it-works (3 placeholders), feature grid (6 cards), privacy callout, download CTA, footer all render.
2. **Theme toggle** — clicking ☾ flips to dark mode; reload preserves the choice via localStorage.
3. **Search** — ⌘K opens the modal, typing "permission" returns the install page.
4. **`/docs/install`** — sidebar highlights "Install"; TOC on the right populates; callouts render correctly.
5. **`/docs/tutorial`** — all 9 steps present.
6. **`/docs/features`** — long page, every H2 reachable via TOC.
7. **`/docs/troubleshooting`** — all 9 issues anchored.
8. **`/docs/under-the-hood`** — privacy table renders, ascii diagram preserved.
9. **Mobile width** (resize browser to 375px) — sidebar collapses, header nav collapses, content reflows without horizontal scroll.

Stop the preview server.

- [ ] **Step 4: Final summary commit (no code changes; the work is done)**

If any visual fixes were needed during the smoke test, they should have been done as small commits along the way. If nothing needs changing, skip this step.

---

## Self-Review Notes

- **Spec coverage:** Every spec section maps to at least one task. Landing layout (Spec § "Landing"): Tasks 8, 12-16. Doc layout (§ "Doc page"): Tasks 9-11. IA (§ "Information Architecture"): Tasks 17-21. Asset strategy (§ "Asset Strategy"): Task 6 (Screenshot component with placeholder fallback). Build & deploy (§ "Build & Deploy"): Tasks 1, 23, 25, 26. Component inventory: every component named in the spec appears in a task.
- **Placeholder scan:** No "TBD" or "implement later" in steps. The `meetingscribe.example.com` in Task 1's `astro.config.mjs` and Task 25's `CNAME` is a deliberate, documented placeholder for the user to swap before deploy.
- **Type consistency:** `Screenshot.astro` props (`src`, `alt`, `caption`, `width`, `height`) are used consistently across `Hero.astro`, `HowItWorks.astro`, and the MDX pages. `Callout.astro` types are `note | tip | warning` everywhere. The `frontmatter` shape in `Doc.astro` (`{ title: string; description?: string }`) matches every MDX file's frontmatter.

## Execution

**Approach:** subagent-driven-development (user's explicit choice).

Before the first task dispatch, the implementer skill must invoke
`superpowers:using-git-worktrees` to set up an isolated workspace off the
current branch, so the in-flight Swift changes on `feat/native-overhaul` stay
clean while the docs site is built.

Once that worktree exists, dispatch one fresh subagent per task in order. Each
subagent reads this plan and the spec, executes only its assigned task, and
returns. The driver reviews the diff and the verification output before moving
to the next task.
