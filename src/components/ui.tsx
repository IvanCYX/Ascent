import type { CSSProperties, ReactNode } from 'react';
import { colourHex } from '../domain/vocab';

/* ── Chips ──────────────────────────────────────────────────────────────── */

export function Chip({
  label,
  on,
  onClick,
  small,
  dashed,
  blocked,
  pain,
  title,
}: {
  label: ReactNode;
  on?: boolean;
  onClick?: () => void;
  small?: boolean;
  dashed?: boolean;
  blocked?: boolean;
  pain?: boolean;
  title?: string;
}) {
  const cls = [
    'chip',
    small ? 'sm' : '',
    on ? (pain ? 'pain-on' : 'on') : '',
    dashed ? 'dashed' : '',
    blocked ? 'blocked' : '',
  ]
    .filter(Boolean)
    .join(' ');
  return (
    <button type="button" className={cls} onClick={blocked ? undefined : onClick} title={title} aria-pressed={!!on}>
      {label}
    </button>
  );
}

/* ── Colour swatch ──────────────────────────────────────────────────────── */

export function Swatch({
  colour,
  size = 40,
  on,
  onClick,
  flex,
  title,
}: {
  colour: string;
  size?: number | string;
  on?: boolean;
  onClick?: () => void;
  flex?: boolean;
  title?: string;
}) {
  const hex = colourHex(colour);
  const style: CSSProperties = {
    height: size,
    width: flex ? undefined : size,
    flex: flex ? 1 : undefined,
    background: hex,
  };
  const cls = ['swatch', colour === 'white' ? 'white' : '', on ? 'on' : ''].filter(Boolean).join(' ');
  if (!onClick) return <i className={cls} style={{ ...style, display: 'block' }} title={title} />;
  return <button type="button" className={cls} style={style} onClick={onClick} title={title} aria-label={title} aria-pressed={!!on} />;
}

/* ── Segmented control ──────────────────────────────────────────────────── */

export function Segmented<T extends string>({
  options,
  value,
  onChange,
}: {
  options: { id: T; label: string }[];
  value: T;
  onChange: (id: T) => void;
}) {
  return (
    <div className="seg">
      {options.map((o) => (
        <button
          key={o.id}
          type="button"
          className={o.id === value ? 'on' : ''}
          onClick={() => onChange(o.id)}
        >
          {o.label}
        </button>
      ))}
    </div>
  );
}

/* ── Page header (desktop screens) ──────────────────────────────────────── */

export function PageHead({
  eyebrow,
  title,
  right,
}: {
  eyebrow: string;
  title: ReactNode;
  right?: ReactNode;
}) {
  return (
    <div className="page-head">
      <div>
        <div className="eyebrow">{eyebrow}</div>
        <div className="serif" style={{ fontSize: 26, lineHeight: 1.1, marginTop: 11 }}>
          {title}
        </div>
      </div>
      {right}
    </div>
  );
}

/* ── Micro label ────────────────────────────────────────────────────────── */

export const Micro = ({ children, style }: { children: ReactNode; style?: CSSProperties }) => (
  <div className="micro" style={style}>
    {children}
  </div>
);

/* ── Section band ───────────────────────────────────────────────────────── */

export function Band({
  children,
  style,
  last,
}: {
  children: ReactNode;
  style?: CSSProperties;
  last?: boolean;
}) {
  return (
    <div
      style={{
        padding: '22px 26px',
        borderBottom: last ? 'none' : '1px solid rgba(0,0,0,.14)',
        ...style,
      }}
    >
      {children}
    </div>
  );
}

/* ── Section heading with an optional right-hand mono note ──────────────── */

export function SectionHead({
  title,
  note,
  noteWarn,
}: {
  title: ReactNode;
  note?: ReactNode;
  noteWarn?: boolean;
}) {
  return (
    <div
      style={{
        display: 'flex',
        alignItems: 'baseline',
        justifyContent: 'space-between',
        gap: 14,
        marginBottom: 14,
      }}
    >
      <span className="section-title">{title}</span>
      {note !== undefined && (
        <span
          className="mono"
          style={{
            font: '400 10px/1 var(--mono)',
            letterSpacing: '.08em',
            color: noteWarn ? 'var(--warn)' : 'var(--muted)',
            textAlign: 'right',
          }}
        >
          {note}
        </span>
      )}
    </div>
  );
}

/* ── Insight line ("Read:" / "Comp prep:") ──────────────────────────────── */

export function Insight({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div
      style={{
        display: 'flex',
        gap: 9,
        marginTop: 16,
        paddingTop: 14,
        borderTop: '1px solid var(--rule)',
        font: '400 11.5px/1.5 var(--sans)',
        color: 'var(--muted)',
      }}
    >
      <span style={{ color: 'var(--ink)', fontWeight: 600, whiteSpace: 'nowrap' }}>{label}</span>
      <span style={{ textWrap: 'pretty' } as CSSProperties}>{children}</span>
    </div>
  );
}

/* ── Warn panel ─────────────────────────────────────────────────────────── */

export function WarnPanel({
  lead,
  children,
  style,
}: {
  lead: string;
  children: ReactNode;
  style?: CSSProperties;
}) {
  return (
    <div className="warn-panel" style={style}>
      <b>{lead} · </b>
      {children}
    </div>
  );
}

/* ── Slider with the paper-palette knob ─────────────────────────────────── */

export function ScoreSlider({
  value,
  onChange,
}: {
  value: number;
  onChange: (v: number) => void;
}) {
  const pct = (value / 10) * 100;
  return (
    <div style={{ position: 'relative', height: 20, display: 'flex', alignItems: 'center' }}>
      <div style={{ position: 'absolute', left: 0, right: 0, height: 8, background: 'rgba(0,0,0,.1)' }}>
        <div style={{ position: 'absolute', inset: 0, width: `${pct}%`, background: 'var(--ink)' }} />
      </div>
      <div
        style={{
          position: 'absolute',
          left: `${pct}%`,
          width: 20,
          height: 20,
          borderRadius: '50%',
          background: 'var(--paper)',
          border: '2px solid var(--ink)',
          transform: 'translateX(-50%)',
          pointerEvents: 'none',
        }}
      />
      <input
        type="range"
        min={0}
        max={10}
        step={0.1}
        value={value}
        onChange={(e) => onChange(Number(e.target.value))}
        aria-label="Overall session score"
        style={{
          position: 'absolute',
          left: 0,
          right: 0,
          width: '100%',
          margin: 0,
          opacity: 0,
          height: 20,
          cursor: 'pointer',
        }}
      />
    </div>
  );
}

/* ── Small horizontal meter (comp readiness, felt score) ────────────────── */

export function Meter({
  pct,
  warn,
  height = 8,
  width,
}: {
  pct: number;
  warn?: boolean;
  height?: number;
  width?: number;
}) {
  const fill = warn ? 'var(--warn)' : 'var(--ink)';
  return (
    <i
      style={{
        display: 'block',
        flex: width ? undefined : 1,
        width,
        height,
        background: `linear-gradient(90deg, ${fill} ${pct}%, rgba(0,0,0,.1) ${pct}%)`,
      }}
    />
  );
}

/* ── Empty state ────────────────────────────────────────────────────────── */

export const Empty = ({ children }: { children: ReactNode }) => (
  <div className="empty">{children}</div>
);
