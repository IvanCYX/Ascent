import type { Climb, Gym, Session, SessionReview, RehabExercise, RehabLog } from '../db/schema';
import {
  CAMP5_TAGS,
  GRADE_BANDS,
  READINESS_ROWS,
  type ClimbStyle,
} from './vocab';
import { addDays, daysBetween, todayISO } from './dates';

/* ── Primitives ─────────────────────────────────────────────────────────── */

export const isSend = (c: Climb): boolean => c.tickType !== 'attempt';
export const isFlash = (c: Climb): boolean => c.tickType === 'flash';

export const isNumericGymClimb = (c: Climb): boolean => c.gradeKind === 'number';
export const isTagClimb = (c: Climb): boolean => c.gradeKind === 'tag';
export const isBoardClimb = (c: Climb): boolean => c.gradeKind === 'v';

/** Numbered gyms share a 1–15 spine; each gym carries a soft/hard offset. */
export const adjustedGrade = (c: Climb, gyms: Gym[]): number => {
  const gym = gyms.find((g) => g.id === c.gymId);
  return c.grade + (gym?.offset ?? 0);
};

export const climbsInRange = (climbs: Climb[], from: string, to: string): Climb[] =>
  climbs.filter((c) => {
    const d = c.createdAt.slice(0, 10);
    return d >= from && d <= to;
  });

const mean = (xs: number[]): number =>
  xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : 0;

const round1 = (n: number): number => Math.round(n * 10) / 10;

/* ── KPIs ───────────────────────────────────────────────────────────────── */

export const FLASH_RATE_THRESHOLD = 8;
export const HARD_GRADE_THRESHOLD = 10;

export interface MaxGradeResult {
  grade: number | null;
  gymName: string;
  date: string;
}

/** Highest grade with ≥1 send in range, on the numbered-gym spine, offset adjusted. */
export function maxGradeSent(climbs: Climb[], gyms: Gym[]): MaxGradeResult {
  const pool = climbs.filter((c) => isNumericGymClimb(c) && isSend(c));
  if (!pool.length) return { grade: null, gymName: '', date: '' };
  let best = pool[0];
  let bestAdj = adjustedGrade(best, gyms);
  for (const c of pool) {
    const adj = adjustedGrade(c, gyms);
    if (adj > bestAdj || (adj === bestAdj && c.createdAt > best.createdAt)) {
      best = c;
      bestAdj = adj;
    }
  }
  return {
    grade: best.grade,
    gymName: gyms.find((g) => g.id === best.gymId)?.name ?? '',
    date: best.createdAt.slice(0, 10),
  };
}

/** Flashed sends ÷ total sends, restricted to grade 8+ on the numbered spine. */
export function flashRate(climbs: Climb[], threshold = FLASH_RATE_THRESHOLD): number | null {
  const sends = climbs.filter((c) => isNumericGymClimb(c) && isSend(c) && c.grade >= threshold);
  if (!sends.length) return null;
  return (sends.filter(isFlash).length / sends.length) * 100;
}

/** Mean attempts over sends at grade 10+. */
export function attemptsPerSend(climbs: Climb[], threshold = HARD_GRADE_THRESHOLD): number | null {
  const sends = climbs.filter((c) => isNumericGymClimb(c) && isSend(c) && c.grade >= threshold);
  if (!sends.length) return null;
  return mean(sends.map((c) => c.attempts));
}

/** Count of sends at grade ≥10 in range. */
export function volumeAtHard(climbs: Climb[], threshold = HARD_GRADE_THRESHOLD): number {
  return climbs.filter((c) => isNumericGymClimb(c) && isSend(c) && c.grade >= threshold).length;
}

export interface Kpi {
  label: string;
  value: string;
  caption: string;
  delta: string;
  deltaStrong: boolean;
}

