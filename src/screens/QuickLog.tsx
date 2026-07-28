import { useEffect, useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import type { Snapshot } from '../db/store';
import { addClimb, deleteClimb, setActiveGym } from '../db/store';
import {
  CLIMB_STYLES,
  HOLD_COLOURS,
  TICK_TYPES,
  colourHex,
  colourLabel,
  type ClimbStyle,
  type TickType,
} from '../domain/vocab';
import { elapsedLabel, timeOfDay, todayISO, weekStart } from '../domain/dates';
import { isFlash, isSend, loadRuleUsage } from '../domain/metrics';
import { Chip, Swatch, WarnPanel } from '../components/ui';
import SessionStarter from '../components/SessionStarter';

export default function QuickLog({ snap }: { snap: Snapshot }) {
  const nav = useNavigate();
  const activeId = snap.settings.activeSessionId as string | null | undefined;
  const session = snap.sessions.find((s) => s.id === activeId && s.status === 'active');
  const gym = snap.gyms.find((g) => g.id === session?.gymId);

  /* Draft — optional fields persist from the previous climb inside a session. */
  const [grade, setGrade] = useState<number | null>(null);
  const [colour, setColour] = useState<string | null>(null);
  const [tickType, setTickType] = useState<TickType>('flash');
  const [styles, setStyles] = useState<ClimbStyle[]>([]);
  const [location, setLocation] = useState('');
  const [showAllGrades, setShowAllGrades] = useState(false);
  const [switching, setSwitching] = useState(false);

  useEffect(() => {
    setGrade(null);
    setColour(null);
  }, [session?.gymId]);

  const climbs = useMemo(
    () => snap.climbs.filter((c) => c.sessionId === session?.id).sort((a, b) => b.createdAt.localeCompare(a.createdAt)),
    [snap.climbs, session?.id],
  );
  const sends = climbs.filter(isSend);
  const gymSends = sends.filter((c) => c.gradeKind !== 'v');
  const flashed = sends.filter(isFlash).length;

  /* Load rules that the current style selection would trip. */
  const usage = useMemo(
    () => loadRuleUsage(snap.loadRules.filter((r) => r.maxPerWeek !== null), snap.climbs, weekStart(todayISO())),
    [snap.loadRules, snap.climbs],
  );
  const tripped = usage.filter(
    (u) =>
      (u.blocked || u.nearing) &&
      styles.includes(
        (snap.loadRules.find((r) => r.id === u.ruleId)?.styleOrType ?? '') as ClimbStyle,
      ),
  );

  if (!session) {
    return <SessionStarter snap={snap} title="Log a send" hint="Start a session to begin logging." />;
  }

  const isCamp5 = gym?.scaleType === 'ranked-colour';

  /* ── Actions ──────────────────────────────────────────────────────────── */

  const save = async () => {
    if (grade === null || !colour || !gym) return;
    await addClimb({
      sessionId: session.id,
      gymId: gym.id,
      gradeKind: 'number',
      grade,
      holdColour: colour,
      styles,
      location: location.trim() || undefined,
      tickType,
      attempts: tickType === 'flash' ? 1 : tickType === 'second-go' ? 2 : 3,
    });
    setGrade(null);
    setColour(null);
  };

  const tally = async (tagId: string, ordinal: number) => {
    await addClimb({
      sessionId: session.id,
      gymId: gym!.id,
      gradeKind: 'tag',
      grade: ordinal,
      tagId,
      holdColour: tagId,
      styles,
      location: location.trim() || undefined,
      tickType,
      attempts: tickType === 'flash' ? 1 : 2,
    });
  };

  const undo = async () => {
    if (climbs[0]) await deleteClimb(climbs[0].id);
  };

  const clearOptional = () => {
    setTickType('flash');
    setStyles([]);
    setLocation('');
  };

  const toggleStyle = (s: ClimbStyle) =>
    setStyles((cur) => (cur.includes(s) ? cur.filter((x) => x !== s) : [...cur, s]));

  /* ── Grade range for this gym ─────────────────────────────────────────── */
  const maxGrade = gym?.maxGrade ?? 15;
  const lowest = showAllGrades ? 1 : Math.max(1, maxGrade - 9);
  const gradeList = Array.from({ length: maxGrade - lowest + 1 }, (_, i) => lowest + i);

  /* A session can span both kinds of scale if you switch gyms mid-way. */
  const highLabel = (() => {
    const tagged = gymSends.filter((c) => c.gradeKind === 'tag');
    if (isCamp5 && tagged.length) {
      const best = tagged.reduce((a, b) => (b.grade > a.grade ? b : a));
      return `${colourLabel(best.tagId).toUpperCase()} TAG`;
    }
    const numbered = gymSends.filter((c) => c.gradeKind === 'number');
    if (numbered.length) return String(Math.max(...numbered.map((c) => c.grade)));
    if (tagged.length) {
      const best = tagged.reduce((a, b) => (b.grade > a.grade ? b : a));
      return `${colourLabel(best.tagId).toUpperCase()} TAG`;
    }
    return '—';
  })();

  return (
    <div className="screen-mobile">
      <div className="status-strip">
        <span>{timeOfDay(new Date().toISOString())}</span>
        <span>
          {gym?.name ?? 'No gym'} · {session.startedAt ? elapsedLabel(session.startedAt) : '0m'}
        </span>
      </div>

      <div style={{ padding: '12px 20px 10px' }}>
        <div
          style={{
            display: 'flex',
            alignItems: 'flex-end',
            justifyContent: 'space-between',
            gap: 12,
            marginBottom: 18,
          }}
        >
          <div>
            <div className="serif" style={{ fontSize: 27, lineHeight: 1 }}>
              {isCamp5 ? 'Tally' : 'Log a send'}
            </div>
            <div className="mono" style={{ fontSize: 10.5, color: 'var(--muted)', marginTop: 8, letterSpacing: '.06em' }}>
              {isCamp5
                ? 'CAMP5 COLOUR TAGS · YELLOW → BLACK'
                : `${gym?.name.toUpperCase()} · SCALE 1–${maxGrade}`}
            </div>
          </div>
          <button
            className="btn-secondary"
            style={{ padding: '8px 11px', font: '500 11px/1 var(--sans)', flex: 'none' }}
            onClick={() => setSwitching((s) => !s)}
          >
            Switch gym
          </button>
        </div>

        {switching && (
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6, marginBottom: 18 }}>
            {snap.gyms.map((g) => (
              <Chip
                key={g.id}
                small
                label={g.name}
                on={g.id === gym?.id}
                onClick={async () => {
                  await setActiveGym(session.id, g.id);
                  setSwitching(false);
                }}
              />
            ))}
          </div>
        )}

        {isCamp5 ? (
          /* ── `1d` Camp5 tally mode — no numbers anywhere ─────────────── */
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
            {(gym?.tags ?? []).map((tagId, i) => {
              const count = climbs.filter((c) => c.tagId === tagId && isSend(c)).length;
              const ordinal = i + 1;
              const suffix =
                ordinal === 1 ? ' · EASIEST' : ordinal === (gym?.tags?.length ?? 8) ? ' · HARDEST' : '';
              return (
                <div
                  key={tagId}
                  className="card"
                  style={{
                    display: 'flex',
                    alignItems: 'center',
                    gap: 12,
                    padding: '11px 13px',
                    border: count > 0 ? '2px solid var(--ink)' : '1px solid var(--rule)',
                  }}
                >
                  <i
                    style={{
                      width: 30,
                      height: 30,
                      background: colourHex(tagId),
                      display: 'block',
                      border: tagId === 'white' ? '1px solid rgba(0,0,0,.18)' : undefined,
                    }}
                  />
                  <div style={{ flex: 1 }}>
                    <div style={{ font: '500 13px/1 var(--sans)' }}>{colourLabel(tagId)}</div>
                    <div className="mono" style={{ fontSize: 10, color: 'var(--muted)', marginTop: 5, letterSpacing: '.06em' }}>
                      TAG {ordinal} OF {gym?.tags?.length ?? 8}
                      {suffix}
                    </div>
                  </div>
                  <span
                    className="mono"
                    style={{ fontSize: 18, color: count ? 'var(--ink)' : 'var(--faint)' }}
                  >
                    {count}
                  </span>
                  <button
                    onClick={() => tally(tagId, ordinal)}
                    aria-label={`Log a ${colourLabel(tagId)} tag`}
                    style={{
                      width: 34,
                      height: 34,
                      display: 'grid',
                      placeItems: 'center',
                      font: '400 17px/1 var(--sans)',
                      flex: 'none',
                      background: count > 0 ? 'var(--ink)' : 'transparent',
                      color: count > 0 ? 'var(--paper)' : 'var(--ink)',
                      border: count > 0 ? '1px solid var(--ink)' : '1px solid var(--rule-chip)',
                    }}
                  >
                    +
                  </button>
                </div>
              );
            })}
            <div style={{ font: '400 11px/1.5 var(--sans)', color: 'var(--muted)', padding: '2px 2px 0' }}>
              Set style, tick type or location below and it sticks to every tag you add. Otherwise it
              just counts.
            </div>
          </div>
        ) : (
          /* ── `3a` numbered gym ────────────────────────────────────────── */
          <>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 10 }}>
              <span className="micro">1 · GRADE</span>
              {maxGrade > 10 && (
                <button className="btn-link" onClick={() => setShowAllGrades((v) => !v)}>
                  {showAllGrades ? `Top 10 only` : `Show 1–${maxGrade}`}
                </button>
              )}
            </div>
            <div className="grade-grid" style={{ marginBottom: 20 }}>
              {gradeList.map((g) => (
                <button
                  key={g}
                  className={`grade-btn${grade === g ? ' on' : ''}`}
                  onClick={() => setGrade(g)}
                >
                  {g}
                </button>
              ))}
            </div>

            <div className="micro" style={{ marginBottom: 10 }}>
              2 · HOLD COLOUR
            </div>
            <div style={{ display: 'flex', gap: 7, marginBottom: 20 }}>
              {HOLD_COLOURS.map((c) => (
                <Swatch
                  key={c.id}
                  colour={c.id}
                  flex
                  size={40}
                  on={colour === c.id}
                  title={c.label}
                  onClick={() => setColour(c.id)}
                />
              ))}
            </div>

            {/* Confirmation bar */}
            <div
              style={{
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'space-between',
                gap: 10,
                padding: '14px 15px',
                background: 'var(--card)',
                border: `2px solid ${grade !== null && colour ? 'var(--ink)' : 'var(--rule)'}`,
                marginBottom: 16,
              }}
            >
              <div style={{ display: 'flex', alignItems: 'center', gap: 11, minWidth: 0 }}>
                <span className="serif" style={{ fontSize: 22 }}>
                  {grade ?? '—'}
                </span>
                <i
                  style={{
                    width: 24,
                    height: 24,
                    display: 'block',
                    flex: 'none',
                    background: colour ? colourHex(colour) : 'rgba(0,0,0,.06)',
                    border: colour === 'white' || !colour ? '1px solid rgba(0,0,0,.18)' : undefined,
                  }}
                />
                <div style={{ minWidth: 0 }}>
                  <div style={{ font: '500 12px/1.2 var(--sans)' }}>
                    {grade !== null && colour
                      ? `Grade ${grade} · ${colourLabel(colour).toLowerCase()}`
                      : 'Pick a grade and a colour'}
                  </div>
                  <div className="mono" style={{ fontSize: 10.5, color: 'var(--muted)', marginTop: 5 }}>
                    {grade !== null && colour ? 'tap send to save' : 'two taps, then send'}
                  </div>
                </div>
              </div>
              <button
                className="btn-primary"
                style={{ padding: '12px 20px', font: '600 13px/1 var(--sans)', flex: 'none' }}
                disabled={grade === null || !colour}
                onClick={save}
              >
                Send
              </button>
            </div>
          </>
        )}

        {tripped.length > 0 && (
          <WarnPanel lead="Load flag" style={{ marginBottom: 14 }}>
            {tripped[0].headline} — used {tripped[0].used} of {tripped[0].cap} this week{' '}
            {tripped[0].blocked ? '. You are at the cap.' : '. One more and you are over.'}
          </WarnPanel>
        )}

        {/* Optional block — kept from the last climb */}
        <div
          style={{
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'space-between',
            margin: isCamp5 ? '20px 0 11px' : '0 0 11px',
          }}
        >
          <span className="micro">OPTIONAL — KEPT FROM LAST CLIMB</span>
          <button className="btn-link" onClick={clearOptional}>
            Clear
          </button>
        </div>
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6, marginBottom: 12 }}>
          {TICK_TYPES.map((t) => (
            <Chip
              key={t.id}
              small
              label={t.label}
              on={tickType === t.id}
              onClick={() => setTickType(t.id)}
            />
          ))}
        </div>
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6, marginBottom: 12 }}>
          {CLIMB_STYLES.map((s) => (
            <Chip key={s} small label={s} on={styles.includes(s)} onClick={() => toggleStyle(s)} />
          ))}
        </div>
        <div className="field">
          <label htmlFor="where">WHERE</label>
          <input
            id="where"
            value={location}
            placeholder="cave, right of the arête"
            onChange={(e) => setLocation(e.target.value)}
          />
        </div>
      </div>

      {/* Footer — tonight's log */}
      <div style={{ borderTop: '1px solid rgba(0,0,0,.14)', padding: '14px 20px 24px' }}>
        <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', marginBottom: 12 }}>
          <span className="serif" style={{ fontSize: 17 }}>
            This session · {sends.length} send{sends.length === 1 ? '' : 's'}
          </span>
          <span className="mono" style={{ fontSize: 10.5, color: 'var(--muted)' }}>
            HIGH {highLabel} · {flashed} FLASHED
          </span>
        </div>

        <div style={{ display: 'flex', flexDirection: 'column', gap: 7 }}>
          {climbs.length === 0 && <div className="empty">Nothing logged yet tonight.</div>}
          {climbs.slice(0, 6).map((c) => (
            <div key={c.id} style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
              <span className="serif" style={{ width: 24, fontSize: 15, flex: 'none' }}>
                {c.gradeKind === 'tag' ? '' : c.gradeKind === 'v' ? `V${c.grade}` : c.grade}
              </span>
              <i
                style={{
                  width: 15,
                  height: 15,
                  display: 'block',
                  flex: 'none',
                  background: colourHex(c.holdColour),
                  border: c.holdColour === 'white' ? '1px solid rgba(0,0,0,.18)' : undefined,
                }}
              />
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
                {[
                  c.styles.join(' + ') || undefined,
                  c.tickType === 'flash' ? 'flash' : `${c.attempts} tries`,
                  c.location,
                ]
                  .filter(Boolean)
                  .join(' · ')}
              </span>
              <span className="mono" style={{ fontSize: 10.5, color: 'var(--faint)', flex: 'none' }}>
                {timeOfDay(c.createdAt)}
              </span>
            </div>
          ))}
        </div>

        {climbs.length > 0 && (
          <button className="btn-link" style={{ marginTop: 12, display: 'inline-block' }} onClick={undo}>
            Undo last
          </button>
        )}

        <div style={{ display: 'flex', gap: 8, marginTop: 16 }}>
          <button className="btn-secondary" style={{ flex: 1 }} onClick={() => nav('/board')}>
            Board log
          </button>
          <button className="btn-primary" style={{ flex: 1 }} onClick={() => nav('/review')}>
            End &amp; rate
          </button>
        </div>
      </div>
    </div>
  );
}
