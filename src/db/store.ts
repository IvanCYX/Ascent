import { useLiveQuery } from 'dexie-react-hooks';
import {
  db,
  uid,
  type Climb,
  type Gym,
  type Injury,
  type LoadRule,
  type PlanBlock,
  type RehabExercise,
  type Session,
  type SessionReview,
} from './schema';
import { todayISO } from '../domain/dates';
import type { ClimbStyle, SessionIntent } from '../domain/vocab';

/* ── Reads ──────────────────────────────────────────────────────────────── */

export interface Snapshot {
  gyms: Gym[];
  boards: { id: string; name: string; code: string; angles: number[]; sortOrder: number }[];
  climbs: Climb[];
  sessions: Session[];
  reviews: SessionReview[];
  injuries: Injury[];
  painEntries: { id: string; injuryId: string; sessionId?: string; date: string; level: number }[];
  rehabExercises: RehabExercise[];
  rehabLogs: { id: string; exerciseId: string; date: string; done: boolean }[];
  loadRules: LoadRule[];
  competitions: { id: string; name: string; date: string }[];
  settings: Record<string, unknown>;
}

/** One live snapshot of the whole (single-user, small) database. */
export function useSnapshot(): Snapshot | undefined {
  return useLiveQuery(async () => {
    const [
      gyms,
      boards,
      climbs,
      sessions,
      reviews,
      injuries,
      painEntries,
      rehabExercises,
      rehabLogs,
      loadRules,
      competitions,
      settingRows,
    ] = await Promise.all([
      db.gyms.orderBy('sortOrder').toArray(),
      db.boards.orderBy('sortOrder').toArray(),
      db.climbs.toArray(),
      db.sessions.toArray(),
      db.reviews.toArray(),
      db.injuries.toArray(),
      db.painEntries.toArray(),
      db.rehabExercises.toArray(),
      db.rehabLogs.toArray(),
      db.loadRules.toArray(),
      db.competitions.toArray(),
      db.settings.toArray(),
    ]);
    const settings: Record<string, unknown> = {};
    for (const r of settingRows) settings[r.key] = r.value;
    return {
      gyms,
      boards,
      climbs: climbs.sort((a, b) => a.createdAt.localeCompare(b.createdAt)),
      sessions: sessions.sort((a, b) => a.date.localeCompare(b.date)),
      reviews,
      injuries,
      painEntries,
      rehabExercises,
      rehabLogs,
      loadRules,
      competitions,
      settings,
    };
  }, []);
}

/* ── Settings ───────────────────────────────────────────────────────────── */

export const setSetting = (key: string, value: unknown) => db.settings.put({ key, value });

/* ── Sessions ───────────────────────────────────────────────────────────── */

export async function startSession(opts: {
  gymId?: string;
  intent?: SessionIntent;
  focusStyles?: ClimbStyle[];
  plannedBlocks?: PlanBlock[];
  fromPlanId?: string;
}): Promise<string> {
  const id = opts.fromPlanId ?? uid();
  const now = new Date().toISOString();
  const existing = opts.fromPlanId ? await db.sessions.get(opts.fromPlanId) : undefined;
  await db.sessions.put({
    ...(existing ?? {}),
    id,
    date: todayISO(),
    gymId: opts.gymId ?? existing?.gymId,
    intent: opts.intent ?? existing?.intent,
    focusStyles: opts.focusStyles ?? existing?.focusStyles,
    plannedBlocks: opts.plannedBlocks ?? existing?.plannedBlocks,
    status: 'active',
    startedAt: now,
  });
  await setSetting('activeSessionId', id);
  return id;
}

export async function endSession(sessionId: string): Promise<void> {
  const s = await db.sessions.get(sessionId);
  if (!s) return;
  const now = new Date().toISOString();
  const mins = s.startedAt
    ? Math.max(1, Math.round((Date.now() - new Date(s.startedAt).getTime()) / 60_000))
    : undefined;
  await db.sessions.put({ ...s, status: 'done', endedAt: now, durationMin: mins });
  await setSetting('activeSessionId', null);
}

export async function updateSession(sessionId: string, patch: Partial<Session>): Promise<void> {
  const s = await db.sessions.get(sessionId);
  if (!s) return;
  await db.sessions.put({ ...s, ...patch });
}

