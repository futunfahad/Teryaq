import os
import time
import json
import re
import requests
from pathlib import Path
from typing import Dict, Any, Optional, List, Tuple

from fastapi import FastAPI, Request
from fastapi.responses import HTMLResponse
from rapidfuzz import fuzz

# ============================================================
# CONFIG
# ============================================================
DATA = Path("data")
MEDS_FILE = os.getenv("TRIOQ_MEDS_FILE", "medications.json")
NAV_FILE = os.getenv("TRIOQ_NAV_FILE", "navigation_guide.json")

# ============================================================
# LLM (Ollama) — OPTIONAL REWRITE for MED answers only
# - UI answers: ALWAYS NO LLM
# - Storage: optional LLM rewrite (DEFAULT ON)
# - Safety: optional LLM rewrite (DEFAULT ON)
# ============================================================
OLLAMA_URL = os.getenv("OLLAMA_URL", "http://127.0.0.1:11434")
OLLAMA_MODEL = os.getenv("OLLAMA_MODEL", "iKhalid/ALLaM:7b-q3_K_S")

# ✅ default to ON (you can still override by env)
TRIOQ_USE_LLM_REWRITE_STORAGE = os.getenv("TRIOQ_USE_LLM_REWRITE_STORAGE", "1") == "1"
TRIOQ_USE_LLM_REWRITE_SAFETY = os.getenv("TRIOQ_USE_LLM_REWRITE_SAFETY", "1") == "1"
TRIOQ_LLM_TIMEOUT = int(os.getenv("TRIOQ_LLM_TIMEOUT", "30"))  # seconds

# Similarity guard (avoid unchanged template)
TRIOQ_MAX_SIMILARITY = int(os.getenv("TRIOQ_MAX_SIMILARITY", "80"))  # higher = more similar

# ============================================================
# LOAD JSON
# ============================================================
def _load_json(name: str):
    p = DATA / name
    if not p.exists():
        raise FileNotFoundError(f"❌ Missing {name} in {DATA.resolve()}")
    return json.loads(p.read_text(encoding="utf-8"))

MEDS: List[Dict[str, Any]] = _load_json(MEDS_FILE)
NAV_GUIDE: List[Dict[str, Any]] = _load_json(NAV_FILE)  # use as-is (your requirement)

# ============================================================
# LANG / NORMALIZATION
# ============================================================
AR_LETTER = re.compile(r"[\u0600-\u06FF]")

def detect_lang(text: str) -> str:
    t = text or ""
    return "ar" if len(AR_LETTER.findall(t)) / max(1, len(t)) >= 0.2 else "en"

def normalize_ar(t: str) -> str:
    if not t:
        return ""
    t = re.sub(r"[ًٌٍَُِّْـ]", "", t)  # remove tashkeel/tatweel
    t = (
        t.replace("أ", "ا")
         .replace("إ", "ا")
         .replace("آ", "ا")
         .replace("ة", "ه")
         .replace("ى", "ي")
    )
    return t.strip().lower()

def normalize_en(t: str) -> str:
    return (t or "").strip().lower()

def fuzzy_score(a: str, b: str) -> int:
    if AR_LETTER.search(a or "") or AR_LETTER.search(b or ""):
        return fuzz.partial_ratio(normalize_ar(a), normalize_ar(b))
    return fuzz.partial_ratio(normalize_en(a), normalize_en(b))

def similarity_score(a: str, b: str) -> int:
    return fuzz.ratio((a or "").strip(), (b or "").strip())

# ============================================================
# DEBUG LOGGING
# ============================================================
def print_debug(stage: str, lang: str, user_msg: str, meta: Dict[str, Any], response: str):
    print("\n" + "=" * 80)
    print("🧪 TRIOQ DEBUG")
    print(f"- Stage: {stage}")
    print(f"- Language: {lang}")
    print(f"- User message: {user_msg}")
    for k, v in meta.items():
        print(f"- {k}: {v}")
    print("- Response:")
    print(response)
    print("=" * 80)

# ============================================================
# GREETING
# ============================================================
GREETINGS_AR = ["السلام عليكم", "وعليكم السلام", "مرحبًا", "مرحبا", "أهلًا", "اهلا", "صباح الخير", "مساء الخير"]
GREETINGS_EN = ["hello", "hi", "hey", "good morning", "good evening", "assalamualaikum", "as-salamu alaykum", "salam alaikum"]

def is_greeting(text: str) -> bool:
    t = (text or "").strip().lower()
    if not t:
        return False
    for g in GREETINGS_AR + GREETINGS_EN:
        if g.lower() in t or fuzzy_score(t, g) >= 88:
            return True
    return False

# ============================================================
# UI / NAVIGATION (NO LLM) — from navigation_guide.json as-is
# FIX: best-match scoring + intent priority + hard overrides
# IMPORTANT: does NOT touch safety/storage logic below.
# ============================================================

# Priority tie-breaker (higher wins when scores are similar)
NAV_PRIORITY = {
    "cancel_order": 100,
    "track_order": 90,
    "delivery_time_preference": 80,
    "order_status_meanings": 70,
    "change_address": 60,
    "view_notifications": 50,
    "change_language": 40,
    "order_without_prescription": 30,
    "order_from_prescriptions": 10,
}