export function buildKpis(
  cur: Climb[],
  prev: Climb[],
  gyms: Gym[],
  sessionCount: number,
  rangeLabelText: string,
): Kpi[] {
  const max = maxGradeSent(cur, gyms);
  const maxPrev = maxGradeSent(prev, gyms);
  const maxDelta =
    max.grade !== null && maxPrev.grade !== null
      ? max.grade - maxPrev.grade
      : null;

  const fr = flashRate(cur);
  const frPrev = flashRate(prev);
  const aps = attemptsPerSend(cur);
  const apsPrev = attemptsPerSend(prev);
  const vol = volumeAtHard(cur);

  return [
    {
      label: 'MAX GRADE SENT',
      value: max.grade === null ? '—' : String(max.grade),
      caption: max.grade === null ? 'no sends in range' : `${max.gymName} · ${fmtDay(max.date)}`,
      delta:
        maxDelta === null
          ? '— no prior window'
          : maxDelta > 0
            ? `▲ +${maxDelta} vs previous ${rangeLabelText}`
            : maxDelta < 0
              ? `▼ ${maxDelta} vs previous ${rangeLabelText}`
              : `— level vs previous ${rangeLabelText}`,
      deltaStrong: maxDelta !== null && maxDelta !== 0,
    },
    {
      label: 'FLASH RATE',
      value: fr === null ? '—' : `${Math.round(fr)}%`,
      caption: `grade ${FLASH_RATE_THRESHOLD}+`,
      delta:
        fr === null || frPrev === null
          ? '— no prior window'
          : Math.round(Math.abs(fr - frPrev)) === 0
            ? '— level vs previous'
            : `${fr >= frPrev ? '▲ +' : '▼ '}${Math.round(Math.abs(fr - frPrev))} pts`,
      deltaStrong: fr !== null && frPrev !== null && Math.round(fr) !== Math.round(frPrev),
    },
    {
      label: 'ATTEMPTS / SEND',
      value: aps === null ? '—' : round1(aps).toFixed(1),
      caption: `at ${HARD_GRADE_THRESHOLD}+`,
      delta:
        aps === null || apsPrev === null
          ? '— no prior window'
          : aps < apsPrev
            ? `▼ ${round1(apsPrev).toFixed(1)} → ${round1(aps).toFixed(1)} (better)`
            : aps > apsPrev
              ? `▲ ${round1(apsPrev).toFixed(1)} → ${round1(aps).toFixed(1)}`
              : `— flat at ${round1(aps).toFixed(1)}`,
      deltaStrong: aps !== null && apsPrev !== null && round1(aps) !== round1(apsPrev),
    },
    {
      label: `VOLUME AT ${HARD_GRADE_THRESHOLD}+`,
      value: String(vol),
      caption: `sends / ${rangeLabelText}`,
      delta: sessionCount
        ? `— ${round1(vol / sessionCount).toFixed(1)} per session`
        : '— no sessions yet',
      deltaStrong: false,
    },
  ];
}

const fmtDay = (iso: string): string => {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  const [y, m, d] = iso.split('-').map(Number);
  void y;
  return `${d} ${months[m - 1]}`;
};

/* ── Send pyramid (numbered gyms only) ──────────────────────────────────── */

export interface PyramidRow {
  grade: number;
  count: number;
  flashed: number;
  /** 0–1 of the widest row */
  width: number;
  /** 0–1 flashed share of this row */
  flashShare: number;
}

export function sendPyramid(climbs: Climb[], top = 13, bottom = 7): PyramidRow[] {
  const sends = climbs.filter((c) => isNumericGymClimb(c) && isSend(c));
  const rows: PyramidRow[] = [];
  for (let g = top; g >= bottom; g--) {
    const at = sends.filter((c) => c.grade === g);
    rows.push({
      grade: g,
      count: at.length,
      flashed: at.filter(isFlash).length,
      width: 0,
      flashShare: at.length ? at.filter(isFlash).length / at.length : 0,
    });
  }
  const max = Math.max(1, ...rows.map((r) => r.count));
  return rows.map((r) => ({ ...r, width: r.count / max }));
}

export function pyramidRead(rows: PyramidRow[]): string {
  const nonEmpty = rows.filter((r) => r.count > 0);
  if (nonEmpty.length < 2) return 'Not enough sends in this range to read a shape yet.';
  const widest = nonEmpty.reduce((a, b) => (b.count > a.count ? b : a));
  const top = nonEmpty[0];
  const consolidating = nonEmpty.find((r) => r.grade < top.grade && r.count >= 5);
  const parts: string[] = [];
  parts.push(`Base is widest at ${widest.grade}`);
  if (consolidating) {
    parts.push(
      consolidating.flashed > 0
        ? `the ${consolidating.grade}s are consolidating (${consolidating.count} sends, ${consolidating.flashed} flashed)`
        : `the ${consolidating.grade}s are going but none first go yet (${consolidating.count} sends)`,
    );
  }
  parts.push(
    top.count <= 2
      ? `only ${top.count} send${top.count === 1 ? '' : 's'} at ${top.grade} — that is the projecting edge`
      : `${top.grade} is established at ${top.count} sends`,
  );
  return `${parts.join(' and ')}.`;
}

