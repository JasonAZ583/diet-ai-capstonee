from dotenv import load_dotenv
load_dotenv()

from fastapi import FastAPI, Depends, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session
from sqlalchemy import func as sql_func
from typing import List, Optional
from datetime import date

from app.database import engine, get_db, Base
from app.models import FoodItem as FoodItemModel, UserProfile as UserProfileModel, MealLog as MealLogModel
from app.schemas import (
    FoodItem, FoodItemBase, FoodItemCreate, FoodItemUpdate, BarcodeResponse,
    UserProfile, UserProfileUpdate, DailyGoals, GoalsCalculateRequest,
    MealLog, MealLogCreate, DailyProgress,
    MealSuggestion, MealSuggestionsResponse, MealIngredient, ConfirmMealRequest
)
from app.services.openfoodfacts import fetch_product_by_barcode
from app.services.local_food_db import search_products_local
from app.services.meal_ai import generate_meal_suggestions_async, MealSuggestion as AIMealSuggestion
from app.services.chat_ai import (
    ChatRequest as ChatReq,
    ChatResponse as ChatResp,
    LoggedMealAction,
    generate_chat_reply_async,
)

# Create tables
Base.metadata.create_all(bind=engine)


def _migrate_sqlite_schema() -> None:
    """Add columns to existing tables on SQLite when the model gains new fields.

    SQLAlchemy's ``create_all`` doesn't alter existing tables, so we issue
    idempotent ``ALTER TABLE`` statements for columns we know we added.
    """
    from sqlalchemy import text
    from sqlalchemy.exc import OperationalError
    adds = [
        ("meal_logs", "ingredients_json", "TEXT"),
    ]
    with engine.connect() as conn:
        for table, col, ctype in adds:
            try:
                existing = {row[1] for row in conn.exec_driver_sql(f"PRAGMA table_info({table})").fetchall()}
            except OperationalError:
                continue
            if col not in existing:
                try:
                    conn.exec_driver_sql(f"ALTER TABLE {table} ADD COLUMN {col} {ctype}")
                    conn.commit()
                except OperationalError as e:
                    print(f"migration warning: {e}")


_migrate_sqlite_schema()

app = FastAPI(title="DietAI", description="Smart diet tracking with food vault")

# Allow the SwiftUI demo client (and other local dev clients) to call the API.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Serve static files
app.mount("/static", StaticFiles(directory="static"), name="static")


# --- Startup: Create default user ---

@app.on_event("startup")
def create_default_user():
    from app.database import SessionLocal
    db = SessionLocal()
    try:
        user = db.query(UserProfileModel).first()
        if not user:
            user = UserProfileModel(id=1, name="User")
            db.add(user)
            db.commit()
    finally:
        db.close()


@app.on_event("startup")
async def warm_food_search():
    """Touch the local food TSV once so DuckDB pages it into memory before
    the first user request — turns the first real search from a cold ~2s
    scan into a warm sub-second response."""
    try:
        await search_products_local("chicken", limit=1)
    except Exception:
        pass


@app.get("/")
async def home():
    """Serve the main HTML page."""
    return FileResponse("static/index.html")


# --- Barcode Scanning ---

@app.get("/api/barcode/{barcode}", response_model=BarcodeResponse)
async def scan_barcode(barcode: str):
    """Scan a barcode and get product nutrition info from Open Food Facts."""
    product = await fetch_product_by_barcode(barcode)

    if not product:
        return BarcodeResponse(
            found=False,
            product=None,
            message=f"Product with barcode {barcode} not found"
        )

    return BarcodeResponse(
        found=True,
        product=product,
        message="Product found"
    )


@app.get("/api/foods/search", response_model=List[FoodItemBase])
async def search_foods(q: str, limit: int = 25):
    """Search the bundled Open Food Facts parquet by product name or brand."""
    if not q or not q.strip():
        return []
    limit = max(1, min(limit, 50))
    return await search_products_local(q, limit=limit)