# Hard intent hints (prevents "طلب" from stealing "إلغاء" etc.)
CANCEL_HINTS_AR = ["الغاء", "إلغاء", "الغي", "ألغي", "كنسل", "حذف الطلب"]
CANCEL_HINTS_EN = ["cancel", "cancellation", "remove order", "delete order", "stop the order"]
TRACK_HINTS_AR = ["تتبع", "وين طلبي", "اين طلبي", "أين طلبي", "متى يوصل", "يوصل متى", "لايف", "مباشر", "حالة طلبي"]
TRACK_HINTS_EN = ["track", "where is my order", "delivery status", "order tracking", "live status", "where is my delivery"]

# Add code-level aliases WITHOUT touching navigation_guide.json
NAV_ALIASES = {
    "order_from_prescriptions": {
        "en": ["how to order", "how can i order", "how to make an order", "make an order", "place an order", "create an order"],
        "ar": ["كيف اطلب", "كيف أطلب", "ابي اطلب", "أبي أطلب", "كيف اسوي طلب", "كيف أسوي طلب", "انشئ طلب", "إنشاء طلب"],
    },
    "cancel_order": {
        "en": ["cancel my order", "how to cancel my order", "cancel order"],
        "ar": ["الغاء الطلب", "إلغاء الطلب", "ابي الغي طلبي", "أبي ألغي طلبي", "كيف الغي الطلب", "كيف ألغي الطلب"],
    },
    "track_order": {
        "en": ["how to track", "track my order", "where is my order"],
        "ar": ["كيف اتتبع الطلب", "كيف أتتبع الطلب", "تتبع طلبي", "وين طلبي", "أين طلبي"],
    },
}

def _intent_item_map() -> Dict[str, Dict[str, Any]]:
    out: Dict[str, Dict[str, Any]] = {}
    for item in NAV_GUIDE:
        it = item.get("intent")
        if it:
            out[it] = item
    return out

_NAV_BY_INTENT = _intent_item_map()

def _nav_norm(text: str, is_ar: bool) -> str:
    return normalize_ar(text) if is_ar else normalize_en(text)

def _is_marker_pattern(p: str) -> bool:
    """
    Ignore markers like س1, س2, Q1, etc.
    These create noisy fuzzy hits.
    """
    p = (p or "").strip()
    if not p:
        return True
    if re.fullmatch(r"[سsS]\s*\d+", p):
        return True
    if re.fullmatch(r"[qQ]\s*\d+", p):
        return True
    return False

def _boundary_phrase_score(m: str, p: str) -> int:
    """
    Strong score if pattern appears as a whole phrase with boundaries.
    """
    if not p:
        return 0
    rx = r"(^|[\s\W])" + re.escape(p) + r"($|[\s\W])"
    return 5000 + len(p) if re.search(rx, m) else 0

def nav_score(msg: str, pattern: str) -> int:
    if not msg or not pattern:
        return 0
    if _is_marker_pattern(pattern):
        return 0

    is_ar = bool(AR_LETTER.search(msg)) or bool(AR_LETTER.search(pattern))
    m = _nav_norm(msg, is_ar)
    p = _nav_norm(pattern, is_ar)
    if not m or not p:
        return 0

    # Ignore too-short patterns (cause noisy matches like "طلب")
    if len(p) <= 2:
        return 0

    # Exact match (strongest)
    if m == p:
        return 10000 + len(p)

    # Phrase boundary match (very strong)
    phrase_sc = _boundary_phrase_score(m, p)
    if phrase_sc:
        return phrase_sc

    # Substring gets strong but not as strong as phrase boundary
    if p in m:
        return 2000 + len(p)

    # Fuzzy match (moderate)
    sc = fuzz.partial_ratio(m, p)

    # Penalize short patterns so "order/طلب" doesn't dominate everything
    if len(p) < 6:
        sc -= 10
    if len(p) < 4:
        sc -= 20

    return max(sc, 0)

def _contains_any(msg: str, hints: List[str], is_ar: bool) -> bool:
    m = _nav_norm(msg, is_ar)
    for h in hints:
        hh = _nav_norm(h, is_ar)
        if hh and hh in m:
            return True
    return False

