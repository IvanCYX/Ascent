import { useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import type { Snapshot } from '../db/store';
import { addClimb, deleteClimb } from '../db/store';
import { BOARD_STYLES, TICK_TYPES, type ClimbStyle, type TickType } from '../domain/vocab';
import { elapsedLabel, timeOfDay, todayISO, weekStart } from '../domain/dates';
import { boardHistogram, loadRuleUsage } from '../domain/metrics';
import { Chip, WarnPanel } from '../components/ui';
import SessionStarter from '../components/SessionStarter';

const V_GRADES = Array.from({ length: 10 }, (_, i) => i + 1);

export default function BoardLog({ snap }: { snap: Snapshot }) {
  const nav = useNavigate();
  const activeId = snap.settings.activeSessionId as string | null | undefined;
  const session = snap.sessions.find((s) => s.id === activeId && s.status === 'active');

  const [boardId, setBoardId] = useState(snap.boards[0]?.id ?? 'kilter');
  const board = snap.boards.find((b) => b.id === boardId) ?? snap.boards[0];
  const [angle, setAngle] = useState<number>(board?.angles.includes(40) ? 40 : board?.angles[0] ?? 40);
  const [v, setV] = useState<number | null>(null);
  const [name, setName] = useState('');
  const [styles, setStyles] = useState<ClimbStyle[]>([]);
  const [tickType, setTickType] = useState<TickType>('second-go');

  const usage = useMemo(
    () =>
      loadRuleUsage(
        snap.loadRules.filter((r) => r.maxPerWeek !== null),
        snap.climbs,
        weekStart(todayISO()),
      ),
    [snap.loadRules, snap.climbs],
  );
  const tripped = usage.filter((u) => {
    const rule = snap.loadRules.find((r) => r.id === u.ruleId);
    return (u.blocked || u.nearing) && !!rule && styles.includes(rule.styleOrType as ClimbStyle);
  });

  const bars = useMemo(
    () => boardHistogram(snap.climbs, boardId, angle),
    [snap.climbs, boardId, angle],
  );
  const maxV = bars.filter((b) => b.count > 0).map((b) => b.v).pop() ?? null;

  const tonight = snap.climbs
    .filter((c) => c.sessionId === session?.id && c.boardId)
    .sort((a, b) => b.createdAt.localeCompare(a.createdAt));

  if (!session) {
    return <SessionStarter snap={snap} title="Board session" hint="Start a session before logging board climbs." />;
  }

  const gym = snap.gyms.find((g) => g.id === session.gymId);

  const save = async () => {
    if (v === null || !board) return;
    await addClimb({
      sessionId: session.id,
      boardId: board.id,
      angle,
      gradeKind: 'v',
      grade: v,
      styles,
      name: name.trim() || undefined,
      tickType,
      attempts: tickType === 'flash' ? 1 : tickType === 'second-go' ? 2 : 4,
    });
    setV(null);
    setName('');
  };

  const toggleStyle = (s: ClimbStyle) =>
    setStyles((cur) => (cur.includes(s) ? cur.filter((x) => x !== s) : [...cur, s]));

  return (
    <div className="screen-mobile">
      <div className="status-strip">
        <span>{timeOfDay(new Date().toISOString())}</span>
        <span>
          {gym?.name ?? 'Board'} · {session.startedAt ? elapsedLabel(session.startedAt) : '0m'}
        </span>
      </div>

      <div style={{ padding: '12px 20px 6px' }}>
        <div className="serif" style={{ fontSize: 27, lineHeight: 1 }}>
          Board session
        </div>

        {/* Board switch */}
        <div style={{ display: 'flex', gap: 6, margin: '16px 0' }}>
          {snap.boards.map((b) => (
            <button
              key={b.id}
              onClick={() => {
                setBoardId(b.id);
                if (!b.angles.includes(angle)) setAngle(b.angles[0]);
              }}
              style={{
                flex: 1,
                textAlign: 'center',
                padding: '12px 0',
                font: `${b.id === boardId ? 600 : 500} 12px/1 var(--sans)`,
                color: b.id === boardId ? 'var(--paper)' : 'var(--ink)',
                background: b.id === boardId ? 'var(--ink)' : 'var(--card)',
                border: `1px solid ${b.id === boardId ? 'var(--ink)' : 'var(--rule-chip)'}`,
              }}
            >
              {b.name}
            </button>
          ))}
        </div>

        {/* Angle */}
        <div className="field" style={{ justifyContent: 'space-between', marginBottom: 18 }}>
          <label>ANGLE</label>
          <div style={{ display: 'flex', gap: 5 }}>
            {(board?.angles ?? []).map((a) => (
              <button
                key={a}
                onClick={() => setAngle(a)}
                className="mono"
                style={{
                  padding: '7px 10px',
                  font: `${a === angle ? 600 : 500} 11.5px/1 var(--mono)`,
                  color: a === angle ? 'var(--paper)' : 'var(--ink)',
                  background: a === angle ? 'var(--ink)' : 'transparent',
                  border: `1px solid ${a === angle ? 'var(--ink)' : 'var(--rule-chip)'}`,
                }}
              >
                {a}°
              </button>
            ))}
          </div>
        </div>

        <div className="micro" style={{ marginBottom: 10 }}>
          GRADE SENT
        </div>
        <div className="grade-grid" style={{ marginBottom: 18 }}>
          {V_GRADES.map((g) => (
            <button
              key={g}
              className={`grade-btn${v === g ? ' on' : ''}`}
              style={{ fontSize: 14, padding: '13px 0' }}
              onClick={() => setV(g)}
            >
              V{g}
            </button>
          ))}
        </div>

        <div className="field" style={{ marginBottom: 10 }}>
          <label htmlFor="climb-name">CLIMB</label>
          <input
            id="climb-name"
            value={name}
            placeholder="shrimp cocktail"
            onChange={(e) => setName(e.target.value)}
          />
        </div>

        <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6, marginBottom: 12 }}>
          {BOARD_STYLES.map((s) => (
            <Chip key={s} small label={s} on={styles.includes(s)} onClick={() => toggleStyle(s)} />
          ))}
        </div>

        <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6, marginBottom: 14 }}>
          {TICK_TYPES.map((t) => (
            <Chip key={t.id} small label={t.label} on={tickType === t.id} onClick={() => setTickType(t.id)} />
          ))}
        </div>

        {tripped.length > 0 && (
          <WarnPanel lead={`${shortRuleName(tripped[0].headline)} load flag`} style={{ marginBottom: 14 }}>
            {tripped[0].used === tripped[0].cap
              ? `You are at the cap — ${tripped[0].used} of ${tripped[0].cap} this week ${tripped[0].condition}.`
              : `${ordinal(tripped[0].used + 1)} session this week against a cap of ${tripped[0].cap}. One more and you are over.`}
          </WarnPanel>
        )}

        <button
          className="btn-primary"
          style={{ width: '100%', padding: '15px 0' }}
          disabled={v === null}
          onClick={save}
        >
          {v === null ? 'Pick a V-grade' : `Log V${v} · ${board?.name} ${angle}°`}
        </button>

        {tonight.length > 0 && (
          <div style={{ marginTop: 16, display: 'flex', flexDirection: 'column', gap: 7 }}>
            {tonight.slice(0, 5).map((c) => (
              <div key={c.id} style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                <span className="serif" style={{ width: 28, fontSize: 15, flex: 'none' }}>
                  V{c.grade}
                </span>
                <span
                  style={{
                    flex: 1,
                    font: '400 11.5px/1.3 var(--sans)',
                    color: 'var(--muted)',
                    overflow: 'hidden',
                    textOverflow: 'ellipsis',
                    whiteSpace: 'nowrap',
                  }}
                >
                  {[c.name, `${c.angle}°`, c.tickType === 'flash' ? 'flash' : `${c.attempts} tries`]
                    .filter(Boolean)
                    .join(' · ')}
                </span>
                <button className="btn-link" onClick={() => deleteClimb(c.id)}>
                  Undo
                </button>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* All-time histogram for this board + angle */}
      <div style={{ borderTop: '1px solid rgba(0,0,0,.14)', padding: '15px 20px 24px' }}>
        <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', marginBottom: 12 }}>
          <span className="serif" style={{ fontSize: 17 }}>
            {board?.name.replace('Board', '').trim()} {angle}° · all time
          </span>
          <span className="mono" style={{ fontSize: 10.5 }}>
            {maxV ? `MAX V${maxV}` : 'NO SENDS'}
          </span>
        </div>
        <div style={{ display: 'flex', alignItems: 'flex-end', gap: 5, height: 62 }}>
          {bars.map((b) => (
            <div
              key={b.v}
              style={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 6 }}
              title={`${b.count} sends at V${b.v}`}
            >
              <div
                style={{
                  width: '100%',
                  height: b.count === 0 ? 3 : Math.max(6, b.height * 44),
                  background:
                    b.count === 0 ? 'rgba(0,0,0,.12)' : b.isMax ? 'var(--ink)' : 'rgba(23,21,15,.22)',
                }}
              />
              <span
                className="mono"
                style={{ fontSize: 9, color: b.count === 0 ? 'var(--faint)' : b.isMax ? 'var(--ink)' : 'var(--muted)' }}
              >
                V{b.v}
              </span>
            </div>
          ))}
        </div>
        <div style={{ display: 'flex', gap: 8, marginTop: 18 }}>
          <button className="btn-secondary" style={{ flex: 1 }} onClick={() => nav('/log')}>
            Gym log
          </button>
          <button className="btn-primary" style={{ flex: 1 }} onClick={() => nav('/review')}>
            End &amp; rate
          </button>
        </div>
      </div>
    </div>
  );
}

/** "Crimpy sessions · max 2 per week" → "Crimpy" */
const shortRuleName = (headline: string): string => headline.split(' ')[0];

const ordinal = (n: number): string =>
  n === 1 ? '1st' : n === 2 ? '2nd' : n === 3 ? '3rd' : `${n}th`;
