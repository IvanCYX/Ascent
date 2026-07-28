import Dexie, { type Table } from 'dexie';
import type { ClimbStyle, SessionIntent, TickType } from '../domain/vocab';

/* ── Entities ───────────────────────────────────────────────────────────── */

export type ScaleType = 'numeric' | 'ranked-colour';

export interface Gym {
  id: string;
  name: string;
  shortName: string;
  scaleType: ScaleType;
  /** numeric gyms only — top of the gym's own label range on the 1–15 spine */
  maxGrade?: number;
  /** ranked-colour gyms only — ordered easiest → hardest, values are HoldColour ids */
  tags?: string[];
  /** soft/hard offset, -1..+1, applied when comparing gyms in aggregate */
  offset: number;
  note?: string;
  sortOrder: number;
}

export interface Board {
  id: string;
  name: string;
  code: string;
  angles: number[];
  sortOrder: number;
}

export type GradeKind = 'number' | 'tag' | 'v';

export interface Climb {
  id: string;
  sessionId: string;
  gymId?: string;
  boardId?: string;
  angle?: number;
  gradeKind: GradeKind;
  /** numeric gyms: 1–15 · ranked-colour: tag ordinal 1–8 · boards: V-grade 1–10 */
  grade: number;
  /** ranked-colour gyms only — the tag itself */
  tagId?: string;
  holdColour?: string;
  styles: ClimbStyle[];
  location?: string;
  name?: string;
  tickType: TickType;
  attempts: number;
  createdAt: string;
}

export type SessionStatus = 'planned' | 'active' | 'done';

export interface PlanBlock {
  durationMin: number;
  description: string;
  target?: string;
  emphasis?: boolean;
  rehab?: boolean;
}

export interface Session {
  id: string;
  date: string; // ISO yyyy-mm-dd
  gymId?: string;
  intent?: SessionIntent;
  focusStyles?: ClimbStyle[];
  plannedBlocks?: PlanBlock[];
  durationMin?: number;
  notes?: string;
  status: SessionStatus;
  startedAt?: string;
  endedAt?: string;
}

export interface SessionReview {
  sessionId: string;
  chips: string[];
  overallScore: number; // 0–10, one decimal
  note?: string;
  createdAt: string;
}

export type InjuryStatus = 'active' | 'watching' | 'resolved';

export interface Injury {
  id: string;
  bodyPart: string;
  name: string;
  onsetDate: string;
  status: InjuryStatus;
  severity?: string;
  diagnosis?: string;
  rehabStart?: string;
  physioNext?: string;
  physioNote?: string;
}

export interface PainEntry {
  id: string;
  injuryId: string;
  sessionId?: string;
  date: string;
  level: number; // 0–10
}

export interface RehabExercise {
  id: string;
  injuryId: string;
  name: string;
  prescription: string;
  /** times per week; 7 = daily */
  frequency: number;
}

export interface RehabLog {
  id: string;
  exerciseId: string;
  date: string;
  done: boolean;
}

export interface LoadRule {
  id: string;
  injuryId: string;
  /** a ClimbStyle, or a free-form type like "campus" */
  styleOrType: string;
  /** null = a hard prohibition rather than a weekly cap */
  maxPerWeek: number | null;
  condition: string;
  headline: string;
}

export interface Competition {
  id: string;
  name: string;
  date: string;
}

export interface Setting {
  key: string;
  value: unknown;
}

/* ── Database ───────────────────────────────────────────────────────────── */

export class SendlogDB extends Dexie {
  gyms!: Table<Gym, string>;
  boards!: Table<Board, string>;
  climbs!: Table<Climb, string>;
  sessions!: Table<Session, string>;
  reviews!: Table<SessionReview, string>;
  injuries!: Table<Injury, string>;
  painEntries!: Table<PainEntry, string>;
  rehabExercises!: Table<RehabExercise, string>;
  rehabLogs!: Table<RehabLog, string>;
  loadRules!: Table<LoadRule, string>;
  competitions!: Table<Competition, string>;
  settings!: Table<Setting, string>;

  constructor() {
    super('sendlog');
    this.version(1).stores({
      gyms: 'id, sortOrder',
      boards: 'id, sortOrder',
      climbs: 'id, sessionId, gymId, boardId, createdAt, gradeKind',
      sessions: 'id, date, gymId, status',
      reviews: 'sessionId',
      injuries: 'id, status',
      painEntries: 'id, injuryId, sessionId, date',
      rehabExercises: 'id, injuryId',
      rehabLogs: 'id, exerciseId, date',
      loadRules: 'id, injuryId',
      competitions: 'id, date',
      settings: 'key',
    });
  }
}

export const db = new SendlogDB();

export const uid = (): string =>
  `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`;
