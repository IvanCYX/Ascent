import { useMemo, useState } from 'react';
import type { Snapshot } from '../db/store';
import {
  addLoadRule,
  addPainEntry,
  addRehabExercise,
  createInjury,
  deleteLoadRule,
  toggleRehabLog,
  updateInjury,
} from '../db/store';
import { BODY_PARTS, CLIMB_STYLES, type ClimbStyle } from '../domain/vocab';
import { prettyDate, shortDate, todayISO, weekStart, weeksBetween } from '../domain/dates';
import { loadRuleUsage, rehabAdherence } from '../domain/metrics';
import BodyMap, { type BodyStatus } from '../components/BodyMap';
import { Chip, PageHead } from '../components/ui';

export default function Injuries({ snap }: { snap: Snapshot }) {
  const today = todayISO();
  const [filter, setFilter] = useState<string | null>(null);
  const [adding, setAdding] = useState(false);
  const [draftName, setDraftName] = useState('');
  const [draftPart, setDraftPart] = useState<string>(BODY_PARTS[6].id);
  const [draftStatus, setDraftStatus] = useState<'active' | 'watching'>('watching');
  const [newRule, setNewRule] = useState<{ style: ClimbStyle; cap: number } | null>(null);
  const [newEx, setNewEx] = useState<{ name: string; prescription: string } | null>(null);

  const bodyStatus = useMemo(() => {
    const map: Record<string, BodyStatus> = {};
    for (const inj of snap.injuries) {
      if (inj.status === 'resolved') continue;
      const cur = map[inj.bodyPart];
      if (inj.status === 'active' || cur !== 'active') {
        map[inj.bodyPart] = inj.status === 'active' ? 'active' : 'watching';
      }
    }
    return map;
  }, [snap.injuries]);

  const visible = snap.injuries
    .filter((i) => i.status !== 'resolved')
    .filter((i) => !filter || i.bodyPart === filter);

  const active = visible.filter((i) => i.status === 'active');
  const watching = visible.filter((i) => i.status === 'watching');
  const shown = active.length ? active : visible;

  const activeCount = snap.injuries.filter((i) => i.status === 'active').length;
  const watchingCount = snap.injuries.filter((i) => i.status === 'watching').length;

  return (
    <div className="screen-desktop" style={{ maxWidth: 860 }}>
      <PageHead
        eyebrow="BODY LOG"
        title={`${activeCount} active · ${watchingCount} watching`}
        right={
          <button className="btn-primary" style={{ padding: '11px 16px' }} onClick={() => setAdding((v) => !v)}>
            + Log something new
          </button>
        }
      />

      {adding && (
        <div style={{ padding: '18px 28px', borderBottom: '1px solid var(--rule)', background: 'var(--card)' }}>
          <div className="micro" style={{ marginBottom: 12 }}>
            NEW ENTRY
          </div>
          <div className="field" style={{ marginBottom: 10 }}>
            <label>WHAT</label>
            <input
              value={draftName}
              placeholder="Left ring finger · A2 pulley strain"
              onChange={(e) => setDraftName(e.target.value)}
            />
          </div>
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 5, marginBottom: 12 }}>
            {BODY_PARTS.map((p) => (
              <Chip key={p.id} small label={p.label} on={draftPart === p.id} onClick={() => setDraftPart(p.id)} />
            ))}
          </div>
          <div style={{ display: 'flex', gap: 6, alignItems: 'center' }}>
            <Chip small label="Active" on={draftStatus === 'active'} onClick={() => setDraftStatus('active')} />
            <Chip small label="Watching" on={draftStatus === 'watching'} onClick={() => setDraftStatus('watching')} />
            <button
              className="btn-primary"
              onClick={async () => {
                if (!draftName.trim()) return;
                await createInjury({
                  bodyPart: draftPart,
                  name: draftName.trim(),
                  onsetDate: today,
                  status: draftStatus,
                  rehabStart: draftStatus === 'active' ? today : undefined,
                });
                setDraftName('');
                setAdding(false);
              }}
            >
              Add
            </button>
          </div>
        </div>
      )}

      <div className="injury-cols" style={{ display: 'grid', gridTemplateColumns: '236px 1fr' }}>
        {/* Left rail — body map */}
        <div style={{ padding: '22px 24px', borderRight: '1px solid var(--rule)' }}>
          <div className="micro" style={{ marginBottom: 18 }}>
            TAP THE AREA
          </div>
          <BodyMap status={bodyStatus} selected={filter} onSelect={setFilter} />
          <div
            style={{
              display: 'flex',
              flexDirection: 'column',
              gap: 8,
              marginTop: 16,
              font: '400 11px/1.35 var(--sans)',
            }}
          >
            <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
              <i style={{ width: 11, height: 11, borderRadius: 3, background: 'var(--warn)', display: 'block', flex: 'none' }} />
              Active — {snap.injuries.filter((i) => i.status === 'active').map(shortLabel).join(', ') || 'none'}
            </div>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
              <i style={{ width: 11, height: 11, borderRadius: 3, background: '#f2c744', display: 'block', flex: 'none' }} />
              Watching — {snap.injuries.filter((i) => i.status === 'watching').map(shortLabel).join(', ') || 'none'}
            </div>
            {filter && (
              <button className="btn-link" style={{ marginTop: 4 }} onClick={() => setFilter(null)}>
                Clear filter
              </button>
            )}
          </div>
        </div>

        {/* Right — injury detail */}
        <div style={{ padding: '22px 26px 34px' }}>
          {shown.length === 0 && (
            <div className="empty">Nothing logged for this area. Tap another part, or clear the filter.</div>
          )}

          {shown.map((inj) => {
            const pain = snap.painEntries
              .filter((p) => p.injuryId === inj.id)
              .sort((a, b) => a.date.localeCompare(b.date))
              .slice(-12);
            const ex = snap.rehabExercises.filter((e) => e.injuryId === inj.id);
            const adh = rehabAdherence(ex, snap.rehabLogs, 12, today);
            const rehabWeek = inj.rehabStart ? Math.max(1, weeksBetween(inj.rehabStart, today) + 1) : null;
            const rules = snap.loadRules.filter((r) => r.injuryId === inj.id);
            const usage = loadRuleUsage(
              rules.filter((r) => r.maxPerWeek !== null),
              snap.climbs,
              weekStart(today),
            );

            return (
              <div key={inj.id} style={{ marginBottom: 26 }}>
                <div style={{ padding: '16px 18px', border: '1px solid rgba(0,0,0,.18)', marginBottom: 16 }}>
                  <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', gap: 14 }}>
                    <div>
                      <div className="serif" style={{ fontSize: 21, lineHeight: 1.1 }}>
                        {inj.name}
                      </div>
                      <div style={{ font: '400 11px/1.4 var(--sans)', color: 'var(--muted)', marginTop: 7 }}>
                        Onset {prettyDate(inj.onsetDate)}
                        {inj.severity ? ` · ${inj.severity}` : ''}
                        {inj.diagnosis ? ` · ${inj.diagnosis}` : ''}
                      </div>
                    </div>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 10, flex: 'none' }}>
                      {rehabWeek && inj.status === 'active' && (
                        <span className="mono" style={{ fontSize: 10, color: 'var(--warn)', letterSpacing: '.1em', whiteSpace: 'nowrap' }}>
                          REHAB WK {rehabWeek}
                        </span>
                      )}
                      <button
                        className="btn-link"
                        onClick={() =>
                          updateInjury(inj.id, {
                            status: inj.status === 'active' ? 'watching' : inj.status === 'watching' ? 'resolved' : 'active',
                          })
                        }
                      >
                        {inj.status === 'active' ? 'Downgrade' : inj.status === 'watching' ? 'Resolve' : 'Reopen'}
                      </button>
                    </div>
                  </div>

                  <div className="pain-cols" style={{ display: 'grid', gridTemplateColumns: '1.5fr 1fr', gap: 22, marginTop: 18 }}>
                    {/* Pain by session */}
                    <div>
                      <div className="micro" style={{ marginBottom: 11, letterSpacing: '.1em' }}>
                        PAIN 0–10 · BY SESSION
                      </div>
                      <div
                        style={{
                          display: 'flex',
                          alignItems: 'flex-end',
                          gap: 4,
                          height: 66,
                          borderBottom: '1px solid rgba(0,0,0,.2)',
                        }}
                      >
                        {pain.length === 0 && <div className="empty">no entries yet</div>}
                        {pain.map((p, i) => (
                          <div
                            key={p.id}
                            title={`${shortDate(p.date)} · ${p.level}/10`}
                            style={{
                              flex: 1,
                              height: `${Math.max(6, (p.level / 10) * 100)}%`,
                              background:
                                i >= pain.length - 2 ? 'var(--warn)' : i === pain.length - 3 ? 'rgba(192,57,43,.5)' : 'rgba(192,57,43,.28)',
                            }}
                          />
                        ))}
                      </div>
                      {pain.length > 0 && (
                        <div
                          className="mono"
                          style={{ display: 'flex', justifyContent: 'space-between', marginTop: 8, fontSize: 10, color: 'var(--muted)' }}
                        >
                          <span>
                            {shortDate(pain[0].date)} · {pain[0].level}/10
                          </span>
                          <span>NOW · {pain[pain.length - 1].level}/10</span>
                        </div>
                      )}
                      <div style={{ display: 'flex', gap: 4, marginTop: 12, flexWrap: 'wrap', alignItems: 'center' }}>
                        <span className="mono" style={{ fontSize: 10, color: 'var(--muted)' }}>
                          LOG TODAY
                        </span>
                        {[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10].map((n) => (
                          <button
                            key={n}
                            onClick={() => addPainEntry(inj.id, n, undefined, today)}
                            className="mono"
                            style={{
                              width: 22,
                              height: 22,
                              display: 'grid',
                              placeItems: 'center',
                              fontSize: 10,
                              border: '1px solid var(--rule-chip)',
                              background: 'var(--card)',
                            }}
                          >
                            {n}
                          </button>
                        ))}
                      </div>
                    </div>

                    {/* Adherence */}
                    <div>
                      <div className="micro" style={{ marginBottom: 11, letterSpacing: '.1em' }}>
                        ADHERENCE
                      </div>
                      <div className="serif" style={{ fontSize: 34, lineHeight: 1 }}>
                        {adh.streak}
                        <span style={{ fontSize: 15, color: 'var(--muted)' }}> day streak</span>
                      </div>
                      <div style={{ display: 'flex', gap: 3, marginTop: 12 }}>
                        {adh.days.map((d) => (
                          <i
                            key={d.date}
                            title={shortDate(d.date)}
                            style={{
                              flex: 1,
                              height: 20,
                              display: 'block',
                              background: d.done ? 'var(--ink)' : 'rgba(0,0,0,.12)',
                            }}
                          />
                        ))}
                      </div>
                      <div style={{ font: '400 10px/1.4 var(--sans)', color: 'var(--muted)', marginTop: 8 }}>
                        {adh.doneDays} of {adh.total} days
                        {adh.missedLabel ? ` · missed ${prettyDate(adh.missedLabel)}` : ''}
                      </div>
                    </div>
                  </div>
                </div>

                {/* Protocol + rules */}
                <div className="rehab-cols" style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 20 }}>
                  <div>
                    <div className="serif" style={{ fontSize: 17, marginBottom: 13 }}>
                      Rehab protocol
                    </div>
                    <div style={{ display: 'flex', flexDirection: 'column', gap: 9 }}>
                      {ex.length === 0 && <div className="empty">No exercises yet.</div>}
                      {ex.map((e) => {
                        const doneToday = snap.rehabLogs.some(
                          (l) => l.exerciseId === e.id && l.date === today && l.done,
                        );
                        const thisWeek = snap.rehabLogs.filter(
                          (l) => l.exerciseId === e.id && l.date >= weekStart(today) && l.done,
                        ).length;
                        const status =
                          e.frequency >= 7
                            ? doneToday
                              ? 'DONE'
                              : 'DUE'
                            : `${Math.min(thisWeek, e.frequency)} OF ${e.frequency}`;
                        return (
                          <button
                            key={e.id}
                            onClick={() => toggleRehabLog(e.id, today)}
                            className="card"
                            style={{ display: 'flex', alignItems: 'center', gap: 11, padding: '11px 13px', width: '100%' }}
                          >
                            <i
                              style={{
                                width: 16,
                                height: 16,
                                display: 'block',
                                flex: 'none',
                                background: doneToday ? 'var(--ink)' : 'transparent',
                                border: doneToday ? '1px solid var(--ink)' : '1px solid rgba(0,0,0,.3)',
                              }}
                            />
                            <div style={{ flex: 1 }}>
                              <div style={{ font: '500 12px/1.3 var(--sans)' }}>{e.name}</div>
                              <div className="mono" style={{ fontSize: 10.5, color: 'var(--muted)', marginTop: 5 }}>
                                {e.prescription}
                              </div>
                            </div>
                            <span
                              className="mono"
                              style={{ fontSize: 10, color: status === 'DUE' ? 'var(--warn)' : 'var(--muted)', flex: 'none' }}
                            >
                              {status}
                            </span>
                          </button>
                        );
                      })}
                      {newEx ? (
                        <div className="card" style={{ padding: 12 }}>
                          <div className="field" style={{ marginBottom: 8, border: 'none', padding: 0 }}>
                            <label>NAME</label>
                            <input
                              value={newEx.name}
                              placeholder="Tendon glides"
                              onChange={(e) => setNewEx({ ...newEx, name: e.target.value })}
                            />
                          </div>
                          <div className="field" style={{ marginBottom: 10, border: 'none', padding: 0 }}>
                            <label>DOSE</label>
                            <input
                              value={newEx.prescription}
                              placeholder="2 × 10 · MORNING & NIGHT"
                              onChange={(e) => setNewEx({ ...newEx, prescription: e.target.value })}
                            />
                          </div>
                          <button
                            className="btn-primary"
                            style={{ width: '100%' }}
                            onClick={async () => {
                              if (!newEx.name.trim()) return;
                              await addRehabExercise({
                                injuryId: inj.id,
                                name: newEx.name.trim(),
                                prescription: newEx.prescription.trim().toUpperCase() || 'DAILY',
                                frequency: 7,
                              });
                              setNewEx(null);
                            }}
                          >
                            Add exercise
                          </button>
                        </div>
                      ) : (
                        <button
                          className="btn-link"
                          onClick={() => setNewEx({ name: '', prescription: '' })}
                          style={{ alignSelf: 'flex-start' }}
                        >
                          + Add exercise
                        </button>
                      )}
                    </div>
                  </div>

                  <div>
                    <div className="serif" style={{ fontSize: 17, marginBottom: 13 }}>
                      Load rules &amp; notes
                    </div>
                    {rules.map((r) => {
                      const u = usage.find((x) => x.ruleId === r.id);
                      const capped = r.maxPerWeek !== null;
                      return (
                        <div
                          key={r.id}
                          style={{
                            padding: '13px 15px',
                            marginBottom: 11,
                            background: capped ? 'rgba(192,57,43,.08)' : 'var(--card)',
                            border: capped ? '1px solid rgba(192,57,43,.35)' : '1px solid var(--rule)',
                          }}
                        >
                          <div
                            style={{
                              display: 'flex',
                              justifyContent: 'space-between',
                              gap: 8,
                              font: `600 11.5px/1.3 var(--sans)`,
                              color: capped ? 'var(--warn)' : 'var(--ink)',
                              marginBottom: 8,
                            }}
                          >
                            <span>{r.headline}</span>
                            <button className="btn-link" style={{ color: 'var(--faint)' }} onClick={() => deleteLoadRule(r.id)}>
                              ×
                            </button>
                          </div>
                          {capped && u && (
                            <div style={{ display: 'flex', gap: 4, marginBottom: 8 }}>
                              {Array.from({ length: r.maxPerWeek! + 1 }, (_, i) => (
                                <i
                                  key={i}
                                  style={{
                                    width: 28,
                                    height: 8,
                                    display: 'block',
                                    background: i < u.used ? 'var(--warn)' : 'rgba(0,0,0,.12)',
                                  }}
                                />
                              ))}
                            </div>
                          )}
                          <div style={{ font: '400 11px/1.45 var(--sans)', color: 'var(--muted)', textWrap: 'pretty' }}>
                            {capped && u
                              ? `Used ${u.used} of ${r.maxPerWeek} this week ${r.condition}. Planning a ${r.styleOrType.toLowerCase()} day will warn you.`
                              : `In force ${r.condition}.`}
                          </div>
                        </div>
                      );
                    })}

                    {newRule ? (
                      <div className="card" style={{ padding: 12, marginBottom: 11 }}>
                        <div className="micro" style={{ marginBottom: 10 }}>
                          CAP A STYLE
                        </div>
                        <div style={{ display: 'flex', flexWrap: 'wrap', gap: 5, marginBottom: 10 }}>
                          {CLIMB_STYLES.map((s) => (
                            <Chip key={s} small label={s} on={newRule.style === s} onClick={() => setNewRule({ ...newRule, style: s })} />
                          ))}
                        </div>
                        <div className="field" style={{ marginBottom: 10 }}>
                          <label>MAX / WEEK</label>
                          <input
                            type="number"
                            min={0}
                            max={7}
                            value={newRule.cap}
                            onChange={(e) => setNewRule({ ...newRule, cap: Number(e.target.value) })}
                          />
                        </div>
                        <button
                          className="btn-primary"
                          style={{ width: '100%' }}
                          onClick={async () => {
                            await addLoadRule({
                              injuryId: inj.id,
                              styleOrType: newRule.style,
                              maxPerWeek: newRule.cap,
                              condition: `while ${shortLabel(inj)} is above 1/10`,
                              headline: `${newRule.style} sessions · max ${newRule.cap} per week`,
                            });
                            setNewRule(null);
                          }}
                        >
                          Add rule
                        </button>
                      </div>
                    ) : (
                      <button className="btn-link" onClick={() => setNewRule({ style: 'Crimpy', cap: 2 })}>
                        + Add load rule
                      </button>
                    )}

                    {(inj.physioNext || inj.physioNote) && (
                      <div style={{ padding: '13px 15px', border: '1px dashed rgba(0,0,0,.25)', marginTop: 11 }}>
                        {inj.physioNext && (
                          <div className="micro" style={{ marginBottom: 9, letterSpacing: '.1em' }}>
                            PHYSIO · NEXT {prettyDate(inj.physioNext).toUpperCase()}
                          </div>
                        )}
                        {inj.physioNote && (
                          <div style={{ font: '400 12px/1.5 var(--sans)', textWrap: 'pretty' }}>
                            “{inj.physioNote}”
                          </div>
                        )}
                      </div>
                    )}
                  </div>
                </div>
              </div>
            );
          })}

          {watching.length > 0 && active.length > 0 && !filter && (
            <div style={{ paddingTop: 18, borderTop: '1px solid var(--rule)' }}>
              <div className="micro" style={{ marginBottom: 12 }}>
                WATCHING
              </div>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
                {watching.map((w) => (
                  <div
                    key={w.id}
                    className="card"
                    style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '11px 14px' }}
                  >
                    <i style={{ width: 11, height: 11, borderRadius: 3, background: '#f2c744', display: 'block', flex: 'none' }} />
                    <span style={{ flex: 1, font: '500 12px/1.3 var(--sans)' }}>{w.name}</span>
                    <span className="mono" style={{ fontSize: 10, color: 'var(--muted)' }}>
                      SINCE {prettyDate(w.onsetDate).toUpperCase()}
                    </span>
                    <button className="btn-link" onClick={() => updateInjury(w.id, { status: 'active', rehabStart: today })}>
                      Escalate
                    </button>
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>
      </div>

      <style>{`
        @media (max-width: 760px) {
          .injury-cols { grid-template-columns: 1fr !important; }
          .injury-cols > div:first-child { border-right: none !important; border-bottom: 1px solid var(--rule); }
          .pain-cols, .rehab-cols { grid-template-columns: 1fr !important; }
        }
      `}</style>
    </div>
  );
}

const shortLabel = (inj: { name: string }): string => {
  const head = inj.name.split('·')[0].trim();
  return head.replace(/^Left /, 'L ').replace(/^Right /, 'R ');
};
