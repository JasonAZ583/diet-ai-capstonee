"""AI-powered meal suggestion service using Dedalus Labs.

Uses structured outputs for type-safe AI responses.
"""
import os
import json
import asyncio
from typing import List, Optional
from pydantic import BaseModel, Field

# Dedalus Labs SDK - using async client for structured outputs
from dedalus_labs import AsyncDedalus


# --- Response Schemas for Structured Outputs ---

class AIIngredient(BaseModel):
    """AI response schema for a single ingredient."""
    food_item_id: int = Field(description="ID from the vault list")
    name: str = Field(description="Name of the ingredient")
    amount_grams: float = Field(description="Amount in grams to use")


class AIMealSuggestion(BaseModel):
    """AI response schema for a meal suggestion."""
    name: str = Field(description="Creative meal name")
    description: str = Field(description="Brief description of the meal")
    ingredients: List[AIIngredient] = Field(description="List of ingredients from vault")
    instructions: List[str] = Field(default_factory=list, description="Step-by-step cooking instructions")


class AIMealResponse(BaseModel):
    """Structured output schema for meal suggestions."""
    suggestions: List[AIMealSuggestion] = Field(description="List of meal suggestions")


# --- Application Models ---

class MealIngredient(BaseModel):
    """An ingredient in a suggested meal with calculated macros."""
    food_item_id: int
    name: str
    amount_grams: float
    calories: float
    protein: float
    carbs: float
    fat: float


class MealSuggestion(BaseModel):
    """A suggested meal with full nutritional breakdown."""
    name: str
    description: str
    ingredients: List[MealIngredient]
    total_calories: float
    total_protein: float
    total_carbs: float
    total_fat: float
    is_makeable: bool
    missing_items: List[str] = []
    instructions: List[str] = []


def get_dedalus_client() -> Optional[AsyncDedalus]:
    """Get async Dedalus client if API key is configured."""
    api_key = os.getenv("DEDALUS_API_KEY")
    if not api_key:
        return None
    return AsyncDedalus(api_key=api_key, timeout=120)