/* ── Camp5 colour tally ─────────────────────────────────────────────────── */

export interface TagBar {
  tagId: string;
  ordinal: number;
  count: number;
  /** 0–1 of the tallest bar */
  height: number;
}

export function camp5Tally(climbs: Climb[], tags: string[] = [...CAMP5_TAGS]): TagBar[] {
  const sends = climbs.filter((c) => isTagClimb(c) && isSend(c));
  const bars = tags.map((tagId, i) => ({
    tagId,
    ordinal: i + 1,
    count: sends.filter((c) => c.tagId === tagId).length,
    height: 0,
  }));
  const max = Math.max(1, ...bars.map((b) => b.count));
  return bars.map((b) => ({ ...b, height: b.count / max }));
}

/* ── Style × grade heatmap ──────────────────────────────────────────────── */

/** Documented intensity ramp, keyed off send-rate %. */
export function intensityAlpha(pct: number): number {
  if (pct >= 90) return 1;
  if (pct >= 80) return 0.82;
  if (pct >= 76) return 0.78;
  if (pct >= 72) return 0.68;
  if (pct >= 69) return 0.62;
  if (pct >= 64) return 0.6;
  if (pct >= 58) return 0.55;
  if (pct >= 42) return 0.4;
  if (pct >= 36) return 0.32;
  if (pct >= 28) return 0.28;
  if (pct >= 20) return 0.2;
  return 0.15;
}

export interface HeatCell {
  band: string;
  /** null = no attempts logged in this band */
  pct: number | null;
  attempts: number;
}

export interface HeatRow {
  style: ClimbStyle;
  cells: HeatCell[];
  weak: boolean;
  comment: string;
}

export const HEATMAP_STYLES: ClimbStyle[] = [
  'Slopey',
  'Coordination',
  'Slab',
  'Compression',
  'Crimpy',
];

/** Style send rate = sends ÷ (sends + attempt-only) per style × grade band. */
export function styleSendRate(
  climbs: Climb[],
  style: ClimbStyle,
  min: number,
  max: number,
): { pct: number | null; attempts: number } {
  const pool = climbs.filter(
    (c) => isNumericGymClimb(c) && c.styles.includes(style) && c.grade >= min && c.grade <= max,
  );
  if (!pool.length) return { pct: null, attempts: 0 };
  const sends = pool.filter(isSend).length;
  return { pct: (sends / pool.length) * 100, attempts: pool.length };
}

export function styleGradeMatrix(climbs: Climb[]): HeatRow[] {
  const rows = HEATMAP_STYLES.map((style) => {
    const cells: HeatCell[] = GRADE_BANDS.map((b) => {
      const { pct, attempts } = styleSendRate(climbs, style, b.min, b.max);
      return { band: b.label, pct: pct === null ? null : Math.round(pct), attempts };
    });
    // a zero cell above the easy bands is a gap, not just a bad night
    const zeroIdx = cells.findIndex((c, i) => c.pct === 0 && i >= 2);
    return { style, cells, weak: zeroIdx >= 0, zeroIdx, comment: 'steady' };
  });

  // only the strongest surviving row gets to claim it carries the pyramid
  const ceiling = (r: (typeof rows)[number]) =>
    r.cells.reduce((best, c, i) => (c.pct && c.pct > 0 ? i * 100 + c.pct : best), -1);
  const strongest = rows
    .filter((r) => !r.weak)
    .sort((a, b) => ceiling(b) - ceiling(a))[0];

  return rows.map(({ style, cells, weak, zeroIdx }) => {
    let comment = 'steady';
    if (weak) {
      comment = `gap — nothing above ${GRADE_BANDS[Math.max(0, zeroIdx - 1)].max}`;
    } else if (strongest && strongest.style === style) {
      comment = 'strength — carries the pyramid';
    } else if ((cells[1].pct ?? 0) >= 75) {
      comment = 'comp-ready';
    }
    return { style, cells, weak, comment };
  });
}

