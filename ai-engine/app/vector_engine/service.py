"""Main VectorEngine service - unified entry point for all vector operations."""

from typing import Any

from core.logging import logger

from .core.client import VectorClient, get_vector_client
from .core.config import VectorCoreConfig
from .core.exceptions import VectorEngineError
from .embeddings.service import EmbeddingService
from .indexing.service import VectorIndexingEngine
from .search.service import VectorSearchEngine


class VectorEngine:
    """
    Unified vector database management system.

    Single entry point for all vector operations including indexing, search,
    and embedding generation. Designed for domain services to use without
    knowing about internal vector DB complexities.

    Usage:
        vector_engine = VectorEngine(workspace_id=123)
        vector_engine.index(content, CodeIndexingConfig())
        results = vector_engine.search(query, CodeSearchConfig())
    """

    def __init__(
        self,
        workspace_id: int,
        config: VectorCoreConfig | None = None,
        client: VectorClient | None = None,
    ):
        """Initialize VectorEngine for specific workspace."""
        self.workspace_id = workspace_id
        self.config = config or VectorCoreConfig()
        self.client = client or get_vector_client(self.config)
        self.logger = logger

        self.embedding_service = EmbeddingService()
        self.indexing_engine = VectorIndexingEngine(self.config, self.client)
        self.search_engine = VectorSearchEngine(self.config, self.client)

        self._register_default_strategies()

    def index(
        self, content: str, config: Any, metadata: dict[str, Any] | None = None
    ) -> str:
        """
        Index content using specified configuration.

        Args:
            content: Content to index
            config: Indexing configuration object (e.g., CodeIndexingConfig)
            metadata: Additional metadata to attach

        Returns:
            Document ID of indexed content
        """
        from .core.models import VectorDocument

        asset_id = getattr(config, "asset_id", None) or metadata.get("asset_id")
        asset_type = getattr(config, "asset_type", None) or metadata.get(
            "asset_type", "unknown"
        )

        if not asset_id:
            raise VectorEngineError("asset_id is required in config or metadata")

        document = VectorDocument(
            document_id=f"doc_{self.workspace_id}_{asset_id}",
            content=content,
            content_type=config.content_type,
            workspace_id=self.workspace_id,
            asset_id=asset_id,
            asset_type=asset_type,
            metadata=metadata or {},
        )

        self.indexing_engine.index_document_with_config(document, config)

        self.logger.debug(
            f"Successfully indexed content (asset_id: {asset_id}, document_id: {document.document_id}, content_length: {len(content)})"
        )

        return document

    def search(self, query: str, config: Any) -> list[dict[str, Any]]:
        """
        Search using specified configuration.

        Args:
            query: Search query
            config: Search configuration object (e.g., CodeSearchConfig)

        Returns:
            List of search results
        """
        try:
            results = self.search_engine.search_with_config(
                query=query, workspace_id=self.workspace_id, config=config
            )

            self.logger.info(
                "Search completed", query_length=len(query), results_count=len(results)
            )

            return results

        except Exception as e:
            self.logger.error(f"Search failed: {e}")
            raise VectorEngineError(f"Search failed: {e}")

    def delete_asset_content(self, asset_id: int) -> None:
        """Delete all content for specific asset."""
        self.indexing_engine.delete_asset_documents(self.workspace_id, asset_id)
        self.logger.info(f"Deleted content for asset {asset_id}")

    def get_collection_info(self) -> dict[str, Any]:
        """Get collection information for workspace."""
        try:
            return self.search_engine.get_collection_info(self.workspace_id)
        except Exception as e:
            self.logger.error(f"Failed to get collection info: {e}")
            raise VectorEngineError(f"Collection info retrieval failed: {e}")

    def _register_default_strategies(self) -> None:
        """Register default indexing strategies."""
        try:
            # Import and register real strategies
            from .indexing.strategies.code_strategy import CodeIndexingStrategy
            from .indexing.strategies.document_strategy import DocumentIndexingStrategy
            from .indexing.strategies.ui_strategy import UIIndexingStrategy

            # Register strategies with default configs
            code_strategy = CodeIndexingStrategy()
            self.indexing_engine.register_strategy(code_strategy)

            doc_strategy = DocumentIndexingStrategy()
            self.indexing_engine.register_strategy(doc_strategy)

            ui_strategy = UIIndexingStrategy()
            self.indexing_engine.register_strategy(ui_strategy)

        except ImportError as e:
            self.logger.warning(f"Failed to register some strategies: {e}")
        except Exception as e:
            self.logger.error(f"Strategy registration failed: {e}")
