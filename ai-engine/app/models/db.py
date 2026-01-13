"""Database models module - auto-generated from Rails schema.

This module provides lazy-loaded access to all Rails models via SQLAlchemy automap.

Usage:
    from models import Workspace, Asset, Specification

    with get_db_session_context() as session:
        workspace = session.query(Workspace).filter_by(id=1).first()
        assets = workspace.assets_collection  # Access relationships
"""

from typing import Any

import inflect

from core import Base, reflect_all_models

# Initialize inflect engine for proper singularization (like Rails inflector)
_inflect_engine = inflect.engine()


def _to_class_name(table_name: str) -> str:
    """Convert table name to PascalCase class name using inflect.

    Examples:
        workspaces -> Workspace
        account_users -> AccountUser
        quality_issues -> QualityIssue
        people -> Person
        analyses -> Analysis
    """
    # Split by underscore
    parts = table_name.split("_")

    # Singularize the last part (Rails convention: table names are plural)
    if parts:
        parts[-1] = _inflect_engine.singular_noun(parts[-1]) or parts[-1]

    # Convert to PascalCase
    return "".join(part.capitalize() for part in parts)


class _ModelProxy:
    """Proxy for accessing reflected models.

    Models are reflected lazily on first access.
    Supports both table names (lowercase, plural) and class names (PascalCase, singular).
    """

    _reflected = False
    _name_map: dict[str, str] = {}  # Maps PascalCase names to table names

    def __init__(self):
        """Initialize proxy (reflection happens lazily on first access)."""
        pass

    def _ensure_reflected(self) -> None:
        """Ensure models are reflected (lazy initialization)."""
        if not _ModelProxy._reflected:
            reflect_all_models()
            _ModelProxy._reflected = True

            # Build name mapping: Workspace -> workspaces, AccountUser -> account_users
            for table_name in dir(Base.classes):
                if not table_name.startswith("_"):
                    class_name = _to_class_name(table_name)
                    _ModelProxy._name_map[class_name] = table_name

    def __getattr__(self, name: str) -> Any:
        """Get model by name (supports both table name and class name)."""
        self._ensure_reflected()

        # Try direct table name first
        try:
            return getattr(Base.classes, name)
        except AttributeError:
            pass

        # Try mapped class name (e.g., Workspace -> workspaces)
        table_name = _ModelProxy._name_map.get(name)
        if table_name:
            try:
                return getattr(Base.classes, table_name)
            except AttributeError:
                pass

        # Not found
        available = [n for n in dir(Base.classes) if not n.startswith("_")]
        available_classes = list(_ModelProxy._name_map.keys())
        raise AttributeError(
            f"Model '{name}' not found.\n"
            f"Available table names: {', '.join(available[:5])}...\n"
            f"Available class names: {', '.join(available_classes[:5])}..."
        )


# Create proxy instance (reflection happens lazily on first access)
_models: _ModelProxy | None = None


def _get_models() -> _ModelProxy:
    """Get models proxy instance (lazy initialization)."""
    global _models
    if _models is None:
        _models = _ModelProxy()
    return _models


# Export commonly used models with proper names
def __getattr__(name: str) -> Any:
    """Module-level attribute access for models."""
    return getattr(_get_models(), name)


def list_models() -> list[str]:
    """List all available model names."""
    models = _get_models()
    models._ensure_reflected()
    return [name for name in dir(Base.classes) if not name.startswith("_")]


def get_model(name: str) -> Any:
    """Get model class by name.

    Args:
        name: Table name (e.g., 'workspaces', 'assets')

    Returns:
        SQLAlchemy model class

    Example:
        Workspace = get_model('workspaces')
    """
    return getattr(_get_models(), name)