@app.post("/api/barcode/{barcode}/add", response_model=FoodItem)
async def add_from_barcode(barcode: str, quantity: float = 1, db: Session = Depends(get_db)):
    """Scan barcode and add directly to vault."""
    product = await fetch_product_by_barcode(barcode)

    if not product:
        raise HTTPException(status_code=404, detail=f"Product with barcode {barcode} not found")

    # Check if already in vault
    existing = db.query(FoodItemModel).filter(FoodItemModel.barcode == barcode).first()
    if existing:
        existing.quantity += quantity
        db.commit()
        db.refresh(existing)
        return existing

    # Add new item
    product_data = product.model_dump(exclude={"quantity"})
    db_item = FoodItemModel(**product_data, quantity=quantity)
    db.add(db_item)
    db.commit()
    db.refresh(db_item)
    return db_item


# --- Vault CRUD ---

@app.get("/api/vault", response_model=List[FoodItem])
def list_vault(db: Session = Depends(get_db)):
    """List all items in the food vault."""
    return db.query(FoodItemModel).all()


@app.post("/api/vault", response_model=FoodItem)
def add_to_vault(item: FoodItemCreate, db: Session = Depends(get_db)):
    """Manually add an item to the vault."""
    db_item = FoodItemModel(**item.model_dump())
    db.add(db_item)
    db.commit()
    db.refresh(db_item)
    return db_item


@app.get("/api/vault/{item_id}", response_model=FoodItem)
def get_vault_item(item_id: int, db: Session = Depends(get_db)):
    """Get a specific item from the vault."""
    item = db.query(FoodItemModel).filter(FoodItemModel.id == item_id).first()
    if not item:
        raise HTTPException(status_code=404, detail="Item not found")
    return item


@app.patch("/api/vault/{item_id}", response_model=FoodItem)
def update_vault_item(item_id: int, updates: FoodItemUpdate, db: Session = Depends(get_db)):
    """Update an item in the vault (e.g., quantity)."""
    item = db.query(FoodItemModel).filter(FoodItemModel.id == item_id).first()
    if not item:
        raise HTTPException(status_code=404, detail="Item not found")

    for key, value in updates.model_dump(exclude_unset=True).items():
        setattr(item, key, value)

    db.commit()
    db.refresh(item)
    return item


@app.delete("/api/vault/{item_id}")
def delete_vault_item(item_id: int, db: Session = Depends(get_db)):
    """Remove an item from the vault."""
    item = db.query(FoodItemModel).filter(FoodItemModel.id == item_id).first()
    if not item:
        raise HTTPException(status_code=404, detail="Item not found")

    db.delete(item)
    db.commit()
    return {"message": "Item deleted"}


# --- User Profile & Goals ---

@app.get("/api/profile", response_model=UserProfile)
def get_profile(db: Session = Depends(get_db)):
    """Get user profile."""
    user = db.query(UserProfileModel).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return user


@app.patch("/api/profile", response_model=UserProfile)
def update_profile(updates: UserProfileUpdate, db: Session = Depends(get_db)):
    """Update user profile and goals."""
    user = db.query(UserProfileModel).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    for key, value in updates.model_dump(exclude_unset=True).items():
        setattr(user, key, value.value if hasattr(value, 'value') else value)

    db.commit()
    db.refresh(user)
    return user


def calculate_tdee(weight: float, height: float, age: int, gender: str, activity_level: str) -> float:
    """Calculate Total Daily Energy Expenditure using Mifflin-St Jeor equation."""
    # BMR calculation
    if gender.lower() == "male":
        bmr = 10 * weight + 6.25 * height - 5 * age + 5
    else:
        bmr = 10 * weight + 6.25 * height - 5 * age - 161

    # Activity multiplier
    multipliers = {
        "sedentary": 1.2,
        "light": 1.375,
        "moderate": 1.55,
        "active": 1.725,
        "very_active": 1.9
    }
    multiplier = multipliers.get(activity_level, 1.55)

    return bmr * multiplier


def calculate_macros(calories: float, goal_type: str) -> dict:
    """Calculate macro targets based on calories and goal."""
    if goal_type == "lose":
        # Higher protein for muscle preservation during deficit
        protein_pct = 0.30
        fat_pct = 0.25
        carb_pct = 0.45
    elif goal_type == "gain":
        # Balanced for muscle building
        protein_pct = 0.25
        fat_pct = 0.25
        carb_pct = 0.50
    else:  # maintain
        protein_pct = 0.25
        fat_pct = 0.30
        carb_pct = 0.45

    return {
        "protein": round((calories * protein_pct) / 4, 1),  # 4 cal/g
        "carbs": round((calories * carb_pct) / 4, 1),  # 4 cal/g
        "fat": round((calories * fat_pct) / 9, 1),  # 9 cal/g
    }