def detect_navigation(msg: str, lang: Optional[str] = None) -> Optional[Dict[str, Any]]:
    """
    UI detection:
    1) Hard overrides for cancel/track
    2) Otherwise: score all intents (JSON patterns + code aliases) and pick best
    """
    if not msg:
        return None

    raw = msg.strip()
    lang = lang if lang in ("ar", "en") else detect_lang(raw)
    is_ar = (lang == "ar") or bool(AR_LETTER.search(raw))
    low = raw.lower()
    nar = normalize_ar(raw)

    # ---- 1) HARD OVERRIDES ----
    if _contains_any(raw, CANCEL_HINTS_AR, True) or any(h in low for h in CANCEL_HINTS_EN):
        return _NAV_BY_INTENT.get("cancel_order") or None

    if _contains_any(raw, TRACK_HINTS_AR, True) or any(h in low for h in TRACK_HINTS_EN):
        return _NAV_BY_INTENT.get("track_order") or None

    # ---- 2) SCORED MATCH (best wins) ----
    best_item = None
    best_score = 0
    best_priority = -1
    best_pat_len = 0
    best_pattern = ""

    for item in NAV_GUIDE:
        intent = item.get("intent", "") or ""
        pr = NAV_PRIORITY.get(intent, 0)

        # combine JSON patterns + code aliases (lang-specific)
        patterns = list(item.get("question_patterns", []) or [])
        aliases = (NAV_ALIASES.get(intent, {}) or {}).get(lang, []) or []
        patterns.extend(aliases)

        for pattern in patterns:
            sc = nav_score(raw, pattern)
            if sc <= 0:
                continue

            pnorm = _nav_norm(pattern, is_ar)
            plen = len(pnorm)

            if (
                sc > best_score
                or (sc == best_score and pr > best_priority)
                or (sc == best_score and pr == best_priority and plen > best_pat_len)
            ):
                best_item = item
                best_score = sc
                best_priority = pr
                best_pat_len = plen
                best_pattern = pattern

    # Accept if phrase/exact/substring match OR very strong fuzzy match
    if best_score >= 2000 or best_score >= 85:
        # Optional: debug why matched
        # print("NAV MATCH:", {"intent": best_item.get("intent"), "score": best_score, "pattern": best_pattern})
        return best_item

    return None

def render_navigation(item: Dict[str, Any], lang: str) -> str:
    if lang == "ar":
        return item.get("response_ar") or item.get("response_en") or ""
    return item.get("response_en") or item.get("response_ar") or ""

# ============================================================
# MEDICATION INDEX
# ============================================================
MED_IDX: List[Tuple[str, Dict[str, Any]]] = []
for med in MEDS:
    for kw in (med.get("keywords") or []):
        kw = (kw or "").strip()
        if kw:
            MED_IDX.append((kw, med))

def best_med_match(msg: str, thr: int = 70) -> Optional[Dict[str, Any]]:
    best, score = None, 0
    for kw, med in MED_IDX:
        s = fuzzy_score(msg, kw)
        if s > score:
            best, score = med, s
    return best if score >= thr else None

def med_display_name(med: Dict[str, Any], lang: str) -> str:
    if lang == "ar":
        return med.get("display_name_ar") or med.get("display_name_en") or med.get("id", "هذا الدواء")
    return med.get("display_name_en") or med.get("display_name_ar") or med.get("id", "this medication")

# ============================================================
# INTENT DETECTION — ORDER MATTERS
# 1) UI (already handled earlier)
# 2) Storage
# 3) Safety explain / safety evaluation
# 4) Clarify (if ambiguous)
# ============================================================

# Strong storage keywords (include "ابرد" explicitly)
STORAGE_PATTERNS_AR = [
    "كيف اخزن", "كيف أُخزن", "كيف احفظ", "كيف أحفظ", "تخزين", "حفظ",
    "كيف ابرد", "كيف أبرد", "تبريد", "برد", "برّد",
    "ثلاجه", "ثلاجة", "تبريد", "درجة حرارة", "حراره", "حرارة",
    "ارجعه للثلاجه", "ارجعه للثلاجة", "ارجعه للثلاجه", "ارجعه"
]
STORAGE_PATTERNS_EN = [
    "how to store", "storage", "keep", "refrigerate", "fridge", "temperature", "room temperature", "return to fridge"
]

SAFETY_EXPLAIN_PATTERNS = [
    "كيف أعرف أنه غير آمن", "كيف اعرف انه غير امن",
    "ما علامات عدم السلامة", "علامات عدم السلامة", "متى يكون غير آمن",
    "كيف أعرف أنه خربان", "كيف اعرف انه خربان",
    "how do i know it's not safe", "unsafe signs", "when is it unsafe", "how do i know it's spoiled",
]

# Generic “is it unsafe/spoiled” phrases
GENERIC_UNSAFE_PHRASES_AR = ["غير آمن", "غير امن", "خربان", "فاسد", "ما اقدر استخدمه", "ما أقدر أستخدمه"]
GENERIC_UNSAFE_PHRASES_EN = ["unsafe", "not safe", "spoiled", "ruined", "cant use it", "can't use it", "doesn't work", "doesnt work"]

# Unsafe signs vocabulary (lightweight; real check is via allowed unsafe_signs)
UNSAFE_HINTS_AR = ["لون", "تغير اللون", "متغير اللون", "رائحة", "ريحة", "قوام", "متكتل", "رواسب", "مجمد", "تجمّد", "منتهي", "انتهى", "لزج", "زلق", "رطب", "مبلول"]
UNSAFE_HINTS_EN = ["color", "discolored", "smell", "odor", "texture", "clumpy", "particles", "frozen", "expired", "sticky", "slimy", "wet"]

def _pattern_match_general(msg: str, pattern: str) -> bool:
    if AR_LETTER.search(msg) or AR_LETTER.search(pattern):
        m = normalize_ar(msg)
        p = normalize_ar(pattern)
        if p in m:
            return True
        return fuzz.partial_ratio(m, p) >= 78
    m = normalize_en(msg)
    p = normalize_en(pattern)
    if p in m:
        return True
    return fuzz.partial_ratio(m, p) >= 80

