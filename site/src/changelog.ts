// The app's releases for the Updates page, read from CHANGELOG.md in the repo at build time,
// so the timeline always matches the changelog. Keep a Changelog format:
//   ## [0.9.2] - 2026-11-14   then optional text, then "### Added" etc. with "- " bullets.
// "Unreleased" is left out.
import raw from '../../CHANGELOG.md?raw';
import { REPO_URL } from './i18n/ui';

export interface ReleaseGroup { title: string; items: string[] }
export interface ReleaseEntry { version: string; date: string; url: string; intro: string[]; groups: ReleaseGroup[] }

export function parseChangelog(text: string): ReleaseEntry[] {
  const entries: ReleaseEntry[] = [];
  let entry: ReleaseEntry | null = null;
  let group: ReleaseGroup | null = null;
  // A bullet may wrap over several lines; a blank line ends a paragraph.
  let paragraph: string[] | null = null;
  const flush = () => {
    if (entry && paragraph?.length) entry.intro.push(paragraph.join(' '));
    paragraph = null;
  };
  for (const line of text.split('\n')) {
    const head = line.match(/^## \[([^\]]+)\](?:\s*-\s*(\S+))?/);
    if (head) {
      flush();
      group = null;
      entry = head[1].toLowerCase() === 'unreleased'
        ? null
        : { version: head[1], date: head[2] ?? '', url: `${REPO_URL}/releases/tag/v${head[1]}`, intro: [], groups: [] };
      if (entry) entries.push(entry);
      continue;
    }
    if (!entry || /^\[[^\]]+\]:/.test(line)) continue;
    const sub = line.match(/^### (.+)/);
    if (sub) {
      flush();
      group = { title: sub[1].trim(), items: [] };
      entry.groups.push(group);
      continue;
    }
    const bullet = line.match(/^- (.+)/);
    if (bullet && group) {
      group.items.push(bullet[1].trim());
      continue;
    }
    if (/^\s+\S/.test(line) && group?.items.length) {
      group.items[group.items.length - 1] += ' ' + line.trim();
      continue;
    }
    if (!line.trim()) {
      flush();
      continue;
    }
    if (!group) (paragraph ??= []).push(line.trim());
  }
  flush();
  return entries;
}

export const releases = parseChangelog(raw);
