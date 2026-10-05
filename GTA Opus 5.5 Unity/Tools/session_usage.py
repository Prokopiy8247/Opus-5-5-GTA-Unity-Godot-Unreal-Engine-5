"""Token usage + API-equivalent cost for THIS project's Claude session(s).

Reads only `usage`/`model`/ids/timestamps from Claude Code transcript JSONL files
(no message content is printed or stored). Deduplicates per API message id
(Claude Code writes one line per content block, repeating the same usage).

Usage: python Tools/session_usage.py <session-id> [<session-id> ...]
"""
import json, os, sys, glob, datetime

PROJECT_DIR = os.path.expanduser(r"~/.claude/projects/W--YouTube-Claude-Opus-5-5-GTA-Unity-Unity-Opus5-5-GTA")
# Official Standard Claude API rates, USD per million tokens, verified 2026-10-03 at
# https://platform.claude.com/docs/en/about-claude/pricing
RATES = {
    "claude-opus-5-5": {"input": 4.00, "cache_write_5m": 5.00, "cache_write_1h": 8.00, "cache_read": 0.20, "output": 20.00},
}

def rate_key(model):
    m = (model or "").lower()
    for k in RATES:
        if m.startswith(k):
            return k
    return None

def collect(session_id):
    files = [os.path.join(PROJECT_DIR, session_id + ".jsonl")]
    files += glob.glob(os.path.join(PROJECT_DIR, session_id, "subagents", "*.jsonl"))
    msgs = {}
    first_ts = last_ts = None
    for path in files:
        if not os.path.exists(path):
            continue
        sub = "subagent" if "subagents" in path else "main"
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                try:
                    e = json.loads(line)
                except Exception:
                    continue
                ts = e.get("timestamp")
                if ts:
                    first_ts = ts if first_ts is None or ts < first_ts else first_ts
                    last_ts = ts if last_ts is None or ts > last_ts else last_ts
                if e.get("type") != "assistant":
                    continue
                m = e.get("message") or {}
                u = m.get("usage")
                mid = m.get("id") or e.get("requestId") or e.get("uuid")
                if not u or not mid:
                    continue
                key = (sub, mid)
                prev = msgs.get(key)
                # keep the most complete snapshot for the message (max output tokens)
                if prev is None or (u.get("output_tokens") or 0) >= (prev["usage"].get("output_tokens") or 0):
                    msgs[key] = {"usage": u, "model": m.get("model"), "src": sub}
    return msgs, first_ts, last_ts

def main():
    ids = sys.argv[1:]
    tot = {"input": 0, "cache_read": 0, "cache_write_total": 0, "cache_write_5m": 0, "cache_write_1h": 0,
           "cache_write_unsplit": 0, "output": 0, "thinking_included_in_output": 0}
    per_model = {}
    n = 0
    span = []
    for sid in ids:
        msgs, a, b = collect(sid)
        span.append((sid, a, b, len(msgs)))
        for (_, _), rec in msgs.items():
            u, model = rec["usage"], rec["model"] or "unknown"
            n += 1
            inp = u.get("input_tokens") or 0
            cr = u.get("cache_read_input_tokens") or 0
            cw = u.get("cache_creation_input_tokens") or 0
            cc = u.get("cache_creation") or {}
            w5 = cc.get("ephemeral_5m_input_tokens")
            w1 = cc.get("ephemeral_1h_input_tokens")
            out = u.get("output_tokens") or 0
            tot["thinking_included_in_output"] += ((u.get("output_tokens_details") or {}).get("thinking_tokens") or 0)
            pm = per_model.setdefault(model, {"msgs": 0, "input": 0, "cache_read": 0, "cw5": 0, "cw1": 0, "cw_unsplit": 0, "output": 0})
            pm["msgs"] += 1; pm["input"] += inp; pm["cache_read"] += cr; pm["output"] += out
            tot["input"] += inp; tot["cache_read"] += cr; tot["cache_write_total"] += cw; tot["output"] += out
            if w5 is not None or w1 is not None:
                w5 = w5 or 0; w1 = w1 or 0
                pm["cw5"] += w5; pm["cw1"] += w1
                tot["cache_write_5m"] += w5; tot["cache_write_1h"] += w1
                rest = cw - w5 - w1
                if rest > 0:
                    pm["cw_unsplit"] += rest; tot["cache_write_unsplit"] += rest
            else:
                pm["cw_unsplit"] += cw; tot["cache_write_unsplit"] += cw
    print("observation_cutoff_utc:", datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))
    for sid, a, b, k in span:
        print(f"session {sid}: transcript span {a} .. {b}, unique API messages {k}")
    print("unique_api_messages:", n)
    for k, v in tot.items():
        print(f"{k}: {v}")
    # thinking tokens are part of output_tokens (billed as output) - not added again
    dedup_total = tot["input"] + tot["cache_read"] + tot["cache_write_total"] + tot["output"]
    print("deduplicated_total_tokens (input+cache_read+cache_write+output):", dedup_total)
    # delegated work (sub-agents) reported separately; their usage is already included in the totals above
    per_src = {}
    for sid in ids:
        msgs, _, _ = collect(sid)
        for (_, _), rec in msgs.items():
            u = rec["usage"]; key = (rec["src"], rec["model"] or "unknown")
            d = per_src.setdefault(key, {"msgs": 0, "input": 0, "cache_read": 0, "cache_write": 0, "output": 0})
            d["msgs"] += 1; d["input"] += u.get("input_tokens") or 0; d["cache_read"] += u.get("cache_read_input_tokens") or 0
            d["cache_write"] += u.get("cache_creation_input_tokens") or 0; d["output"] += u.get("output_tokens") or 0
    for (src, model), d in sorted(per_src.items()):
        print(f"source={src} model={model}: {d}")
    grand = 0.0
    for model, pm in per_model.items():
        rk = rate_key(model)
        if rk is None:
            print(f"model {model}: {pm} -> NO VERIFIED RATE, cost excluded")
            continue
        r = RATES[rk]
        # unsplit cache writes priced at the 5m rate only if no split exists; flagged below
        cost = (pm["input"] * r["input"] + pm["cache_read"] * r["cache_read"] + pm["cw5"] * r["cache_write_5m"]
                + pm["cw1"] * r["cache_write_1h"] + pm["output"] * r["output"]) / 1e6
        unsplit_lo = pm["cw_unsplit"] * r["cache_write_5m"] / 1e6
        unsplit_hi = pm["cw_unsplit"] * r["cache_write_1h"] / 1e6
        print(f"model {model}: msgs={pm['msgs']} input={pm['input']} cache_read={pm['cache_read']} cw5m={pm['cw5']} cw1h={pm['cw1']} cw_unsplit={pm['cw_unsplit']} output={pm['output']}")
        print(f"  cost_usd_excluding_unsplit_writes={cost:.4f}; unsplit cache-write range +{unsplit_lo:.4f}..+{unsplit_hi:.4f}")
        grand += cost + unsplit_lo
    print(f"TOTAL_API_EQUIVALENT_USD (unsplit writes at 5m rate if any) = {grand:.4f}")

if __name__ == "__main__":
    main()