@app.post("/api/goals/calculate", response_model=DailyGoals)
def calculate_goals(request: GoalsCalculateRequest, db: Session = Depends(get_db)):
    """Calculate daily goals based on user stats."""
    tdee = calculate_tdee(
        request.weight, request.height, request.age,
        request.gender, request.activity_level.value
    )

    # Adjust for goal
    if request.goal_type.value == "lose":
        calories = tdee - 500  # 500 cal deficit
    elif request.goal_type.value == "gain":
        calories = tdee + 300  # 300 cal surplus
    else:
        calories = tdee

    macros = calculate_macros(calories, request.goal_type.value)

    # Save to user profile
    user = db.query(UserProfileModel).first()
    if user:
        user.weight = request.weight
        user.height = request.height
        user.age = request.age
        user.gender = request.gender
        user.activity_level = request.activity_level.value
        user.goal_type = request.goal_type.value
        # Clear manual goals since we're using calculated
        user.manual_calories = None
        user.manual_protein = None
        user.manual_carbs = None
        user.manual_fat = None
        db.commit()

    return DailyGoals(
        calories=round(calories, 0),
        protein=macros["protein"],
        carbs=macros["carbs"],
        fat=macros["fat"],
        is_manual=False
    )


@app.get("/api/goals", response_model=DailyGoals)
def get_goals(db: Session = Depends(get_db)):
    """Get current daily goals."""
    user = db.query(UserProfileModel).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    # Check for manual goals
    if user.manual_calories is not None:
        return DailyGoals(
            calories=user.manual_calories,
            protein=user.manual_protein or 0,
            carbs=user.manual_carbs or 0,
            fat=user.manual_fat or 0,
            is_manual=True
        )

    # Calculate from stats
    if not all([user.weight, user.height, user.age, user.gender]):
        # Return defaults if stats not set
        return DailyGoals(calories=2000, protein=150, carbs=200, fat=67, is_manual=False)

    tdee = calculate_tdee(user.weight, user.height, user.age, user.gender, user.activity_level)

    if user.goal_type == "lose":
        calories = tdee - 500
    elif user.goal_type == "gain":
        calories = tdee + 300
    else:
        calories = tdee

    macros = calculate_macros(calories, user.goal_type)

    return DailyGoals(
        calories=round(calories, 0),
        protein=macros["protein"],
        carbs=macros["carbs"],
        fat=macros["fat"],
        is_manual=False
    )


@app.post("/api/goals/manual", response_model=DailyGoals)
def set_manual_goals(goals: DailyGoals, db: Session = Depends(get_db)):
    """Set manual daily goals."""
    user = db.query(UserProfileModel).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    user.manual_calories = goals.calories
    user.manual_protein = goals.protein
    user.manual_carbs = goals.carbs
    user.manual_fat = goals.fat
    db.commit()

    return DailyGoals(
        calories=goals.calories,
        protein=goals.protein,
        carbs=goals.carbs,
        fat=goals.fat,
        is_manual=True
    )


# --- Meal Logging ---

import json as _json


@app.post("/api/meals", response_model=MealLog)
def log_meal(meal: MealLogCreate, db: Session = Depends(get_db)):
    """Log a meal eaten."""
    if meal.food_item_id:
        # Get macros from vault item
        food_item = db.query(FoodItemModel).filter(FoodItemModel.id == meal.food_item_id).first()
        if not food_item:
            raise HTTPException(status_code=404, detail="Food item not found")

        # Calculate macros based on amount
        ratio = (meal.amount / 100) * meal.servings
        db_meal = MealLogModel(
            user_id=1,
            food_item_id=food_item.id,
            name=meal.name or food_item.name,
            amount=meal.amount,
            servings=meal.servings,
            calories=round(food_item.calories * ratio, 1),
            protein=round(food_item.protein * ratio, 1),
            carbs=round(food_item.carbs * ratio, 1),
            fat=round(food_item.fat * ratio, 1),
            ingredients_json=_json.dumps([
                {"food_item_id": food_item.id, "servings": meal.servings, "amount_grams": meal.amount}
            ]),
        )

        # Decrement vault quantity
        food_item.quantity -= meal.servings
        if food_item.quantity < 0:
            food_item.quantity = 0

    else:
        # Manual entry
        if not meal.name:
            raise HTTPException(status_code=400, detail="Meal name required")

        db_meal = MealLogModel(
            user_id=1,
            name=meal.name,
            amount=meal.amount,
            servings=meal.servings,
            calories=meal.calories or 0,
            protein=meal.protein or 0,
            carbs=meal.carbs or 0,
            fat=meal.fat or 0
        )

    # Honor explicit time if provided (so users can log meals at the time they ate them)
    if meal.eaten_at is not None:
        db_meal.created_at = meal.eaten_at
        db_meal.date = meal.eaten_at.date()

    db.add(db_meal)
    db.commit()
    db.refresh(db_meal)
    return db_meal


