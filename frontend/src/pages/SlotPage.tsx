import { useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";
import type { SlotDetail } from "../api";
import { getSlot } from "../api";

export default function SlotPage() {
  const { slot: slotStr } = useParams();
  const slot = Number(slotStr);
  const [data, setData] = useState<SlotDetail | null>(null);
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    if (!Number.isFinite(slot)) return;
    let cancel = false;
    (async () => {
      try {
        const d = await getSlot(slot);
        if (!cancel) {
          setData(d);
          setErr(null);
        }
      } catch (e) {
        if (!cancel) setErr(e instanceof Error ? e.message : String(e));
      }
    })();
    return () => {
      cancel = true;
    };
  }, [slot]);

  if (!Number.isFinite(slot)) return <p className="err">Invalid slot</p>;
  if (err) return <p className="err">{err}</p>;
  if (!data) return <p className="loading">Loading…</p>;

  return (
    <div className="panel">
      <h2>Slot {data.slot}</h2>
      {data.blocks.length === 0 ? (
        <p>No blocks in DB for this slot.</p>
      ) : (
        <table>
          <thead>
            <tr>
              <th>Root</th>
              <th>Weight</th>
              <th>Proposer</th>
              <th>Parent</th>
            </tr>
          </thead>
          <tbody>
            {data.blocks.map((b) => (
              <tr key={b.root}>
                <td className="mono">
                  <Link to={`/block/${encodeURIComponent(b.root)}`}>{b.root.slice(0, 20)}…</Link>
                </td>
                <td>{b.weight}</td>
                <td>{b.proposer_index}</td>
                <td className="mono">{b.parent_root.slice(0, 14)}…</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  );
}
