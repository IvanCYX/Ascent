import type { ChipTrendRow } from '../domain/metrics';
import { SectionHead } from './ui';

/** `1g` — "What keeps coming up": one row per chip, one cell per recent session. */
export default function ChipTrendPanel({
  rows,
  pattern,
  window = 12,
}: {
  rows: ChipTrendRow[];
  pattern: string | null;
  window?: number;
}) {
  if (!rows.length) {
    return <div className="empty">No reviews saved yet — chips start trending after a few sessions.</div>;
  }
  return (
    <div>
      <SectionHead title="What keeps coming up" note={`LAST ${window} SESSIONS`} />
      <div style={{ display: 'flex', flexDirection: 'column', gap: 11 }}>
        {rows.map((r) => (
          <div key={r.chip} style={{ display: 'flex', alignItems: 'center', gap: 14 }}>
            <span
              style={{
                width: 132,
                flex: 'none',
                font: '400 12.5px/1.2 var(--sans)',
              }}
            >
              {r.chip}
            </span>
            <div style={{ flex: 1, display: 'flex', gap: 3 }}>
              {r.cells.map((on, i) => (
                <i
                  key={i}
                  style={{
                    flex: 1,
                    height: 16,
                    display: 'block',
                    background: on ? 'var(--ink)' : 'rgba(0,0,0,.1)',
                  }}
                />
              ))}
            </div>
            <span
              className="mono"
              style={{ width: 30, fontSize: 11.5, textAlign: 'right', flex: 'none' }}
            >
              {r.count}×
            </span>
          </div>
        ))}
      </div>
      {pattern && (
        <div
          style={{
            marginTop: 18,
            paddingTop: 14,
            borderTop: '1px solid var(--rule)',
            display: 'flex',
            gap: 10,
            font: '400 12px/1.5 var(--sans)',
            color: 'var(--muted)',
          }}
        >
          <span style={{ fontWeight: 600, color: 'var(--ink)', whiteSpace: 'nowrap' }}>Pattern:</span>
          <span>{pattern}</span>
        </div>
      )}
    </div>
  );
}
