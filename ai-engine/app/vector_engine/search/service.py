from typing import Any

from core.logging import logger
from qdrant_client import models

from models.llm import ModelDefinition
from vector_engine.core.client import VectorClient, get_vector_client
from vector_engine.core.config import VectorCoreConfig
from vector_engine.core.exceptions import SearchError
from vector_engine.core.models import VectorSearchFilter, VectorSearchResult
from vector_engine.core.retry import RetryConfig, with_retry


class VectorSearchEngine:
    def __init__(
        self,
        config: VectorCoreConfig | None = None,
        client: VectorClient | None = None,
    ):
        """Initialize the search engine."""
        self.config = config or VectorCoreConfig()
        self.client = client or get_vector_client(self.config)
        self.logger = logger

    @with_retry(
        RetryConfig(
            max_attempts=3, retryable_exceptions=(SearchError, ConnectionError)
        ),
        "search_by_text",
    )
    def search_by_text(
        self,
        query: str,
        workspace_id: int,
        limit: int = 10,
        search_filter: VectorSearchFilter | None = None,
        vector_name: str = "semantic_description",
        embedding_model: str = "text-embedding-3-small",
        semantic_expansion: bool = False,
        concept_extraction_model: ModelDefinition | None = None,
        score_threshold: float | None = None,
    ) -> list[VectorSearchResult]:
        """
        Search by text query.

        Args:
            query: Text query to search for
            workspace_id: Workspace to search in
            limit: Maximum number of results
            search_filter: Additional filters
            vector_name: Vector type to search
            embedding_model: Model for query embedding
            semantic_expansion: Enable semantic query expansion
            concept_extraction_model: Model for semantic expansion
            score_threshold: Minimal score threshold for results

        Returns:
            List of search results
        """
        try:
            # Expand query semantically if enabled
            expanded_query = query
            if semantic_expansion and concept_extraction_model:
                expanded_query = self._expand_query_semantically(
                    query, workspace_id, concept_extraction_model
                )
                self.logger.debug(f"Query expanded: '{query}' -> '{expanded_query}'")

            # Generate embedding for (potentially expanded) query
            from vector_engine.embeddings.service import EmbeddingService

            embedding_service = EmbeddingService()
            query_vector = embedding_service.get_embedding(
                expanded_query, embedding_model
            )

            return self.search_by_vector(
                vector=query_vector,
                workspace_id=workspace_id,
                limit=limit,
                search_filter=search_filter,
                vector_name=vector_name,
                score_threshold=score_threshold,
            )

        except Exception as e:
            raise SearchError(f"Text search failed: {e}")

    @with_retry(
        RetryConfig(
            max_attempts=3, retryable_exceptions=(SearchError, ConnectionError)
        ),
        "search_by_vector",
    )
    def search_by_vector(
        self,
        vector: list[float],
        workspace_id: int,
        limit: int = 10,
        search_filter: VectorSearchFilter | None = None,
        vector_name: str = "semantic_description",
        score_threshold: float | None = None,
    ) -> list[VectorSearchResult]:
        """
        Search by vector.

        Args:
            vector: Query vector
            workspace_id: Workspace to search in
            limit: Maximum number of results
            search_filter: Additional filters
            vector_name: Vector type to search
            score_threshold: Minimal score threshold for results

        Returns:
            List of search results
        """
        try:
            collection_name = self.config.get_collection_name(workspace_id)

            # Check if collection exists
            if not self.client.collection_exists(collection_name):
                self.logger.warning(f"Collection {collection_name} does not exist")
                return []

            # Build query filter
            query_filter = self._build_query_filter(search_filter, vector_name)

            # Perform search
            client = self.client.get_client()
            search_results = client.search(
                collection_name=collection_name,
                query_vector=vector,
                query_filter=query_filter,
                limit=limit,
                with_payload=True,
                score_threshold=score_threshold,
            )

            # Convert to VectorSearchResult objects
            results = []
            for result in search_results:
                payload = result.payload or {}

                payload_workspace_id = payload.get("workspace_id", workspace_id)
                if isinstance(payload_workspace_id, str):
                    try:
                        payload_workspace_id = int(payload_workspace_id.split("_")[-1])
                    except (ValueError, AttributeError):
                        payload_workspace_id = workspace_id

                search_result = VectorSearchResult(
                    document_id=payload.get("document_id", ""),
                    chunk_id=payload.get("chunk_id", ""),
                    content=payload.get("content", ""),
                    score=float(result.score),
                    workspace_id=payload_workspace_id,
                    asset_id=payload.get("asset_id", 0),
                    asset_type=payload.get("asset_type", ""),
                    content_type=payload.get("content_type", ""),
                    metadata={
                        k: v
                        for k, v in payload.items()
                        if k
                        not in [
                            "document_id",
                            "chunk_id",
                            "content",
                            "workspace_id",
                            "asset_id",
                            "asset_type",
                            "content_type",
                        ]
                    },
                )
                results.append(search_result)

            self.logger.debug(f"Search returned {len(results)} results")
            return results

        except Exception as e:
            raise SearchError(f"Vector search failed: {e}")

    def _build_query_filter(
        self,
        search_filter: VectorSearchFilter | None,
        vector_name: str,
    ) -> models.Filter | None:
        """Build Qdrant filter from search parameters."""
        conditions = []

        # Always filter by vector name
        conditions.append(
            models.FieldCondition(
                key="vector_name",
                match=models.MatchValue(value=vector_name),
            )
        )

        # Add search filter conditions
        if search_filter:
            qdrant_filter = search_filter.to_qdrant_filter()
            if qdrant_filter.get("must"):
                for condition in qdrant_filter["must"]:
                    if "key" in condition and "match" in condition:
                        if "value" in condition["match"]:
                            conditions.append(
                                models.FieldCondition(
                                    key=condition["key"],
                                    match=models.MatchValue(
                                        value=condition["match"]["value"]
                                    ),
                                )
                            )
                        elif "any" in condition["match"]:
                            conditions.append(
                                models.FieldCondition(
                                    key=condition["key"],
                                    match=models.MatchAny(
                                        any=condition["match"]["any"]
                                    ),
                                )
                            )

        return models.Filter(must=conditions) if conditions else None

    def get_document_chunks(
        self,
        workspace_id: int,
        document_id: str,
        vector_name: str | None = None,
    ) -> list[VectorSearchResult]:
        """Get all chunks for a specific document."""
        try:
            collection_name = self.config.get_collection_name(workspace_id)
            client = self.client.get_client()

            # Build filter
            conditions = [
                models.FieldCondition(
                    key="document_id",
                    match=models.MatchValue(value=document_id),
                )
            ]

            if vector_name:
                conditions.append(
                    models.FieldCondition(
                        key="vector_name",
                        match=models.MatchValue(value=vector_name),
                    )
                )

            # Scroll through all results
            results = []
            offset = None

            while True:
                response = client.scroll(
                    collection_name=collection_name,
                    scroll_filter=models.Filter(must=conditions),
                    limit=100,
                    offset=offset,
                    with_payload=True,
                )

                if not response[0]:  # No more results
                    break

                for point in response[0]:
                    payload = point.payload or {}

                    payload_workspace_id = payload.get("workspace_id", workspace_id)
                    if isinstance(payload_workspace_id, str):
                        try:
                            payload_workspace_id = int(
                                payload_workspace_id.split("_")[-1]
                            )
                        except (ValueError, AttributeError):
                            payload_workspace_id = workspace_id

                    search_result = VectorSearchResult(
                        document_id=payload.get("document_id", ""),
                        chunk_id=payload.get("chunk_id", ""),
                        content=payload.get("content", ""),
                        score=1.0,  # Not a similarity search
                        workspace_id=payload_workspace_id,
                        asset_id=payload.get("asset_id", 0),
                        asset_type=payload.get("asset_type", ""),
                        content_type=payload.get("content_type", ""),
                        metadata={
                            k: v
                            for k, v in payload.items()
                            if k
                            not in [
                                "document_id",
                                "chunk_id",
                                "content",
                                "workspace_id",
                                "asset_id",
                                "asset_type",
                                "content_type",
                            ]
                        },
                    )
                    results.append(search_result)

                offset = response[1]  # Next offset

            return results

        except Exception as e:
            raise SearchError(f"Failed to get document chunks: {e}")

    def count_documents(
        self,
        workspace_id: int,
        search_filter: VectorSearchFilter | None = None,
    ) -> int:
        """Count documents matching filter."""
        try:
            collection_name = self.config.get_collection_name(workspace_id)

            if not self.client.collection_exists(collection_name):
                return 0

            client = self.client.get_client()

            # Build filter
            query_filter = None
            if search_filter:
                qdrant_filter = search_filter.to_qdrant_filter()
                if qdrant_filter.get("must"):
                    conditions = []
                    for condition in qdrant_filter["must"]:
                        if "key" in condition and "match" in condition:
                            if "value" in condition["match"]:
                                conditions.append(
                                    models.FieldCondition(
                                        key=condition["key"],
                                        match=models.MatchValue(
                                            value=condition["match"]["value"]
                                        ),
                                    )
                                )
                            elif "any" in condition["match"]:
                                conditions.append(
                                    models.FieldCondition(
                                        key=condition["key"],
                                        match=models.MatchAny(
                                            any=condition["match"]["any"]
                                        ),
                                    )
                                )

                    if conditions:
                        query_filter = models.Filter(must=conditions)

            # Count points
            result = client.count(
                collection_name=collection_name,
                count_filter=query_filter,
            )

            return result.count

        except Exception as e:
            raise SearchError(f"Failed to count documents: {e}")

    def collection_exists(self, workspace_id: int) -> bool:
        """Check if collection exists for workspace."""
        collection_name = self.config.get_collection_name(workspace_id)
        return self.client.collection_exists(collection_name)

    def get_collection_info(self, workspace_id: int) -> dict[str, Any]:
        """Get collection information."""
        collection_name = self.config.get_collection_name(workspace_id)
        info = self.client.get_collection_info(collection_name)

        if info:
            return {
                "collection_name": collection_name,
                "points_count": info.points_count,
                "segments_count": info.segments_count,
                "status": info.status,
                "optimizer_status": info.optimizer_status,
                "vectors_count": info.vectors_count
                if hasattr(info, "vectors_count")
                else None,
            }

        return {"collection_name": collection_name, "exists": False}

    def search_with_config(
        self,
        query: str,
        workspace_id: int,
        config: Any,
    ) -> list[dict[str, Any]]:
        """
        Search using configuration object.

        Args:
            query: Search query
            workspace_id: Workspace to search in
            config: Search configuration object

        Returns:
            List of search results in dictionary format
        """
        try:
            # Create search filter from config
            search_filter = self._config_to_filter(config, workspace_id)

            # Check if config supports semantic expansion
            semantic_expansion = getattr(config, "semantic_expansion", False)

            # Perform search with potential expansion
            results = self.search_by_text(
                query=query,
                workspace_id=workspace_id,
                limit=config.limit,
                search_filter=search_filter,
                vector_name=getattr(config, "vector_name", "semantic_description"),
                embedding_model=getattr(
                    config, "embedding_model", "text-embedding-3-small"
                ),
                semantic_expansion=semantic_expansion,
                concept_extraction_model=getattr(
                    config, "concept_extraction_model", None
                ),
            )

            # Filter by score threshold
            filtered_results = [
                self._result_to_dict(result)
                for result in results
                if result.score >= config.score_threshold
            ]

            return filtered_results

        except Exception as e:
            raise SearchError(f"Config-based search failed: {e}")

    def _config_to_filter(
        self, config: Any, workspace_id: int
    ) -> VectorSearchFilter | None:
        """Convert search config to VectorSearchFilter."""
        filter_kwargs = {"workspace_id": workspace_id}

        # Extract common filter attributes
        if hasattr(config, "asset_types") and config.asset_types:
            filter_kwargs["asset_types"] = config.asset_types
        if hasattr(config, "content_types") and config.content_types:
            filter_kwargs["content_types"] = config.content_types
        if hasattr(config, "asset_ids") and config.asset_ids:
            filter_kwargs["asset_ids"] = config.asset_ids

        # Handle domain-specific filters
        metadata_filters = {}
        if hasattr(config, "target_domains") and config.target_domains:
            metadata_filters["domain"] = config.target_domains
        if hasattr(config, "languages") and config.languages:
            metadata_filters["language"] = config.languages

        if metadata_filters:
            filter_kwargs["metadata_filters"] = metadata_filters

        return VectorSearchFilter(**filter_kwargs)

    def _expand_query_semantically(
        self, query: str, workspace_id: int, concept_extraction_model: ModelDefinition
    ) -> str:
        """
        Expand query with semantic alternatives and synonyms.

        Args:
            query: Original query text
            workspace_id: Workspace context for expansion
            concept_extraction_model: Model for semantic expansion

        Returns:
            Expanded query with additional semantic terms
        """
        try:
            # Use ConceptExtractionAgent to find semantic alternatives

            from agents import ConceptExtractionAgent
            from services.telemetry_factory import TelemetryFactory

            telemetry = TelemetryFactory.create_context(
                entity_type="workspace",
                entity_id=workspace_id,
                operation_type="vector_search",
            )

            # Initialize agent with required parameters
            concept_agent = ConceptExtractionAgent(
                telemetry=telemetry,
                concept_extraction_model=concept_extraction_model,
            )

            # Extract concepts from the original query
            concept_result = concept_agent.extract_concepts_from_content(
                content=query,
                domain_name="search_query",
                domain_description="User search query for semantic expansion",
            )

            if not concept_result.search_terms:
                # Fallback: just return original query
                return query

            # Combine original query with extracted search terms
            all_terms = [query] + concept_result.search_terms[
                :3
            ]  # Limit to 3 additional terms
            expanded_query = " ".join(all_terms)

            self.logger.debug(
                f"Semantic expansion: {len(concept_result.search_terms)} terms added"
            )
            return expanded_query

        except Exception as e:
            self.logger.warning(f"Semantic expansion failed: {e}")
            # Fallback to original query if expansion fails
            return query
    def _get_query_embedding(self, query: str) -> list[float]:
        """Get embedding for query."""
        from vector_engine.embeddings.service import EmbeddingService

        embedding_service = EmbeddingService()
        return embedding_service.get_embedding(query, "text-embedding-3-small")

    def _result_to_dict(self, result: VectorSearchResult) -> dict[str, Any]:
        """Convert VectorSearchResult to dictionary."""
        return {
            "id": result.chunk_id,
            "document_id": result.document_id,
            "content": result.content,
            "score": result.score,
            "workspace_id": result.workspace_id,
            "asset_id": result.asset_id,
            "asset_type": result.asset_type,
            "content_type": result.content_type,
            "metadata": result.metadata,
        }

