import { useEffect, useMemo, useState } from "react";
import { Link, useSearchParams } from "react-router-dom";
import { getSlots } from "../api";

const LIMIT_OPTIONS = [50, 100, 200, 500] as const;

function parsePositiveInt(s: string | null, fallback: number, max: number): number {
  if (s == null || s === "") return fallback;
  const n = Number.parseInt(s, 10);
  if (!Number.isFinite(n) || n < 0) return fallback;
  return Math.min(n, max);
}

export default function Slots() {
  const [searchParams, setSearchParams] = useSearchParams();
  const limit = useMemo(() => {
    const raw = searchParams.get("limit");
    const n = parsePositiveInt(raw, 200, 2000);
    return (LIMIT_OPTIONS as readonly number[]).includes(n) ? n : 200;
  }, [searchParams]);
  const offset = useMemo(
    () => parsePositiveInt(searchParams.get("offset"), 0, 1_000_000),
    [searchParams],
  );

  const [slots, setSlots] = useState<number[]>([]);
  const [hasMore, setHasMore] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    let cancel = false;
    (async () => {
      try {
        const r = await getSlots(limit, offset);
        if (!cancel) {
          setSlots(r.slots);
          setHasMore(r.has_more);
          setErr(null);
        }
      } catch (e) {
        if (!cancel) setErr(e instanceof Error ? e.message : String(e));
      }
    })();
    return () => {
      cancel = true;
    };
  }, [limit, offset]);

  const canPrev = offset > 0;
  const canNext = hasMore;

  const goPrev = () => {
    const nextOffset = Math.max(0, offset - limit);
    setSearchParams({ limit: String(limit), offset: String(nextOffset) });
  };

  const goNext = () => {
    setSearchParams({ limit: String(limit), offset: String(offset + limit) });
  };

  const onLimitChange = (nextLimit: number) => {
    setSearchParams({ limit: String(nextLimit), offset: "0" });
  };

  if (err) return <p className="err">{err}</p>;

  const slotRangeLabel =
    slots.length > 0
      ? `${slots[slots.length - 1]}–${slots[0]}`
      : null;

  return (
    <div className="panel">
      <h2>Slots</h2>
      <p className="slots-intro">
        Distinct slots seen in persisted fork-choice snapshots (SQLite). Page size{" "}
        <select
          value={limit}
          onChange={(e) => onLimitChange(Number(e.target.value))}
          className="slots-limit-select"
        >
          {LIMIT_OPTIONS.map((n) => (
            <option key={n} value={n}>
              {n}
            </option>
          ))}
        </select>
      </p>
      <div className="slots-nav" aria-label="Slot list pages">
        <button type="button" disabled={!canPrev} onClick={goPrev}>
          ← Previous
        </button>
        <span className="slots-nav-meta">
          {slotRangeLabel != null ? (
            <>
              Newest-first: <span className="mono">{slotRangeLabel}</span>
              <span className="slots-nav-offset"> · offset {offset}</span>
            </>
          ) : (
            <>offset {offset}</>
          )}
        </span>
        <button type="button" disabled={!canNext} onClick={goNext}>
          Next →
        </button>
      </div>
      {slots.length === 0 ? (
        <p className="loading">No slots yet — ensure a node is running and Nemo can reach it.</p>
      ) : (
        <ul className="slots-list">
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
