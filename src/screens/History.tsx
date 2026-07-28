import { useMemo } from 'react';
import type { Snapshot } from '../db/store';
import { chipPattern, chipTrends, sessionSends, topGrades } from '../domain/metrics';
import { shortDate } from '../domain/dates';
import ChipTrendPanel from '../components/ChipTrendPanel';
import { Meter, PageHead } from '../components/ui';
import { colourCode, colourHex } from '../domain/vocab';

/** `1g` as its own history view, plus the full session ledger. */
export default function History({ snap }: { snap: Snapshot }) {
  const trends = useMemo(() => chipTrends(snap.reviews, snap.sessions), [snap.reviews, snap.sessions]);
  const sessions = useMemo(
    () => [...snap.sessions].filter((s) => s.status === 'done').sort((a, b) => b.date.localeCompare(a.date)),
    [snap.sessions],
  );

  return (
    <div className="screen-desktop" style={{ maxWidth: 860 }}>
      <PageHead
        eyebrow="HISTORY"
        title={`${sessions.length} sessions logged`}
        right={
          <span className="mono" style={{ fontSize: 10, color: 'var(--muted)', letterSpacing: '.08em' }}>
            EVERY SESSION, NEWEST FIRST
          </span>
        }
      />

      <div style={{ padding: '22px 28px', borderBottom: '1px solid var(--rule)' }}>
        <ChipTrendPanel rows={trends} pattern={chipPattern(trends)} />
      </div>

      <div style={{ padding: '22px 28px 40px' }}>
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
        {sessions.map((s) => {
          const sends = sessionSends(snap.climbs, s.id);
          const top = topGrades(sends);
          const review = snap.reviews.find((r) => r.sessionId === s.id);
          return (
            <div
              key={s.id}
              style={{
                display: 'grid',
                gridTemplateColumns: '88px 1.1fr 1fr 70px 1fr 92px',
                alignItems: 'center',
                padding: '12px 0',
                borderBottom: '1px solid var(--rule-light)',
              }}
            >
              <span className="mono" style={{ fontSize: 11.5, color: 'var(--muted)' }}>
                {shortDate(s.date)}
              </span>
              <span style={{ font: '500 12px/1 var(--sans)' }}>
                {snap.gyms.find((g) => g.id === s.gymId)?.name ?? '—'}
              </span>
              <span style={{ font: '400 11.5px/1.3 var(--sans)', color: 'var(--muted)' }}>
                {s.intent ?? '—'}
              </span>
              <span className="serif" style={{ fontSize: 13 }}>
                {sends.length}
              </span>
              <span style={{ display: 'flex', gap: 4, alignItems: 'center' }}>
                {top.kind === 'tag'
                  ? top.values.map((t) => (
                      <span key={String(t)} style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
                        <i style={{ width: 15, height: 15, background: colourHex(String(t)), display: 'block' }} />
                        <em className="mono" style={{ fontSize: 10, fontStyle: 'normal', color: 'var(--muted)' }}>
                          {colourCode(String(t))}
                        </em>
                      </span>
                    ))
                  : top.values.map((v, i) => (
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
  );
}
