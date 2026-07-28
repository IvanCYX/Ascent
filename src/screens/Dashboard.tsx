import { useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import type { Snapshot } from '../db/store';
import { setSetting } from '../db/store';
import {
  RANGES,
  rangeWindows,
  todayISO,
  weekRangeLabel,
  rangeLabel,
  shortDate,
  weeksBetween,
  weekStart,
  type RangeId,
} from '../domain/dates';
import {
  buildKpis,
  camp5Tally,
  climbsInRange,
  compReadiness,
  boardSummaries,
  heatmapRead,
  intensityAlpha,
  loadRuleUsage,
  pyramidRead,
  rehabAdherence,
  sendPyramid,
  sessionSends,
  styleGradeMatrix,
  topGrades,
  weeksOut,
} from '../domain/metrics';
import { GRADE_BANDS, colourCode, colourHex } from '../domain/vocab';
import { Insight, Meter, SectionHead, Segmented } from '../components/ui';

export default function Dashboard({ snap }: { snap: Snapshot }) {
  const nav = useNavigate();
  const today = todayISO();
  const range = (snap.settings.dashboardRange as RangeId) ?? '8w';
  const [showInsights, setShowInsights] = useState(true);

  const m = useMemo(() => {
    const w = rangeWindows(range, today);
    const cur = climbsInRange(snap.climbs, w.from, w.to);
    const prev = climbsInRange(snap.climbs, w.prevFrom, w.prevTo);
    const sessionsInRange = snap.sessions.filter(
      (s) => s.status === 'done' && s.date >= w.from && s.date <= w.to,
    );
    const rangeWeeks = Math.max(1, weeksBetween(w.from, w.to));

    return {
      w,
      cur,
      prev,
      sessionsInRange,
      rangeWeeks,
      kpis: buildKpis(cur, prev, snap.gyms, sessionsInRange.length, rangeLabel(range).toLowerCase()),
      pyramid: sendPyramid(cur),
      tally: camp5Tally(cur, snap.gyms.find((g) => g.scaleType === 'ranked-colour')?.tags),
      boards: boardSummaries(cur, prev, snap.boards, rangeWeeks),
      heat: styleGradeMatrix(cur),
      readiness: compReadiness(cur, snap.reviews),
    };
  }, [snap, range, today]);

  const comp = [...snap.competitions].sort((a, b) => a.date.localeCompare(b.date))[0];
  const compWeeks = comp ? weeksOut(today, comp.date) : null;

  const activeInjury = snap.injuries.find((i) => i.status === 'active');
  const painSeries = activeInjury
    ? snap.painEntries
        .filter((p) => p.injuryId === activeInjury.id)
        .sort((a, b) => a.date.localeCompare(b.date))
        .slice(-7)
    : [];
  const rehabEx = activeInjury
    ? snap.rehabExercises.filter((e) => e.injuryId === activeInjury.id)
    : [];
  const adherence = rehabAdherence(rehabEx, snap.rehabLogs, 12, today);
  const rehabWeek = activeInjury?.rehabStart
    ? Math.max(1, weeksBetween(activeInjury.rehabStart, today) + 1)
    : null;

  const ruleUsage = loadRuleUsage(
    snap.loadRules.filter((r) => r.maxPerWeek !== null),
    snap.climbs,
    weekStart(today),
  );
  const hotRule = ruleUsage.find((r) => r.blocked) ?? ruleUsage.find((r) => r.nearing);

  const recent = [...m.sessionsInRange].sort((a, b) => b.date.localeCompare(a.date)).slice(0, 5);

  return (
    <div className="screen-desktop" style={{ maxWidth: 1240 }}>
      {/* 1 · Header bar */}
      <div
        className="band"
        style={{
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          gap: 16,
          padding: '18px 26px',
          flexWrap: 'wrap',
        }}
      >
        <div style={{ display: 'flex', alignItems: 'baseline', gap: 15 }}>
          <span style={{ font: '600 15px/1 var(--sans)', letterSpacing: '.14em' }}>SENDLOG</span>
          <span
            className="mono"
            style={{ fontSize: 11, color: 'var(--muted)', letterSpacing: '.06em' }}
          >
            {weekRangeLabel(today)}
          </span>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
          <Segmented
            options={RANGES.map((r) => ({ id: r.id, label: r.label }))}
            value={range}
            onChange={(id) => setSetting('dashboardRange', id)}
          />
          <button className="btn-primary" style={{ padding: '10px 15px' }} onClick={() => nav('/plan')}>
            + Log session
          </button>
        </div>
      </div>

      {/* 2 · KPI row */}
      <div
        className="band kpi-row"
        style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)' }}
      >
        {m.kpis.map((k, i) => (
          <div
            key={k.label}
            style={{
              padding: '18px 24px',
              borderRight: i < 3 ? '1px solid var(--rule)' : undefined,
            }}
          >
            <div className="micro" style={{ marginBottom: 13 }}>
              {k.label}
            </div>
            <div style={{ display: 'flex', alignItems: 'baseline', gap: 9 }}>
              <span className="serif" style={{ fontSize: 44, lineHeight: 0.85 }}>
                {k.value}
              </span>
              <span style={{ font: '400 11px/1 var(--sans)', color: 'var(--muted)' }}>
                {k.caption}
              </span>
            </div>
            <div
              className="mono"
              style={{
                fontSize: 11,
                marginTop: 12,
                color: k.deltaStrong ? 'var(--ink)' : 'var(--muted)',
              }}
            >
              {k.delta}
            </div>
          </div>
        ))}
      </div>

      {/* 3 · Two-column band */}
      <div className="dash-cols" style={{ display: 'grid', gridTemplateColumns: '1.35fr 1fr' }}>
        <div style={{ padding: '22px 26px', borderRight: '1px solid var(--rule)' }}>
          <SectionHead
            title="Send pyramid · numbered gyms"
            note={
              <span style={{ display: 'flex', alignItems: 'center', gap: 15, font: '400 10px/1 var(--sans)' }}>
                <span style={{ display: 'flex', alignItems: 'center', gap: 5 }}>
                  <i style={{ width: 9, height: 9, background: 'var(--ink)', display: 'block' }} />
                  flashed
                </span>
                <span style={{ display: 'flex', alignItems: 'center', gap: 5 }}>
                  <i style={{ width: 9, height: 9, background: 'var(--worked)', display: 'block' }} />
                  worked
                </span>
              </span>
            }
          />
          <div style={{ display: 'flex', flexDirection: 'column', gap: 7 }}>
            {m.pyramid.map((r) => (
              <div key={r.grade} style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
                <span
                  className="serif"
                  style={{ width: 26, fontSize: 15, textAlign: 'right', flex: 'none' }}
                >
                  {r.grade}
                </span>
                <div style={{ flex: 1, height: 20, background: 'var(--track)', display: 'flex' }}>
                  <div style={{ width: `${r.width * 100}%`, background: 'var(--worked)', display: 'flex' }}>
                    <div style={{ width: `${r.flashShare * 100}%`, background: 'var(--ink)' }} />
                  </div>
                </div>
                <span
                  className="mono"
                  style={{ width: 22, fontSize: 12, color: 'var(--muted)', flex: 'none' }}
                >
                  {r.count}
                </span>
              </div>
            ))}
          </div>
          {showInsights && (
            <div onClick={() => setShowInsights(false)} style={{ cursor: 'pointer' }} title="Hide insight">
              <Insight label="Read:">{pyramidRead(m.pyramid)}</Insight>
            </div>
          )}
          {!showInsights && (
            <button className="btn-link" style={{ marginTop: 14 }} onClick={() => setShowInsights(true)}>
              Show reads
            </button>
          )}

          {/* Camp5 · colour tags */}
          <div style={{ marginTop: 20, paddingTop: 18, borderTop: '1px solid var(--rule)' }}>
            <SectionHead title="Camp5 · colour tags" note="RANKED, NOT NUMBERED" />
            <div style={{ display: 'flex', alignItems: 'flex-end', gap: 8, height: 96 }}>
              {m.tally.map((b) => (
                <div
                  key={b.tagId}
                  style={{
                    flex: 1,
                    display: 'flex',
                    flexDirection: 'column',
                    alignItems: 'center',
                    gap: 7,
                  }}
                >
                  <span
                    className="mono"
                    style={{ fontSize: 11, color: b.count ? 'var(--muted)' : 'var(--faint)' }}
                  >
                    {b.count}
                  </span>
                  {b.count === 0 ? (
                    <i style={{ width: '100%', height: 3, background: 'var(--worked)', display: 'block' }} />
                  ) : (
                    <i
                      style={{
                        width: '100%',
                        height: Math.max(6, b.height * 66),
                        background: colourHex(b.tagId),
                        display: 'block',
                        border: b.tagId === 'white' ? '1px solid rgba(0,0,0,.18)' : undefined,
                      }}
                    />
                  )}
                  <em
                    className="mono"
                    style={{
                      fontSize: 9.5,
                      fontStyle: 'normal',
                      color: b.count === 0 ? 'var(--faint)' : 'var(--muted)',
                    }}
                  >
                    {colourCode(b.tagId)}
                  </em>
                </div>
              ))}
            </div>
            <div
              style={{
                marginTop: 12,
                font: '400 11px/1.5 var(--sans)',
                color: 'var(--muted)',
                textWrap: 'pretty',
              }}
            >
              {camp5Read(m.tally)}
            </div>
          </div>
        </div>

        {/* Right column */}
        <div style={{ padding: '22px 26px', display: 'flex', flexDirection: 'column', gap: 22 }}>
          <div>
            <div className="section-title" style={{ marginBottom: 14 }}>
              Board grades · tracked separately
            </div>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
              {m.boards.length === 0 && (
                <div className="empty">No board sends in this range.</div>
              )}
              {m.boards.map((b) => {
                const up = b.prevMaxV !== null && b.maxV !== null && b.maxV > b.prevMaxV;
                return (
                  <div
                    key={b.boardId}
                    className="card"
                    style={{ display: 'flex', alignItems: 'center', gap: 13, padding: '12px 14px' }}
                  >
                    <div
                      style={{
                        width: 34,
                        height: 34,
                        background: 'var(--ink)',
                        display: 'grid',
                        placeItems: 'center',
                        font: '500 10px/1 var(--mono)',
                        color: 'var(--paper)',
                        flex: 'none',
                      }}
                    >
                      {b.code}
                    </div>
                    <div style={{ flex: 1 }}>
                      <div style={{ font: '500 12px/1.2 var(--sans)' }}>
                        {b.name} · {b.angle}°
                      </div>
                      <div className="mono" style={{ fontSize: 10.5, color: 'var(--muted)', marginTop: 5 }}>
                        {b.sends} sends · {b.sessionsPerWeek} sessions/wk
                      </div>
                    </div>
                    <div style={{ textAlign: 'right' }}>
                      <div className="serif" style={{ fontSize: 20 }}>
                        V{b.maxV}
                      </div>
                      <div
                        className="mono"
                        style={{ fontSize: 10, marginTop: 4, color: up ? 'var(--ink)' : 'var(--muted)' }}
                      >
                        {up ? `▲ V${b.prevMaxV}→V${b.maxV}` : '— flat this range'}
                      </div>
                    </div>
                  </div>
                );
              })}
            </div>
          </div>

          {activeInjury && (
            <div>
              <div className="section-title" style={{ marginBottom: 13 }}>
                Injury watch
              </div>
              <div
                style={{
                  padding: '14px 16px',
                  border: '1px solid var(--warn-border)',
                  background: 'rgba(192,57,43,.06)',
                  cursor: 'pointer',
                }}
                onClick={() => nav('/body')}
              >
                <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 10 }}>
                  <span style={{ font: '500 12px/1 var(--sans)' }}>{activeInjury.name}</span>
                  {rehabWeek && (
                    <span
                      className="mono"
                      style={{ fontSize: 10, color: 'var(--warn)', letterSpacing: '.08em', whiteSpace: 'nowrap' }}
                    >
                      REHAB · WK {rehabWeek}
                    </span>
                  )}
                </div>
                <div style={{ display: 'flex', alignItems: 'flex-end', gap: 3, height: 34, margin: '13px 0 8px' }}>
                  {painSeries.map((p, i) => (
                    <div
                      key={p.id}
                      style={{
                        flex: 1,
                        height: `${Math.max(8, (p.level / 10) * 100)}%`,
                        background:
                          i === painSeries.length - 1
                            ? 'var(--warn)'
                            : i === painSeries.length - 2
                              ? 'rgba(192,57,43,.5)'
                              : 'rgba(192,57,43,.25)',
                      }}
                    />
                  ))}
                  {painSeries.length === 0 && <div className="empty">no pain entries yet</div>}
                </div>
                <div
                  className="mono"
                  style={{ display: 'flex', justifyContent: 'space-between', fontSize: 10, color: 'var(--muted)' }}
                >
                  <span>
                    {painSeries.length
                      ? `pain ${painSeries[0].level}/10 → ${painSeries[painSeries.length - 1].level}/10`
                      : 'no pain logged'}
                  </span>
                  <span>{adherence.streak}-day rehab streak</span>
                </div>
              </div>
              {hotRule && (
                <div
                  className="card"
                  style={{
                    marginTop: 10,
                    padding: '12px 15px',
                    font: '400 11.5px/1.5 var(--sans)',
                    color: 'var(--muted)',
                    textWrap: 'pretty',
                  }}
                >
                  <span style={{ color: 'var(--warn)', fontWeight: 600 }}>Load flag · </span>
                  {hotRule.headline} {hotRule.condition}. Used {hotRule.used} of {hotRule.cap} this
                  week{hotRule.blocked ? ' — swap to slopers?' : '.'}
                </div>
              )}
            </div>
          )}

          <div>
            <div className="micro" style={{ marginBottom: 13, fontSize: 11 }}>
              COMP READINESS{compWeeks !== null ? ` · ${compWeeks} WEEKS OUT` : ''}
            </div>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 9 }}>
              {m.readiness.map((r) => (
                <div key={r.label} style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
                  <span
                    style={{
                      width: 104,
                      flex: 'none',
                      font: `${r.warn ? 600 : 400} 12px/1 var(--sans)`,
                      color: r.warn ? 'var(--warn)' : 'var(--ink)',
                    }}
                  >
                    {r.label}
                  </span>
                  <Meter pct={r.score} warn={r.warn} />
                  <span
                    className="mono"
                    style={{
                      fontSize: 11,
                      width: 24,
                      textAlign: 'right',
                      flex: 'none',
                      color: r.warn ? 'var(--warn)' : 'var(--muted)',
                    }}
                  >
                    {r.score}
                  </span>
                </div>
              ))}
            </div>
          </div>
        </div>
      </div>

      {/* 4 · Style × grade heatmap */}
      <div style={{ borderTop: '1px solid rgba(0,0,0,.14)', padding: '22px 26px' }}>
        <SectionHead
          title="Where you send · style × grade"
          note={`SEND RATE % · ${rangeLabel(range).toUpperCase()} · ${m.heat.filter((r) => r.weak).length} GAPS`}
        />
        <div className="scroll-x">
          <div
            style={{
              display: 'grid',
              gridTemplateColumns: '118px repeat(5, minmax(64px, 1fr)) 1.5fr',
              gap: 5,
              alignItems: 'center',
              minWidth: 720,
            }}
          >
            <span />
            {GRADE_BANDS.map((b) => (
              <span key={b.label} className="mono" style={{ fontSize: 9.5, color: 'var(--muted)', textAlign: 'center' }}>
                {b.label}
              </span>
            ))}
            <span />

            {m.heat.map((row) => (
              <HeatRowCells key={row.style} row={row} />
            ))}
          </div>
        </div>
        {showInsights && <Insight label="Comp prep:">{heatmapRead(m.heat, comp?.name)}</Insight>}
      </div>

      {/* 5 · Recent sessions */}
      <div style={{ borderTop: '1px solid rgba(0,0,0,.14)', padding: '20px 26px 32px' }}>
        <div
          style={{
            display: 'flex',
            alignItems: 'baseline',
            justifyContent: 'space-between',
            marginBottom: 14,
          }}
        >
          <span className="section-title">Recent sessions</span>
          <span style={{ font: '400 11px/1 var(--sans)', color: 'var(--muted)' }}>
            {snap.sessions.filter((s) => s.status === 'done').length} logged
          </span>
        </div>
        <div className="scroll-x">
          <div style={{ minWidth: 720 }}>
            <div
              style={{
                display: 'grid',
                gridTemplateColumns: '88px 1.1fr 1fr 70px 1fr 92px',
                font: '500 9.5px/1 var(--sans)',
                letterSpacing: '.1em',
                color: 'var(--muted)',
                paddingBottom: 10,
                borderBottom: '1px solid var(--rule-strong)',
              }}
            >
              <span>DATE</span>
              <span>GYM</span>
              <span>SESSION TYPE</span>
              <span>SENDS</span>
              <span>TOP GRADES</span>
              <span>FELT</span>
            </div>
            {recent.length === 0 && <div className="empty">No sessions in this range.</div>}
            {recent.map((s, i) => {
              const sends = sessionSends(snap.climbs, s.id);
              const boardIds = new Set(
                snap.climbs.filter((c) => c.sessionId === s.id && c.boardId).map((c) => c.boardId!),
              );
              const boardLabel = [...boardIds]
                .map((id) => snap.boards.find((b) => b.id === id)?.name)
                .filter(Boolean)
                .join(' · ');
              const top = topGrades(sends);
              const review = snap.reviews.find((r) => r.sessionId === s.id);
              return (
                <div
                  key={s.id}
                  style={{
                    display: 'grid',
                    gridTemplateColumns: '88px 1.1fr 1fr 70px 1fr 92px',
                    alignItems: 'center',
                    padding: '13px 0',
                    borderBottom: i < recent.length - 1 ? '1px solid var(--rule-light)' : undefined,
                  }}
                >
                  <span className="mono" style={{ fontSize: 11.5, color: 'var(--muted)' }}>
                    {shortDate(s.date)}
                  </span>
                  <span style={{ font: '500 12px/1 var(--sans)' }}>
                    {snap.gyms.find((g) => g.id === s.gymId)?.name ?? '—'}
                  </span>
                  <span style={{ font: '400 11.5px/1.3 var(--sans)', color: 'var(--muted)' }}>
                    {[s.intent, boardLabel].filter(Boolean).join(' · ') || '—'}
                  </span>
                  <span className="serif" style={{ fontSize: 13 }}>
                    {sends.length}
                  </span>
                  <TopGradeCell top={top} />
                  <span style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                    {review ? (
                      <>
                        <Meter pct={review.overallScore * 10} height={5} width={44} />
                        <em className="serif" style={{ fontSize: 13, fontStyle: 'normal' }}>
                          {review.overallScore.toFixed(1)}
                        </em>
                      </>
                    ) : (
                      <span className="mono" style={{ fontSize: 10, color: 'var(--faint)' }}>
                        NOT RATED
                      </span>
                    )}
                  </span>
                </div>
              );
            })}
          </div>
        </div>
      </div>

      <style>{`
        @media (max-width: 900px) {
          .dash-cols { grid-template-columns: 1fr !important; }
          .dash-cols > div { border-right: none !important; border-bottom: 1px solid var(--rule); }
          .kpi-row { grid-template-columns: repeat(2, 1fr) !important; }
          .kpi-row > div:nth-child(2) { border-right: none !important; }
          .kpi-row > div:nth-child(-n+2) { border-bottom: 1px solid var(--rule); }
        }
      `}</style>
    </div>
  );
}

