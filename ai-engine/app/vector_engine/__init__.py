"""Vector Engine - Unified vector database management system.

This module provides a clean, scalable architecture for vector indexing and search operations.
It replaces the old embeddings_store with better separation of concerns and object-oriented design.

Main entry point: VectorEngine class for domain services
Pre-configured objects: IndexingConfigs and SearchConfigs
"""

from .core.exceptions import IndexingError, SearchError, VectorEngineError

# Core models
from .core.models import VectorChunk, VectorDocument
from .embeddings.service import EmbeddingService

# Individual engines (for advanced usage)
from .indexing.service import VectorIndexingEngine
from .indexing.strategies import (
    CodeIndexingConfig,
    DocumentIndexingConfig,
    UIIndexingConfig,
)

# Pre-configured search configs
from .search.configs import (
    CodebaseSearchConfig,
    ContentSearchConfig,
    DocumentSearchConfig,
    DomainSearchConfig,
)
from .search.service import VectorSearchEngine

# Main service
from .service import VectorEngine

__all__ = [
    # Main entry point
    "VectorEngine",
    # Core models
    "VectorDocument",
    "VectorChunk",
    "VectorEngineError",
    "IndexingError",
    "SearchError",
    # Pre-configured configs
    "CodeIndexingConfig",
    "DocumentIndexingConfig",
    "UIIndexingConfig",
    # Pre-configured search configs
    "CodebaseSearchConfig",
    "DocumentSearchConfig",
    "DomainSearchConfig",
    "ContentSearchConfig",
    # Individual services (advanced usage)
    "VectorIndexingEngine",
    "VectorSearchEngine",
    "EmbeddingService",
]
