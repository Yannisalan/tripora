import logging
from datetime import date, datetime
from decimal import Decimal, InvalidOperation

from flask import Blueprint, jsonify, request
from flask_jwt_extended import (
    get_jwt_identity,
    jwt_required,
)

from config.database import db
from models.expense import (
    EXPENSE_CATEGORIES,
    PAYMENT_METHODS,
    VALID_CURRENCIES,
    Expense,
)
from models.trip import Trip

logger = logging.getLogger(__name__)


expenses_bp = Blueprint(
    "expenses",
    __name__,
    url_prefix="/api",
)


# ============================================================
# HELPERS
# ============================================================

def _get_authenticated_user_id():
    user_id = get_jwt_identity()
    try:
        return int(user_id)
    except (TypeError, ValueError):
        raise ValueError("Invalid authenticated user.")


def _get_owned_trip_or_404(trip_id, user_id):
    """Return the trip owned by ``user_id`` or None (already resolved to 404)."""
    return Trip.query.filter_by(
        id=trip_id,
        user_id=user_id,
    ).first()


def _parse_expense_payload(data, partial=False):
    """Validate/create an update dict for an Expense.

    ``partial=True`` means every field is optional (PATCH semantics).
    Returns (update_dict, errors_message_or_None).
    """
    if not data:
        return None, "No expense data provided."

    update = {}
    now = datetime.utcnow()

    amount = data.get("amount")
    if amount is not None or not partial:
        if amount is None or amount == "":
            return None, "Amount is required."
        try:
            value = Decimal(str(amount))
            if not value.is_finite() or value <= 0:
                raise InvalidOperation
            update["amount"] = value.quantize(Decimal("0.01"))
        except (InvalidOperation, TypeError):
            return None, "Amount must be a positive number."
    else:
        update["amount"] = None

    currency = data.get("currency")
    if currency is not None or not partial:
        clean_currency = str(currency or "USD").strip().upper()
        if clean_currency not in VALID_CURRENCIES:
            return None, "Currency is invalid."
        update["currency"] = clean_currency
    else:
        update["currency"] = None

    category = data.get("category")
    if category is not None or not partial:
        clean_category = str(category or "").strip().lower()
        if clean_category not in EXPENSE_CATEGORIES:
            return None, "Expense category is invalid."
        update["category"] = clean_category
    else:
        update["category"] = None

    description = data.get("description")
    if description is not None or not partial:
        clean_description = str(description or "").strip()
        if len(clean_description) > 255:
            return None, "Description is too long."
        update["description"] = clean_description or None
    else:
        update["description"] = None

    expense_date = data.get("date")
    if expense_date is not None or not partial:
        if not expense_date:
            return None, "Date is required."
        try:
            date_value = date.fromisoformat(str(expense_date)[:10])
        except (ValueError, TypeError):
            return None, "Invalid date format."
        if date_value > now.date():
            return None, "Expense date cannot be in the future."
        update["date"] = date_value
    else:
        update["date"] = None

    payment_method = data.get("paymentMethod")
    if payment_method is not None or not partial:
        clean_method = str(payment_method or "").strip().lower()
        if not clean_method and not partial:
            clean_method = "other"
        if clean_method not in PAYMENT_METHODS:
            return None, "Payment method is invalid."
        update["payment_method"] = clean_method or None
    else:
        update["payment_method"] = None

    return update, None


# ============================================================
# LIST TRIP EXPENSES
# GET /api/trips/<trip_id>/expenses
# ============================================================

@expenses_bp.route("/trips/<int:trip_id>/expenses", methods=["GET"])
@jwt_required()
def get_trip_expenses(trip_id):

    try:
        user_id = _get_authenticated_user_id()
    except ValueError as error:
        return jsonify({
            "success": False,
            "message": str(error),
        }), 401

    try:
        trip = _get_owned_trip_or_404(trip_id, user_id)

        if trip is None:
            return jsonify({
                "success": False,
                "message": "Trip not found.",
            }), 404

        from models.user import User
        owner = db.session.get(User, user_id)
        budget_currency = (
            owner.preferred_currency if owner is not None else "USD"
        )

        expenses = Expense.query.filter_by(
            trip_id=trip_id,
            user_id=user_id,
        ).order_by(
            Expense.date.desc(),
            Expense.created_at.desc(),
        ).all()

        return jsonify({
            "success": True,
            "count": len(expenses),
            "expenses": [e.to_dict() for e in expenses],
            "budgetAmount": (
                float(trip.budget_amount)
                if trip.budget_amount is not None
                else None
            ),
            "budgetCurrency": budget_currency,
            "tripTitle": trip.destination,
        }), 200

    except Exception:
        logger.exception("Listing trip expenses failed")
        return jsonify({
            "success": False,
            "message": "Failed to retrieve expenses.",
            "error": "Internal server error.",
        }), 500


