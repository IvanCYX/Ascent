import { db, uid, type Climb, type Session, type SessionReview } from './schema';
import {
  addDays,
  todayISO,
  toISODate,
  fromISODate,
  weekStart,
} from '../domain/dates';
import {
  CAMP5_TAGS,
  CLIMB_STYLES,
  REVIEW_CHIPS,
  type ClimbStyle,
  type SessionIntent,
  type TickType,
} from '../domain/vocab';

/* Deterministic PRNG so the demo log is the same every time it is rebuilt. */
function mulberry32(a: number) {
  return () => {
    a |= 0;
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const rnd = mulberry32(20260728);
const pick = <T>(xs: readonly T[]): T => xs[Math.floor(rnd() * xs.length)];
const chance = (p: number) => rnd() < p;
const intBetween = (lo: number, hi: number) => lo + Math.floor(rnd() * (hi - lo + 1));

const weighted = <T>(entries: [T, number][]): T => {
  const total = entries.reduce((a, [, w]) => a + w, 0);
  let r = rnd() * total;
  for (const [v, w] of entries) {
    r -= w;
    if (r <= 0) return v;
  }
  return entries[entries.length - 1][0];
};

/* ── Fixed reference data ───────────────────────────────────────────────── */

export const GYMS = [
  {
    id: 'batuu',
    name: 'Batuu',
    shortName: 'Batuu',
    scaleType: 'numeric' as const,
    maxGrade: 15,
    offset: 0,
    note: 'Reference scale for the numbered spine.',
    sortOrder: 1,
  },
  {
    id: 'camp5',
    name: 'Camp5 Eco City',
    shortName: 'Camp5',
    scaleType: 'ranked-colour' as const,
    tags: [...CAMP5_TAGS],
    offset: 0,
    note: 'Ranked colour tags only — never numbered.',
    sortOrder: 2,
  },
  {
    id: 'bump-pbj',
    name: 'Bump PBJ',
    shortName: 'Bump PBJ',
    scaleType: 'numeric' as const,
    maxGrade: 12,
    offset: 0,
    note: 'Shares one 1–12 scale with J1 and SSQ.',
    sortOrder: 3,
  },
  {
    id: 'bump-j1',
    name: 'Bump J1',
    shortName: 'Bump J1',
    scaleType: 'numeric' as const,
    maxGrade: 12,
    offset: 0,
    sortOrder: 4,
  },
  {
    id: 'bump-ssq',
    name: 'Bump SSQ',
    shortName: 'Bump SSQ',
    scaleType: 'numeric' as const,
    maxGrade: 12,
    offset: 0,
    sortOrder: 5,
  },
  {
    id: 'bhub',
    name: 'BHUB',
    shortName: 'BHUB',
    scaleType: 'numeric' as const,
    maxGrade: 10,
    offset: -0.5,
    note: 'Soft relative to Batuu.',
    sortOrder: 6,
  },
];

export const BOARDS = [
  { id: 'kilter', name: 'KilterBoard', code: 'KB', angles: [25, 30, 40, 45], sortOrder: 1 },
  { id: 'tb2', name: 'TensionBoard 2', code: 'TB', angles: [25, 40], sortOrder: 2 },
];

/** Send-rate targets per style across the five grade bands — shapes the heatmap. */
const SEND_RATE: Record<string, number[]> = {
  Slopey: [0.92, 0.78, 0.61, 0.24, 0],
  Coordination: [0.95, 0.83, 0.66, 0.31, 0],
  Slab: [0.84, 0.7, 0.45, 0.17, 0],
  Compression: [0.74, 0.39, 0.18, 0, 0],
  Crimpy: [0.68, 0.34, 0.15, 0, 0],
  Power: [0.88, 0.72, 0.52, 0.2, 0],
};

const bandIndex = (grade: number) => Math.min(4, Math.max(0, Math.floor((grade - 6) / 2)));

const FLASH_BY_GRADE: Record<number, number> = {
  6: 0.82,
  7: 0.73,
  8: 0.5,
  9: 0.42,
  10: 0.3,
  11: 0.2,
  12: 0.18,
  13: 0,
  14: 0,
  15: 0,
};

/**
 * Weights are over *attempted* climbs, not sends — the high grades carry a lot
 * of failed attempts, which is what puts a taper on the send pyramid.
 */
const GYM_GRADE_WEIGHTS: [number, number][] = [
  [6, 10],
  [7, 26],
  [8, 48],
  [9, 38],
  [10, 40],
  [11, 22],
  [12, 16],
  [13, 6],
];

/** Batuu is the home gym; BHUB is the soft one you drop into. */
const GYM_WEIGHTS: [string, number][] = [
  ['batuu', 34],
  ['bump-pbj', 20],
  ['bump-j1', 15],
  ['bump-ssq', 11],
  ['bhub', 20],
];

const TAG_WEIGHTS: [string, number][] = [
  ['yellow', 7],
  ['pink', 10],
  ['blue', 14],
  ['orange', 17],
  ['green', 14],
  ['purple', 10],
  ['red', 5],
];

const HOLD_POOL = ['yellow', 'pink', 'blue', 'orange', 'green', 'purple', 'red', 'black', 'white'];

const LOCATIONS = [
  'cave, right of the arête',
  'main wall roof',
  'slab corner',
  'comp wall',
  'the prow',
  'left of the volume',
  'training bay',
];

const BOARD_CLIMB_NAMES = [
  'shrimp cocktail',
  'tiny dancer',
  'gravity check',
  'sloper heaven',
  'the pinch',
  'moon boots',
  'crimp city',
  'hangdog',
];

const INTENTS: SessionIntent[] = [
  'Max strength',
  'Power endurance',
  'Coordination',
  'Comp sim',
  'Slab / technique',
  'Chill maintenance',
];

/* ── Generators ─────────────────────────────────────────────────────────── */

const stylesForIntent = (intent: SessionIntent): ClimbStyle[] => {
  switch (intent) {
    case 'Coordination':
      return ['Coordination', 'Coordination', 'Slopey', 'Power'];
    case 'Slab / technique':
      return ['Slab', 'Slab', 'Slopey', 'Crimpy'];
    case 'Max strength':
      return ['Crimpy', 'Compression', 'Power', 'Slopey'];
    case 'Power endurance':
      return ['Power', 'Slopey', 'Coordination', 'Compression'];
    case 'Comp sim':
      return [...CLIMB_STYLES];
    default:
      return ['Slopey', 'Slab', 'Coordination'];
  }
};

const tickFor = (grade: number, sent: boolean): { tickType: TickType; attempts: number } => {
  if (!sent) return { tickType: 'attempt', attempts: intBetween(2, 6) };
  if (chance(FLASH_BY_GRADE[grade] ?? 0.3)) return { tickType: 'flash', attempts: 1 };
  // hard sends take more goes, which is what attempts-per-send is measuring
  if (chance(grade >= 10 ? 0.45 : 0.6)) return { tickType: 'second-go', attempts: 2 };
  return { tickType: 'project', attempts: intBetween(3, 8) };
};

const at = (date: string, hour: number, minute: number): string => {
  const d = fromISODate(date);
  d.setHours(hour, minute, 0, 0);
  return d.toISOString();
};

function buildGymClimbs(sessionId: string, gymId: string, date: string, intent: SessionIntent) {
  const climbs: Climb[] = [];
  const pool = stylesForIntent(intent);
  const cap = gymId === 'bhub' ? 10 : gymId === 'batuu' ? 13 : 12;
  const n = intBetween(8, 14);
  for (let i = 0; i < n; i++) {
    // resample rather than clamp, so a low-ceiling gym does not pile up on its top grade
    let grade = weighted(GYM_GRADE_WEIGHTS);
    for (let tries = 0; grade > cap && tries < 6; tries++) grade = weighted(GYM_GRADE_WEIGHTS);
    if (grade > cap) grade = cap;
    const primary = pick(pool);
    const styles: ClimbStyle[] = [primary];
    if (chance(0.3)) {
      const second = pick(CLIMB_STYLES);
      if (second !== primary) styles.push(second);
    }
    const rate = SEND_RATE[primary]?.[bandIndex(grade)] ?? 0.6;
    const sent = chance(rate);
    const { tickType, attempts } = tickFor(grade, sent);
    climbs.push({
      id: uid(),
      sessionId,
      gymId,
      gradeKind: 'number',
      grade,
      holdColour: pick(HOLD_POOL),
      styles,
      location: chance(0.55) ? pick(LOCATIONS) : undefined,
      tickType,
      attempts,
      createdAt: at(date, 18 + Math.floor(i / 5), (i * 11) % 60),
    });
  }
  return climbs;
}

/**
 * Independent sampling leaves a single tag missing from a whole range often
 * enough to look like a bug, so each session draws from a proportional urn —
 * the tally then holds its intended hump across the range.
 */
const tagUrn = (() => {
  const urn: string[] = [];
  for (const [tag, w] of TAG_WEIGHTS) for (let i = 0; i < w; i++) urn.push(tag);
  return urn;
})();

function buildCamp5Climbs(sessionId: string, date: string) {
  const climbs: Climb[] = [];
  const n = intBetween(10, 15);
  const offset = Math.floor(rnd() * tagUrn.length);
  const step = 7; // coprime with the urn size, so a session walks the whole spread
  for (let i = 0; i < n; i++) {
    const tagId = tagUrn[(offset + i * step) % tagUrn.length];
    const ordinal = CAMP5_TAGS.indexOf(tagId as never) + 1;
    const sent = chance(ordinal >= 7 ? 0.45 : ordinal >= 5 ? 0.72 : 0.9);
    const { tickType, attempts } = tickFor(Math.min(13, 5 + ordinal), sent);
    climbs.push({
      id: uid(),
      sessionId,
      gymId: 'camp5',
      gradeKind: 'tag',
      grade: ordinal,
      tagId,
      holdColour: tagId,
      styles: [pick(CLIMB_STYLES)],
      tickType,
      attempts,
      createdAt: at(date, 19 + Math.floor(i / 6), (i * 9) % 60),
    });
  }
  return climbs;
}

function buildBoardClimbs(sessionId: string, date: string, boardId: string, angle: number) {
  const climbs: Climb[] = [];
  const maxV = boardId === 'kilter' ? 6 : 5;
  const n = intBetween(1, 3);
  for (let i = 0; i < n; i++) {
    const v = weighted([
      [Math.max(1, maxV - 3), 3],
      [Math.max(1, maxV - 2), 7],
      [maxV - 1, 8],
      [maxV, 5],
      [maxV + 1, 3],
    ] as [number, number][]);
    const sent = chance(v > maxV ? 0 : v === maxV ? 0.4 : 0.78);
    const { tickType, attempts } = tickFor(Math.min(13, 6 + v), sent);
    climbs.push({
      id: uid(),
      sessionId,
      boardId,
      angle,
      gradeKind: 'v',
      grade: v,
      name: pick(BOARD_CLIMB_NAMES),
      styles: chance(0.5) ? ['Crimpy', 'Tension'] : [pick(['Compression', 'Power', 'Tension'] as const)],
      tickType,
      attempts,
      createdAt: at(date, 20, 10 + i * 13),
    });
  }
  return climbs;
}

function buildReview(sessionId: string, intent: SessionIntent, sends: number): SessionReview {
  const chips: string[] = [];
  const good = sends >= 8;
  chips.push(good ? 'Felt strong' : pick(['Felt weak', 'Fatigued early']));
  if (chance(0.5)) chips.push('Good tension');
  chips.push(pick(REVIEW_CHIPS.HEAD));
  if (intent === 'Comp sim') chips.push('Sloppy feet');
  else if (chance(0.45)) chips.push(pick(REVIEW_CHIPS.EXECUTION));
  if (intent === 'Coordination' && chance(0.7)) chips.push('Coordination dialled');
  const score = Math.max(3, Math.min(9.6, Math.round((4.5 + sends * 0.32 + rnd() * 1.4) * 10) / 10));
  return {
    sessionId,
    chips: [...new Set(chips)],
    overallScore: score,
    note: chance(0.35)
      ? pick([
          'First 12 went second go after resting 8 min. Long rests are working.',
          'Skin was gone by the third block. Cut it short.',
          'Felt light on the feet all night — keep the warm-up length.',
          'Shoulder grumbled on the big span. Watch it.',
        ])
      : undefined,
    createdAt: at(sessionId.length ? todayISO() : todayISO(), 21, 30),
  };
}

/**
 * The random walk gets the shape right but leaves the very top of the pyramid
 * to luck, and an empty 12/13 row reads as a broken chart rather than a hard
 * grade. This tops the tail up to the counts the demo is meant to show.
 */
function topUpMilestones(sessions: Session[], climbs: Climb[], today: string) {
  const since = addDays(today, -55);
  const recent = sessions.filter((s) => s.date >= since);
  const inWindow = (c: Climb) => c.createdAt.slice(0, 10) >= since;
  const isSent = (c: Climb) => c.tickType !== 'attempt';

  const add = (
    session: Session | undefined,
    body: Omit<Climb, 'id' | 'sessionId' | 'createdAt'>,
    minute: number,
  ) => {
    if (!session) return;
    climbs.push({
      ...body,
      id: uid(),
      sessionId: session.id,
      createdAt: at(session.date, 20, minute % 60),
    });
  };

  const lastAt = (gymIds: string[]) =>
    [...recent].reverse().find((s) => s.gymId && gymIds.includes(s.gymId));

  /* one 13 at Batuu — the projecting edge */
  const at13 = climbs.filter((c) => inWindow(c) && c.gradeKind === 'number' && c.grade === 13 && isSent(c));
  if (at13.length === 0) {
    add(
      lastAt(['batuu']),
      {
        gymId: 'batuu',
        gradeKind: 'number',
        grade: 13,
        holdColour: 'black',
        styles: ['Slopey', 'Power'],
        location: 'the prow',
        tickType: 'project',
        attempts: 9,
      },
      41,
    );
  }

  /*
   * The 12–13 band is where the style story lives: the hard grades go down on
   * slopers and coordination, and nothing crimpy or compressive goes at all.
   * Small samples up there leave that to chance, so pin it.
   */
  const hosts = recent.filter((s) => s.gymId && s.gymId !== 'camp5' && s.gymId !== 'bhub');
  const band3 = (c: Climb) =>
    inWindow(c) && c.gradeKind === 'number' && c.grade >= 12 && c.grade <= 13;

  const addAt12 = (style: ClimbStyle, tickType: TickType, attempts: number, minute: number) =>
    add(
      hosts[minute % Math.max(1, hosts.length)],
      {
        gymId: hosts[minute % Math.max(1, hosts.length)]?.gymId,
        gradeKind: 'number',
        grade: 12,
        holdColour: pick(HOLD_POOL),
        styles: [style],
        tickType,
        attempts,
      },
      minute,
    );

  // strong styles keep a foothold at 12, at roughly the send rate the row claims
  ([
    ['Slopey', 2, 0.24],
    ['Coordination', 2, 0.31],
    ['Slab', 1, 0.17],
  ] as [ClimbStyle, number, number][]).forEach(([style, target, rate], si) => {
    const sentAt12 = climbs.filter(
      (c) => band3(c) && isSent(c) && c.grade === 12 && c.styles.includes(style),
    ).length;
    for (let i = sentAt12; i < target; i++) {
      addAt12(style, i === 0 ? 'second-go' : 'project', i === 0 ? 2 : intBetween(3, 7), 44 + si * 3 + i);
    }
    const wantTotal = Math.round(target / rate);
    const total = climbs.filter((c) => band3(c) && c.styles.includes(style)).length;
    for (let i = total; i < wantTotal; i++) {
      addAt12(style, 'attempt', intBetween(2, 6), 70 + si * 6 + i);
    }
  });

  // the two gap styles: attempts up there, never a send
  (['Compression', 'Crimpy'] as ClimbStyle[]).forEach((style, si) => {
    for (const c of climbs) {
      if (band3(c) && isSent(c) && c.styles.includes(style)) {
        c.tickType = 'attempt';
        c.attempts = intBetween(3, 7);
      }
    }
    const tried = climbs.filter((c) => band3(c) && c.styles.includes(style)).length;
    for (let i = tried; i < 5; i++) addAt12(style, 'attempt', intBetween(3, 7), 56 + si * 4 + i);
  });

  /* five reds at Camp5 — first of the season */
  const reds = climbs.filter((c) => inWindow(c) && c.tagId === 'red' && isSent(c));
  const camp5Sessions = recent.filter((s) => s.gymId === 'camp5');
  for (let i = reds.length; i < 5 && camp5Sessions.length; i++) {
    add(
      camp5Sessions[i % camp5Sessions.length],
      {
        gymId: 'camp5',
        gradeKind: 'tag',
        grade: 7,
        tagId: 'red',
        holdColour: 'red',
        styles: [pick(CLIMB_STYLES)],
        tickType: 'project',
        attempts: intBetween(3, 7),
      },
      30 + i,
    );
  }

  /* each board's ceiling gets touched at least once */
  for (const [boardId, angle, maxV] of [
    ['kilter', 40, 6],
    ['tb2', 25, 5],
  ] as const) {
    const hit = climbs.some(
      (c) => inWindow(c) && c.boardId === boardId && c.angle === angle && c.grade === maxV && isSent(c),
    );
    if (hit) continue;
    const host = [...recent].reverse().find((s) => climbs.some((c) => c.sessionId === s.id && c.boardId === boardId));
    add(
      host ?? recent[recent.length - 1],
      {
        boardId,
        angle,
        gradeKind: 'v',
        grade: maxV,
        styles: ['Crimpy', 'Tension'],
        name: pick(BOARD_CLIMB_NAMES),
        tickType: 'project',
        attempts: intBetween(5, 9),
      },
      52,
    );
  }
}

/* ── Seed ───────────────────────────────────────────────────────────────── */

export async function seedIfEmpty(): Promise<void> {
  const already = await db.gyms.count();
  if (already > 0) return;
  await seed();
}

export async function seed(): Promise<void> {
  const today = todayISO();

  await db.gyms.bulkPut(GYMS);
  await db.boards.bulkPut(BOARDS);

  /* Competition + training block */
  const comp = { id: uid(), name: 'KL Open · Bouldering', date: addDays(today, 42) };
  await db.competitions.put(comp);

  /* ── Injuries ─────────────────────────────────────────────────────────── */
  const a2 = {
    id: 'inj-a2',
    bodyPart: 'l-hand',
    name: 'Left ring finger · A2 pulley strain',
    onsetDate: addDays(today, -197),
    status: 'active' as const,
    severity: 'grade I',
    diagnosis: 'self-diagnosed, confirmed by physio 19 Jan',
    rehabStart: addDays(today, -20),
    physioNext: addDays(today, 7),
    physioNote:
      'Cleared for 40° board at V6 as long as it is not a full-crimp move. Reassess edge size in two weeks.',
  };
  const shoulder = {
    id: 'inj-shoulder',
    bodyPart: 'r-shoulder',
    name: 'Right shoulder · impingement niggle',
    onsetDate: addDays(today, -60),
    status: 'watching' as const,
    severity: 'niggle',
  };
  const elbow = {
    id: 'inj-elbow',
    bodyPart: 'l-elbow',
    name: 'Left elbow · medial tendinopathy',
    onsetDate: addDays(today, -95),
    status: 'watching' as const,
    severity: 'low grade',
  };
  await db.injuries.bulkPut([a2, shoulder, elbow]);

  await db.rehabExercises.bulkPut([
    {
      id: 'rx-1',
      injuryId: a2.id,
      name: 'No-hang half crimp',
      prescription: '10S × 5 · 60% BW · DAILY',
      frequency: 7,
    },
    {
      id: 'rx-2',
      injuryId: a2.id,
      name: 'Finger extensor band',
      prescription: '3 × 15 · DAILY',
      frequency: 7,
    },
    {
      id: 'rx-3',
      injuryId: a2.id,
      name: 'Tendon glides',
      prescription: '2 × 10 · MORNING & NIGHT',
      frequency: 7,
    },
    {
      id: 'rx-4',
      injuryId: a2.id,
      name: 'Progressive edge loading',
      prescription: '20MM · 7S × 4 · 3×/WEEK',
      frequency: 3,
    },
  ]);

  /* 11 of the last 12 days done — one missed */
  const missedDay = addDays(today, -8);
  const rehabLogs = [];
  for (let i = 11; i >= 0; i--) {
    const date = addDays(today, -i);
    if (date === missedDay) continue;
    rehabLogs.push({ id: uid(), exerciseId: 'rx-1', date, done: true });
    if (i > 0 || chance(0.5)) rehabLogs.push({ id: uid(), exerciseId: 'rx-2', date, done: true });
    if (i % 3 === 0) rehabLogs.push({ id: uid(), exerciseId: 'rx-4', date, done: true });
  }
  await db.rehabLogs.bulkPut(rehabLogs);

  await db.loadRules.bulkPut([
    {
      id: 'lr-1',
      injuryId: a2.id,
      styleOrType: 'Crimpy',
      maxPerWeek: 2,
      condition: 'while A2 pain is above 1/10',
      headline: 'Crimpy sessions · max 2 per week',
    },
    {
      id: 'lr-2',
      injuryId: a2.id,
      styleOrType: 'Campus',
      maxPerWeek: null,
      condition: 'until pain ≤ 1/10 for 14 straight days',
      headline: 'No campus / no full crimp',
    },
  ]);

  /* ── Sessions across 26 weeks ─────────────────────────────────────────── */
  const sessions: Session[] = [];
  const climbs: Climb[] = [];
  const reviews: SessionReview[] = [];

  const startDay = addDays(today, -182);
  let cursor = startDay;
  let camp5Countdown = 0;
  let boardCountdown = 0;
  let boardBlock = 0;

  while (cursor < today) {
    const dow = fromISODate(cursor).getDay();
    // train Mon / Wed / Thu / Sat, roughly
    const trains = [1, 3, 4, 6].includes(dow) && chance(0.86);
    if (!trains) {
      cursor = addDays(cursor, 1);
      continue;
    }

    const isCamp5 = camp5Countdown <= 0 && chance(0.4);
    const gymId = isCamp5 ? 'camp5' : weighted(GYM_WEIGHTS);
    if (isCamp5) camp5Countdown = 2;
    else camp5Countdown--;

    const intent = weighted(
      INTENTS.map((i) => [i, i === 'Comp sim' ? 1.4 : 1] as [SessionIntent, number]),
    );

    const id = uid();
    const sessionClimbs = isCamp5
      ? buildCamp5Climbs(id, cursor)
      : buildGymClimbs(id, gymId, cursor, intent);

    const withBoard = !isCamp5 && boardCountdown <= 0 && chance(0.8);
    if (withBoard) {
      boardCountdown = 1;
      // Kilter is the main board — two blocks on it for every one on the TB2
      boardBlock++;
      const boardId = boardBlock % 3 === 0 ? 'tb2' : 'kilter';
      const angle = boardId === 'kilter' ? 40 : 25;
      sessionClimbs.push(...buildBoardClimbs(id, cursor, boardId, angle));
    } else boardCountdown--;

    sessions.push({
      id,
      date: cursor,
      gymId,
      intent,
      durationMin: intBetween(75, 145),
      status: 'done',
      startedAt: at(cursor, 18, 30),
      endedAt: at(cursor, 21, 0),
    });
    climbs.push(...sessionClimbs);
    const sends = sessionClimbs.filter((c) => c.tickType !== 'attempt').length;
    reviews.push({ ...buildReview(id, intent, sends), createdAt: at(cursor, 21, 15) });

    cursor = addDays(cursor, 1);
  }

  topUpMilestones(sessions, climbs, today);

  /* ── Pain entries: last 12 sessions, 7/10 → 2/10 ──────────────────────── */
  const painSessions = sessions.slice(-12);
  const painCurve = [7, 8, 6, 6, 5, 5, 4, 4, 3, 3, 2, 2];
  await db.painEntries.bulkPut(
    painSessions.map((s, i) => ({
      id: uid(),
      injuryId: a2.id,
      sessionId: s.id,
      date: s.date,
      level: painCurve[i] ?? 2,
    })),
  );

  /* ── Tonight: a live session at Batuu, 7 sends ────────────────────────── */
  const liveId = uid();
  const started = new Date();
  started.setMinutes(started.getMinutes() - 72);
  const live: Session = {
    id: liveId,
    date: today,
    gymId: 'batuu',
    intent: 'Comp sim',
    status: 'active',
    startedAt: started.toISOString(),
  };
  const tonight: [number, string, ClimbStyle[], TickType, number, string | undefined][] = [
    [9, 'green', ['Slopey'], 'flash', 1, undefined],
    [8, 'blue', ['Slab'], 'flash', 1, 'slab corner'],
    [10, 'purple', ['Coordination'], 'flash', 1, undefined],
    [9, 'pink', ['Power'], 'second-go', 2, 'comp wall'],
    [10, 'yellow', ['Compression'], 'project', 5, 'main wall roof'],
    [8, 'red', ['Crimpy'], 'second-go', 2, undefined],
    [11, 'orange', ['Crimpy'], 'project', 4, 'cave, right of the arête'],
  ];
  const liveClimbs: Climb[] = tonight.map(([grade, colour, styles, tickType, attempts, loc], i) => {
    const d = new Date(started.getTime() + i * 11 * 60_000);
    return {
      id: uid(),
      sessionId: liveId,
      gymId: 'batuu',
      gradeKind: 'number',
      grade,
      holdColour: colour,
      styles,
      location: loc,
      tickType,
      attempts,
      createdAt: d.toISOString(),
    };
  });

  /* ── A plan sitting on today ──────────────────────────────────────────── */
  const planId = uid();
  const plan: Session = {
    id: planId,
    date: today,
    gymId: 'bump-j1',
    intent: 'Max strength',
    focusStyles: ['Compression'],
    plannedBlocks: [
      { durationMin: 20, description: 'Warm-up + footwork drill', target: 'easy 5–7' },
      {
        durationMin: 45,
        description: 'Kilter 40° · limit boulders, long rests',
        target: 'V5–V7 · 4 tries max',
        emphasis: true,
      },
      {
        durationMin: 30,
        description: 'Compression project · main wall roof',
        target: 'grade 11–12',
      },
      { durationMin: 10, description: 'A2 rehab · no-hang 10s × 5', target: 'rehab', rehab: true },
    ],
    status: 'planned',
  };

  await db.sessions.bulkPut([...sessions, live, plan]);
  await db.climbs.bulkPut([...climbs, ...liveClimbs]);
  await db.reviews.bulkPut(reviews);

  await db.settings.bulkPut([
    { key: 'activeSessionId', value: liveId },
    { key: 'dashboardRange', value: '8w' },
    { key: 'blockStart', value: weekStart(addDays(today, -21)) },
    { key: 'blockWeeks', value: 6 },
    { key: 'blockPhase', value: 'BUILD' },
    { key: 'seededAt', value: toISODate(new Date()) },
  ]);
}

export async function resetToDemo(): Promise<void> {
  await Promise.all(db.tables.map((t) => t.clear()));
  await seed();
}

export async function clearAll(): Promise<void> {
  await Promise.all(db.tables.map((t) => t.clear()));
  await db.gyms.bulkPut(GYMS);
  await db.boards.bulkPut(BOARDS);
  await db.settings.bulkPut([{ key: 'dashboardRange', value: '8w' }]);
}
