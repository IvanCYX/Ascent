/** Date helpers. Everything is stored as ISO `yyyy-mm-dd` in local time. */

const MONTHS = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
const DAYS = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];

export const toISODate = (d: Date): string => {
  const p = (n: number) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
};

export const fromISODate = (iso: string): Date => {
  const [y, m, d] = iso.split('-').map(Number);
  return new Date(y, m - 1, d);
};

export const todayISO = (): string => toISODate(new Date());

export const addDays = (iso: string, days: number): string => {
  const d = fromISODate(iso);
  d.setDate(d.getDate() + days);
  return toISODate(d);
};

export const daysBetween = (a: string, b: string): number =>
  Math.round((fromISODate(b).getTime() - fromISODate(a).getTime()) / 86_400_000);

/** "26 JUL" */
export const shortDate = (iso: string): string => {
  const d = fromISODate(iso);
  return `${d.getDate()} ${MONTHS[d.getMonth()]}`;
};

/** "12 Jan" */
export const prettyDate = (iso: string): string => {
  const d = fromISODate(iso);
  const m = MONTHS[d.getMonth()];
  return `${d.getDate()} ${m[0]}${m.slice(1).toLowerCase()}`;
};

/** "TUE 28 JUL" */
export const planDate = (iso: string): string => {
  const d = fromISODate(iso);
  return `${DAYS[d.getDay()]} ${d.getDate()} ${MONTHS[d.getMonth()]}`;
};

/** ISO week number (Mon-based), used for load-rule counting. */
export const isoWeek = (iso: string): { year: number; week: number; key: string } => {
  const d = fromISODate(iso);
  const target = new Date(d.getFullYear(), d.getMonth(), d.getDate());
  const dayNr = (target.getDay() + 6) % 7;
  target.setDate(target.getDate() - dayNr + 3);
  const firstThursday = new Date(target.getFullYear(), 0, 4);
  const firstDayNr = (firstThursday.getDay() + 6) % 7;
  firstThursday.setDate(firstThursday.getDate() - firstDayNr + 3);
  const week = 1 + Math.round((target.getTime() - firstThursday.getTime()) / (7 * 86_400_000));
  return { year: target.getFullYear(), week, key: `${target.getFullYear()}-W${week}` };
};

/** Monday of the ISO week containing `iso`. */
export const weekStart = (iso: string): string => {
  const d = fromISODate(iso);
  const dayNr = (d.getDay() + 6) % 7;
  d.setDate(d.getDate() - dayNr);
  return toISODate(d);
};

/** "WK 30 · 20–26 JUL 2026" */
export const weekRangeLabel = (iso: string): string => {
  const start = weekStart(iso);
  const end = addDays(start, 6);
  const s = fromISODate(start);
  const e = fromISODate(end);
  const { week } = isoWeek(iso);
  const sameMonth = s.getMonth() === e.getMonth();
  const left = sameMonth ? `${s.getDate()}` : `${s.getDate()} ${MONTHS[s.getMonth()]}`;
  return `WK ${week} · ${left}–${e.getDate()} ${MONTHS[e.getMonth()]} ${e.getFullYear()}`;
};

export const timeOfDay = (isoDateTime: string): string => {
  const d = new Date(isoDateTime);
  return `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
};

export const elapsedLabel = (fromISO: string, now = Date.now()): string => {
  const mins = Math.max(0, Math.round((now - new Date(fromISO).getTime()) / 60_000));
  const h = Math.floor(mins / 60);
  return h > 0 ? `${h}h ${mins % 60}m` : `${mins}m`;
};

export const weeksBetween = (a: string, b: string): number =>
  Math.round(daysBetween(a, b) / 7);

/* ── Dashboard range ────────────────────────────────────────────────────── */

export type RangeId = '8w' | '6m' | 'season';

export const RANGES: { id: RangeId; label: string; days: number }[] = [
  { id: '8w', label: '8 weeks', days: 56 },
  { id: '6m', label: '6 months', days: 183 },
  { id: 'season', label: 'Season', days: 365 },
];

export const rangeDays = (id: RangeId): number =>
  RANGES.find((r) => r.id === id)?.days ?? 56;

export const rangeLabel = (id: RangeId): string =>
  RANGES.find((r) => r.id === id)?.label ?? '8 weeks';

/** Current window [from, to] and the immediately preceding window of equal length. */
export const rangeWindows = (id: RangeId, today = todayISO()) => {
  const days = rangeDays(id);
  return {
    from: addDays(today, -days + 1),
    to: today,
    prevFrom: addDays(today, -days * 2 + 1),
    prevTo: addDays(today, -days),
  };
};

export const inRange = (iso: string, from: string, to: string): boolean =>
  iso >= from && iso <= to;