async def generate_meal_suggestions_async(
    vault_items: List[dict],
    remaining_calories: float,
    remaining_protein: float,
    remaining_carbs: float,
    remaining_fat: float,
    num_suggestions: int = 3,
    meal_type: str = None
) -> List[MealSuggestion]:
    """
    Generate meal suggestions using Dedalus Labs AI with structured outputs.

    Uses Pydantic schemas for type-safe, validated responses.
    """
    client = get_dedalus_client()

    if not client:
        # Fallback to simple rule-based suggestions if no API key
        return generate_simple_suggestions(
            vault_items, remaining_calories, remaining_protein,
            remaining_carbs, remaining_fat, num_suggestions
        )

    # Build prompt with vault contents
    vault_info = "\n".join([
        f"- ID:{item['id']} | {item['name']} | {item['quantity']} units available | "
        f"Per 100g: {item['calories']} cal, {item['protein']}g protein, "
        f"{item['carbs']}g carbs, {item['fat']}g fat"
        for item in vault_items if item['quantity'] > 0
    ])

    meal_type_instruction = ""
    if meal_type:
        meal_type_label = meal_type.capitalize()
        meal_type_hints = {
            "breakfast": "Think omelettes, smoothie bowls, overnight oats, breakfast burritos, pancakes, etc.",
            "lunch": "Think salads, wraps, sandwiches, grain bowls, soups, etc.",
            "dinner": "Think stir-fries, pasta, roasted plates, curries, casseroles, etc.",
            "snack": "Think lighter bites - dips, trail mix, energy bites, small plates, etc.",
            "dessert": "Think sweet treats - fruit bowls, yogurt parfaits, protein desserts, etc.",
        }
        hint = meal_type_hints.get(meal_type, "")
        meal_type_instruction = f"\nMEAL TYPE: {meal_type_label}\nAll suggestions MUST be appropriate for {meal_type_label.lower()}. {hint}\n"

    prompt = f"""You are a meal planning assistant. Based on the available ingredients, suggest {num_suggestions} creative meal ideas that COMBINE multiple ingredients together.
{meal_type_instruction}
AVAILABLE INGREDIENTS IN VAULT:
{vault_info}

REMAINING MACRO BUDGET FOR TODAY:
- Calories: {remaining_calories:.0f}
- Protein: {remaining_protein:.1f}g
- Carbs: {remaining_carbs:.1f}g
- Fat: {remaining_fat:.1f}g

RULES:
1. COMBINE multiple ingredients into each meal (e.g., "Chicken Stir Fry with Rice and Broccoli")
2. Use realistic portion sizes in grams
3. Create tasty, practical meal combinations
4. Only use food_item_id values from the vault list above
5. Stay within the calorie budget
6. Each meal MUST combine 2+ ingredients
7. Include 3-6 clear cooking steps as an ordered list of short imperative sentences

Respond with JSON in this EXACT format (include "instructions" as an array of strings):
{{"suggestions": [{{"name": "Meal Name", "description": "Brief description", "ingredients": [{{"food_item_id": 1, "name": "Item Name", "amount_grams": 150}}], "instructions": ["Step 1 ...", "Step 2 ...", "Step 3 ..."]}}]}}"""

    try:
        # Use a non-reasoning model — gpt-5-nano is a reasoning model that burns
        # all output tokens on internal reasoning and returns empty content,
        # causing "AI returned empty content" errors.
        completion = await client.chat.completions.create(
            model="openai/gpt-4o-mini",
            messages=[
                {"role": "system", "content": "You are a meal planning assistant. Always respond with valid JSON only, no other text."},
                {"role": "user", "content": prompt},
            ],
            max_tokens=2000,
            temperature=0.7,
            response_format={"type": "json_object"},
        )

        # Parse JSON response and validate with Pydantic
        content = completion.choices[0].message.content or ""
        content = content.strip()
        if not content:
            print(f"AI returned empty content. Full response: {completion}")
            raise ValueError("AI returned empty content")
        # Strip markdown code fences if present
        if content.startswith("```"):
            content = content.split("\n", 1)[1] if "\n" in content else content[3:]
            content = content.rsplit("```", 1)[0].strip()
        raw_json = json.loads(content)
        ai_response = AIMealResponse.model_validate(raw_json)
        raw_suggestions = ai_response.suggestions

        # Build a lookup dict for vault items
        vault_lookup = {item['id']: item for item in vault_items}

        suggestions = []
        for raw in raw_suggestions:
            ingredients = []
            total_cal = 0
            total_p = 0
            total_c = 0
            total_f = 0
            is_makeable = True
            missing = []

            for ing in raw.ingredients:
                item_id = ing.food_item_id
                amount = ing.amount_grams

                if item_id not in vault_lookup:
                    is_makeable = False
                    missing.append(ing.name or f'Unknown item {item_id}')
                    continue

                item = vault_lookup[item_id]
                # Check if enough quantity (rough check: amount needed vs serving_size * quantity)
                servings_needed = amount / item.get('serving_size', 100)
                if servings_needed > item.get('quantity', 0):
                    is_makeable = False
                    missing.append(f"{item['name']} (need {servings_needed:.1f}, have {item['quantity']})")

                # Calculate macros for this portion
                ratio = amount / 100  # Nutrition is per 100g
                cal = item['calories'] * ratio
                p = item['protein'] * ratio
                c = item['carbs'] * ratio
                f = item['fat'] * ratio

                total_cal += cal
                total_p += p
                total_c += c
                total_f += f

                ingredients.append(MealIngredient(
                    food_item_id=item_id,
                    name=item['name'],
                    amount_grams=amount,
                    calories=round(cal, 1),
                    protein=round(p, 1),
                    carbs=round(c, 1),
                    fat=round(f, 1)
                ))

            suggestions.append(MealSuggestion(
                name=raw.name,
                description=raw.description,
                ingredients=ingredients,
                total_calories=round(total_cal, 1),
                total_protein=round(total_p, 1),
                total_carbs=round(total_c, 1),
                total_fat=round(total_f, 1),
                is_makeable=is_makeable,
                missing_items=missing,
                instructions=list(raw.instructions or []),
            ))

        return suggestions

    except Exception as e:
        print(f"AI generation error: {e}")
        # Fallback to simple suggestions
        return generate_simple_suggestions(
            vault_items, remaining_calories, remaining_protein,
            remaining_carbs, remaining_fat, num_suggestions
        )


def generate_meal_suggestions(
    vault_items: List[dict],
    remaining_calories: float,
    remaining_protein: float,
    remaining_carbs: float,
    remaining_fat: float,
    num_suggestions: int = 3
) -> List[MealSuggestion]:
    """
    Sync wrapper for generate_meal_suggestions_async.

    Maintains backward compatibility with existing sync code.
    """
    try:
        # Check if we're already in an async context
        loop = asyncio.get_running_loop()
        # If we get here, we're in async context - this shouldn't happen in normal usage
        # Fall back to simple suggestions to avoid nested event loop issues
        return generate_simple_suggestions(
            vault_items, remaining_calories, remaining_protein,
            remaining_carbs, remaining_fat, num_suggestions
        )
    except RuntimeError:
        # No running event loop - safe to use asyncio.run()
        return asyncio.run(generate_meal_suggestions_async(
            vault_items, remaining_calories, remaining_protein,
            remaining_carbs, remaining_fat, num_suggestions
        ))




