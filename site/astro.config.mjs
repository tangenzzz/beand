// @ts-check
import { defineConfig } from 'astro/config';
import node from '@astrojs/node';
import sitemap from '@astrojs/sitemap';

// Static by default. Pages that set `export const prerender = false`
// (currently only /s/[id] for shared shots) run on the Node server.
export default defineConfig({
  site: 'https://beand.app',
  output: 'static',
  adapter: node({ mode: 'standalone' }),
  trailingSlash: 'ignore',
  scopedStyleStrategy: 'where',
  build: { format: 'directory' },
  // sitemap-index.xml for search engines. Shared shots (/s/) and the 404 page stay out.
  integrations: [sitemap({ filter: (page) => !page.includes('/s/') && !page.includes('/404') })],
});
