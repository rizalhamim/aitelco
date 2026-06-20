"""City Profile Radar - Core Scoring Engine
Pure functions for calculating City Profile health scores (0 to 100).
No I/O or framework imports allowed here.
"""
import math

def clip(x):
    if x is None or math.isnan(x):
        return None
    return max(0.0, min(100.0, x))

def get_tier(score):
    if score is None or math.isnan(score):
        return "N/A"
    if score >= 60:
        return "Win"
    if score >= 40:
        return "Watch"
    return "Risk"

def compute_percentile(values, p):
    """Calculate the p-th percentile (0-100) of a list of values."""
    if not values:
        return None
    sorted_vals = sorted(values)
    k = (len(sorted_vals) - 1) * (p / 100.0)
    f = math.floor(k)
    c = math.ceil(k)
    if f == c:
        return sorted_vals[int(k)]
    d0 = sorted_vals[int(f)] * (c - k)
    d1 = sorted_vals[int(c)] * (k - f)
    return d0 + d1

def normalize_signal(signal_def, metrics, peers, config, lens="level", period_basis=None):
    """Normalize a single metric into a 0-100 score."""
    key = signal_def["key"]
    field = signal_def["field"]
    sig_type = signal_def["type"]
    
    # Overrides from UI
    if lens == "growth":
        # Force all signals to be evaluated as growth
        sig_type = "growth"
        
    period = period_basis if period_basis else signal_def.get("period", "yoy")
    
    # Read metrics
    m_data = metrics.get(field)
    if not m_data:
        return {"score": 50, "status": "no-data", "raw": None, "growth": None}
        
    raw_val = m_data.get("mtd")
    
    # Handle Partial Month fallback for FB metrics
    is_partial = metrics.get("partial_month", False)
    if is_partial and field.startswith("fb_") and (raw_val is None or raw_val == 0):
        raw_val = m_data.get("lmtd")
        status = "partial-month"
    else:
        status = "ok"

    growth_val = m_data.get(period)
    if growth_val is None and period == "yoy":
        # Fallback to mom if yoy not available (e.g. gross add)
        growth_val = m_data.get("mom")

    if raw_val is None:
        return {"score": 50, "status": "no-data", "raw": None, "growth": growth_val}

    score = 50.0

    if sig_type == "growth":
        band = signal_def.get("band", config.get("default_band", 20))
        invert = signal_def.get("invert", False)
        
        if growth_val is None:
            return {"score": 50, "status": "no-data", "raw": raw_val, "growth": None}
            
        g = -growth_val if invert else growth_val
        score = clip(50 + (g / band) * 50)

    elif sig_type == "size":
        min_peers = config.get("min_peers", 5)
        peer_vals = [p["metrics"].get(field, {}).get("mtd") for p in peers if p["metrics"].get(field)]
        peer_vals = [v for v in peer_vals if v is not None]
        
        if len(peer_vals) < min_peers:
            # Fallback to RATIO or neutral
            status = "insufficient-peers"
            target = signal_def.get("target")
            if target:
                score = clip((raw_val / target) * 100)
            else:
                score = 50.0
        else:
            p10 = compute_percentile(peer_vals, 10)
            p90 = compute_percentile(peer_vals, 90)
            if p90 == p10:
                score = 50.0
            else:
                score = clip((raw_val - p10) / (p90 - p10) * 100)

    elif sig_type == "ratio":
        target = signal_def.get("target", 100)
        score = clip((raw_val / target) * 100)

    elif sig_type == "rank":
        n_groups = signal_def.get("n", 3)
        rank_val = raw_val
        if rank_val is None or rank_val == 0:
            return {"score": 50, "status": "no-data", "raw": raw_val, "growth": growth_val}
        score = ((n_groups - rank_val) / (n_groups - 1)) * 100
        score = clip(score)

    elif sig_type == "share_vs_fair":
        fair_field = signal_def.get("fair_field")
        fair_band = signal_def.get("fair_band", 5)
        
        fair_data = metrics.get(fair_field, {})
        fair_val = fair_data.get("mtd")
        if is_partial and fair_field.startswith("fb_") and (fair_val is None or fair_val == 0):
            fair_val = fair_data.get("lmtd")
            
        if fair_val is None:
            score = 50.0
            status = "no-data"
        else:
            score = clip(50 + ((raw_val - fair_val) / fair_band) * 50)
            
    return {"score": score, "status": status, "raw": raw_val, "growth": growth_val}

def computeProfile(target, peers, config, options=None):
    """Main entrypoint for scoring."""
    if options is None:
        options = {}
    lens = options.get("lens", "level")
    period = options.get("period", None) # Let it fallback to config default
    
    overall_score = 0.0
    pillars_out = []
    
    total_pillar_weight = sum(p["weight"] for p in config["pillars"].values())
    
    for p_key, p_def in config["pillars"].items():
        pillar_score = 0.0
        signals_out = []
        
        total_sig_weight = sum(s["weight"] for s in p_def["signals"])
        
        for sig_def in p_def["signals"]:
            res = normalize_signal(sig_def, target["metrics"], peers, config, lens, period)
            norm_w = sig_def["weight"] / total_sig_weight if total_sig_weight else 0
            contrib = norm_w * res["score"]
            pillar_score += contrib
            
            signals_out.append({
                "key": sig_def["key"],
                "label": sig_def["label"],
                "type": "growth" if lens == "growth" else sig_def["type"],
                "raw": res["raw"],
                "growth": res["growth"],
                "score": res["score"],
                "contribution": contrib,
                "status": res["status"]
            })
            
        # Find top driver (max absolute deviation from 50)
        top_driver = None
        max_dev = -1
        for s in signals_out:
            dev = abs(s["score"] - 50)
            if dev > max_dev:
                max_dev = dev
                top_driver = s["label"]
                
        norm_p_w = p_def["weight"] / total_pillar_weight if total_pillar_weight else 0
        overall_score += norm_p_w * pillar_score
        
        pillars_out.append({
            "key": p_key,
            "label": p_def["label"],
            "score": pillar_score,
            "tier": get_tier(pillar_score),
            "topDriver": top_driver,
            "signals": signals_out
        })
        
    return {
        "overall": overall_score,
        "overallTier": get_tier(overall_score),
        "pillars": pillars_out
    }
