German versions of the home and roaster pages, parked while the site is English-only.
To bring them back: move them to src/pages/de/ and set the de routes in src/i18n/ui.ts.

The German home copy that used to live in src/i18n/home.ts is in home-copy-old.ts.txt (outdated). Home.astro is English-only now; give it a `lang` prop again when the German home page comes back.

roasters.astro is the English page for roasters, parked until the roaster catalog exists. To bring it back: move it to src/pages/ and add `roasters: { en: '/roasters/', de: null }` to the routes in src/i18n/ui.ts.
