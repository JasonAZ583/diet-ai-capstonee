"""Local barcode lookup + product search against the bundled Open Food Facts
TSV dump.

DuckDB reads the TSV directly via ``read_csv`` and pushes filters down so cold
queries on broad terms ("chicken") finish in ~2 seconds. A small in-process
cache makes repeat searches instant.

If ``app/foods.tsv`` is missing the lookup falls through to the remote OFF
API (handled by :func:`app.services.openfoodfacts.fetch_product_by_barcode`).
"""

from __future__ import annotations

import asyncio
import re
import threading
from pathlib import Path
from typing import Optional

import duckdb

from app.schemas import FoodItemBase

_BASE = Path(__file__).resolve().parent.parent
TSV_PATH = _BASE / "foods.tsv"

# Energy in OFF is reported in kJ (`energy_100g`). 1 kcal = 4.184 kJ.
_KJ_PER_KCAL = 4.184

_con_lock = threading.Lock()
_con: Optional[duckdb.DuckDBPyConnection] = None


def _get_connection() -> Optional[duckdb.DuckDBPyConnection]:
    global _con
    if not TSV_PATH.exists():
        return None
    with _con_lock:
        if _con is None:
            _con = duckdb.connect(":memory:")
    return _con


# Shared CSV reader options. `all_varchar=true` keeps the parser simple and
# fast — we cast individual columns to numbers ourselves.
_TSV_FROM = f"""
FROM read_csv(
    '{TSV_PATH.as_posix()}',
    delim='\t',
    header=true,
    strict_mode=false,
    ignore_errors=true,
    all_varchar=true
)
""".strip()


_PROJECT = """
    code,
    NULLIF(brands, '') AS brands,
    NULLIF(product_name, '') AS name,
    serving_size AS serving_raw,
    TRY_CAST(energy_100g       AS DOUBLE) AS energy_kj,
    TRY_CAST(proteins_100g     AS DOUBLE) AS protein,
    TRY_CAST(carbohydrates_100g AS DOUBLE) AS carbs,
    TRY_CAST(fat_100g          AS DOUBLE) AS fat,
    TRY_CAST(fiber_100g        AS DOUBLE) AS fiber
"""


# ── Barcode lookup ─────────────────────────────────────────────────────────

_LOOKUP_SQL = f"""
SELECT {_PROJECT}
{_TSV_FROM}
WHERE code = ?
LIMIT 1
"""


def _lookup_sync(code: str) -> Optional[FoodItemBase]:
    con = _get_connection()
    if con is None:
        return None

    candidates: list[str] = []
    seen: set[str] = set()
    for c in (code, code.zfill(13), code.lstrip("0")):
        if c and c not in seen:
            candidates.append(c)
            seen.add(c)

    cur = con.cursor()
    try:
        for cand in candidates:
            row = cur.execute(_LOOKUP_SQL, [cand]).fetchone()
            if row:
                return _row_to_item(row, fallback_code=code)
    finally:
        cur.close()
    return None


async def fetch_product_by_barcode_local(code: str) -> Optional[FoodItemBase]:
    return await asyncio.to_thread(_lookup_sync, code)


# ── Search by name ─────────────────────────────────────────────────────────

# We rank by data completeness (full macros > partial > none) then by short
# name (cleaner items first). The TSV doesn't ship a popularity score.
_SEARCH_TEMPLATE = f"""
SELECT {_PROJECT}
{_TSV_FROM}
WHERE
    product_name IS NOT NULL
    AND ({{predicate}})
ORDER BY
    (TRY_CAST(energy_100g AS DOUBLE) IS NOT NULL
     AND TRY_CAST(proteins_100g AS DOUBLE) IS NOT NULL
     AND TRY_CAST(carbohydrates_100g AS DOUBLE) IS NOT NULL
     AND TRY_CAST(fat_100g AS DOUBLE) IS NOT NULL) DESC,
    length(product_name) ASC
LIMIT ?
"""


def _build_predicate(words: list[str]) -> tuple[str, list[str]]:
    parts: list[str] = []
    args: list[str] = []
    for w in words:
        like = f"%{w}%"
        parts.append("(product_name ILIKE ? OR brands ILIKE ?)")
        args.extend([like, like])
    return " AND ".join(parts) if parts else "1=1", args


_search_cache_lock = threading.Lock()
_search_cache: dict[tuple[str, int], list[FoodItemBase]] = {}
_SEARCH_CACHE_MAX = 64


def _search_sync(query: str, limit: int) -> list[FoodItemBase]:
    key = (query.lower().strip(), limit)
    with _search_cache_lock:
        cached = _search_cache.get(key)
        if cached is not None:
            return cached

    con = _get_connection()
    if con is None:
        return []
    words = [w for w in query.lower().split() if w]
    if not words:
        return []

    predicate, args = _build_predicate(words)
    sql = _SEARCH_TEMPLATE.format(predicate=predicate)

    cur = con.cursor()
    try:
        rows = cur.execute(sql, args + [limit]).fetchall()
    finally:
        cur.close()

    items = [_row_to_item(r) for r in rows]

    with _search_cache_lock:
        if len(_search_cache) >= _SEARCH_CACHE_MAX:
            _search_cache.pop(next(iter(_search_cache)))
        _search_cache[key] = items

    return items


async def search_products_local(query: str, limit: int = 25) -> list[FoodItemBase]:
    return await asyncio.to_thread(_search_sync, query, limit)


# ── Helpers ────────────────────────────────────────────────────────────────


_SERVING_NUMERIC = re.compile(r"(\d+(?:[.,]\d+)?)")


def _parse_serving_grams(raw: Optional[str]) -> float:
    """Pull a numeric gram weight out of strings like '100g', '30 ml', '1/4 cup (62g)'."""
    if not raw:
        return 100.0
    match = _SERVING_NUMERIC.search(raw)
    if not match:
        return 100.0
    try:
        return float(match.group(1).replace(",", "."))
    except ValueError:
        return 100.0


def _row_to_item(row, fallback_code: Optional[str] = None) -> FoodItemBase:
    code, brands, name, serving_raw, energy_kj, protein, carbs, fat, fiber = row
    calories = (energy_kj / _KJ_PER_KCAL) if energy_kj else 0.0
    return FoodItemBase(
        barcode=code or fallback_code,
        name=(name or "Unknown").strip() or "Unknown",
        brand=(brands or None) or None,
        calories=round(float(calories), 1),
        protein=float(protein or 0),
        carbs=float(carbs or 0),
        fat=float(fat or 0),
        fiber=float(fiber or 0),
        serving_size=_parse_serving_grams(serving_raw),
        unit="g",
    )
