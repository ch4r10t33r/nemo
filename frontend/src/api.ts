export type ForkChoice = {
  nodes: {
    root: string;
    slot: number;
    parent_root: string;
    proposer_index: number;
    weight: number;
  }[];
  head: string;
  justified: { slot: number; root: string };
  finalized: { slot: number; root: string };
  safe_target: string;
  validator_count: number;
};

export type Health = {
  lean_upstream_ok: boolean;
  db: null | {
    last_sync_ms: number;
    source: string;
    head: string;
    justified_slot: number;
    finalized_slot: number;
    validator_count: number;
  };
};

export type SlotsResponse = {
  slots: number[];
  limit: number;
  offset: number;
  has_more: boolean;
};

export type SlotDetail = {
  slot: number;
  blocks: {
    root: string;
    parent_root: string;
    proposer_index: number;
    weight: number;
    source_url: string;
    updated_at_ms: number;
  }[];
};

export type BlockDetail = {
  root: string;
  slot: number;
  parent_root: string;
  proposer_index: number;
  weight: number;
  source_url: string;
  updated_at_ms: number;
};

async function fetchJson<T>(path: string): Promise<T> {
  const r = await fetch(path);
  if (!r.ok) throw new Error(`${r.status} ${r.statusText}`);
  return r.json() as Promise<T>;
}

export async function getHealth(): Promise<Health> {
  return fetchJson<Health>("/api/health");
}

export async function getForkChoice(): Promise<{ data: ForkChoice; stale: boolean }> {
  const r = await fetch("/api/fork_choice");
  if (!r.ok) throw new Error(`${r.status} ${r.statusText}`);
  const stale = r.headers.get("X-Nemo-Stale") === "true";
  const data = (await r.json()) as ForkChoice;
  return { data, stale };
}

export async function getSlots(limit = 200, offset = 0): Promise<SlotsResponse> {
  return fetchJson<SlotsResponse>(`/api/slots?limit=${limit}&offset=${offset}`);
}

export async function getSlot(slot: number): Promise<SlotDetail> {
  return fetchJson<SlotDetail>(`/api/slot/${slot}`);
}

export async function getBlock(root: string): Promise<BlockDetail> {
  const enc = encodeURIComponent(root);
  return fetchJson<BlockDetail>(`/api/block/${enc}`);
}
