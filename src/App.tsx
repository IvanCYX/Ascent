import { NavLink, Navigate, Route, Routes } from 'react-router-dom';
import { useSnapshot } from './db/store';
import Dashboard from './screens/Dashboard';
import QuickLog from './screens/QuickLog';
import BoardLog from './screens/BoardLog';
import SessionReview from './screens/SessionReview';
import SessionPlan from './screens/SessionPlan';
import Gyms from './screens/Gyms';
import Injuries from './screens/Injuries';
import History from './screens/History';

const NAV = [
  { to: '/', label: 'Dashboard', end: true },
  { to: '/plan', label: 'Plan' },
  { to: '/log', label: 'Quick log' },
  { to: '/board', label: 'Board' },
  { to: '/review', label: 'Review' },
  { to: '/history', label: 'History' },
  { to: '/gyms', label: 'Gyms' },
  { to: '/body', label: 'Body' },
];

export default function App() {
  const snap = useSnapshot();

  return (
    <>
      <nav className="app-nav">
        {NAV.map((n) => (
          <NavLink key={n.to} to={n.to} end={n.end} className={({ isActive }) => (isActive ? 'active' : '')}>
            {n.label}
          </NavLink>
        ))}
        <span className="spacer" />
        {snap && (
          <span className="mono" style={{ fontSize: 10, color: 'var(--faint)', whiteSpace: 'nowrap' }}>
            {snap.climbs.length} climbs logged
          </span>
        )}
      </nav>

      {!snap ? (
        <div style={{ padding: 40 }} className="micro">
          LOADING LOG…
        </div>
      ) : (
        <Routes>
          <Route path="/" element={<Dashboard snap={snap} />} />
          <Route path="/plan" element={<SessionPlan snap={snap} />} />
          <Route path="/log" element={<QuickLog snap={snap} />} />
          <Route path="/board" element={<BoardLog snap={snap} />} />
          <Route path="/review" element={<SessionReview snap={snap} />} />
          <Route path="/history" element={<History snap={snap} />} />
          <Route path="/gyms" element={<Gyms snap={snap} />} />
          <Route path="/body" element={<Injuries snap={snap} />} />
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      )}
    </>
  );
}