def is_safety_explain_request(msg: str) -> bool:
    for p in SAFETY_EXPLAIN_PATTERNS:
        if _pattern_match_general(msg, p):
            return True
    return False

def has_generic_unsafe_phrase(msg: str) -> bool:
    t = (msg or "").lower()
    for p in GENERIC_UNSAFE_PHRASES_EN:
        if p in t:
            return True
    for p in GENERIC_UNSAFE_PHRASES_AR:
        if p in (msg or ""):
            return True
    # fuzzy fallback
    for p in GENERIC_UNSAFE_PHRASES_EN + GENERIC_UNSAFE_PHRASES_AR:
        if fuzzy_score(msg, p) >= 88:
            return True
    return False

# ============================================================
# SIGN DETECTION (allowed by meds.json safety.unsafe_signs/safe_signs)
# ============================================================
UNSAFE_SYNONYMS = {
    "clumpy": ["clumpy", "particles", "sediment", "lumps", "متكتل", "رواسب", "شوائب", "حبيبات"],
    "frozen": ["frozen", "freezing", "ice", "مجمد", "تجمّد", "ثلج"],
    "discolored": ["discolored", "color changed", "yellow", "brown", "black", "تغير اللون", "متغير اللون", "مصفر", "اسود", "بني"],
    "expired": ["expired", "out of date", "منتهي", "انتهت الصلاحية", "منتهي الصلاحيه"],
    "overheated": ["overheated", "heat", "hot", "sun", "car", "حرارة", "شمس", "سيارة", "سخن", "حار"],
    "not_refrigerated": ["not refrigerated", "outside fridge", "left out", "خارج الثلاجة", "برا الثلاجه"],
    "bad_smell": ["bad smell", "weird smell", "odor", "rotten", "رائحة", "ريحة", "كريه"],
    "thickened": ["thickened", "gooey", "gel", "viscous", "slimy", "sticky", "لزج", "زلق", "قوام سميك", "هلامي"],
    "moist": ["moist", "wet", "damp", "رطب", "مبلول", "مبلله"],
    "cracked": ["cracked", "crumbly", "broken", "تفتت", "مفتت", "مشقّق", "متكسر"],
    "fermented": ["fermented", "foamy", "bubbly", "فقاعات", "رغوة", "مخمر"],
    "smell_alcohol": ["alcohol smell", "رائحة كحول", "ريحة كحول"],
    "contaminated": ["contaminated", "dirty", "opened", "ملوث", "تلوث"],
    "separated": ["separated", "layered", "انفصل", "منفصل", "طبقات"],
    "damaged": ["damaged", "broken", "leaking", "تالف", "مكسور", "تسريب"],
}

SAFE_SYNONYMS = {
    "clear": ["clear", "transparent", "colorless", "شفاف", "صافي", "عديم اللون", "لا لون له"],
    "normal_smell": ["normal smell", "smells normal", "رائحته طبيعية", "ريحة طبيعية"],
    "looks_normal": ["looks normal", "normal", "طبيعي", "شكله طبيعي"],
    "dry_intact": ["dry", "intact", "جاف", "سليم", "غير رطب"],
}

def detect_sign_keys(msg: str, med: Dict[str, Any]) -> Dict[str, List[str]]:
    safety = (med.get("safety") or {})
    allowed_unsafe = set(safety.get("unsafe_signs") or [])
    allowed_safe = set(safety.get("safe_signs") or [])

    res = {"unsafe": [], "safe": []}
    text = msg or ""

    for key, syns in UNSAFE_SYNONYMS.items():
        if key not in allowed_unsafe:
            continue
        for s in syns:
            if s and (s.lower() in text.lower() or fuzzy_score(text, s) >= 85):
                if key not in res["unsafe"]:
                    res["unsafe"].append(key)
                break

    for key, syns in SAFE_SYNONYMS.items():
        if key not in allowed_safe:
            continue
        for s in syns:
            if s and (s.lower() in text.lower() or fuzzy_score(text, s) >= 85):
                if key not in res["safe"]:
                    res["safe"].append(key)
                break

    return res

# ============================================================
# INTENT: Storage vs Safety (after medication match)
# ============================================================
def _collect_med_patterns(med: Dict[str, Any], key: str) -> List[str]:
    """
    Supports improved meds.json:
      med.intent_patterns.storage / med.intent_patterns.safety
    Backward-compatible: returns empty list if not present.
    """
    ip = med.get("intent_patterns") or {}
    vals = ip.get(key) or []
    return [v for v in vals if isinstance(v, str) and v.strip()]

def score_storage_intent(msg: str, med: Optional[Dict[str, Any]]) -> int:
    patterns = STORAGE_PATTERNS_AR + STORAGE_PATTERNS_EN
    if med:
        patterns += _collect_med_patterns(med, "storage")
    return max((fuzzy_score(msg, p) for p in patterns), default=0)

def score_safety_intent(msg: str, med: Optional[Dict[str, Any]]) -> int:
    patterns = UNSAFE_HINTS_AR + UNSAFE_HINTS_EN
    if med:
        patterns += _collect_med_patterns(med, "safety")
    return max((fuzzy_score(msg, p) for p in patterns), default=0)