def _simple_steps(ingredients: List["MealIngredient"]) -> List[str]:
    """Return basic cooking steps for a rule-based meal combination."""
    if not ingredients:
        return []
    steps = [
        f"Prepare your ingredients: {', '.join(f'{round(i.amount_grams)}g {i.name}' for i in ingredients)}.",
    ]
    first = ingredients[0].name
    steps.append(f"Start with the {first} as the base in a bowl or plate.")
    for ing in ingredients[1:]:
        steps.append(f"Add {round(ing.amount_grams)}g of {ing.name} and combine.")
    steps.append("Season to taste, plate, and serve.")
    return steps


def generate_simple_suggestions(
    vault_items: List[dict],
    remaining_calories: float,
    remaining_protein: float,
    remaining_carbs: float,
    remaining_fat: float,
    num_suggestions: int = 3
) -> List[MealSuggestion]:
    """
    Generate smart rule-based meal suggestions that combine vault items.
    Creates balanced meals using multiple ingredients.
    """
    suggestions = []
    available_items = [item for item in vault_items if item.get('quantity', 0) > 0]

    if not available_items:
        return []

    # Categorize items by their primary macro
    proteins = []  # High protein items (>15g per 100g)
    carbs_items = []  # High carb items (>15g per 100g)
    veggies = []  # Low calorie items (<50 cal per 100g)
    fats_items = []  # High fat items (>10g per 100g)

    for item in available_items:
        cal = item.get('calories', 0)
        p = item.get('protein', 0)
        c = item.get('carbs', 0)
        f = item.get('fat', 0)

        if p >= 15:
            proteins.append(item)
        elif c >= 15:
            carbs_items.append(item)
        elif cal < 50:
            veggies.append(item)
        elif f >= 10:
            fats_items.append(item)
        else:
            # Default to carbs if no clear category
            carbs_items.append(item)

    def calc_portion(item, target_cal):
        """Calculate portion size to hit target calories."""
        cal_per_100g = item.get('calories', 100) or 100
        portion = (target_cal / cal_per_100g) * 100
        # Clamp to reasonable serving sizes
        return min(300, max(50, portion))

    def make_ingredient(item, grams):
        """Create ingredient with calculated macros."""
        ratio = grams / 100
        return MealIngredient(
            food_item_id=item['id'],
            name=item['name'],
            amount_grams=round(grams, 0),
            calories=round(item['calories'] * ratio, 1),
            protein=round(item['protein'] * ratio, 1),
            carbs=round(item['carbs'] * ratio, 1),
            fat=round(item['fat'] * ratio, 1)
        )

    def check_makeable(ingredients, vault_lookup):
        """Check if all ingredients are available in sufficient quantity."""
        missing = []
        for ing in ingredients:
            item = vault_lookup.get(ing.food_item_id)
            if not item:
                missing.append(ing.name)
                continue
            servings_needed = ing.amount_grams / item.get('serving_size', 100)
            if servings_needed > item.get('quantity', 0):
                missing.append(f"{ing.name} (need {servings_needed:.1f}, have {item['quantity']})")
        return len(missing) == 0, missing

    vault_lookup = {item['id']: item for item in available_items}
    target_cal_per_meal = remaining_calories / 3 if remaining_calories > 0 else 500

    # Suggestion 1: Balanced Plate (protein + carb + veggie)
    if proteins and (carbs_items or veggies):
        ingredients = []
        total_cal, total_p, total_c, total_f = 0, 0, 0, 0

        # Add protein (40% of calories)
        protein_item = proteins[0]
        protein_grams = calc_portion(protein_item, target_cal_per_meal * 0.4)
        ing = make_ingredient(protein_item, protein_grams)
        ingredients.append(ing)
        total_cal += ing.calories
        total_p += ing.protein
        total_c += ing.carbs
        total_f += ing.fat

        # Add carb if available (40% of calories)
        if carbs_items:
            carb_item = carbs_items[0]
            carb_grams = calc_portion(carb_item, target_cal_per_meal * 0.4)
            ing = make_ingredient(carb_item, carb_grams)
            ingredients.append(ing)
            total_cal += ing.calories
            total_p += ing.protein
            total_c += ing.carbs
            total_f += ing.fat

        # Add veggie if available (20% of calories or 100g min)
        if veggies:
            veg_item = veggies[0]
            veg_grams = max(100, calc_portion(veg_item, target_cal_per_meal * 0.2))
            ing = make_ingredient(veg_item, veg_grams)
            ingredients.append(ing)
            total_cal += ing.calories
            total_p += ing.protein
            total_c += ing.carbs
            total_f += ing.fat

        is_makeable, missing = check_makeable(ingredients, vault_lookup)
        suggestions.append(MealSuggestion(
            name="Balanced Plate",
            description="A well-rounded meal with protein, carbs, and veggies",
            ingredients=ingredients,
            total_calories=round(total_cal, 1),
            total_protein=round(total_p, 1),
            total_carbs=round(total_c, 1),
            total_fat=round(total_f, 1),
            is_makeable=is_makeable,
            missing_items=missing,
            instructions=_simple_steps(ingredients),
        ))

    # Suggestion 2: High Protein Bowl
    if proteins:
        ingredients = []
        total_cal, total_p, total_c, total_f = 0, 0, 0, 0

        # Use up to 2 protein sources
        for protein_item in proteins[:2]:
            protein_grams = calc_portion(protein_item, target_cal_per_meal * 0.35)
            ing = make_ingredient(protein_item, protein_grams)
            ingredients.append(ing)
            total_cal += ing.calories
            total_p += ing.protein
            total_c += ing.carbs
            total_f += ing.fat

        # Add veggie for volume
        if veggies:
            veg_item = veggies[0] if len(veggies) == 1 else veggies[1] if len(veggies) > 1 else veggies[0]
            veg_grams = 150
            ing = make_ingredient(veg_item, veg_grams)
            ingredients.append(ing)
            total_cal += ing.calories
            total_p += ing.protein
            total_c += ing.carbs
            total_f += ing.fat

        is_makeable, missing = check_makeable(ingredients, vault_lookup)
        suggestions.append(MealSuggestion(
            name="High Protein Bowl",
            description="Protein-packed meal for muscle building and satiety",
            ingredients=ingredients,
            total_calories=round(total_cal, 1),
            total_protein=round(total_p, 1),
            total_carbs=round(total_c, 1),
            total_fat=round(total_f, 1),
            is_makeable=is_makeable,
            missing_items=missing,
            instructions=_simple_steps(ingredients),
        ))

    # Suggestion 3: Light & Fresh (veggie-forward)
    if veggies or carbs_items:
        ingredients = []
        total_cal, total_p, total_c, total_f = 0, 0, 0, 0

        # Add all available veggies (small portions each)
        for veg_item in veggies[:3]:
            veg_grams = 100
            ing = make_ingredient(veg_item, veg_grams)
            ingredients.append(ing)
            total_cal += ing.calories
            total_p += ing.protein
            total_c += ing.carbs
            total_f += ing.fat

        # Add a protein for balance if available
        if proteins:
            protein_item = proteins[-1] if len(proteins) > 1 else proteins[0]
            protein_grams = calc_portion(protein_item, target_cal_per_meal * 0.3)
            ing = make_ingredient(protein_item, protein_grams)
            ingredients.append(ing)
            total_cal += ing.calories
            total_p += ing.protein
            total_c += ing.carbs
            total_f += ing.fat

        if ingredients:
            is_makeable, missing = check_makeable(ingredients, vault_lookup)
            suggestions.append(MealSuggestion(
                name="Light & Fresh",
                description="A lighter meal with plenty of vegetables",
                ingredients=ingredients,
                total_calories=round(total_cal, 1),
                total_protein=round(total_p, 1),
                total_carbs=round(total_c, 1),
                total_fat=round(total_f, 1),
                is_makeable=is_makeable,
                missing_items=missing
            ))

    # If we don't have enough variety, create combo meals from what's available
    if len(suggestions) < num_suggestions:
        # Create a meal using all available items
        ingredients = []
        total_cal, total_p, total_c, total_f = 0, 0, 0, 0

        for item in available_items[:4]:
            grams = calc_portion(item, target_cal_per_meal / min(len(available_items), 4))
            ing = make_ingredient(item, grams)
            ingredients.append(ing)
            total_cal += ing.calories
            total_p += ing.protein
            total_c += ing.carbs
            total_f += ing.fat

        if ingredients:
            is_makeable, missing = check_makeable(ingredients, vault_lookup)
            suggestions.append(MealSuggestion(
                name="Everything Bowl",
                description="A mix of everything in your vault",
                ingredients=ingredients,
                total_calories=round(total_cal, 1),
                total_protein=round(total_p, 1),
                total_carbs=round(total_c, 1),
                total_fat=round(total_f, 1),
                is_makeable=is_makeable,
                missing_items=missing
            ))

    return suggestions[:num_suggestions]
