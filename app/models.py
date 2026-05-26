from sqlalchemy import Column, Integer, String, Float, DateTime, Date, ForeignKey, Enum
from sqlalchemy.sql import func
from sqlalchemy.orm import relationship
import enum
from app.database import Base


class ActivityLevel(str, enum.Enum):
    SEDENTARY = "sedentary"  # Little or no exercise
    LIGHT = "light"  # Light exercise 1-3 days/week
    MODERATE = "moderate"  # Moderate exercise 3-5 days/week
    ACTIVE = "active"  # Hard exercise 6-7 days/week
    VERY_ACTIVE = "very_active"  # Very hard exercise, physical job


class GoalType(str, enum.Enum):
    LOSE = "lose"  # Weight loss
    MAINTAIN = "maintain"  # Maintain weight
    GAIN = "gain"  # Weight gain / muscle building


class UserProfile(Base):
    __tablename__ = "user_profiles"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, default="User")

    # Physical stats
    weight = Column(Float, nullable=True)  # kg
    height = Column(Float, nullable=True)  # cm
    age = Column(Integer, nullable=True)
    gender = Column(String, nullable=True)  # male, female

    # Goals
    activity_level = Column(String, default=ActivityLevel.MODERATE.value)
    goal_type = Column(String, default=GoalType.MAINTAIN.value)

    # Manual goals (if set, override calculated)
    manual_calories = Column(Float, nullable=True)
    manual_protein = Column(Float, nullable=True)
    manual_carbs = Column(Float, nullable=True)
    manual_fat = Column(Float, nullable=True)

    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, onupdate=func.now())


class MealLog(Base):
    __tablename__ = "meal_logs"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("user_profiles.id"), default=1)
    date = Column(Date, server_default=func.current_date())

    # What was eaten
    name = Column(String, nullable=False)
    food_item_id = Column(Integer, ForeignKey("food_items.id"), nullable=True)

    # Amount consumed
    amount = Column(Float, default=100)  # grams
    servings = Column(Float, default=1)

    # Macros for this meal (calculated at log time)
    calories = Column(Float, default=0)
    protein = Column(Float, default=0)
    carbs = Column(Float, default=0)
    fat = Column(Float, default=0)

    # JSON list of {food_item_id, amount_grams} used to build this meal.
    # Populated for vault-based and suggestion-confirmed meals so we can
    # restore vault quantities if the meal is deleted.
    ingredients_json = Column(String, nullable=True)

    created_at = Column(DateTime, server_default=func.now())

    # Relationships
    food_item = relationship("FoodItem")


class FoodItem(Base):
    __tablename__ = "food_items"

    id = Column(Integer, primary_key=True, index=True)
    barcode = Column(String, index=True, nullable=True)
    name = Column(String, nullable=False)
    brand = Column(String, nullable=True)

    # Nutrition per 100g
    calories = Column(Float, default=0)
    protein = Column(Float, default=0)
    carbs = Column(Float, default=0)
    fat = Column(Float, default=0)
    fiber = Column(Float, default=0)

    # Quantity in vault
    quantity = Column(Float, default=1)  # number of units
    serving_size = Column(Float, default=100)  # grams per serving
    unit = Column(String, default="g")

    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, onupdate=func.now())
