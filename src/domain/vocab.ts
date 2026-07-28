/** Exact vocabularies from the handoff. Strings are final — do not paraphrase. */

export const CLIMB_STYLES = [
  'Crimpy',
  'Compression',
  'Slopey',
  'Slab',
  'Coordination',
  'Power',
] as const;

/** Tension is board-only. */
export const BOARD_STYLES = [...CLIMB_STYLES, 'Tension'] as const;

export type ClimbStyle = (typeof BOARD_STYLES)[number];

export const SESSION_INTENTS = [
  'Max strength',
  'Power endurance',
  'Coordination',
  'Comp sim',
  'Slab / technique',
  'Chill maintenance',
] as const;

export type SessionIntent = (typeof SESSION_INTENTS)[number];

export const TICK_TYPES = [
  { id: 'flash', label: 'Flash' },
  { id: 'second-go', label: '2nd go' },
  { id: 'project', label: 'Project' },
  { id: 'attempt', label: 'Attempt only' },
] as const;

export type TickType = (typeof TICK_TYPES)[number]['id'];

/** Hold / tag colours — the only place saturated colour is allowed. */
export const HOLD_COLOURS = [
  { id: 'yellow', label: 'Yellow', code: 'YEL', hex: '#f2c744' },
  { id: 'pink', label: 'Pink', code: 'PNK', hex: '#ec6ba8' },
  { id: 'blue', label: 'Blue', code: 'BLU', hex: '#3f7fd6' },
  { id: 'orange', label: 'Orange', code: 'ORG', hex: '#f08a3c' },
  { id: 'green', label: 'Green', code: 'GRN', hex: '#4caf6a' },
  { id: 'purple', label: 'Purple', code: 'PUR', hex: '#8a63d2' },
  { id: 'red', label: 'Red', code: 'RED', hex: '#d8443c' },
  { id: 'black', label: 'Black', code: 'BLK', hex: '#1b1b1b' },
  { id: 'white', label: 'White', code: 'WHT', hex: '#ffffff' },
] as const;

export type HoldColourId = (typeof HOLD_COLOURS)[number]['id'];

export const colourHex = (id?: string): string =>
  HOLD_COLOURS.find((c) => c.id === id)?.hex ?? 'rgba(0,0,0,.12)';

export const colourCode = (id?: string): string =>
  HOLD_COLOURS.find((c) => c.id === id)?.code ?? '—';

export const colourLabel = (id?: string): string =>
  HOLD_COLOURS.find((c) => c.id === id)?.label ?? '';

/** Camp5 ranked-colour tags, ordinal 1–8. Never mapped onto 1–15. */
export const CAMP5_TAGS = [
  'yellow',
  'pink',
  'blue',
  'orange',
  'green',
  'purple',
  'red',
  'black',
] as const;

export type ReviewChipGroup = 'BODY' | 'HEAD' | 'EXECUTION' | 'PAIN';

export const REVIEW_CHIPS: Record<Exclude<ReviewChipGroup, 'PAIN'>, string[]> = {
  BODY: ['Felt strong', 'Felt weak', 'Fatigued early', 'Good tension', 'Poor recovery'],
  HEAD: ['Locked in', 'Distracted', 'Hesitant', 'Confident first go', 'Scared of the fall'],
  EXECUTION: [
    'Coordination dialled',
    'Missed the timing',
    'Sloppy feet',
    'Read beta wrong',
    'Good beta reading',
  ],
};

export const ALL_REVIEW_CHIPS = [
  ...REVIEW_CHIPS.BODY,
  ...REVIEW_CHIPS.HEAD,
  ...REVIEW_CHIPS.EXECUTION,
];

/** Grade bands used by the style × grade heatmap. */
export const GRADE_BANDS: { label: string; min: number; max: number }[] = [
  { label: '6–7', min: 6, max: 7 },
  { label: '8–9', min: 8, max: 9 },
  { label: '10–11', min: 10, max: 11 },
  { label: '12–13', min: 12, max: 13 },
  { label: '14–15', min: 14, max: 15 },
];

/** Readiness rows on the dashboard blend styles with a couple of training qualities. */
export const READINESS_ROWS = [
  'Coordination',
  'Power',
  'Slab',
  'Power endurance',
  'Compression',
  'Crimps',
] as const;

export const READINESS_WARN_BELOW = 55;

/** Body parts offered by the injury body map. */
export const BODY_PARTS = [
  { id: 'head', label: 'Head / neck' },
  { id: 'torso', label: 'Torso / core' },
  { id: 'l-shoulder', label: 'L shoulder' },
  { id: 'r-shoulder', label: 'R shoulder' },
  { id: 'l-elbow', label: 'L elbow' },
  { id: 'r-elbow', label: 'R elbow' },
  { id: 'l-hand', label: 'L hand / fingers' },
  { id: 'r-hand', label: 'R hand / fingers' },
  { id: 'l-leg', label: 'L leg / knee' },
  { id: 'r-leg', label: 'R leg / knee' },
] as const;

export type BodyPartId = (typeof BODY_PARTS)[number]['id'];

export const bodyPartLabel = (id: string): string =>
  BODY_PARTS.find((p) => p.id === id)?.label ?? id;