export async function savePlan(plan: {
  id?: string;
  date: string;
  gymId?: string;
  intent?: SessionIntent;
  focusStyles?: ClimbStyle[];
  plannedBlocks?: PlanBlock[];
}): Promise<string> {
  const id = plan.id ?? uid();
  const existing = await db.sessions.get(id);
  await db.sessions.put({
    ...(existing ?? { status: 'planned' as const }),
    ...plan,
    id,
    status: existing?.status ?? 'planned',
  });
  return id;
}

export async function setActiveGym(sessionId: string, gymId: string): Promise<void> {
  await updateSession(sessionId, { gymId });
}

/* ── Climbs ─────────────────────────────────────────────────────────────── */

export async function addClimb(climb: Omit<Climb, 'id' | 'createdAt'>): Promise<string> {
  const id = uid();
  await db.climbs.put({ ...climb, id, createdAt: new Date().toISOString() });
  return id;
}

export const deleteClimb = (id: string) => db.climbs.delete(id);

/* ── Reviews ────────────────────────────────────────────────────────────── */

export async function saveReview(
  sessionId: string,
  chips: string[],
  overallScore: number,
  note?: string,
): Promise<void> {
  await db.reviews.put({
    sessionId,
    chips,
    overallScore,
    note,
    createdAt: new Date().toISOString(),
  });
}

/* ── Injuries, pain, rehab ──────────────────────────────────────────────── */

export async function addPainEntry(
  injuryId: string,
  level: number,
  sessionId?: string,
  date = todayISO(),
): Promise<void> {
  const existing = await db.painEntries
    .where('injuryId')
    .equals(injuryId)
    .filter((p) => p.date === date)
    .first();
  await db.painEntries.put({
    id: existing?.id ?? uid(),
    injuryId,
    sessionId,
    date,
    level,
  });
}

export async function createInjury(injury: Omit<Injury, 'id'>): Promise<string> {
  const id = uid();
  await db.injuries.put({ ...injury, id });
  return id;
}

export const updateInjury = (id: string, patch: Partial<Injury>) =>
  db.injuries.get(id).then((i) => (i ? db.injuries.put({ ...i, ...patch }) : undefined));

export async function toggleRehabLog(exerciseId: string, date = todayISO()): Promise<void> {
  const existing = await db.rehabLogs
    .where('exerciseId')
    .equals(exerciseId)
    .filter((l) => l.date === date)
    .first();
  if (existing) await db.rehabLogs.delete(existing.id);
  else await db.rehabLogs.put({ id: uid(), exerciseId, date, done: true });
}

export async function addRehabExercise(ex: Omit<RehabExercise, 'id'>): Promise<void> {
  await db.rehabExercises.put({ ...ex, id: uid() });
}

export const deleteRehabExercise = (id: string) => db.rehabExercises.delete(id);

export async function addLoadRule(rule: Omit<LoadRule, 'id'>): Promise<void> {
  await db.loadRules.put({ ...rule, id: uid() });
}

export const deleteLoadRule = (id: string) => db.loadRules.delete(id);

/* ── Gyms ───────────────────────────────────────────────────────────────── */

export async function saveGym(gym: Omit<Gym, 'id'> & { id?: string }): Promise<void> {
  const id = gym.id ?? uid();
  await db.gyms.put({ ...gym, id } as Gym);
}

export const deleteGym = (id: string) => db.gyms.delete(id);

/* ── Competitions ───────────────────────────────────────────────────────── */

export async function saveCompetition(name: string, date: string, id?: string): Promise<void> {
  await db.competitions.put({ id: id ?? uid(), name, date });
}

/* ── Backup ─────────────────────────────────────────────────────────────── */

export async function exportJSON(): Promise<string> {
  const data: Record<string, unknown> = {};
  for (const table of db.tables) data[table.name] = await table.toArray();
  return JSON.stringify({ version: 1, exportedAt: new Date().toISOString(), data }, null, 2);
}

export async function importJSON(json: string): Promise<void> {
  const parsed = JSON.parse(json) as { data: Record<string, unknown[]> };
  await db.transaction('rw', db.tables, async () => {
    for (const table of db.tables) {
      const rows = parsed.data[table.name];
      if (!rows) continue;
      await table.clear();
      await table.bulkPut(rows as never[]);
    }
  });
}