/* ── Heatmap row ────────────────────────────────────────────────────────── */

function HeatRowCells({ row }: { row: ReturnType<typeof styleGradeMatrix>[number] }) {
  return (
    <>
      <span
        style={{
          font: `${row.weak ? 600 : 500} 11.5px/1 var(--sans)`,
          color: row.weak ? 'var(--warn)' : 'var(--ink)',
        }}
      >
        {row.style}
      </span>
      {row.cells.map((cell) => {
        if (cell.pct === null) {
          return (
            <div
              key={cell.band}
              style={{
                height: 34,
                background: 'rgba(0,0,0,.05)',
                display: 'grid',
                placeItems: 'center',
                font: '400 11px/1 var(--mono)',
                color: 'var(--faint)',
              }}
              title="no attempts logged"
            >
              —
            </div>
          );
        }
        const gap = row.weak && cell.pct <= 20;
        const alpha = intensityAlpha(cell.pct);
        return (
          <div
            key={cell.band}
            title={`${cell.attempts} logged · ${cell.pct}% sent`}
            style={{
              height: 34,
              background: gap
                ? `rgba(192,57,43,${cell.pct === 0 ? 0.12 : 0.26})`
                : `rgba(23,21,15,${alpha})`,
              border: gap ? '1px solid rgba(192,57,43,.6)' : undefined,
              display: 'grid',
              placeItems: 'center',
              font: `${cell.pct === 0 ? 600 : 500} 11px/1 var(--mono)`,
              color: gap
                ? cell.pct === 0
                  ? 'var(--warn)'
                  : 'var(--ink)'
                : alpha >= 0.5
                  ? 'var(--paper)'
                  : 'var(--ink)',
            }}
          >
            {cell.pct}
          </div>
        );
      })}
      <span
        style={{
          font: '400 11px/1.4 var(--sans)',
          color: row.weak ? 'var(--warn)' : 'var(--muted)',
          paddingLeft: 10,
        }}
      >
        {row.comment}
      </span>
    </>
  );
}

