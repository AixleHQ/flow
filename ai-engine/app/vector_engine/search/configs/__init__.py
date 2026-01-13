"""Pre-configured search configurations."""

from .codebase import CodebaseSearchConfig
from .content import ContentSearchConfig
from .document import DocumentSearchConfig
from .domain import DomainSearchConfig

__all__ = [
    "CodebaseSearchConfig",
    "DocumentSearchConfig",
    "DomainSearchConfig",
    "ContentSearchConfig",
]