def detect_med_intent(msg: str, med: Dict[str, Any]) -> str:
    """
    Returns:
      - "storage"
      - "safety_explain"
      - "safety_eval"
      - "clarify" (ask user which one)
    """
    if is_safety_explain_request(msg):
        return "safety_explain"

    # Storage priority: if message contains storage verbs, do NOT fall into safety
    s_store = score_storage_intent(msg, med)

    # Safety triggers:
    detected_signs = detect_sign_keys(msg, med)
    has_signs = bool(detected_signs["unsafe"] or detected_signs["safe"])
    s_safe = score_safety_intent(msg, med)
    generic_unsafe = has_generic_unsafe_phrase(msg)

    # Rule: explicit storage wins unless safety is very explicit
    if s_store >= 75 and (not generic_unsafe) and (not has_signs) and s_safe < 85:
        return "storage"

    # If there are unsafe/safe signals, it’s safety eval
    if has_signs or generic_unsafe or s_safe >= 85:
        return "safety_eval"

    # If store is still clearly higher, choose storage
    if s_store >= s_safe + 8 and s_store >= 70:
        return "storage"

    # Otherwise ambiguous
    return "clarify"

# ============================================================
# RENDERING (deterministic base answers)
# ============================================================
UNSAFE_LABELS = {
    "ar": {
        "clumpy": "متكتل/فيه رواسب",
        "frozen": "مجمد/تعرض للتجمّد",
        "discolored": "متغير اللون",
        "expired": "منتهي الصلاحية",
        "overheated": "تعرض لحرارة عالية",
        "not_refrigerated": "حُفظ خارج التبريد",
        "bad_smell": "رائحة سيئة/غريبة",
        "thickened": "القوام صار سميك/لزج",
        "moist": "رطب/مبلول",
        "cracked": "مشقّق/مفتت",
        "fermented": "فيه رغوة/فقاعات (تخمّر)",
        "smell_alcohol": "رائحة كحول",
        "contaminated": "اشتباه تلوث",
        "separated": "منفصل/طبقات",
        "damaged": "تالف/مكسور/تسريب",
    },
    "en": {
        "clumpy": "clumpy/particles",
        "frozen": "frozen",
        "discolored": "color changed",
        "expired": "expired",
        "overheated": "overheated",
        "not_refrigerated": "not refrigerated",
        "bad_smell": "bad/weird smell",
        "thickened": "unusually thick/gel-like",
        "moist": "moist/wet",
        "cracked": "cracked/crumbly",
        "fermented": "foamy/bubbly (fermented)",
        "smell_alcohol": "alcohol smell",
        "contaminated": "possible contamination",
        "separated": "separated/layered",
        "damaged": "damaged/leaking",
    }
}

def render_storage(med: Dict[str, Any], lang: str) -> str:
    dn = med_display_name(med, lang)
    storage = med.get("storage") or {}

    notes_en = (storage.get("notes_en") or "").strip()
    notes_ar = (storage.get("notes_ar") or "").strip()
    can_back = storage.get("can_return_to_fridge")

    # optional structured fields (if you add them)
    temp = storage.get("temp_c") or {}
    tmin = temp.get("min")
    tmax = temp.get("max")
    room_max = storage.get("room_temp_max_c")
    opened_days = storage.get("opened_days_hint")

    if lang == "ar":
        back = "نعم" if bool(can_back) else "لا"
        line1 = f"طريقة حفظ {dn}:"
        structured = []
        if isinstance(tmin, (int, float)) and isinstance(tmax, (int, float)):
            structured.append(f"• الثلاجة: {tmin}–{tmax}°C")
        if isinstance(room_max, (int, float)):
            structured.append(f"• درجة الغرفة (حد أعلى تقريبي): أقل من {room_max}°C")
        if isinstance(opened_days, (int, float)):
            structured.append(f"• بعد الفتح (تقريبًا): {int(opened_days)} يوم (حسب نوعك)")
        structured_text = ("\n" + "\n".join(structured)) if structured else ""

        notes = notes_ar or "يرجى اتباع تعليمات الحفظ المذكورة على ملصق الدواء/النشرة."
        return (
            f"{line1}\n"
            f"{notes}"
            f"{structured_text}\n"
            f"هل يمكن إعادته إلى الثلاجة؟ {back}."
        )

    back = "Yes" if bool(can_back) else "No"
    line1 = f"Storage for {dn}:"
    structured = []
    if isinstance(tmin, (int, float)) and isinstance(tmax, (int, float)):
        structured.append(f"• Fridge: {tmin}–{tmax}°C")
    if isinstance(room_max, (int, float)):
        structured.append(f"• Room temperature (approx max): below {room_max}°C")
    if isinstance(opened_days, (int, float)):
        structured.append(f"• After opening (approx): {int(opened_days)} days (brand-dependent)")
    structured_text = ("\n" + "\n".join(structured)) if structured else ""

    notes = notes_en or "Please follow the storage instructions on the label/leaflet."
    return (
        f"{line1}\n"
        f"{notes}"
        f"{structured_text}\n"
        f"Can it return to the fridge? {back}."
    )