export function heatmapRead(rows: HeatRow[], compName?: string): string {
  const strong = rows.filter((r) => !r.weak).map((r) => r.style.toLowerCase());
  const weak = rows.filter((r) => r.weak).map((r) => r.style.toLowerCase());
  if (!weak.length) {
    return 'No style is capping you inside this range — every row still has sends at its top band.';
  }
  const target = compName ? `the ${compName}` : 'your next comp';
  return `Your ceiling is style-specific, not physical — the hard grades go down on ${strong.slice(0, 2).join(' and ')}, nothing at the top band that is ${weak.join(' or ')}. Two ${weak[0]} blocks a week for four weeks would move that row before ${target}.`;
}

/* ── Board panel ────────────────────────────────────────────────────────── */

export interface BoardSummary {
  boardId: string;
  name: string;
  code: string;
  angle: number;
  sends: number;
  sessionsPerWeek: number;
  maxV: number | null;
  prevMaxV: number | null;
}

export function boardSummaries(
  climbs: Climb[],
  prevClimbs: Climb[],
  boards: { id: string; name: string; code: string }[],
  weeks: number,
): BoardSummary[] {
  const out: BoardSummary[] = [];
  for (const board of boards) {
    const mine = climbs.filter((c) => c.boardId === board.id && isSend(c));
    if (!mine.length) continue;
    // headline the angle with the most sends
    const byAngle = new Map<number, Climb[]>();
    for (const c of mine) {
      const a = c.angle ?? 0;
      byAngle.set(a, [...(byAngle.get(a) ?? []), c]);
    }
    const [angle, at] = [...byAngle.entries()].sort((a, b) => b[1].length - a[1].length)[0];
    const sessions = new Set(at.map((c) => c.sessionId)).size;
    const prevAt = prevClimbs.filter(
      (c) => c.boardId === board.id && isSend(c) && (c.angle ?? 0) === angle,
    );
    out.push({
      boardId: board.id,
      name: board.name,
      code: board.code,
      angle,
      sends: at.length,
      sessionsPerWeek: weeks ? Math.round((sessions / weeks) * 10) / 10 : 0,
      maxV: at.length ? Math.max(...at.map((c) => c.grade)) : null,
      prevMaxV: prevAt.length ? Math.max(...prevAt.map((c) => c.grade)) : null,
    });
  }
  return out;
}

export interface VBar {
  v: number;
  count: number;
  height: number;
  isMax: boolean;
}

export function boardHistogram(climbs: Climb[], boardId: string, angle: number): VBar[] {
  const sends = climbs.filter(
    (c) => c.boardId === boardId && (c.angle ?? 0) === angle && isSend(c),
  );
  const counts = new Map<number, number>();
  for (const c of sends) counts.set(c.grade, (counts.get(c.grade) ?? 0) + 1);
  const maxV = sends.length ? Math.max(...sends.map((c) => c.grade)) : 0;
  const lo = 1;
  const hi = Math.max(maxV + 2, 7);
  const maxCount = Math.max(1, ...counts.values());
  const bars: VBar[] = [];
  for (let v = lo; v <= Math.min(hi, 10); v++) {
    const count = counts.get(v) ?? 0;
    bars.push({ v, count, height: count / maxCount, isMax: v === maxV && count > 0 });
  }
  // trim leading empties so the chart starts where the data does
  const first = bars.findIndex((b) => b.count > 0);
  return first > 0 ? bars.slice(Math.max(0, first - 1)) : bars;
}

/* ── Comp readiness ─────────────────────────────────────────────────────── */

export interface ReadinessRow {
  label: string;
  score: number;
  warn: boolean;
}

/** Chips that push a readiness row up (+) or down (−). */
const CHIP_SIGNAL: Record<string, number> = {
  'Felt strong': 0.15,
  'Good tension': 0.12,
  'Locked in': 0.1,
  'Confident first go': 0.12,
  'Coordination dialled': 0.15,
  'Good beta reading': 0.1,
  'Felt weak': -0.15,
  'Fatigued early': -0.15,
  'Poor recovery': -0.12,
  Distracted: -0.08,
  Hesitant: -0.1,
  'Scared of the fall': -0.12,
  'Missed the timing': -0.12,
  'Sloppy feet': -0.1,
  'Read beta wrong': -0.1,
};

const READINESS_STYLE: Record<string, ClimbStyle> = {
  Coordination: 'Coordination',
  Power: 'Power',
  Slab: 'Slab',
  'Power endurance': 'Power',
  Compression: 'Compression',
  Crimps: 'Crimpy',
};