@app.get("/api/meals", response_model=List[MealLog])
def list_meals(target_date: date = None, db: Session = Depends(get_db)):
    """List meals for a date (default: today)."""
    if target_date is None:
        target_date = date.today()

    return db.query(MealLogModel).filter(MealLogModel.date == target_date).all()


@app.get("/api/meals/history", response_model=List[MealLog])
def meal_history(limit: int = 50, db: Session = Depends(get_db)):
    """Get recent meal history."""
    return db.query(MealLogModel).order_by(MealLogModel.created_at.desc()).limit(limit).all()


@app.delete("/api/meals/{meal_id}")
def delete_meal(meal_id: int, db: Session = Depends(get_db)):
    """Delete a logged meal and restore any consumed ingredients to the vault."""
    meal = db.query(MealLogModel).filter(MealLogModel.id == meal_id).first()
    if not meal:
        raise HTTPException(status_code=404, detail="Meal not found")

    restored = []
    if meal.ingredients_json:
        try:
            ingredients = _json.loads(meal.ingredients_json)
        except (ValueError, TypeError):
            ingredients = []
        for ing in ingredients:
            fid = ing.get("food_item_id")
            if not fid:
                continue
            food_item = db.query(FoodItemModel).filter(FoodItemModel.id == fid).first()
            if not food_item:
                continue
            # Prefer explicit servings if present (single-item log); otherwise
            # convert grams back to servings using the item's serving_size.
            if "servings" in ing and ing["servings"] is not None:
                delta = float(ing["servings"])
            else:
                amt = float(ing.get("amount_grams", 0) or 0)
                size = float(food_item.serving_size or 100) or 100
                delta = amt / size
            food_item.quantity = (food_item.quantity or 0) + delta
            restored.append({"id": food_item.id, "name": food_item.name, "restored": round(delta, 3)})
    elif meal.food_item_id and meal.servings:
        # Older rows without ingredients_json — fall back to the direct link.
        food_item = db.query(FoodItemModel).filter(FoodItemModel.id == meal.food_item_id).first()
        if food_item:
            food_item.quantity = (food_item.quantity or 0) + float(meal.servings or 0)
            restored.append({"id": food_item.id, "name": food_item.name, "restored": round(float(meal.servings or 0), 3)})

    db.delete(meal)
    db.commit()
    return {"message": "Meal deleted", "restored": restored}


# --- Dashboard ---

@app.get("/api/dashboard", response_model=DailyProgress)
def get_dashboard(target_date: date = None, db: Session = Depends(get_db)):
    """Get daily progress dashboard."""
    if target_date is None:
        target_date = date.today()

    # Get goals
    goals = get_goals(db)

    # Get today's meals
    meals = db.query(MealLogModel).filter(MealLogModel.date == target_date).all()

    # Sum consumed
    consumed_calories = sum(m.calories for m in meals)
    consumed_protein = sum(m.protein for m in meals)
    consumed_carbs = sum(m.carbs for m in meals)
    consumed_fat = sum(m.fat for m in meals)

    consumed = DailyGoals(
        calories=round(consumed_calories, 1),
        protein=round(consumed_protein, 1),
        carbs=round(consumed_carbs, 1),
        fat=round(consumed_fat, 1)
    )

    remaining = DailyGoals(
        calories=round(goals.calories - consumed_calories, 1),
        protein=round(goals.protein - consumed_protein, 1),
        carbs=round(goals.carbs - consumed_carbs, 1),
        fat=round(goals.fat - consumed_fat, 1)
    )

    return DailyProgress(
        date=target_date,
        goals=goals,
        consumed=consumed,
        remaining=remaining,
        meals=meals
    )


