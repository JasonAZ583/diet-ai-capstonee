import httpx
from typing import Optional

from app.schemas import FoodItemBase
from app.services.local_food_db import fetch_product_by_barcode_local

OFF_API_URL = "https://world.openfoodfacts.org/api/v2/product"


async def _fetch_product_by_barcode_remote(barcode: str) -> Optional[FoodItemBase]:
    """Fetch product info from the Open Food Facts web API."""
    try:
        async with httpx.AsyncClient() as client:
            response = await client.get(
                f"{OFF_API_URL}/{barcode}.json",
                timeout=10.0,
            )
    except httpx.HTTPError:
        return None

    if response.status_code != 200:
        return None

    data = response.json()
    if data.get("status") != 1:
        return None

    product = data.get("product", {})
    nutriments = product.get("nutriments", {})

    return FoodItemBase(
        barcode=barcode,
        name=product.get("product_name", "Unknown"),
        brand=product.get("brands", None),
        calories=nutriments.get("energy-kcal_100g", 0) or 0,
        protein=nutriments.get("proteins_100g", 0) or 0,
        carbs=nutriments.get("carbohydrates_100g", 0) or 0,
        fat=nutriments.get("fat_100g", 0) or 0,
        fiber=nutriments.get("fiber_100g", 0) or 0,
        serving_size=product.get("serving_quantity", 100) or 100,
        unit="g",
    )


async def fetch_product_by_barcode(barcode: str) -> Optional[FoodItemBase]:
    """Resolve a barcode to a ``FoodItemBase``.

    Prefers the local Open Food Facts parquet bundle (``app/food.parquet``)
    when present; falls back to the remote OFF API otherwise. Local hits
    avoid network latency entirely and work offline.
    """
    local = await fetch_product_by_barcode_local(barcode)
    if local is not None:
        return local
    return await _fetch_product_by_barcode_remote(barcode)