# ============================================================
# CREATE EXPENSE
# POST /api/trips/<trip_id>/expenses
# ============================================================

@expenses_bp.route("/trips/<int:trip_id>/expenses", methods=["POST"])
@jwt_required()
def create_expense(trip_id):

    try:
        user_id = _get_authenticated_user_id()
    except ValueError as error:
        return jsonify({
            "success": False,
            "message": str(error),
        }), 401

    data = request.get_json(silent=True)

    update, error = _parse_expense_payload(data, partial=False)
    if error:
        return jsonify({
            "success": False,
            "message": error,
        }), 400

    try:
        trip = _get_owned_trip_or_404(trip_id, user_id)

        if trip is None:
            return jsonify({
                "success": False,
                "message": "Trip not found.",
            }), 404

        expense = Expense(
            trip_id=trip_id,
            user_id=user_id,
            amount=update["amount"],
            currency=update["currency"],
            category=update["category"],
            description=update["description"],
            date=update["date"],
            payment_method=update["payment_method"],
        )

        db.session.add(expense)
        db.session.commit()

        logger.info(
            "Expense created: %s (trip: %s, user: %s)",
            expense.id, trip_id, user_id,
        )

        return jsonify({
            "success": True,
            "message": "Expense added successfully.",
            "expense": expense.to_dict(),
        }), 201

    except Exception:
        db.session.rollback()
        logger.exception("Creating expense failed")
        return jsonify({
            "success": False,
            "message": "Failed to add expense.",
            "error": "Internal server error.",
        }), 500


# ============================================================
# GET EXPENSE
# GET /api/expenses/<expense_id>
# ============================================================

@expenses_bp.route("/expenses/<int:expense_id>", methods=["GET"])
@jwt_required()
def get_expense(expense_id):

    try:
        user_id = _get_authenticated_user_id()
    except ValueError as error:
        return jsonify({
            "success": False,
            "message": str(error),
        }), 401

    try:
        expense = Expense.query.filter_by(
            id=expense_id,
            user_id=user_id,
        ).first()

        if expense is None:
            return jsonify({
                "success": False,
                "message": "Expense not found.",
            }), 404

        return jsonify({
            "success": True,
            "expense": expense.to_dict(),
        }), 200

    except Exception:
        logger.exception("Retrieving expense failed")
        return jsonify({
            "success": False,
            "message": "Failed to retrieve expense.",
            "error": "Internal server error.",
        }), 500


# ============================================================
# UPDATE EXPENSE
# PATCH /api/expenses/<expense_id>
# ============================================================

@expenses_bp.route("/expenses/<int:expense_id>", methods=["PATCH"])
@jwt_required()
def update_expense(expense_id):

    try:
        user_id = _get_authenticated_user_id()
    except ValueError as error:
        return jsonify({
            "success": False,
            "message": str(error),
        }), 401

    try:
        expense = Expense.query.filter_by(
            id=expense_id,
            user_id=user_id,
        ).first()

        if expense is None:
            return jsonify({
                "success": False,
                "message": "Expense not found.",
            }), 404

        data = request.get_json(silent=True)

        update, error = _parse_expense_payload(data, partial=True)
        if error:
            return jsonify({
                "success": False,
                "message": error,
            }), 400

        for field, value in update.items():
            if value is not None:
                setattr(expense, field, value)

        db.session.commit()

        logger.info(
            "Expense updated: %s (user: %s)",
            expense_id, user_id,
        )

        return jsonify({
            "success": True,
            "message": "Expense updated successfully.",
            "expense": expense.to_dict(),
        }), 200

    except Exception:
        db.session.rollback()
        logger.exception("Updating expense failed")
        return jsonify({
            "success": False,
            "message": "Failed to update expense.",
            "error": "Internal server error.",
        }), 500


# ============================================================
# DELETE EXPENSE
# DELETE /api/expenses/<expense_id>
# ============================================================

@expenses_bp.route("/expenses/<int:expense_id>", methods=["DELETE"])
@jwt_required()
def delete_expense(expense_id):

    try:
        user_id = _get_authenticated_user_id()
    except ValueError as error:
        return jsonify({
            "success": False,
            "message": str(error),
        }), 401

    try:
        expense = Expense.query.filter_by(
            id=expense_id,
            user_id=user_id,
        ).first()

        if expense is None:
            return jsonify({
                "success": False,
                "message": "Expense not found.",
            }), 404

        db.session.delete(expense)
        db.session.commit()

        logger.info(
            "Expense deleted: %s (user: %s)",
            expense_id, user_id,
        )

        return jsonify({
            "success": True,
            "message": "Expense deleted successfully.",
        }), 200

    except Exception:
        db.session.rollback()
        logger.exception("Deleting expense failed")
        return jsonify({
            "success": False,
            "message": "Failed to delete expense.",
            "error": "Internal server error.",
        }), 500