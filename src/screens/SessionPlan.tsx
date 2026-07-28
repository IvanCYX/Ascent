import { useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import type { Snapshot } from '../db/store';
import { savePlan, setSetting, startSession } from '../db/store';
import type { PlanBlock } from '../db/schema';
import { CLIMB_STYLES, SESSION_INTENTS, type ClimbStyle, type SessionIntent } from '../domain/vocab';
import { planDate, todayISO, weekStart, weeksBetween } from '../domain/dates';
import { compReadiness, climbsInRange, loadRuleUsage } from '../domain/metrics';
import { rangeWindows } from '../domain/dates';
import { Chip, WarnPanel } from '../components/ui';

const BLOCK_TEMPLATES: Record<SessionIntent, PlanBlock[]> = {
  'Max strength': [
    { durationMin: 20, description: 'Warm-up + footwork drill', target: 'easy 5–7' },
    {
      durationMin: 45,
      description: 'Kilter 40° · limit boulders, long rests',
      target: 'V5–V7 · 4 tries max',
      emphasis: true,
    },
    { durationMin: 30, description: 'Project block · main wall roof', target: 'grade 11–12' },
  ],
  'Power endurance': [
    { durationMin: 20, description: 'Warm-up + easy circuit', target: 'easy 5–7' },
    { durationMin: 40, description: '4×4s on mid-grade boulders', target: 'grade 8–9', emphasis: true },
    { durationMin: 20, description: 'Down-climbs, no matching', target: 'grade 6–7' },
  ],
  Coordination: [
    { durationMin: 15, description: 'Warm-up + dynamic mobility', target: 'easy 5–6' },
    { durationMin: 45, description: 'Comp-style dynos and run-and-jumps', target: 'grade 9–11', emphasis: true },
    { durationMin: 20, description: 'Repeat the two you flashed, faster', target: 'flow' },
  ],
  'Comp sim': [
    { durationMin: 20, description: 'Warm-up, then no previews', target: 'easy 6–7' },
    { durationMin: 50, description: '5 boulders · 4 min on, 4 min off', target: 'grade 9–12', emphasis: true },
    { durationMin: 15, description: 'Cool-down + notes while it is fresh', target: '—' },
  ],
  'Slab / technique': [
    { durationMin: 15, description: 'Warm-up + silent-feet drill', target: 'easy 5–6' },
    { durationMin: 45, description: 'Slab ladder, no hand matching', target: 'grade 8–10', emphasis: true },
    { durationMin: 20, description: 'Balance holds, 10s each', target: 'technique' },
  ],
  'Chill maintenance': [
    { durationMin: 15, description: 'Long easy warm-up', target: 'easy 5–6' },
    { durationMin: 45, description: 'Volume at two grades below limit', target: 'grade 7–9', emphasis: true },
    { durationMin: 15, description: 'Stretch + antagonists', target: 'recovery' },
  ],
};

export default function SessionPlan({ snap }: { snap: Snapshot }) {
  const nav = useNavigate();
  const today = todayISO();
  const existingPlan = snap.sessions.find((s) => s.status === 'planned' && s.date === today);

  const [gymId, setGymId] = useState(existingPlan?.gymId ?? snap.gyms[0]?.id ?? '');
  const [intent, setIntent] = useState<SessionIntent>(existingPlan?.intent ?? 'Max strength');
  const [focus, setFocus] = useState<ClimbStyle[]>(existingPlan?.focusStyles ?? []);
  const [blocks, setBlocks] = useState<PlanBlock[]>(
    existingPlan?.plannedBlocks ?? BLOCK_TEMPLATES['Max strength'],
  );
  const [savedTemplate, setSavedTemplate] = useState(false);

  /* Load rules — evaluated when planning, before anything is logged. */
  const usage = useMemo(
    () =>
      loadRuleUsage(
        snap.loadRules.filter((r) => r.maxPerWeek !== null),
        snap.climbs,
        weekStart(today),
      ),
    [snap.loadRules, snap.climbs, today],
  );
  const blockedStyles = useMemo(() => {
    const map = new Map<string, (typeof usage)[number] & { injuryName: string }>();
    for (const u of usage) {
      if (!u.blocked) continue;
      const rule = snap.loadRules.find((r) => r.id === u.ruleId);
      if (!rule) continue;
      const injury = snap.injuries.find((i) => i.id === rule.injuryId);
      map.set(rule.styleOrType, { ...u, injuryName: injury?.name ?? 'an active injury' });
    }
    return map;
  }, [usage, snap.loadRules, snap.injuries]);

  /* Weak styles feed the focus list. */
  const weak = useMemo(() => {
    const w = rangeWindows('8w', today);
    const cur = climbsInRange(snap.climbs, w.from, w.to);
    return compReadiness(cur, snap.reviews)
      .filter((r) => r.warn)
      .map((r) => (r.label === 'Crimps' ? 'Crimpy' : r.label));
  }, [snap.climbs, snap.reviews, today]);

  const suggested = useMemo(() => {
    const ranked = [...CLIMB_STYLES].sort((a, b) => {
      const aw = weak.includes(a) ? 0 : 1;
      const bw = weak.includes(b) ? 0 : 1;
      return aw - bw;
    });
    return ranked.slice(0, 5);
  }, [weak]);

  const comp = [...snap.competitions].sort((a, b) => a.date.localeCompare(b.date))[0];
  const blockStart = (snap.settings.blockStart as string) ?? weekStart(today);
  const blockWeeks = (snap.settings.blockWeeks as number) ?? 6;
  const blockPhase = (snap.settings.blockPhase as string) ?? 'BUILD';
  const weekOfBlock = Math.min(blockWeeks, Math.max(1, weeksBetween(blockStart, today) + 1));

  const gym = snap.gyms.find((g) => g.id === gymId);
  const activeBlockedFocus = focus.filter((f) => blockedStyles.has(f));
  const firstBlocked = [...blockedStyles.entries()][0];

  /* A rehab block is appended while an injury is active, unless one is already there. */
  const rehabInjury = snap.injuries.find((i) => i.status === 'active');
  const rehabEx = rehabInjury
    ? snap.rehabExercises.find((e) => e.injuryId === rehabInjury.id)
    : undefined;
  const rehabBlock: PlanBlock | null =
    rehabInjury && !blocks.some((b) => b.rehab)
      ? {
          durationMin: 10,
          description: `${shortName(rehabInjury.name)} rehab · ${
            rehabEx ? rehabEx.name.toLowerCase() : 'protocol'
          }`,
          target: 'rehab',
          rehab: true,
        }
      : null;
  const allBlocks = rehabBlock ? [...blocks, rehabBlock] : blocks;
  const totalMin = allBlocks.reduce((a, b) => a + b.durationMin, 0);

  const applyIntent = (i: SessionIntent) => {
    setIntent(i);
    setBlocks(BLOCK_TEMPLATES[i]);
  };

  const persist = () =>
    savePlan({
      id: existingPlan?.id,
      date: today,
      gymId,
      intent,
      focusStyles: focus,
      plannedBlocks: allBlocks,
    });

  const start = async () => {
    const id = await persist();
    await startSession({ gymId, intent, focusStyles: focus, plannedBlocks: allBlocks, fromPlanId: id });
    nav('/log');
  };

  return (
    <div className="screen-desktop" style={{ maxWidth: 560 }}>
      <div className="page-head" style={{ padding: '20px 26px 16px' }}>
        <div>
          <div className="eyebrow">
            PLAN · {planDate(today)} · {gym?.name.toUpperCase() ?? 'NO GYM'}
          </div>
          <div className="serif" style={{ fontSize: 26, lineHeight: 1.1, marginTop: 11 }}>
            Today is a {intent.toLowerCase()} day
          </div>
        </div>
        <span
          className="mono"
          style={{
            font: '400 10px/1 var(--mono)',
            border: '1px solid rgba(0,0,0,.25)',
            padding: '8px 11px',
            letterSpacing: '.06em',
            whiteSpace: 'nowrap',
          }}
        >
          WK {weekOfBlock} OF {blockWeeks} · {blockPhase}
        </span>
      </div>

      {/* Gym */}
      <div style={{ padding: '18px 26px', borderBottom: '1px solid var(--rule)' }}>
        <div className="micro" style={{ marginBottom: 12 }}>
          GYM
        </div>
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6 }}>
          {snap.gyms.map((g) => (
            <Chip key={g.id} small label={g.name} on={g.id === gymId} onClick={() => setGymId(g.id)} />
          ))}
        </div>
      </div>

      {/* Intent */}
      <div style={{ padding: '20px 26px', borderBottom: '1px solid var(--rule)' }}>
        <div className="micro" style={{ marginBottom: 12 }}>
          SESSION INTENT
        </div>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 7 }}>
          {SESSION_INTENTS.map((i) => (
            <button
              key={i}
              onClick={() => applyIntent(i)}
              style={{
                font: `${i === intent ? 600 : 500} 12px/1.3 var(--sans)`,
                padding: '13px 12px',
                color: i === intent ? 'var(--paper)' : 'var(--ink)',
                background: i === intent ? 'var(--ink)' : 'var(--card)',
                border: `1px solid ${i === intent ? 'var(--ink)' : 'var(--rule-chip)'}`,
                transition: 'background var(--t), color var(--t)',
              }}
            >
              {i}
            </button>
          ))}
        </div>
      </div>

      {/* Focus styles */}
      <div style={{ padding: '20px 26px', borderBottom: '1px solid var(--rule)' }}>
        <div
          style={{
            display: 'flex',
            alignItems: 'baseline',
            justifyContent: 'space-between',
            marginBottom: 14,
          }}
        >
          <span className="serif" style={{ fontSize: 19 }}>
            Focus styles
          </span>
          <span className="mono" style={{ fontSize: 10, color: 'var(--muted)', letterSpacing: '.08em' }}>
            FROM YOUR WEAK COLUMN
          </span>
        </div>
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: 7, marginBottom: firstBlocked ? 15 : 0 }}>
          {suggested.map((s) => {
            const blocked = blockedStyles.has(s);
            return (
              <Chip
                key={s}
                label={s}
                on={focus.includes(s)}
                blocked={blocked}
                title={blocked ? 'Blocked by an active load rule' : undefined}
                onClick={() =>
                  setFocus((cur) => (cur.includes(s) ? cur.filter((x) => x !== s) : [...cur, s]))
                }
              />
            );
          })}
        </div>
        {firstBlocked && (
          <WarnPanel lead={`${firstBlocked[0]} removed`}>
            {firstBlocked[1].injuryName} caps {firstBlocked[0].toLowerCase()} sessions at{' '}
            {firstBlocked[1].cap}/wk {firstBlocked[1].condition} and you have used{' '}
            {firstBlocked[1].used === firstBlocked[1].cap ? 'both' : `${firstBlocked[1].used}`}.{' '}
            {suggested.find((s) => !blockedStyles.has(s) && weak.includes(s))
              ? `${suggested.find((s) => !blockedStyles.has(s) && weak.includes(s))} keeps the comp gap closing without loading it.`
              : 'Pick a style that does not load it.'}
          </WarnPanel>
        )}
        {activeBlockedFocus.length > 0 && (
          <div className="mono" style={{ fontSize: 10, color: 'var(--warn)', marginTop: 8 }}>
            REMOVE {activeBlockedFocus.join(', ').toUpperCase()} BEFORE STARTING
          </div>
        )}
      </div>

      {/* Blocks */}
      <div style={{ padding: '20px 26px 32px' }}>
        <div
          style={{
            display: 'flex',
            alignItems: 'baseline',
            justifyContent: 'space-between',
            marginBottom: 14,
          }}
        >
          <span className="serif" style={{ fontSize: 19 }}>
            Blocks
          </span>
          <span className="mono" style={{ fontSize: 10, color: 'var(--muted)' }}>
            {totalMin} MIN TOTAL
          </span>
        </div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
          {allBlocks.map((b, i) => (
            <div
              key={`${b.description}-${i}`}
              style={{
                display: 'flex',
                alignItems: 'center',
                gap: 14,
                padding: '13px 15px',
                background: 'var(--card)',
                border: b.emphasis ? '2px solid var(--ink)' : '1px solid var(--rule)',
              }}
            >
              <span
                className="mono"
                style={{
                  width: 44,
                  flex: 'none',
                  fontSize: 10.5,
                  color: b.emphasis ? 'var(--ink)' : 'var(--muted)',
                }}
              >
                {b.durationMin} min
              </span>
              <span style={{ flex: 1, font: '500 12.5px/1.35 var(--sans)' }}>{b.description}</span>
              <span
                style={{
                  font: '400 11px/1.3 var(--sans)',
                  color: b.rehab ? 'var(--warn)' : b.emphasis ? 'var(--ink)' : 'var(--muted)',
                  textAlign: 'right',
                  flex: 'none',
                }}
              >
                {b.target}
              </span>
            </div>
          ))}
        </div>

        <div style={{ display: 'flex', gap: 8, marginTop: 18 }}>
          <button
            className="btn-secondary"
            onClick={async () => {
              await persist();
              await setSetting(`template:${intent}`, allBlocks);
              setSavedTemplate(true);
            }}
          >
            {savedTemplate ? 'Template saved' : 'Save as template'}
          </button>
          <button
            className="btn-primary"
            style={{ flex: 1 }}
            disabled={activeBlockedFocus.length > 0}
            onClick={start}
          >
            Start session
          </button>
        </div>
        {comp && (
          <div className="mono" style={{ fontSize: 10, color: 'var(--muted)', marginTop: 14, letterSpacing: '.08em' }}>
            NEXT COMP · {comp.name.toUpperCase()} · {Math.max(0, weeksBetween(today, comp.date))} WEEKS OUT
          </div>
        )}
      </div>
    </div>
  );
}

const shortName = (name: string): string => {
  const tail = name.split('·').pop()?.trim() ?? name;
  return tail.replace(/ (strain|pulley strain|tendinopathy|niggle|impingement niggle)$/i, '');
};