# --- AI Meal Suggestions ---

# Store last suggestions in memory for confirm flow (simple approach for MVP)
_last_suggestions: List[MealSuggestion] = []


@app.get("/api/meals/suggest", response_model=MealSuggestionsResponse)
async def suggest_meals(
    num_suggestions: int = 3,
    meal_type: Optional[str] = None,
    item_ids: Optional[str] = None,  # comma-separated vault item IDs
    db: Session = Depends(get_db),
):
    """Get AI-powered meal suggestions based on vault contents and remaining macros.

    If ``item_ids`` is provided, only those vault items are used (even if their
    stored quantity is 0 — the user is asserting they have them).
    """
    global _last_suggestions

    # Get remaining macros for today
    dashboard = get_dashboard(db=db)

    # Get vault items (filtered by explicit IDs if provided)
    force_available = False
    if item_ids:
        try:
            ids = [int(x) for x in item_ids.split(",") if x.strip()]
        except ValueError:
            raise HTTPException(status_code=400, detail="item_ids must be comma-separated integers")
        vault_items = db.query(FoodItemModel).filter(FoodItemModel.id.in_(ids)).all()
        # When caller picks items explicitly, treat them as available regardless of stored quantity
        force_available = True
    else:
        vault_items = db.query(FoodItemModel).filter(FoodItemModel.quantity > 0).all()
    vault_data = [
        {
            "id": item.id,
            "name": item.name,
            "quantity": max(1, item.quantity or 0) if force_available else item.quantity,
            "serving_size": item.serving_size,
            "calories": item.calories,
            "protein": item.protein,
            "carbs": item.carbs,
            "fat": item.fat
        }
        for item in vault_items
    ]

    if not vault_data:
        return MealSuggestionsResponse(
            suggestions=[],
            remaining_budget=dashboard.remaining
        )

    # Generate suggestions using async structured outputs
    ai_suggestions = await generate_meal_suggestions_async(
        vault_items=vault_data,
        remaining_calories=dashboard.remaining.calories,
        remaining_protein=dashboard.remaining.protein,
        remaining_carbs=dashboard.remaining.carbs,
        remaining_fat=dashboard.remaining.fat,
        num_suggestions=num_suggestions,
        meal_type=meal_type
    )

    # Convert to response schema
    suggestions = [
        MealSuggestion(
            name=s.name,
            description=s.description,
            ingredients=[
                MealIngredient(
                    food_item_id=ing.food_item_id,
                    name=ing.name,
                    amount_grams=ing.amount_grams,
                    calories=ing.calories,
                    protein=ing.protein,
                    carbs=ing.carbs,
                    fat=ing.fat
                ) for ing in s.ingredients
            ],
            total_calories=s.total_calories,
            total_protein=s.total_protein,
            total_carbs=s.total_carbs,
            total_fat=s.total_fat,
            is_makeable=s.is_makeable,
            missing_items=s.missing_items,
            instructions=list(s.instructions or []),
        )
        for s in ai_suggestions
    ]

    _last_suggestions = suggestions

    return MealSuggestionsResponse(
        suggestions=suggestions,
        remaining_budget=dashboard.remaining
    )


