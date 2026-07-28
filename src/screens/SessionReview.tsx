import { useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import type { Snapshot } from '../db/store';
import { addPainEntry, createInjury, endSession, saveReview, updateSession } from '../db/store';
import { REVIEW_CHIPS, SESSION_INTENTS, BODY_PARTS, type SessionIntent } from '../domain/vocab';
import { timeOfDay, todayISO } from '../domain/dates';
import { chipTrends, chipPattern, sessionSends } from '../domain/metrics';
import { Chip, ScoreSlider } from '../components/ui';
import ChipTrendPanel from '../components/ChipTrendPanel';
import SessionStarter from '../components/SessionStarter';

export default function SessionReview({ snap }: { snap: Snapshot }) {
  const nav = useNavigate();
  const activeId = snap.settings.activeSessionId as string | null | undefined;

  /* Review the live session; if none, review the most recent finished one. */
  const session =
    snap.sessions.find((s) => s.id === activeId && s.status === 'active') ??
    [...snap.sessions].filter((s) => s.status === 'done').pop();

  const existing = snap.reviews.find((r) => r.sessionId === session?.id);
  const [chips, setChips] = useState<string[]>(existing?.chips ?? []);
  const [score, setScore] = useState<number>(existing?.overallScore ?? 6.8);
  const [note, setNote] = useState(existing?.note ?? '');
  const [painLevels, setPainLevels] = useState<Record<string, number>>({});
  const [newPain, setNewPain] = useState(false);
  const [newPainName, setNewPainName] = useState('');
  const [newPainPart, setNewPainPart] = useState<string>(BODY_PARTS[6].id);
  const [intent, setIntent] = useState<SessionIntent | undefined>(session?.intent);
  const [saved, setSaved] = useState(false);

  const avgScore = useMemo(() => {
    if (!snap.reviews.length) return null;
    return (
      Math.round((snap.reviews.reduce((a, r) => a + r.overallScore, 0) / snap.reviews.length) * 10) /
      10
    );
  }, [snap.reviews]);

  const trends = useMemo(() => chipTrends(snap.reviews, snap.sessions), [snap.reviews, snap.sessions]);

  if (!session) {
    return <SessionStarter snap={snap} title="How did that feel?" hint="Nothing to review yet — start a session first." />;
  }

  const gym = snap.gyms.find((g) => g.id === session.gymId);
  /* One chip per *active* injury — watching ones stay on the body log until escalated. */
  const activeInjuries = snap.injuries.filter((i) => i.status === 'active');
  const sends = sessionSends(snap.climbs, session.id).length;

  const toggle = (c: string) =>
    setChips((cur) => (cur.includes(c) ? cur.filter((x) => x !== c) : [...cur, c]));

  const cyclePain = (injuryId: string) => {
    setPainLevels((cur) => {
      const next = ((cur[injuryId] ?? 0) + 1) % 11;
      return { ...cur, [injuryId]: next };
    });
    setChips((cur) => cur.filter((c) => c !== 'No pain'));
  };

  const save = async () => {
    const painChips = Object.entries(painLevels)
      .filter(([, level]) => level > 0)
      .map(([id, level]) => `${shortInjury(snap.injuries.find((i) => i.id === id)?.name ?? '')} · ${level}/10`);

    await saveReview(session.id, [...chips, ...painChips], score, note.trim() || undefined);

    for (const [injuryId, level] of Object.entries(painLevels)) {
      if (level > 0) await addPainEntry(injuryId, level, session.id, todayISO());
    }
    if (chips.includes('No pain')) {
      for (const inj of snap.injuries.filter((i) => i.status === 'active')) {
        await addPainEntry(inj.id, 0, session.id, todayISO());
      }
    }
    if (intent && intent !== session.intent) await updateSession(session.id, { intent });
    if (session.status === 'active') await endSession(session.id);
    setSaved(true);
  };

  const addNewPain = async () => {
    if (!newPainName.trim()) return;
    const id = await createInjury({
      bodyPart: newPainPart,
      name: newPainName.trim(),
      onsetDate: todayISO(),
      status: 'watching',
    });
    setPainLevels((cur) => ({ ...cur, [id]: 3 }));
    setNewPain(false);
    setNewPainName('');
  };

  return (
    <div className="screen-mobile">
      <div className="status-strip">
        <span>{timeOfDay(new Date().toISOString())}</span>
        <span>
          {gym?.name ?? '—'}
          {session.intent ? ` · ${session.intent.toLowerCase()}` : ''}
        </span>
      </div>

      <div style={{ padding: '12px 20px 6px' }}>
        <div className="serif" style={{ fontSize: 27, lineHeight: 1 }}>
          How did that feel?
        </div>
        <div style={{ font: '400 11px/1.4 var(--sans)', color: 'var(--muted)', marginTop: 8 }}>
          Tap what applies. Nothing is required. {sends} send{sends === 1 ? '' : 's'} logged.
        </div>

        {!session.intent && (
          <>
            <div className="micro" style={{ margin: '20px 0 9px' }}>
              SESSION TYPE
            </div>
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6 }}>
              {SESSION_INTENTS.map((i) => (
                <Chip key={i} small label={i} on={intent === i} onClick={() => setIntent(i)} />
              ))}
            </div>
          </>
        )}

        {(['BODY', 'HEAD', 'EXECUTION'] as const).map((group) => (
          <div key={group}>
            <div className="micro" style={{ margin: '20px 0 9px' }}>
              {group}
            </div>
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6 }}>
              {REVIEW_CHIPS[group].map((c) => (
                <Chip key={c} label={c} on={chips.includes(c)} onClick={() => toggle(c)} />
              ))}
            </div>
          </div>
        ))}

        {/* PAIN — chips generated from the injury log */}
        <div className="micro" style={{ margin: '20px 0 9px' }}>
          PAIN
        </div>
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6 }}>
          <Chip
            label="No pain"
            on={chips.includes('No pain')}
            onClick={() => {
              toggle('No pain');
              setPainLevels({});
            }}
          />
          {activeInjuries.map((inj) => {
            const level = painLevels[inj.id] ?? 0;
            return (
              <Chip
                key={inj.id}
                pain
                on={level > 0}
                label={`${shortInjury(inj.name)} · ${level}/10`}
                title="Tap to raise the level"
                onClick={() => cyclePain(inj.id)}
              />
            );
          })}
          <Chip dashed label="+ new pain" onClick={() => setNewPain((v) => !v)} />
        </div>

        {newPain && (
          <div className="card" style={{ marginTop: 10, padding: 14 }}>
            <div className="micro" style={{ marginBottom: 10 }}>
              NEW — GOES STRAIGHT INTO THE BODY LOG
            </div>
            <div className="field" style={{ marginBottom: 8 }}>
              <label>WHAT</label>
              <input
                value={newPainName}
                placeholder="R shoulder · front deltoid"
                onChange={(e) => setNewPainName(e.target.value)}
              />
            </div>
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 5, marginBottom: 12 }}>
              {BODY_PARTS.map((p) => (
                <Chip
                  key={p.id}
                  small
                  label={p.label}
                  on={newPainPart === p.id}
                  onClick={() => setNewPainPart(p.id)}
                />
              ))}
            </div>
            <button className="btn-primary" style={{ width: '100%' }} onClick={addNewPain}>
              Add to the log
            </button>
          </div>
        )}

        {/* Overall score */}
        <div className="card" style={{ marginTop: 20, padding: 16 }}>
          <div
            style={{
              display: 'flex',
              alignItems: 'baseline',
              justifyContent: 'space-between',
              marginBottom: 14,
            }}
          >
            <span className="micro">OVERALL SESSION</span>
            <span className="serif" style={{ fontSize: 30 }}>
              {score.toFixed(1)}
            </span>
          </div>
          <ScoreSlider value={score} onChange={setScore} />
          <div
            className="mono"
            style={{
              display: 'flex',
              justifyContent: 'space-between',
              marginTop: 10,
              fontSize: 10,
              color: 'var(--muted)',
            }}
          >
            <span>ROUGH</span>
            <span>{avgScore === null ? 'NO AVG YET' : `AVG ${avgScore.toFixed(1)}`}</span>
            <span>BEST</span>
          </div>
        </div>

        <textarea
          className="note-box"
          style={{ marginTop: 11 }}
          value={note}
          placeholder="Anything worth remembering about tonight…"
          onChange={(e) => setNote(e.target.value)}
        />
      </div>

      <div style={{ padding: '16px 20px 24px' }}>
        <button className="btn-primary" style={{ width: '100%', padding: '15px 0' }} onClick={save}>
          {saved ? 'Saved · update review' : 'Save review'}
        </button>
        {saved && (
          <>
            <div style={{ marginTop: 20 }}>
              <ChipTrendPanel rows={trends} pattern={chipPattern(trends)} />
            </div>
            <div style={{ display: 'flex', gap: 8, marginTop: 16 }}>
              <button className="btn-secondary" style={{ flex: 1 }} onClick={() => nav('/body')}>
                Body log
              </button>
              <button className="btn-secondary" style={{ flex: 1 }} onClick={() => nav('/')}>
                Dashboard
              </button>
            </div>
          </>
        )}
      </div>
    </div>
  );
}

/** "Left ring finger · A2 pulley strain" → "L ring finger" */
export function shortInjury(name: string): string {
  const head = name.split('·')[0].trim();
  return head.replace(/^Left /, 'L ').replace(/^Right /, 'R ');
}
