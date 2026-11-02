// Copy for the home page that is not inside its own component.
// Feature status must match the app (README of tangenzzz/beand).
import type { Point } from '../components/Points.astro';

export const home = {
  hero: {
    title: 'From bag to cup.',
    lead: 'Track your beans and every brew. Rate it, analyse it, and link it to the brew chain you made it with.',
    note: 'Free and open source.',
  },
  machine: {
    eyebrow: 'Machines and scales',
    title: 'Connect your machine or scale. Choose how you brew.',
    body: 'Every machine and brew method gets its own home tab, with a live ring and controls made for it.',
    points: [
      { t: 'Buttons', d: 'Made for every machine and brew mode' },
      { t: 'Hero ring', d: 'Temperature, preheat or flow, whatever matters right now' },
      { t: 'Sensors and live data', d: 'Everything this brew needs, in real time' },
      { t: 'Supported modes', d: 'Meticulous, GaggiMate, pour-over. More coming soon' },
    ] satisfies Point[],
  },
};
