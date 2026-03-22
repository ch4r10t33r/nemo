import { useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";
import type { BlockDetail } from "../api";
import { getBlock } from "../api";

export default function BlockPage() {
  const { root: rootParam } = useParams();
  const root = rootParam ? decodeURIComponent(rootParam) : "";
  const [data, setData] = useState<BlockDetail | null>(null);
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    if (!root) return;
    let cancel = false;
    (async () => {
      try {
        const d = await getBlock(root);
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
  }, [root]);

  if (!root) return <p className="err">Missing block root</p>;
  if (err) return <p className="err">{err}</p>;
  if (!data) return <p className="loading">Loading…</p>;

  return (
    <div className="panel">
      <h2>Block</h2>
      <dl className="grid">
        <dt>Root</dt>
        <dd className="mono">{data.root}</dd>
        <dt>Slot</dt>
        <dd>
          <Link to={`/slot/${data.slot}`}>{data.slot}</Link>
        </dd>
        <dt>Parent root</dt>
        <dd className="mono">
          <Link to={`/block/${encodeURIComponent(data.parent_root)}`}>{data.parent_root}</Link>
        </dd>
        <dt>Proposer index</dt>
        <dd>{data.proposer_index}</dd>
        <dt>Weight</dt>
        <dd>{data.weight}</dd>
        <dt>Source URL</dt>
        <dd className="mono">{data.source_url}</dd>
        <dt>Updated (ms)</dt>
        <dd>{data.updated_at_ms}</dd>
      </dl>
    </div>
  );
}
