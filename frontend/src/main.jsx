import React, { useEffect, useMemo, useState } from 'react';
import { createRoot } from 'react-dom/client';
import './styles.css';

const emptyForm = {
  title: '',
  description: '',
  severity: 'medium',
};

function App() {
  const [incidents, setIncidents] = useState([]);
  const [form, setForm] = useState(emptyForm);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  const openCount = useMemo(
    () => incidents.filter((incident) => incident.status !== 'resolved').length,
    [incidents],
  );

  const resolvedCount = incidents.length - openCount;

  async function loadIncidents() {
    try {
      setError('');
      const response = await fetch('/api/incidents');
      if (!response.ok) throw new Error('Could not load incidents');
      setIncidents(await response.json());
    } catch (loadError) {
      setError(loadError.message);
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    loadIncidents();
  }, []);

  async function createIncident(event) {
    event.preventDefault();
    setSaving(true);
    setError('');

    try {
      const response = await fetch('/api/incidents', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(form),
      });

      const payload = await response.json();
      if (!response.ok) throw new Error(payload.message || 'Could not create incident');

      setIncidents((current) => [payload, ...current]);
      setForm(emptyForm);
    } catch (saveError) {
      setError(saveError.message);
    } finally {
      setSaving(false);
    }
  }

  async function changeStatus(id, status) {
    setError('');

    try {
      const response = await fetch(`/api/incidents/${id}/status`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ status }),
      });
      const payload = await response.json();
      if (!response.ok) throw new Error(payload.message || 'Could not update incident');

      setIncidents((current) =>
        current.map((incident) => (incident.id === id ? payload : incident)),
      );
    } catch (statusError) {
      setError(statusError.message);
    }
  }

  async function deleteIncident(id) {
    setError('');

    try {
      const response = await fetch(`/api/incidents/${id}`, { method: 'DELETE' });
      if (!response.ok) throw new Error('Could not delete incident');
      setIncidents((current) => current.filter((incident) => incident.id !== id));
    } catch (deleteError) {
      setError(deleteError.message);
    }
  }

  return (
    <main className="page-shell">
      <header className="hero">
        <div>
          <p className="eyebrow">Live status board</p>
          <h1>Incident Command Center</h1>
          <p className="hero-subtitle">
            Track, triage and resolve outages across your services.
          </p>
        </div>
        <div className="stat-row">
          <div className="stat-card is-primary">
            <strong>{openCount}</strong>
            <span>Active</span>
          </div>
          <div className="stat-card">
            <strong>{resolvedCount}</strong>
            <span>Resolved</span>
          </div>
        </div>
      </header>

      {error && <div className="error-banner">{error}</div>}

      <section className="grid">
        <form className="panel" onSubmit={createIncident}>
          <h2>Report an incident</h2>
          <p className="panel-hint">
            Capture what broke while the details are still fresh.
          </p>

          <label>
            Incident title
            <input
              required
              minLength="3"
              value={form.title}
              onChange={(event) => setForm({ ...form, title: event.target.value })}
              placeholder="Checkout API returning 503s"
            />
          </label>

          <label>
            Impact &amp; symptoms
            <textarea
              rows="4"
              value={form.description}
              onChange={(event) =>
                setForm({ ...form, description: event.target.value })
              }
              placeholder="Who is affected, what are you seeing, and since when?"
            />
          </label>

          <label>
            Severity
            <select
              value={form.severity}
              onChange={(event) =>
                setForm({ ...form, severity: event.target.value })
              }
            >
              <option value="low">Low · minor annoyance</option>
              <option value="medium">Medium · degraded service</option>
              <option value="high">High · major feature down</option>
              <option value="critical">Critical · full outage</option>
            </select>
          </label>

          <button className="submit-button" disabled={saving}>
            {saving ? 'Reporting…' : 'Report incident'}
          </button>
        </form>

        <section className="panel incidents-panel">
          <div className="panel-heading">
            <h2>Incident feed</h2>
            <button className="secondary" type="button" onClick={loadIncidents}>
              Refresh feed
            </button>
          </div>

          {loading ? (
            <p className="empty-state">Loading the incident feed…</p>
          ) : incidents.length === 0 ? (
            <p className="empty-state">All clear. Nothing is on fire right now.</p>
          ) : (
            <div className="incident-list">
              {incidents.map((incident) => (
                <article className="incident-card" key={incident.id}>
                  <div className="incident-title-row">
                    <div>
                      <span className={`badge ${incident.severity}`}>
                        {incident.severity}
                      </span>
                      <h3>{incident.title}</h3>
                    </div>
                    <button
                      className="danger-link"
                      type="button"
                      onClick={() => deleteIncident(incident.id)}
                    >
                      Delete
                    </button>
                  </div>
                  <p>{incident.description || 'No details were provided.'}</p>
                  <div className="incident-footer">
                    <select
                      className={`status-select ${incident.status}`}
                      aria-label={`Status for ${incident.title}`}
                      value={incident.status}
                      onChange={(event) =>
                        changeStatus(incident.id, event.target.value)
                      }
                    >
                      <option value="open">Open</option>
                      <option value="investigating">Investigating</option>
                      <option value="resolved">Resolved</option>
                    </select>
                    <time>{new Date(incident.created_at).toLocaleString()}</time>
                  </div>
                </article>
              ))}
            </div>
          )}
        </section>
      </section>
    </main>
  );
}

createRoot(document.getElementById('root')).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
);