const READINESS_CHIPS: Record<string, string[]> = {
  Coordination: ['Coordination dialled', 'Missed the timing', 'Good beta reading', 'Read beta wrong'],
  Power: ['Felt strong', 'Felt weak', 'Confident first go'],
  Slab: ['Sloppy feet', 'Scared of the fall', 'Good beta reading'],
  'Power endurance': ['Fatigued early', 'Poor recovery', 'Good tension'],
  Compression: ['Good tension', 'Felt weak'],
  Crimps: ['Felt strong', 'Felt weak', 'Fatigued early'],
};

/**
 * 0–100 per style — normalised blend of send rate at the top two occupied grade
 * bands, recency of exposure, and review-chip signal. Below 55 is flagged warn.
 */
export function compReadiness(
  climbs: Climb[],
  reviews: SessionReview[],
  today = todayISO(),
): ReadinessRow[] {
  const rows = READINESS_ROWS.map((label) => {
    const style = READINESS_STYLE[label];

    // send rate across the two highest bands that actually have attempts
    const bandStats = GRADE_BANDS.map((b) => styleSendRate(climbs, style, b.min, b.max)).filter(
      (s) => s.pct !== null,
    );
    const topTwo = bandStats.slice(-2);
    const rate = topTwo.length
      ? topTwo.reduce((a, s) => a + (s.pct ?? 0), 0) / topTwo.length / 100
      : 0;
    // a 75% send rate at your top two bands is already comp-ready, so that is the ceiling
    const rateNorm = Math.min(1, rate / 0.75);

    // recency — climbs touching this style in the last 21 days, 6 = saturated
    const since = addDays(today, -21);
    const recent = climbs.filter(
      (c) => c.styles.includes(style) && c.createdAt.slice(0, 10) >= since,
    ).length;
    const recency = Math.min(1, recent / 6);

    // review-chip signal, centred on 0.5
    const relevant = READINESS_CHIPS[label] ?? [];
    let signal = 0.5;
    const recentReviews = reviews.slice(-8);
    for (const r of recentReviews) {
      for (const chip of r.chips) {
        if (relevant.includes(chip)) signal += (CHIP_SIGNAL[chip] ?? 0) / 2;
      }
    }
    signal = Math.max(0, Math.min(1, signal));

    const score = Math.round(100 * (0.5 * rateNorm + 0.25 * recency + 0.25 * signal));
    return { label: label as string, score, warn: false };
  });

  return rows
    .map((r) => ({ ...r, warn: r.score < 55 }))
    .sort((a, b) => b.score - a.score);
}

/* ── Chip trends (`1g`) ─────────────────────────────────────────────────── */

export interface ChipTrendRow {
  chip: string;
  cells: boolean[];
  count: number;
}

export function chipTrends(
  reviews: SessionReview[],
  sessions: Session[],
  window = 12,
): ChipTrendRow[] {
  const ordered = [...reviews].sort((a, b) => {
    const da = sessions.find((s) => s.id === a.sessionId)?.date ?? '';
    const dbb = sessions.find((s) => s.id === b.sessionId)?.date ?? '';
    return da.localeCompare(dbb);
  });
  const last = ordered.slice(-window);
  const counts = new Map<string, number>();
  for (const r of last) for (const c of r.chips) counts.set(c, (counts.get(c) ?? 0) + 1);
  return [...counts.entries()]
    .sort((a, b) => b[1] - a[1])
    .slice(0, 6)
    .map(([chip]) => {
      const cells: boolean[] = [];
      for (let i = 0; i < window; i++) {
        const r = last[i - (window - last.length)];
        cells.push(!!r && r.chips.includes(chip));
      }
      return { chip, cells, count: cells.filter(Boolean).length };
    });
}

/** Chips worth acting on — the ones that name something going wrong. */
const WATCH_CHIPS = new Set([
  'Felt weak',
  'Fatigued early',
  'Poor recovery',
  'Distracted',
  'Hesitant',
  'Scared of the fall',
  'Missed the timing',
  'Sloppy feet',
  'Read beta wrong',
]);

export function chipPattern(rows: ChipTrendRow[], window = 12): string | null {
  const threshold = Math.ceil(window / 3);
  const watch = rows.find((r) => WATCH_CHIPS.has(r.chip) && r.count >= threshold);
  if (watch) {
    return `“${watch.chip}” shows up in ${watch.count} of the last ${window} sessions. That is a habit, not a bad night — worth a dedicated block in the warm-up.`;
  }
  const top = rows.find((r) => r.count >= Math.ceil(window / 2));
  if (!top) return null;
  return `“${top.chip}” shows up in ${top.count} of the last ${window} sessions and nothing negative recurs as often. Whatever you changed, keep doing it.`;
}

