export type Lang = 'en' | 'de';

export const REPO_URL = 'https://github.com/tangenzzz/beand';
export const CONTACT_EMAIL = 'beandapp@pm.me';

/** Route names → localized paths. Keep both languages in sync. */
export const routes = {
  // de: null = English only for now (German drafts in site/drafts/de)
  home: { en: '/', de: null },
  imprint: { en: '/imprint/', de: '/de/impressum/' },
  privacy: { en: '/privacy/', de: '/de/datenschutz/' },
  deleteData: { en: '/delete-data/', de: '/de/daten-loeschen/' },
} as const satisfies Record<string, { en: string; de: string | null }>;
export type RouteKey = keyof typeof routes;

export const ui = {
  en: {
    'meta.description': "Track your beans and every espresso and pour-over. Live data from Meticulous and GaggiMate, rate and analyse every cup, link it to the gear you brewed with. Free and open source.",
    'nav.features': 'Features',
    'nav.machines': 'Equipment',
    'footer.tagline': 'From bag to cup.',
    'footer.notrack': 'No cookies. No tracking.',
    'footer.legal': 'Legal',
    'footer.imprint': 'Imprint',
    'footer.privacy': 'Privacy',
    'footer.delete': 'Delete your data',
    'footer.source': 'Source code',
    'footer.trademarks': 'Machine and device names are trademarks of their respective owners. bean’d is an independent project.',
  },
  de: {
    'meta.description': "Behalte deine Bohnen und jeden Espresso und Pour-over im Blick. Live-Daten von Meticulous und GaggiMate, jede Tasse bewerten und analysieren, verknüpft mit der Ausrüstung, mit der du sie gemacht hast. Kostenlos und Open Source.",
    'nav.features': 'Funktionen',
    'nav.machines': 'Maschinen',
    'footer.tagline': 'Von der Packung bis in die Tasse.',
    'footer.notrack': 'Keine Cookies. Kein Tracking.',
    'footer.legal': 'Rechtliches',
    'footer.imprint': 'Impressum',
    'footer.privacy': 'Datenschutz',
    'footer.delete': 'Daten löschen',
    'footer.source': 'Quellcode',
    'footer.trademarks': 'Maschinen- und Gerätenamen sind Marken ihrer jeweiligen Inhaber. bean’d ist ein unabhängiges Projekt.',
  },
} as const;

export type UiKey = keyof (typeof ui)['en'];
export const t = (lang: Lang) => (key: UiKey) => ui[lang][key];
export const path = (lang: Lang, key: RouteKey): string => routes[key][lang] ?? routes[key].en;
