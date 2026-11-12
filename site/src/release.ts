// Latest app release, read from GitHub at build time so the site never shows an old version.
// Pre-releases count too (GitHub's /releases/latest skips them); drafts never do — the
// Actions token can see them. Falls back to FALLBACK when GitHub can't be reached.
import { REPO_URL } from './i18n/ui';

const FALLBACK = '0.9.1';
const api = REPO_URL.replace('https://github.com/', 'https://api.github.com/repos/') + '/releases?per_page=10';

async function latest(): Promise<{ version: string; url: string }> {
  try {
    const res = await fetch(api, {
      headers: { Accept: 'application/vnd.github+json', ...(process.env.GITHUB_TOKEN ? { Authorization: `Bearer ${process.env.GITHUB_TOKEN}` } : {}) },
      signal: AbortSignal.timeout(5000),
    });
    if (!res.ok) throw new Error(`GitHub answered ${res.status}`);
    const list = (await res.json()) as { tag_name: string; html_url: string; draft: boolean }[];
    const r = list.find((x) => !x.draft);
    if (!r) throw new Error('no published release');
    return { version: r.tag_name.replace(/^v/, ''), url: r.html_url };
  } catch (e) {
    console.warn(`[release] using fallback ${FALLBACK}: ${(e as Error).message}`);
    return { version: FALLBACK, url: `${REPO_URL}/releases` };
  }
}

export const release = await latest();
