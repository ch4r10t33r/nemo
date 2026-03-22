import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import type { ForkChoice, Health } from "../api";
import { getForkChoice, getHealth } from "../api";

export default function Dashboard() {
  const [health, setHealth] = useState<Health | null>(null);
  const [fc, setFc] = useState<ForkChoice | null>(null);
  const [stale, setStale] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    let cancel = false;
    (async () => {
      try {
        const [h, f] = await Promise.all([getHealth(), getForkChoice()]);
        if (cancel) return;
        setHealth(h);
        setFc(f.data);
        setStale(f.stale);
        setErr(null);
      } catch (e) {
        if (!cancel) setErr(e instanceof Error ? e.message : String(e));
      }
    })();
    return () => {
      cancel = true;
    };
  }, []);

  if (err) return <p className="err">{err}</p>;
  if (!health || !fc) return <p className="loading">Loading…</p>;

  const headSlot = fc.nodes.find((n) => n.root === fc.head)?.slot;

  return (
    <>
      <div className="panel">
        <h2>Upstream &amp; cache</h2>
        <p>
          <span className={`badge ${health.lean_upstream_ok ? "ok" : "bad"}`}>
            {health.lean_upstream_ok ? "node reachable" : "node unreachable"}
          </span>
          {stale ? (
            <span className="badge stale" style={{ marginLeft: 8 }}>
              fork_choice from DB
            </span>
          ) : null}
        </p>
        {health.db ? (
          <dl className="grid">
            <dt>Last sync (ms)</dt>
            <dd>{health.db.last_sync_ms}</dd>
            <dt>Source</dt>
            <dd className="mono">{health.db.source}</dd>
            <dt>Cached head</dt>
            <dd className="mono">{health.db.head}</dd>
            <dt>Justified / finalized slot</dt>
            <dd>
              {health.db.justified_slot} / {health.db.finalized_slot}
            </dd>
          </dl>
        ) : (
          <p className="muted">No rows in SQLite yet — start a lean node (zeam or lean-spec-node) on LEAN_API_URL.</p>
        )}
      </div>

      <div className="panel">
        <h2>Fork choice</h2>
        <dl className="grid">
          <dt>Head</dt>
          <dd className="mono">
            <Link to={`/block/${encodeURIComponent(fc.head)}`}>{fc.head}</Link>
            {headSlot != null ? ` (slot ${headSlot})` : null}
          </dd>
          <dt>Justified</dt>
          <dd>
            slot {fc.justified.slot}{" "}
            <Link className="mono" to={`/block/${encodeURIComponent(fc.justified.root)}`}>
              {fc.justified.root.slice(0, 18)}…
            </Link>
          </dd>
          <dt>Finalized</dt>
          <dd>
            slot {fc.finalized.slot}{" "}
            <Link className="mono" to={`/block/${encodeURIComponent(fc.finalized.root)}`}>
              {fc.finalized.root.slice(0, 18)}…
            </Link>
          </dd>
          <dt>Validators</dt>
          <dd>{fc.validator_count}</dd>
          <dt>Nodes in tree</dt>
          <dd>{fc.nodes.length}</dd>
        </dl>
      </div>

      <div className="panel">
        <h2>Recent slots (from DB)</h2>
        <p>
          <Link to="/slots">Open slot list →</Link>
        </p>
      </div>
    </>
  );
}