/* ── Rehab adherence ────────────────────────────────────────────────────── */

export interface AdherenceResult {
  days: { date: string; done: boolean }[];
  streak: number;
  doneDays: number;
  total: number;
  missedLabel: string | null;
}

/** Completed exercise-days ÷ prescribed days over the last `window` days. */
export function rehabAdherence(
  exercises: RehabExercise[],
  logs: RehabLog[],
  window = 12,
  today = todayISO(),
): AdherenceResult {
  const ids = new Set(exercises.map((e) => e.id));
  const days: { date: string; done: boolean }[] = [];
  for (let i = window - 1; i >= 0; i--) {
    const date = addDays(today, -i);
    const done = logs.some((l) => ids.has(l.exerciseId) && l.date === date && l.done);
    days.push({ date, done });
  }
  let streak = 0;
  for (let i = days.length - 1; i >= 0; i--) {
    if (days[i].done) streak++;
    else break;
  }
  const doneDays = days.filter((d) => d.done).length;
  const missed = days.filter((d) => !d.done).pop();
  return {
    days,
    streak,
    doneDays,
    total: window,
    missedLabel: missed ? missed.date : null,
  };
}

/* ── Load rules ─────────────────────────────────────────────────────────── */

export interface LoadRuleUsage {
  ruleId: string;
  headline: string;
  used: number;
  cap: number | null;
  condition: string;
  /** at or over the cap */
  blocked: boolean;
  /** one under the cap */
  nearing: boolean;
}

/**
 * Usage is counted per ISO week over *sessions* that included at least one climb
 * of the ruled style — a single crimpy session is one use, not one per climb.
 */
export function loadRuleUsage(
  rules: { id: string; styleOrType: string; maxPerWeek: number | null; condition: string; headline: string }[],
  climbs: Climb[],
  weekStartISO: string,
): LoadRuleUsage[] {
  const weekEnd = addDays(weekStartISO, 6);
  return rules.map((rule) => {
    const inWeek = climbs.filter((c) => {
      const d = c.createdAt.slice(0, 10);
      return d >= weekStartISO && d <= weekEnd && c.styles.includes(rule.styleOrType as ClimbStyle);
    });
    const used = new Set(inWeek.map((c) => c.sessionId)).size;
    return {
      ruleId: rule.id,
      headline: rule.headline,
      used,
      cap: rule.maxPerWeek,
      condition: rule.condition,
      blocked: rule.maxPerWeek === null ? true : used >= rule.maxPerWeek,
      nearing: rule.maxPerWeek !== null && used === rule.maxPerWeek - 1,
    };
  });
}

/* ── Session helpers ────────────────────────────────────────────────────── */

export const sessionSends = (climbs: Climb[], sessionId: string): Climb[] =>
  climbs.filter((c) => c.sessionId === sessionId && isSend(c));

export function topGrades(climbs: Climb[]): { kind: 'number' | 'v' | 'tag'; values: (number | string)[] } {
  const sends = climbs.filter(isSend);
  if (!sends.length) return { kind: 'number', values: [] };
  const tags = sends.filter(isTagClimb);
  if (tags.length >= sends.length / 2) {
    const seen = [...new Set(tags.map((c) => c.tagId!))];
    const ordered = seen.sort(
      (a, b) => CAMP5_TAGS.indexOf(b as never) - CAMP5_TAGS.indexOf(a as never),
    );
    return { kind: 'tag', values: ordered.slice(0, 2) };
  }
  const boards = sends.filter(isBoardClimb);
  if (boards.length >= sends.length / 2) {
    const vs = [...new Set(boards.map((c) => c.grade))].sort((a, b) => b - a).slice(0, 2);
    return { kind: 'v', values: vs.map((v) => `V${v}`) };
  }
  const gs = [...new Set(sends.filter(isNumericGymClimb).map((c) => c.grade))]
    .sort((a, b) => b - a)
    .slice(0, 3);
  return { kind: 'number', values: gs };
}

export const weeksOut = (today: string, compDate: string): number =>
  Math.max(0, Math.ceil(daysBetween(today, compDate) / 7));
