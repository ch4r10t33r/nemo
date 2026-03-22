import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { getSlots } from "../api";

export default function Slots() {
  const [slots, setSlots] = useState<number[]>([]);
  const [limit, setLimit] = useState(200);
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    let cancel = false;
    (async () => {
      try {
        const r = await getSlots(limit);
        if (!cancel) {
          setSlots(r.slots);
          setErr(null);
        }
      } catch (e) {
        if (!cancel) setErr(e instanceof Error ? e.message : String(e));
      }
    })();
    return () => {
      cancel = true;
    };
  }, [limit]);

  if (err) return <p className="err">{err}</p>;

  return (
    <div className="panel">
      <h2>Slots</h2>
      <p style={{ color: "var(--muted)", marginTop: 0 }}>
        Distinct slots seen in persisted fork-choice snapshots (SQLite). Limit{" "}
        <select
          value={limit}
          onChange={(e) => setLimit(Number(e.target.value))}
          style={{ marginLeft: 8 }}
        >
          <option value={50}>50</option>
          <option value={100}>100</option>
          <option value={200}>200</option>
          <option value={500}>500</option>
        </select>
      </p>
      {slots.length === 0 ? (
        <p className="loading">No slots yet — ensure a node is running and Nemo can reach it.</p>
      ) : (
        <ul style={{ columns: 2, margin: 0, paddingLeft: "1.2rem" }}>
          {slots.map((s) => (
            <li key={s}>
              <Link to={`/slot/${s}`}>Slot {s}</Link>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