@app.post("/api/meals/confirm", response_model=MealLog)
def confirm_meal(request: ConfirmMealRequest, db: Session = Depends(get_db)):
    """Confirm making a suggested meal - logs it and decrements vault."""
    global _last_suggestions

    # Get the suggestion to confirm
    if request.ingredients:
        # Direct ingredients provided
        ingredients = request.ingredients
        meal_name = request.name or "Custom Meal"
    elif 0 <= request.suggestion_index < len(_last_suggestions):
        # Use stored suggestion
        suggestion = _last_suggestions[request.suggestion_index]
        ingredients = suggestion.ingredients
        meal_name = suggestion.name
    else:
        raise HTTPException(status_code=400, detail="Invalid suggestion index or no ingredients provided")

    # Calculate totals and decrement vault
    total_cal = 0
    total_p = 0
    total_c = 0
    total_f = 0

    for ing in ingredients:
        # Get vault item
        food_item = db.query(FoodItemModel).filter(FoodItemModel.id == ing.food_item_id).first()
        if not food_item:
            raise HTTPException(status_code=404, detail=f"Food item {ing.food_item_id} not found")

        # Calculate servings used
        servings_used = ing.amount_grams / food_item.serving_size

        # Check if enough in vault
        if food_item.quantity < servings_used:
            raise HTTPException(
                status_code=400,
                detail=f"Not enough {food_item.name} in vault (need {servings_used:.1f}, have {food_item.quantity})"
            )

        # Decrement vault
        food_item.quantity -= servings_used
        if food_item.quantity < 0:
            food_item.quantity = 0

        # Add to totals
        total_cal += ing.calories
        total_p += ing.protein
        total_c += ing.carbs
        total_f += ing.fat

    # Create meal log — persist the ingredient breakdown so delete can restore the vault
    ingredients_payload = [
        {
            "food_item_id": ing.food_item_id,
            "amount_grams": ing.amount_grams,
        }
        for ing in ingredients
    ]
    db_meal = MealLogModel(
        user_id=1,
        name=meal_name,
        amount=sum(ing.amount_grams for ing in ingredients),
        servings=1,
        calories=round(total_cal, 1),
        protein=round(total_p, 1),
        carbs=round(total_c, 1),
        fat=round(total_f, 1),
        ingredients_json=_json.dumps(ingredients_payload),
    )

    db.add(db_meal)
    db.commit()
    db.refresh(db_meal)

    return db_meal


# --- AI Chat ---

async def _log_meal_from_chat(
    args: dict, db: Session
) -> LoggedMealAction:
    """Tool callback the chat AI invokes when it wants to log a meal.

    If `args["ingredients"]` is provided (each entry having `food_item_id`
    and `amount_grams`), the matching vault items are decremented in the
    same transaction and the breakdown is persisted on the meal so a later
    delete restores stock.
    """
    from datetime import datetime as _dt

    # Models occasionally invent slightly different field names — accept the
    # common variants so a tool-call with `food` instead of `name` still works.
    def _pick(*keys, default=None):
        for k in keys:
            if k in args and args[k] not in (None, ""):
                return args[k]
        return default

    name = str(_pick("name", "food", "food_item", "meal", default="Meal")).strip() or "Meal"
    try:
        calories = float(_pick("calories", "kcal", default=0) or 0)
        protein = float(_pick("protein", "protein_g", default=0) or 0)
        carbs = float(_pick("carbs", "carbohydrates", "carbs_g", default=0) or 0)
        fat = float(_pick("fat", "fat_g", default=0) or 0)
        amount = float(_pick("amount_grams", "grams", "weight_grams", default=100) or 100)
    except (TypeError, ValueError):
        calories = protein = carbs = fat = 0.0
        amount = 100.0

    eaten_at_raw = args.get("eaten_at")
    eaten_at: _dt | None = None
    if eaten_at_raw:
        try:
            cleaned = eaten_at_raw.replace("Z", "+00:00")
            eaten_at = _dt.fromisoformat(cleaned)
        except (TypeError, ValueError):
            eaten_at = None

    # Decrement vault for any referenced ingredients. We tolerate bad
    # food_item_ids (model hallucinations) by skipping them silently —
    # we'd rather still log the meal than fail outright.
    ingredient_records: list[dict] = []
    raw_ingredients = args.get("ingredients") or []
    if isinstance(raw_ingredients, list):
        for ing in raw_ingredients:
            if not isinstance(ing, dict):
                continue
            try:
                fid = int(ing.get("food_item_id"))
                grams = float(ing.get("amount_grams") or 0)
            except (TypeError, ValueError):
                continue
            if grams <= 0:
                continue
            food = db.query(FoodItemModel).filter(FoodItemModel.id == fid).first()
            if not food:
                continue
            servings_used = grams / float(food.serving_size or 100)
            food.quantity = max(0.0, float(food.quantity or 0) - servings_used)
            ingredient_records.append({"food_item_id": fid, "amount_grams": grams})

    db_meal = MealLogModel(
        user_id=1,
        name=name,
        amount=amount,
        servings=1,
        calories=round(calories, 1),
        protein=round(protein, 1),
        carbs=round(carbs, 1),
        fat=round(fat, 1),
        ingredients_json=_json.dumps(ingredient_records) if ingredient_records else None,
    )
    if eaten_at is not None:
        db_meal.created_at = eaten_at
        db_meal.date = eaten_at.date()

    db.add(db_meal)
    db.commit()
    db.refresh(db_meal)

    return LoggedMealAction(
        id=db_meal.id,
        name=db_meal.name,
        calories=db_meal.calories,
        protein=db_meal.protein,
        carbs=db_meal.carbs,
        fat=db_meal.fat,
        eaten_at=db_meal.created_at.isoformat() if db_meal.created_at else None,
    )