def render_safety_summary(med: Dict[str, Any], lang: str) -> str:
    dn = med_display_name(med, lang)
    safety = med.get("safety") or {}
    if lang == "ar":
        summary = (safety.get("summary_ar") or "").strip()
        if not summary:
            return f"ملخص سلامة {dn}: لا توجد بيانات كافية ضمن النظام حاليًا."
        return f"ملخص سلامة {dn}:\n{summary}"
    summary = (safety.get("summary_en") or "").strip()
    if not summary:
        return f"Safety summary for {dn}: no sufficient data is available in the system."
    return f"Safety summary for {dn}:\n{summary}"

def render_safety_eval(med: Dict[str, Any], msg: str, lang: str) -> str:
    dn = med_display_name(med, lang)
    safety = med.get("safety") or {}

    detected = detect_sign_keys(msg, med)
    unsafe = detected.get("unsafe", [])
    safe = detected.get("safe", [])

    if unsafe:
        action = (safety.get("if_unsafe_ar") if lang == "ar" else safety.get("if_unsafe_en")) or ""
        if lang == "ar":
            reasons = "، ".join([UNSAFE_LABELS["ar"].get(k, k) for k in unsafe])
            return (
                f"النتيجة: غير آمن ({dn}).\n"
                f"المؤشرات المرصودة: {reasons}.\n"
                f"الإجراء الموصى به: {action}"
            )
        reasons = ", ".join([UNSAFE_LABELS["en"].get(k, k) for k in unsafe])
        return (
            f"Verdict: Unsafe ({dn}).\n"
            f"Detected signals: {reasons}.\n"
            f"Recommended action: {action}"
        )

    if safe:
        caution = (safety.get("if_unclear_ar") if lang == "ar" else safety.get("if_unclear_en")) or ""
        if lang == "ar":
            signals = "، ".join(safe)
            return (
                f"النتيجة: غالبًا آمن ({dn}).\n"
                f"المؤشرات المرصودة: {signals}.\n"
                f"{caution}"
            )
        signals = ", ".join(safe)
        return (
            f"Verdict: Likely safe ({dn}).\n"
            f"Detected signals: {signals}.\n"
            f"{caution}"
        )

    # No signs detected: ask clarifying safety questions (NOT storage!)
    qs = safety.get("clarifying_questions_ar") if lang == "ar" else safety.get("clarifying_questions_en")
    qs = (qs or [])[:3]

    if lang == "ar":
        if not qs:
            return (
                f"لا يمكن تحديد سلامة {dn} لأن الوصف غير كافٍ.\n"
                "هل سؤالك عن التخزين أم عن السلامة؟ (مثال: تخزين = ثلاجة/درجة حرارة، سلامة = تغيّر لون/رائحة/قوام/تجمّد)."
            )
        return (
            f"لفحص سلامة {dn} أحتاج تفاصيل بسيطة:\n"
            + "\n".join([f"• {q}" for q in qs])
        )

    if not qs:
        return (
            f"I can’t determine whether {dn} is safe because details are missing.\n"
            "Is your question about storage or safety?"
        )
    return (
        f"To assess {dn} safety, I need a bit more detail:\n"
        + "\n".join([f"• {q}" for q in qs])
    )

def render_clarify_storage_or_safety(med: Dict[str, Any], lang: str) -> str:
    dn = med_display_name(med, lang)
    if lang == "ar":
        return (
            f"سؤالك عن {dn} غير واضح هل تقصد:\n"
            "1) التخزين (ثلاجة/درجة حرارة/بعد الفتح)\n"
            "أم\n"
            "2) السلامة (هل هو غير آمن بسبب لون/رائحة/قوام/تجمّد/صالحية)\n"
            "اكتب: «تخزين» أو «سلامة» مع تفاصيل قصيرة."
        )
    return (
        f"Your question about {dn} is unclear.\n"
        "Do you mean:\n"
        "1) Storage (fridge/temperature/after opening)\n"
        "or\n"
        "2) Safety (unsafe signs like color/smell/texture/freezing/expiry)\n"
        "Reply with: “storage” or “safety” and one detail."
    )

# ============================================================
# ONBOARDING / FALLBACK (NO LLM)
# ============================================================
def supported_meds_brief(lang: str, max_n: int = 5) -> str:
    names = [med_display_name(m, lang) for m in MEDS]
    names = [n for n in names if n]
    return "، ".join(names[:max_n]) if lang == "ar" else ", ".join(names[:max_n])

def build_onboarding(lang: str) -> str:
    meds = supported_meds_brief(lang)
    if lang == "ar":
        return (
            "مرحبًا بك في ترياق.\n"
            "يمكنك السؤال عن:\n"
            "• طريقة استخدام التطبيق (الطلب/التتبع/الإلغاء/العنوان/اللغة/الإشعارات)\n"
            "• تخزين الدواء (ثلاجة/درجة حرارة)\n"
            "• سلامة الدواء (تغيّر لون/رائحة/قوام/تجمّد/صالحية)\n\n"
            f"أمثلة أدوية مدعومة: {meds}\n"
            "مثال: «كيف أتتبع الطلب؟» أو «كيف أخزن الإنسولين؟» أو «الإنسولين مصفر»"
        )
    return (
        "Welcome to Teryaq.\n"
        "You can ask about:\n"
        "• App usage (order/track/cancel/address/language/notifications)\n"
        "• Medication storage\n"
        "• Medication safety (unsafe signs)\n\n"
        f"Examples of supported meds: {meds}\n"
        "Try: “How do I track my order?” or “How do I store insulin?”"
    )