/* ── Top grades cell — Camp5 never shows numbers ────────────────────────── */

function TopGradeCell({ top }: { top: ReturnType<typeof topGrades> }) {
  if (!top.values.length) return <span className="mono faint" style={{ fontSize: 10 }}>—</span>;

  if (top.kind === 'tag') {
    return (
      <span style={{ display: 'flex', gap: 5, alignItems: 'center' }}>
        {top.values.map((t) => (
          <i
            key={String(t)}
            style={{
              width: 17,
              height: 17,
              background: colourHex(String(t)),
              display: 'block',
              border: t === 'white' ? '1px solid rgba(0,0,0,.18)' : undefined,
            }}
          />
        ))}
        <em className="mono" style={{ fontSize: 10.5, color: 'var(--muted)', fontStyle: 'normal' }}>
          {top.values.map((t) => colourCode(String(t))).join(' · ')}
        </em>
      </span>
    );
  }

  return (
    <span style={{ display: 'flex', gap: 4 }}>
      {top.values.map((v, i) => (
        <i
          key={String(v)}
          style={{
            font: '500 10px/1 var(--mono)',
            fontStyle: 'normal',
            padding: '4px 6px',
            color: i === 0 ? 'var(--paper)' : 'var(--ink)',
            background: i === 0 ? 'var(--ink)' : 'rgba(0,0,0,.09)',
          }}
        >
          {v}
        </i>
      ))}
    </span>
  );
}

/* ── Camp5 read line ────────────────────────────────────────────────────── */

function camp5Read(bars: { tagId: string; count: number; ordinal: number }[]): string {
  const untouched = bars.filter((b) => b.count === 0).sort((a, b) => a.ordinal - b.ordinal);
  const hardestSent = [...bars].filter((b) => b.count > 0).pop();
  if (!hardestSent) return 'No Camp5 sends in this range yet.';
  const name = colourCode(hardestSent.tagId);
  const chase = untouched.find((u) => u.ordinal > hardestSent.ordinal);
  return chase
    ? `${hardestSent.count} ${name.toLowerCase()} tag${hardestSent.count === 1 ? '' : 's'} this range. ${colourCode(chase.tagId)} is still untouched — that is the Camp5 milestone to chase.`
    : `Everything up to ${name.toLowerCase()} has gone this range.`;
}
