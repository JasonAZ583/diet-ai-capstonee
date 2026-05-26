from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime, date
from enum import Enum


class ActivityLevel(str, Enum):
    SEDENTARY = "sedentary"
    LIGHT = "light"
    MODERATE = "moderate"
    ACTIVE = "active"
    VERY_ACTIVE = "very_active"


class GoalType(str, Enum):
    LOSE = "lose"
    MAINTAIN = "maintain"
    GAIN = "gain"


class MealCategory(str, Enum):
    BREAKFAST = "breakfast"
    LUNCH = "lunch"
    DINNER = "dinner"
    SNACK = "snack"
    DESSERT = "dessert"


class FoodItemBase(BaseModel):
    name: str
    barcode: Optional[str] = None
    brand: Optional[str] = None
    calories: float = 0
    protein: float = 0
    carbs: float = 0
    fat: float = 0
    fiber: float = 0
    quantity: float = 1
    serving_size: float = 100
    unit: str = "g"


class FoodItemCreate(FoodItemBase):
    pass


class FoodItemUpdate(BaseModel):
    name: Optional[str] = None
    quantity: Optional[float] = None
    serving_size: Optional[float] = None


class FoodItem(FoodItemBase):
    id: int
    created_at: datetime
    updated_at: Optional[datetime] = None

    class Config:
        from_attributes = True


class BarcodeResponse(BaseModel):
    found: bool
    product: Optional[FoodItemBase] = None
    message: str


# --- User Profile ---

class UserProfileBase(BaseModel):
    name: str = "User"
    weight: Optional[float] = None  # kg
    height: Optional[float] = None  # cm
    age: Optional[int] = None
    gender: Optional[str] = None
    activity_level: ActivityLevel = ActivityLevel.MODERATE
    goal_type: GoalType = GoalType.MAINTAIN


class UserProfileCreate(UserProfileBase):
    pass


class UserProfileUpdate(BaseModel):
    name: Optional[str] = None
    weight: Optional[float] = None
    height: Optional[float] = None
    age: Optional[int] = None
    gender: Optional[str] = None
    activity_level: Optional[ActivityLevel] = None
    goal_type: Optional[GoalType] = None
    manual_calories: Optional[float] = None
    manual_protein: Optional[float] = None
    manual_carbs: Optional[float] = None
    manual_fat: Optional[float] = None


class UserProfile(UserProfileBase):
    id: int
    manual_calories: Optional[float] = None
    manual_protein: Optional[float] = None
    manual_carbs: Optional[float] = None
    manual_fat: Optional[float] = None
    created_at: datetime
    updated_at: Optional[datetime] = None

    class Config:
        from_attributes = True


# --- Goals ---

class DailyGoals(BaseModel):
    calories: float
    protein: float
    carbs: float
    fat: float
    is_manual: bool = False


class GoalsCalculateRequest(BaseModel):
    weight: float  # kg
    height: float  # cm
    age: int
    gender: str  # male or female
    activity_level: ActivityLevel
    goal_type: GoalType


# --- Meal Logging ---

class MealLogCreate(BaseModel):
    food_item_id: Optional[int] = None
    name: Optional[str] = None
    amount: float = 100  # grams
    servings: float = 1
    # If no food_item_id, these are required
    calories: Optional[float] = None
    protein: Optional[float] = None
    carbs: Optional[float] = None
    fat: Optional[float] = None
    # Optional explicit time (ISO 8601). If omitted, server uses current time.
    eaten_at: Optional[datetime] = None


class MealLog(BaseModel):
    id: int
    name: str
    food_item_id: Optional[int] = None
    date: date
    amount: float
    servings: float
    calories: float
    protein: float
    carbs: float
    fat: float
    created_at: datetime

    class Config:
        from_attributes = True


# --- Dashboard ---

class DailyProgress(BaseModel):
    date: date
    goals: DailyGoals
    consumed: DailyGoals
    remaining: DailyGoals
    meals: List[MealLog]


# --- AI Meal Suggestions ---

class MealIngredient(BaseModel):
    food_item_id: int
    name: str
    amount_grams: float
    calories: float
    protein: float
    carbs: float
    fat: float


class MealSuggestion(BaseModel):
    name: str
    description: str
    ingredients: List[MealIngredient]
    total_calories: float
    total_protein: float
    total_carbs: float
    total_fat: float
    is_makeable: bool
    missing_items: List[str] = []
    instructions: List[str] = []  # ordered cooking steps


class MealSuggestionsResponse(BaseModel):
    suggestions: List[MealSuggestion]
    remaining_budget: DailyGoals


class ConfirmMealRequest(BaseModel):
    suggestion_index: int  # Which suggestion to confirm
    # Or provide the meal details directly
    name: Optional[str] = None
    ingredients: Optional[List[MealIngredient]] = None