def fallback_help(lang: str) -> str:
    meds = supported_meds_brief(lang)
    if lang == "ar":
        return (
            "لم أفهم سؤالك بدقة.\n"
            "هل تقصد سؤالًا عن التطبيق (طلب/تتبع/إلغاء...) أم عن دواء؟\n"
            f"أمثلة أدوية مدعومة: {meds}\n"
            "اكتب اسم الدواء + سؤالك (تخزين أو سلامة)."
        )
    return (
        "I couldn’t identify your request.\n"
        "Is it about the app (order/track/cancel...) or a medication?\n"
        f"Examples of supported meds: {meds}\n"
        "Write the medication name + your question (storage or safety)."
    )

# ============================================================
# LLM REWRITE (optional) — NEVER for UI
# (unchanged behavior for safety/storage; only UI matching improved above)
# ============================================================
def _ollama_generate(prompt: str) -> Tuple[str, int, str]:
    start = time.perf_counter()
    try:
        r = requests.post(
            f"{OLLAMA_URL}/api/generate",
            json={
                "model": OLLAMA_MODEL,
                "prompt": prompt,
                "stream": False,
                "options": {
                    "temperature": 0.75,
                    "top_p": 0.9,
                    "repeat_penalty": 1.12
                }
            },
            timeout=TRIOQ_LLM_TIMEOUT
        )
        ms = int((time.perf_counter() - start) * 1000)
        if r.status_code != 200:
            return "", ms, f"HTTP {r.status_code}: {r.text[:200]}"
        data = r.json()
        out = (data.get("response") or "").strip()
        return out, ms, ""
    except Exception as e:
        ms = int((time.perf_counter() - start) * 1000)
        return "", ms, repr(e)

def _basic_lang_check(lang: str, text: str) -> bool:
    if not text.strip():
        return False
    if lang == "ar":
        return (len(AR_LETTER.findall(text)) / max(1, len(text))) >= 0.08
    return (len(AR_LETTER.findall(text)) / max(1, len(text))) < 0.20

def _build_rewrite_prompt(lang: str, user_msg: str, base_text: str, anchors: List[str]) -> str:
    anchor_block = "\n".join([f"- {a}" for a in anchors if a.strip()]) or "- (none)"
    if lang == "ar":
        return f"""أعد صياغة الإجابة فقط لتكون طبيعية وواضحة وبأسلوب مختلف.
ممنوع: إضافة معلومات جديدة أو تغيير أي حقيقة.

قواعد إلزامية:
- يجب أن تتضمن الإجابة الحقائق المطلوبة حرفيًا.
- لا تستخدم نفس قالب النص الأصلي أو نفس عناوينه.

رسالة المستخدم:
{user_msg}

الإجابة الأصلية (للمعنى فقط):
{base_text}

الحقائق المطلوبة (لازم تظهر حرفيًا):
{anchor_block}

اكتب الإجابة النهائية:
"""
    return f"""Rewrite the answer only to be clearer and more natural with different wording.
Forbidden: adding new info or changing facts.

Rules:
- You MUST include the REQUIRED FACTS verbatim.
- Avoid the same template/headings as the original.

USER MESSAGE:
{user_msg}

ORIGINAL (meaning only):
{base_text}

REQUIRED FACTS (must appear verbatim):
{anchor_block}

Write the final rewritten answer:
"""

def _anchors_present(text: str, anchors: List[str]) -> bool:
    for a in anchors:
        if a.strip() and a not in text:
            return False
    return True

def maybe_rewrite_med_answer(
    lang: str,
    user_msg: str,
    base_text: str,
    anchors: List[str],
    enabled: bool
) -> Tuple[str, int, Dict[str, Any]]:
    """
    Optional LLM rewrite with guards:
    - must keep anchors
    - must be correct language
    - must differ from base enough
    Otherwise return base.
    """
    meta: Dict[str, Any] = {"used_llm": False, "llm_error": "", "similarity": None}

    if not enabled:
        return base_text, 0, meta

    prompt = _build_rewrite_prompt(lang, user_msg, base_text, anchors)
    out, ms, err = _ollama_generate(prompt)

    meta["similarity"] = similarity_score(out, base_text) if out else None

    if err:
        meta["llm_error"] = err
        return base_text, ms, meta

    ok = (
        out.strip()
        and _basic_lang_check(lang, out)
        # NOTE: leaving your current behavior intact; not adding anchor/similarity gates here
        # because you asked not to touch safety/storage logic.
    )
    if not ok:
        return base_text, ms, meta

    meta["used_llm"] = True
    return out.strip(), ms, meta

# ============================================================
# FASTAPI
# ============================================================
app = FastAPI(title="TRIOQ (UI deterministic + Storage/Safety deterministic with optional rewrite)")

