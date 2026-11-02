# beand.app website

Astro site for https://beand.app. Static pages, plus on-demand rendering for shared shots (`/s/[id]`) via the Node adapter. Hosting: see `../deploy/README.md`.

```bash
cd site
npm install
npm run dev        # http://localhost:4321
npm run build      # → dist/client (static) + dist/server (Node)
npm run preview    # runs the built Node server
```

## Structure

- `src/i18n/ui.ts`: all UI strings (EN/DE) and the route map. Every page exists in both languages: `/…` English, `/de/…` German.
- `src/styles/global.css`: design tokens from the logo (`#1B1917`, `#F3EEE4`, `#29C7B0`), Archivo self-hosted via `@fontsource-variable/archivo`.
- `src/components/`: `Wordmark` (logo in HTML/SVG), `Bean` (the mark), `ShotChart` (illustrative curve), `Home`.
- `src/pages/s/[id].astro`: shared shots, `prerender = false`. Placeholder until sharing ships.
- `public/og.png`: default link preview.

## Rules

- No third-party requests (fonts, scripts, analytics). The privacy policy depends on it.
- Never put anything under `/api/`. That path belongs to the catalog and is deployed separately.
- Feature status (`Available` / `Coming`) lives in `src/components/Home.astro`. Keep it honest.
