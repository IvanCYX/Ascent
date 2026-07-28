import type { CSSProperties } from 'react';

export type BodyStatus = 'active' | 'watching' | 'clear';

const FILL: Record<BodyStatus, string> = {
  active: '#c0392b',
  watching: '#f2c744',
  clear: '#ffffff',
};

/** Plain geometric divs — no icon set, no images. Tap a part to filter. */
export default function BodyMap({
  status,
  selected,
  onSelect,
}: {
  status: Record<string, BodyStatus>;
  selected: string | null;
  onSelect: (part: string | null) => void;
}) {
  const part = (id: string, style: CSSProperties, label: string) => {
    const s = status[id] ?? 'clear';
    const isSel = selected === id;
    return (
      <button
        key={id}
        aria-label={label}
        title={label}
        onClick={() => onSelect(isSel ? null : id)}
        style={{
          ...style,
          background: FILL[s],
          border: isSel
            ? '2px solid #17150f'
            : s === 'clear'
              ? '1px solid rgba(0,0,0,.2)'
              : '1px solid #17150f',
          padding: 0,
          transition: 'border-color 140ms ease-out',
        }}
      />
    );
  };

  return (
    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 5 }}>
      {part('head', { width: 42, height: 42, borderRadius: '50%' }, 'Head / neck')}

      <div style={{ display: 'flex', alignItems: 'flex-start', gap: 6 }}>
        {/* left arm — viewer's left is the climber's left in this diagram */}
        <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4, paddingTop: 6 }}>
          {part('l-shoulder', { width: 15, height: 15, borderRadius: '50%' }, 'L shoulder')}
          {part('l-elbow', { width: 13, height: 74, borderRadius: 8 }, 'L elbow / arm')}
          {part('l-hand', { width: 22, height: 22, borderRadius: 6 }, 'L hand / fingers')}
        </div>

        {part('torso', { width: 78, height: 118, borderRadius: 12 }, 'Torso / core')}

        <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4, paddingTop: 6 }}>
          {part('r-shoulder', { width: 15, height: 15, borderRadius: '50%' }, 'R shoulder')}
          {part('r-elbow', { width: 13, height: 74, borderRadius: 8 }, 'R elbow / arm')}
          {part('r-hand', { width: 22, height: 22, borderRadius: 6 }, 'R hand / fingers')}
        </div>
      </div>

      <div style={{ display: 'flex', gap: 8, marginTop: 2 }}>
        {part('l-leg', { width: 26, height: 96, borderRadius: 10 }, 'L leg / knee')}
        {part('r-leg', { width: 26, height: 96, borderRadius: 10 }, 'R leg / knee')}
      </div>
    </div>
  );
}
