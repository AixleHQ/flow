"""Main vector indexing service."""

from typing import Any

from core.logging import logger
from qdrant_client import models
import uuid
from vector_engine.core.client import VectorClient, get_vector_client
from vector_engine.core.config import VectorCoreConfig
from vector_engine.core.exceptions import IndexingError
from vector_engine.core.models import VectorDocument
from vector_engine.core.retry import RetryConfig, with_retry

from .strategies.base_strategy import BaseIndexingStrategy


class VectorIndexingEngine:
    """
    Main engine for vector indexing operations.

    This is the primary interface for indexing documents into the vector database.
    It orchestrates chunking, embedding generation, and storage.
    """

    def __init__(
        self,
        config: VectorCoreConfig | None = None,
        client: VectorClient | None = None,
    ):
        """Initialize the indexing engine."""
        self.config = config or VectorCoreConfig()
        self.client = client or get_vector_client(self.config)
        self.logger = logger

        self.strategies: dict[str, BaseIndexingStrategy] = {}

    def register_strategy(self, strategy: BaseIndexingStrategy) -> None:
        """Register an indexing strategy."""
        strategy_name = strategy.config.strategy_name
        self.strategies[strategy_name] = strategy

    def get_strategy(self, strategy_name: str) -> BaseIndexingStrategy:
        """Get a registered strategy."""
        if strategy_name not in self.strategies:
            raise IndexingError(f"Strategy not found: {strategy_name}")
        return self.strategies[strategy_name]

    @with_retry(
        RetryConfig(
            max_attempts=3, retryable_exceptions=(IndexingError, ConnectionError)
        ),
        "index_document",
    )
    def index_document(
        self,
        document: VectorDocument,
        strategy: BaseIndexingStrategy | None = None,
    ) -> str:
        """
        Index a document using the specified strategy.

        Args:
            document: Document to index
            strategy: Indexing strategy to use (auto-detected if None)

        Returns:
            Collection name where document was indexed
        """
        try:
            collection_name = self._ensure_collection(document.workspace_id)

            if strategy is None:
                strategy = self._get_default_strategy(document.content_type)

            processed_document = strategy.process_document(document)

            self._store_document(processed_document, collection_name)

            self.logger.info(
                f"Successfully indexed document {document.document_id} "
                f"with {len(processed_document.chunks)} chunks"
            )

            return collection_name

        except Exception as e:
            self.logger.error(f"Failed to index document {document.document_id}: {e}")
            raise IndexingError(f"Document indexing failed: {e}")

    def index_content(
        self,
        content: str,
        content_type: str,
        workspace_id: int,
        asset_id: int,
        asset_type: str,
        document_id: str | None = None,
        metadata: dict[str, Any] | None = None,
        strategy_name: str | None = None,
    ) -> str:
        """
        Convenience method to index content directly.

        Args:
            content: Content to index
            content_type: Type of content (document, code, ui_image)
            workspace_id: Workspace ID
            asset_id: Asset ID
            asset_type: Asset type
            document_id: Document ID (auto-generated if None)
            metadata: Additional metadata
            strategy_name: Strategy to use (auto-detected if None)

        Returns:
            Collection name where content was indexed
        """
        # Create document
        if document_id is None:
            import uuid

            document_id = f"{content_type}_{asset_id}_{uuid.uuid4().hex[:8]}"

        document = VectorDocument(
            document_id=document_id,
            content=content,
            content_type=content_type,
            workspace_id=workspace_id,
            asset_id=asset_id,
            asset_type=asset_type,
            metadata=metadata or {},
        )

        # Get strategy
        strategy = None
        if strategy_name:
            strategy = self.get_strategy(strategy_name)

        return self.index_document(document, strategy)

    def _ensure_collection(self, workspace_id: int) -> str:
        """Ensure collection exists for workspace."""
        collection_name = self.config.get_collection_name(workspace_id)

        if not self.client.collection_exists(collection_name):
            self.client.create_collection(
                collection_name=collection_name,
                vector_size=self.config.default_vector_size,
            )

        return collection_name

    @with_retry(
        RetryConfig(max_attempts=3, retryable_exceptions=(ConnectionError,)),
        "store_document",
    )
    def _store_document(self, document: VectorDocument, collection_name: str) -> None:
        """Store document chunks in vector database with parallel batch uploads."""
        from concurrent.futures import ThreadPoolExecutor, as_completed

        client = self.client.get_client()

        points = []
        for idx, chunk in enumerate(document.chunks):
            # Create point for each vector type
            for vector_name, embedding in chunk.embeddings.items():
                point_id = uuid.uuid4().int >> 64 + idx

                # Prepare metadata
                payload = {
                    "document_id": document.document_id,
                    "chunk_id": chunk.chunk_id,
                    "content": chunk.content,
                    "workspace_id": document.workspace_id,
                    "asset_id": document.asset_id,
                    "asset_type": document.asset_type,
                    "content_type": document.content_type,
                    "vector_name": vector_name,
                    "token_count": chunk.token_count,
                    **chunk.metadata,
                }

                point = models.PointStruct(
                    id=point_id,  # Convert to int
                    vector=embedding,
                    payload=payload,
                )
                points.append(point)

        # Batch upsert with parallel uploads for large files
        if points:
            batch_size = self.config.batch_size
            total_points = len(points)

            # For very large documents, use smaller batches to avoid timeouts
            if total_points > 500:  # Large document
                batch_size = min(50, batch_size)
                self.logger.info(
                    f"Large document detected ({total_points} points), using smaller batch size: {batch_size}"
                )

            # Create batches
            batches = []
            for i in range(0, len(points), batch_size):
                batch_points = points[i : i + batch_size]
                batches.append((i // batch_size + 1, batch_points))

            total_batches = len(batches)

            # Upload batches in parallel for large documents
            if total_batches > 5:
                self.logger.info(
                    f"Uploading {total_batches} batches in parallel (max 3 concurrent)"
                )

                with ThreadPoolExecutor(max_workers=5) as executor:
                    futures = {
                        executor.submit(
                            self._upload_batch, client, collection_name, batch_points
                        ): batch_num
                        for batch_num, batch_points in batches
                    }

                    uploaded_count = 0
                    for future in as_completed(futures):
                        batch_num = futures[future]
                        points_count = future.result()
                        uploaded_count += points_count
                        self.logger.debug(
                            f"Uploaded batch {batch_num}/{total_batches} ({points_count} points)"
                        )

                    self.logger.info(
                        f"Successfully stored {uploaded_count} points in {total_batches} batches (parallel)"
                    )
            else:
                # For small documents, use sequential upload
                for batch_num, batch_points in batches:
                    client.upsert(
                        collection_name=collection_name,
                        points=batch_points,
                    )
                    self.logger.debug(
                        f"Uploaded batch {batch_num}/{total_batches} ({len(batch_points)} points)"
                    )

                self.logger.info(
                    f"Successfully stored {len(points)} points in {total_batches} batches (sequential)"
                )

    def _upload_batch(self, client, collection_name: str, batch_points: list) -> int:
        """Upload single batch to Qdrant."""
        client.upsert(collection_name=collection_name, points=batch_points)
        return len(batch_points)

    def delete_document(self, workspace_id: int, document_id: str) -> None:
        """Delete a document and all its chunks."""
        collection_name = self.config.get_collection_name(workspace_id)
        client = self.client.get_client()

        # Delete all points for this document
        client.delete(
            collection_name=collection_name,
            points_selector=models.FilterSelector(
                filter=models.Filter(
                    must=[
                        models.FieldCondition(
                            key="document_id",
                            match=models.MatchValue(value=document_id),
                        )
                    ]
                )
            ),
        )

        self.logger.info(f"Deleted document {document_id}")

    def delete_asset_documents(self, workspace_id: int, asset_id: int) -> None:
        """Delete all documents for an asset."""
        collection_name = self.config.get_collection_name(workspace_id)
        client = self.client.get_client()
        try:
            client.delete(
                collection_name=collection_name,
                points_selector=models.FilterSelector(
                    filter=models.Filter(
                        must=[
                            models.FieldCondition(
                                key="asset_id",
                                match=models.MatchValue(value=asset_id),
                            )
                        ]
                    )
                ),
            )
        except Exception as e:
            if any(
                phrase in str(e).lower()
                for phrase in ["not found", "does not exist", "collection not found"]
            ):
                self.logger.debug(
                    f"Asset {asset_id} documents or collection not found, nothing to delete"
                )
                return
            raise

        self.logger.info(f"Deleted all documents for asset {asset_id}")

    def get_collection_info(self, workspace_id: int) -> dict[str, Any]:
        """Get information about a workspace collection."""
        collection_name = self.config.get_collection_name(workspace_id)
        info = self.client.get_collection_info(collection_name)

        if info:
            return {
                "collection_name": collection_name,
                "points_count": info.points_count,
                "segments_count": info.segments_count,
                "vectors_count": info.vectors_count
                if hasattr(info, "vectors_count")
                else None,
                "indexed": info.status,
            }

        return {"collection_name": collection_name, "exists": False}

    def list_strategies(self) -> list[dict[str, Any]]:
        """List all registered strategies."""
        return [strategy.get_strategy_info() for strategy in self.strategies.values()]

    def index_document_with_config(
        self, document: VectorDocument, config: Any | None = None
    ) -> str:
        """
        Index document using configuration object.

        Args:
            document: Document to index
            config: Indexing configuration object

        Returns:
            Collection name where document was indexed
        """
        try:
            # Ensure collection exists
            collection_name = self._ensure_collection(document.workspace_id)

            strategy_name = self._get_strategy_from_config(config)
            strategy = self.get_strategy(strategy_name)

            # Process document with strategy (chunks + embeddings)
            processed_document = strategy.process_document(document)

            # Store processed document in Qdrant
            self._store_document(processed_document, collection_name)

            self.logger.info(
                f"Document indexed successfully (document_id: {document.document_id}, strategy: {strategy_name}, collection: {collection_name}, chunks_count: {len(processed_document.chunks)})"
            )

            return collection_name

        except Exception as e:
            self.logger.error(f"Failed to index document: {e}")
            raise IndexingError(f"Document indexing failed: {e}")

    def _get_strategy_from_config(self, config: Any) -> str:
        """Determine indexing strategy from configuration."""
        if hasattr(config, "strategy_name"):
            return config.strategy_name
        if hasattr(config, "content_type"):
            content_type = config.content_type
            if content_type == "code":
                return "code_indexing"
            if content_type in ["document", "pdf", "markdown", "text"]:
                return "document_indexing"
            if content_type in ["ui_analysis", "ui_image", "ui_content"]:
                return "ui_indexing"

        # Default fallback
        return "document_indexing"
