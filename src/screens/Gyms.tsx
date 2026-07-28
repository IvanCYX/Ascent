import { useMemo, useState } from 'react';
import type { Snapshot } from '../db/store';
import { deleteGym, exportJSON, importJSON, saveGym } from '../db/store';
import { resetToDemo } from '../db/seed';
import { CAMP5_TAGS, colourCode, colourHex } from '../domain/vocab';
import { isSend } from '../domain/metrics';
import { PageHead, Chip } from '../components/ui';
import type { Gym } from '../db/schema';

export default function Gyms({ snap }: { snap: Snapshot }) {
  const [adding, setAdding] = useState(false);
  const [draft, setDraft] = useState<Partial<Gym>>({
    name: '',
    scaleType: 'numeric',
    maxGrade: 12,
    offset: 0,
  });

  const sendsByGym = useMemo(() => {
    const map = new Map<string, number>();
    for (const c of snap.climbs) {
      if (!c.gymId || !isSend(c)) continue;
      map.set(c.gymId, (map.get(c.gymId) ?? 0) + 1);
    }
    return map;
  }, [snap.climbs]);

  const boardSends = snap.climbs.filter((c) => c.boardId && isSend(c)).length;

  /* Grades sent this period per numeric gym — those cells render in ink. */
  const sentGrades = useMemo(() => {
    const map = new Map<string, Set<number>>();
    for (const c of snap.climbs) {
      if (c.gradeKind !== 'number' || !c.gymId || !isSend(c)) continue;
      if (!map.has(c.gymId)) map.set(c.gymId, new Set());
      map.get(c.gymId)!.add(c.grade);
    }
    return map;
  }, [snap.climbs]);

  /* Bump PBJ / J1 / SSQ share one scale — collapse them into a single row. */
  const rows = useMemo(() => {
    const bump = snap.gyms.filter((g) => g.name.startsWith('Bump'));
    const rest = snap.gyms.filter((g) => !g.name.startsWith('Bump'));
    const grouped: { key: string; label: string; gyms: Gym[] }[] = rest.map((g) => ({
      key: g.id,
      label: g.name,
      gyms: [g],
    }));
    if (bump.length) {
      grouped.splice(2, 0, {
        key: 'bump',
        label: bump.map((g) => g.name.replace('Bump ', '')).join(' · ').replace(/^/, 'Bump '),
        gyms: bump,
      });
    }
    return grouped;
  }, [snap.gyms]);

  const add = async () => {
    if (!draft.name?.trim()) return;
    await saveGym({
      name: draft.name.trim(),
      shortName: draft.name.trim(),
      scaleType: draft.scaleType as Gym['scaleType'],
      maxGrade: draft.scaleType === 'numeric' ? Number(draft.maxGrade) || 12 : undefined,
      tags: draft.scaleType === 'ranked-colour' ? [...CAMP5_TAGS] : undefined,
      offset: Number(draft.offset) || 0,
      sortOrder: snap.gyms.length + 1,
    });
    setAdding(false);
    setDraft({ name: '', scaleType: 'numeric', maxGrade: 12, offset: 0 });
  };

  return (
    <div className="screen-desktop" style={{ maxWidth: 860 }}>
      <PageHead
        eyebrow="GYMS & GRADE SYSTEMS"
        title={`${snap.gyms.length} gyms · ${snap.boards.length} boards`}
        right={
          <button className="btn-primary" style={{ padding: '11px 16px' }} onClick={() => setAdding((v) => !v)}>
            + Add gym
          </button>
        }
      />

      {adding && (
        <div style={{ padding: '18px 28px', borderBottom: '1px solid var(--rule)', background: 'var(--card)' }}>
          <div className="micro" style={{ marginBottom: 12 }}>
            NEW GYM
          </div>
          <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap', alignItems: 'center' }}>
            <div className="field" style={{ flex: 1, minWidth: 200 }}>
              <label>NAME</label>
              <input
                value={draft.name ?? ''}
                placeholder="Gym name"
                onChange={(e) => setDraft((d) => ({ ...d, name: e.target.value }))}
              />
            </div>
            <Chip
              small
              label="Numbers"
              on={draft.scaleType === 'numeric'}
              onClick={() => setDraft((d) => ({ ...d, scaleType: 'numeric' }))}
            />
            <Chip
              small
              label="Colour tags"
              on={draft.scaleType === 'ranked-colour'}
              onClick={() => setDraft((d) => ({ ...d, scaleType: 'ranked-colour' }))}
            />
            {draft.scaleType === 'numeric' && (
              <div className="field" style={{ width: 130 }}>
                <label>MAX</label>
                <input
                  type="number"
                  min={1}
                  max={20}
                  value={draft.maxGrade ?? 12}
                  onChange={(e) => setDraft((d) => ({ ...d, maxGrade: Number(e.target.value) }))}
                />
              </div>
            )}
            <div className="field" style={{ width: 150 }}>
              <label>OFFSET</label>
              <input
                type="number"
                step={0.5}
                min={-1}
                max={1}
                value={draft.offset ?? 0}
                onChange={(e) => setDraft((d) => ({ ...d, offset: Number(e.target.value) }))}
              />
            </div>
            <button className="btn-primary" onClick={add}>
              Add
            </button>
          </div>
          <div style={{ font: '400 11px/1.5 var(--sans)', color: 'var(--muted)', marginTop: 10 }}>
            Offset is the soft/hard correction against Batuu, −1 to +1. A soft gym gets a negative
            offset so its 10 does not count as a Batuu 10 in aggregate charts.
          </div>
        </div>
      )}

      <div style={{ padding: '20px 28px 32px' }}>
        <div
          style={{
            display: 'grid',
            gridTemplateColumns: '152px 1fr 70px',
            font: '500 9.5px/1 var(--sans)',
            letterSpacing: '.1em',
            color: 'var(--muted)',
            paddingBottom: 10,
            borderBottom: '1px solid var(--rule-strong)',
          }}
        >
          <span>GYM</span>
          <span>GRADE LABELS</span>
          <span style={{ textAlign: 'right' }}>SENDS</span>
        </div>

        {rows.map((row) => {
          const first = row.gyms[0];
          const sends = row.gyms.reduce((a, g) => a + (sendsByGym.get(g.id) ?? 0), 0);
          const sent = new Set<number>();
          for (const g of row.gyms) for (const v of sentGrades.get(g.id) ?? []) sent.add(v);

          return (
            <div
              key={row.key}
              style={{
                display: 'grid',
                gridTemplateColumns: '152px 1fr 70px',
                alignItems: 'center',
                padding: '14px 0',
                borderBottom: '1px solid var(--rule-light)',
              }}
            >
              <div>
                <div style={{ font: '500 12.5px/1.3 var(--sans)' }}>{row.label}</div>
                <div className="mono" style={{ fontSize: 10, color: 'var(--muted)', marginTop: 6, letterSpacing: '.06em' }}>
                  {first.scaleType === 'numeric'
                    ? `NUMBERS · MAX ${first.maxGrade}`
                    : 'COLOUR TAGS ONLY'}
                </div>
                {row.gyms.length === 1 && sends === 0 && (
                  <button
                    className="btn-link"
                    style={{ marginTop: 6, color: 'var(--faint)' }}
                    onClick={() => deleteGym(first.id)}
                  >
                    Remove
                  </button>
                )}
              </div>

              {first.scaleType === 'numeric' ? (
                <div style={{ display: 'flex', gap: 3 }}>
                  {Array.from({ length: first.maxGrade ?? 12 }, (_, i) => i + 1).map((g) => {
                    const on = sent.has(g);
                    return (
                      <span
                        key={g}
                        style={{
                          flex: 1,
                          textAlign: 'center',
                          font: `${on ? 600 : 500} 10.5px/1 var(--mono)`,
                          color: on ? 'var(--paper)' : 'var(--ink)',
                          background: on ? 'var(--ink)' : 'var(--card)',
                          border: on ? '1px solid var(--ink)' : '1px solid rgba(0,0,0,.1)',
                          padding: '8px 0',
                        }}
                      >
                        {g}
                      </span>
                    );
                  })}
                  {(first.maxGrade ?? 12) < 15 && (
                    <span
                      className="mono"
                      style={{
                        flex: 15 - (first.maxGrade ?? 12),
                        textAlign: 'center',
                        font: '400 9.5px/1 var(--mono)',
                        color: 'var(--faint)',
                        padding: '8px 4px',
                        border: '1px dashed rgba(0,0,0,.2)',
                        letterSpacing: '.06em',
                        overflow: 'hidden',
                        whiteSpace: 'nowrap',
                      }}
                    >
                      NO {(first.maxGrade ?? 12) + 1}–15
                      {first.offset < 0 ? ' · SOFT VS BATUU' : first.offset > 0 ? ' · HARD VS BATUU' : ''}
                    </span>
                  )}
                </div>
              ) : (
                <div style={{ display: 'flex', gap: 5, alignItems: 'center' }}>
                  <span className="mono" style={{ fontSize: 9.5, color: 'var(--muted)', letterSpacing: '.08em' }}>
                    EASY
                  </span>
                  {(first.tags ?? []).map((t) => {
                    const used = snap.climbs.some((c) => c.gymId === first.id && c.tagId === t && isSend(c));
                    return (
                      <span key={t} style={{ flex: 1, display: 'flex', flexDirection: 'column', gap: 5 }}>
                        <i
                          style={{
                            height: 16,
                            background: colourHex(t),
                            display: 'block',
                            border: t === 'white' ? '1px solid rgba(0,0,0,.18)' : undefined,
                          }}
                        />
                        <em
                          className="mono"
                          style={{
                            fontSize: 9,
                            textAlign: 'center',
                            fontStyle: 'normal',
                            color: used ? 'var(--ink)' : 'var(--muted)',
                          }}
                        >
                          {colourCode(t)}
                        </em>
                      </span>
                    );
                  })}
                  <span className="mono" style={{ fontSize: 9.5, color: 'var(--muted)', letterSpacing: '.08em' }}>
                    HARD
                  </span>
                </div>
              )}

              <span className="serif" style={{ fontSize: 15, textAlign: 'right' }}>
                {sends}
              </span>
            </div>
          );
        })}

        {/* Boards */}
        <div
          style={{
            display: 'grid',
            gridTemplateColumns: '152px 1fr 70px',
            alignItems: 'center',
            padding: '14px 0',
          }}
        >
          <div>
            <div style={{ font: '500 12.5px/1 var(--sans)' }}>Boards</div>
            <div className="mono" style={{ fontSize: 10, color: 'var(--muted)', marginTop: 6, letterSpacing: '.06em' }}>
              V-SCALE · NEVER MERGED
            </div>
          </div>
          <div style={{ display: 'flex', gap: 8, alignItems: 'center', flexWrap: 'wrap' }}>
            {snap.boards.map((b) => (
              <span
                key={b.id}
                className="card"
                style={{ font: '500 11px/1 var(--sans)', padding: '9px 12px' }}
              >
                {b.name} · {b.angles.join('/')}°
              </span>
            ))}
            <span style={{ font: '400 10.5px/1.4 var(--sans)', color: 'var(--muted)' }}>
              V1–V10 · kept out of the gym pyramid
            </span>
          </div>
          <span className="serif" style={{ fontSize: 15, textAlign: 'right' }}>
            {boardSends}
          </span>
        </div>

        <div
          className="card"
          style={{
            marginTop: 16,
            padding: '14px 16px',
            font: '400 11.5px/1.5 var(--sans)',
            color: 'var(--muted)',
            textWrap: 'pretty',
          }}
        >
          <span style={{ color: 'var(--ink)', fontWeight: 600 }}>Two kinds of scale · </span>
          Numbered gyms share the 1–15 spine with a soft/hard offset, so BHUB 10 and Batuu 10 are not
          counted as the same climb. Camp5 is ranked, not numbered — its tags stay tags, ordered
          yellow → black, and chart in their own column.
        </div>

        {/* Backup — the log is the whole point, so it must be portable */}
        <div style={{ marginTop: 22, paddingTop: 18, borderTop: '1px solid var(--rule)' }}>
          <div className="micro" style={{ marginBottom: 12 }}>
            DATA
          </div>
          <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap', alignItems: 'center' }}>
            <button
              className="btn-secondary"
              onClick={async () => {
                const json = await exportJSON();
                const url = URL.createObjectURL(new Blob([json], { type: 'application/json' }));
                const a = document.createElement('a');
                a.href = url;
                a.download = `sendlog-${new Date().toISOString().slice(0, 10)}.json`;
                a.click();
                URL.revokeObjectURL(url);
              }}
            >
              Export backup
            </button>
            <label className="btn-secondary" style={{ cursor: 'pointer' }}>
              Import backup
              <input
                type="file"
                accept="application/json"
                style={{ display: 'none' }}
                onChange={async (e) => {
                  const file = e.target.files?.[0];
                  if (!file) return;
                  await importJSON(await file.text());
                }}
              />
            </label>
            <button
              className="btn-secondary"
              onClick={() => {
                if (confirm('Replace everything with the demo dataset? Export a backup first if you care about this log.'))
                  resetToDemo();
              }}
            >
              Reset to demo data
            </button>
            <span style={{ font: '400 11px/1.5 var(--sans)', color: 'var(--muted)' }}>
              Everything lives in this browser. Export before clearing site data.
            </span>
          </div>
        </div>
      </div>
    </div>
  );
}