@app.post("/api/chat", response_model=ChatResp)
async def chat(request: ChatReq, db: Session = Depends(get_db)):
    """Answer user questions using their 14-day diet history via Dedalus LLM.

    The model can call the `log_meal` tool to record meals on the user's
    behalf — those land in the same `meal_logs` table that the dashboard
    and calendar read from, so the UI updates as soon as the chat finishes.
    """
    dashboard = get_dashboard(db=db)

    # Pull meals from the last 14 days so the AI can answer "yesterday", "last Tuesday", etc.
    from datetime import timedelta
    start = date.today() - timedelta(days=13)
    recent_meals = (
        db.query(MealLogModel)
          .filter(MealLogModel.date >= start)
          .order_by(MealLogModel.created_at.asc())
          .all()
    )

    # Group meals by date and compute per-day totals
    by_day = {}
    for m in recent_meals:
        key = m.date.isoformat() if m.date else "unknown"
        day = by_day.setdefault(key, {
            "date": m.date,
            "meals": [],
            "totals": {"calories": 0.0, "protein": 0.0, "carbs": 0.0, "fat": 0.0},
        })
        t = m.created_at.strftime("%-I:%M %p") if m.created_at else ""
        day["meals"].append({
            "time": t,
            "name": m.name,
            "calories": m.calories or 0,
            "protein": m.protein or 0,
            "carbs": m.carbs or 0,
            "fat": m.fat or 0,
        })
        day["totals"]["calories"] += m.calories or 0
        day["totals"]["protein"] += m.protein or 0
        day["totals"]["carbs"] += m.carbs or 0
        day["totals"]["fat"] += m.fat or 0

    # Sort days newest → oldest for the prompt
    history_days = sorted(by_day.values(), key=lambda d: d["date"], reverse=True)

    # Vault snapshot so the AI can propose meals conversationally
    vault_rows = db.query(FoodItemModel).all()
    vault_ctx = [
        {
            "id": v.id,
            "name": v.name,
            "quantity": v.quantity or 0,
            "serving_size": v.serving_size or 100,
            "calories": v.calories or 0,
            "protein": v.protein or 0,
            "carbs": v.carbs or 0,
            "fat": v.fat or 0,
        }
        for v in vault_rows
    ]

    context = {
        "today": date.today().strftime("%A, %B %-d, %Y"),
        "goals": dashboard.goals.model_dump(),
        "today_consumed": dashboard.consumed.model_dump(),
        "today_remaining": dashboard.remaining.model_dump(),
        "history_days": [
            {
                "date": d["date"].strftime("%A, %B %-d, %Y"),
                "iso": d["date"].isoformat(),
                "meals": d["meals"],
                "totals": d["totals"],
            }
            for d in history_days
        ],
        "vault": vault_ctx,
    }

    async def tool_executor(args: dict) -> LoggedMealAction:
        return await _log_meal_from_chat(args, db)

    return await generate_chat_reply_async(
        request.message,
        request.history,
        context,
        tool_executor=tool_executor,
    )


@app.get("/api/meals/check-makeable/{item_id}")
def check_makeable(item_id: int, amount_grams: float = 100, db: Session = Depends(get_db)):
    """Check if a specific amount of a food item is makeable from vault."""
    food_item = db.query(FoodItemModel).filter(FoodItemModel.id == item_id).first()
    if not food_item:
        raise HTTPException(status_code=404, detail="Food item not found")

    servings_needed = amount_grams / food_item.serving_size
    is_makeable = food_item.quantity >= servings_needed

    return {
        "item_id": item_id,
        "name": food_item.name,
        "amount_requested": amount_grams,
        "servings_needed": round(servings_needed, 2),
        "quantity_available": food_item.quantity,
        "is_makeable": is_makeable,
        "shortage": round(servings_needed - food_item.quantity, 2) if not is_makeable else 0
    }
