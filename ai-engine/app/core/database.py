"""Database connection module for AI Engine.

Provides read-only access to Rails database via SQLAlchemy automap.
Python workers should NEVER write directly - all writes go through Ruby Temporal activities.
"""

import inflect
from collections.abc import Generator
from contextlib import contextmanager
from typing import Any

from sqlalchemy import create_engine
from sqlalchemy.ext.automap import automap_base
from sqlalchemy.orm import Session, sessionmaker

from config import settings


def get_database_url() -> str:
    """Build database URL from settings."""
    host = settings.db.host
    port = settings.db.port
    username = settings.db.username
    password = settings.db.password
    database = settings.db.database

    # Build URL with optional password
    if password:
        return f"postgresql://{username}:{password}@{host}:{port}/{database}"
    return f"postgresql://{username}@{host}:{port}/{database}"


pool_size = settings.db.pool_size
max_overflow = settings.db.max_overflow

# Read-only engine configuration
engine = create_engine(
    get_database_url(),
    pool_pre_ping=True,
    pool_recycle=3600,
    pool_size=pool_size,
    max_overflow=max_overflow,
    pool_timeout=180,
    echo=False,
    execution_options={
        "postgresql_readonly": True,
    },
)

SessionLocal = sessionmaker(
    bind=engine, expire_on_commit=False, autocommit=False, autoflush=False
)


@contextmanager
def get_db_session_context():
    """Get database session as context manager.

    Thread-safe for use in Temporal activities.
    """
    session = SessionLocal()
    try:
        yield session
    finally:
        session.close()


# Automap base for automatic model generation from Rails tables
Base = automap_base()


def _name_for_scalar_relationship(base, local_cls, referred_cls, constraint):
    """Generate singular relationship name for belongs_to (many-to-one).

    Rails convention: workspace.account (not workspace.accounts)
    """
    inflect_engine = inflect.engine()

    # referred_cls is the class name (string), not the class itself at this point
    if isinstance(referred_cls, str):
        referred_table_name = referred_cls
    else:
        referred_table_name = getattr(referred_cls, "__name__", str(referred_cls))

    # Singularize it (accounts -> account)
    singular = inflect_engine.singular_noun(referred_table_name) or referred_table_name

    return singular


def _name_for_collection_relationship(base, local_cls, referred_cls, constraint):
    """Generate plural relationship name for has_many (one-to-many).

    Rails convention: account.workspaces (not account.workspace_collection)
    """
    # referred_cls is the class name (string), not the class itself
    if isinstance(referred_cls, str):
        return referred_cls
    else:
        return getattr(referred_cls, "__name__", str(referred_cls))


def reflect_all_models() -> None:
    """Reflect all tables from Rails database and generate model classes.

    Relationships are named following Rails conventions:
    - belongs_to: singular (workspace.account)
    - has_many: plural (account.workspaces)
    """
    Base.prepare(
        autoload_with=engine,
        name_for_scalar_relationship=_name_for_scalar_relationship,
        name_for_collection_relationship=_name_for_collection_relationship,
    )


def get_model(table_name: str) -> Any:
    """Get reflected model class by table name."""
    if not hasattr(Base, "classes") or not Base.classes:
        reflect_all_models()

    return getattr(Base.classes, table_name)


def list_available_tables() -> list[str]:
    """List all tables available in the reflected metadata."""
    if not hasattr(Base, "classes") or not Base.classes:
        reflect_all_models()

    return list(Base.metadata.tables.keys())


def get_db_session() -> Generator[Session, None, None]:
    """Get database session for dependency injection (read-only)."""
    session = SessionLocal()
    try:
        yield session
    finally:
        session.close()