@app.get("/", response_class=HTMLResponse)
def home():
    return "<h3>💊 TRIOQ — UI (NO LLM) + Storage/Safety (deterministic base + LLM rewrite)</h3>"

@app.post("/chat")
async def chat(request: Request):
    d = await request.json()
    msg = (d.get("message") or "").strip()
    if not msg:
        return {"response": "", "llm_ms": 0}

    req_lang = (d.get("lang") or "").strip().lower()
    lang = req_lang if req_lang in ("ar", "en") else detect_lang(msg)

    # 0) Greeting -> onboarding (NO LLM)
    if is_greeting(msg):
        resp = build_onboarding(lang)
        print_debug("ONBOARDING", lang, msg, {"llm_ms": 0}, resp)
        return {"response": resp, "llm_ms": 0}

    # 1) UI / navigation ALWAYS FIRST (NO LLM) — FIXED matcher
    nav = detect_navigation(msg, lang=lang)
    if nav:
        resp = render_navigation(nav, lang)
        print_debug("APP_HELP", lang, msg, {"Intent": nav.get("intent"), "llm_ms": 0}, resp)
        return {"response": resp, "llm_ms": 0}

    # 2) Medication match
    med = best_med_match(msg, thr=70)
    if not med:
        resp = fallback_help(lang)
        print_debug("NO_MED_MATCH", lang, msg, {"llm_ms": 0}, resp)
        return {"response": resp, "llm_ms": 0}

    # 3) Decide between Storage vs Safety vs Clarify
    intent = detect_med_intent(msg, med)

    # 3a) Storage (deterministic base + LLM rewrite)
    if intent == "storage":
        base = render_storage(med, lang)

        anchors = [med_display_name(med, lang)]
        can_back = (med.get("storage") or {}).get("can_return_to_fridge")
        if lang == "ar":
            anchors.append("نعم" if bool(can_back) else "لا")
        else:
            anchors.append("Yes" if bool(can_back) else "No")

        final_text, llm_ms, llm_meta = maybe_rewrite_med_answer(
            lang=lang,
            user_msg=msg,
            base_text=base,
            anchors=anchors,
            enabled=TRIOQ_USE_LLM_REWRITE_STORAGE
        )

        print_debug(
            "MEDICATION_STORAGE",
            lang,
            msg,
            {
                "Medication": med.get("id"),
                "intent": intent,
                "llm_ms": llm_ms,
                "llm_used": llm_meta.get("used_llm"),
                "llm_error": llm_meta.get("llm_error"),
                "similarity": llm_meta.get("similarity"),
            },
            final_text
        )
        return {"response": final_text, "llm_ms": llm_ms}

    # 3b) Safety explain (deterministic base + LLM rewrite)
    if intent == "safety_explain":
        base = render_safety_summary(med, lang)
        anchors = [med_display_name(med, lang)]

        final_text, llm_ms, llm_meta = maybe_rewrite_med_answer(
            lang=lang,
            user_msg=msg,
            base_text=base,
            anchors=anchors,
            enabled=TRIOQ_USE_LLM_REWRITE_SAFETY
        )

        print_debug(
            "SAFETY_EXPLAIN",
            lang,
            msg,
            {
                "Medication": med.get("id"),
                "intent": intent,
                "llm_ms": llm_ms,
                "llm_used": llm_meta.get("used_llm"),
                "llm_error": llm_meta.get("llm_error"),
                "similarity": llm_meta.get("similarity"),
            },
            final_text
        )
        return {"response": final_text, "llm_ms": llm_ms}

    # 3c) Safety evaluation (deterministic base + LLM rewrite)
    if intent == "safety_eval":
        base = render_safety_eval(med, msg, lang)

        anchors = [med_display_name(med, lang)]
        if lang == "ar":
            if "غير آمن" in base:
                anchors.append("غير آمن")
            if "غالبًا آمن" in base:
                anchors.append("غالبًا آمن")
        else:
            if "Unsafe" in base:
                anchors.append("Unsafe")
            if "Likely safe" in base:
                anchors.append("Likely safe")

        final_text, llm_ms, llm_meta = maybe_rewrite_med_answer(
            lang=lang,
            user_msg=msg,
            base_text=base,
            anchors=anchors,
            enabled=TRIOQ_USE_LLM_REWRITE_SAFETY
        )

        detected = detect_sign_keys(msg, med)
        print_debug(
            "MEDICATION_SAFETY",
            lang,
            msg,
            {
                "Medication": med.get("id"),
                "intent": intent,
                "Detected": detected,
                "llm_ms": llm_ms,
                "llm_used": llm_meta.get("used_llm"),
                "llm_error": llm_meta.get("llm_error"),
                "similarity": llm_meta.get("similarity"),
            },
            final_text
        )
        return {"response": final_text, "llm_ms": llm_ms}

    # 3d) Clarify (deterministic)
    resp = render_clarify_storage_or_safety(med, lang)
    print_debug("CLARIFY", lang, msg, {"Medication": med.get("id"), "intent": intent, "llm_ms": 0}, resp)
    return {"response": resp, "llm_ms": 0}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=7860, reload=False)

