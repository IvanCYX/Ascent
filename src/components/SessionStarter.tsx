import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import type { Snapshot } from '../db/store';
import { startSession } from '../db/store';
import { SESSION_INTENTS, type SessionIntent } from '../domain/vocab';
import { planDate, todayISO } from '../domain/dates';
import { Chip } from './ui';

/**
 * Shown on the mobile screens when nothing is in progress. A session started
 * here has no plan attached — intent stays optional and can be set at review.
 */
export default function SessionStarter({
  snap,
  title,
  hint,
}: {
  snap: Snapshot;
  title: string;
  hint: string;
}) {
  const nav = useNavigate();
  const today = todayISO();
  const plan = snap.sessions.find((s) => s.status === 'planned' && s.date === today);
  const [gymId, setGymId] = useState<string>(plan?.gymId ?? snap.gyms[0]?.id ?? '');
  const [intent, setIntent] = useState<SessionIntent | undefined>(plan?.intent);

  return (
    <div className="screen-mobile">
      <div className="status-strip">
        <span>{planDate(today)}</span>
        <span>NO SESSION</span>
      </div>
      <div style={{ padding: '12px 20px 24px' }}>
        <div className="serif" style={{ fontSize: 27, lineHeight: 1 }}>
          {title}
        </div>
        <div style={{ font: '400 11px/1.5 var(--sans)', color: 'var(--muted)', marginTop: 8 }}>
          {hint}
        </div>

        {plan && (
          <div
            className="card"
            style={{ marginTop: 18, padding: '14px 15px', font: '400 11.5px/1.5 var(--sans)', color: 'var(--muted)' }}
          >
            <span style={{ color: 'var(--ink)', fontWeight: 600 }}>Plan for today · </span>
            {plan.intent} at {snap.gyms.find((g) => g.id === plan.gymId)?.name}.{' '}
            <button className="btn-link" onClick={() => nav('/plan')}>
              Open plan
            </button>
          </div>
        )}

        <div className="micro" style={{ margin: '22px 0 10px' }}>
          GYM
        </div>
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6 }}>
          {snap.gyms.map((g) => (
            <Chip key={g.id} small label={g.name} on={g.id === gymId} onClick={() => setGymId(g.id)} />
          ))}
        </div>

        <div className="micro" style={{ margin: '20px 0 10px' }}>
          INTENT — OPTIONAL
        </div>
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6 }}>
          {SESSION_INTENTS.map((i) => (
            <Chip
              key={i}
              small
              label={i}
              on={intent === i}
              onClick={() => setIntent((cur) => (cur === i ? undefined : i))}
            />
          ))}
        </div>

        <button
          className="btn-primary"
          style={{ width: '100%', marginTop: 24, padding: '15px 0' }}
          onClick={async () => {
            await startSession({
              gymId,
              intent,
              fromPlanId: plan && plan.gymId === gymId ? plan.id : undefined,
            });
          }}
        >
          Start session
        </button>
      </div>
    </div>
  );
}
