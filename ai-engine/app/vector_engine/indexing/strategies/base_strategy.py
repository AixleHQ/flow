"""Base indexing strategy for content processing."""

from abc import ABC, abstractmethod
from typing import Any

from core.logging import logger
from pydantic import BaseModel, Field

from vector_engine.core.exceptions import IndexingError
from vector_engine.core.models import VectorChunk, VectorDocument


class VectorConfig(BaseModel):
    """Configuration for a single vector type."""

    name: str = Field(description="Name of the vector (e.g., 'semantic_description')")
    embedding_model: str = Field(
        default="text-embedding-3-small", description="Embedding model to use"
    )
    dimension: int = Field(default=1536, description="Vector dimension")
    description: str = Field(
        default="", description="Description of what this vector represents"
    )


class IndexingConfig(BaseModel):
    """Base configuration for indexing strategies."""

    strategy_name: str = Field(description="Name of the indexing strategy")
    content_type: str = Field(description="Type of content this strategy handles")

    # Vector configurations
    vectors: list[VectorConfig] = Field(
        default_factory=lambda: [
            VectorConfig(
                name="semantic_description",
                embedding_model="text-embedding-3-small",
                dimension=1536,
                description="General semantic content embedding",
            )
        ],
        description="Vector configurations for this strategy",
    )

    # Content processing
    enable_content_cleaning: bool = Field(
        default=True, description="Enable content cleaning before processing"
    )
    enable_chunking: bool = Field(default=True, description="Enable content chunking")

    # Quality settings
    min_content_length: int = Field(
        default=10, description="Minimum content length to process"
    )
    max_content_length: int = Field(
        default=50_000_000,  # 50MB
        description="Maximum content length to process",
    )

    # Batch processing
    batch_size: int = Field(
        default=2000,
        description="Batch size for embedding generation (OpenAI optimized)",
    )

    # Metadata
    default_metadata: dict[str, Any] = Field(
        default_factory=dict, description="Default metadata to add to all chunks"
    )


class BaseIndexingStrategy(ABC):
    """
    Base class for content indexing strategies.

    Each strategy handles a specific content type and knows how to:
    1. Clean and prepare content
    2. Chunk content appropriately
    3. Generate embeddings with the right models
    4. Create appropriate metadata
    5. Validate results
    """

    def __init__(self, config: IndexingConfig | None = None):
        """Initialize indexing strategy."""
        self.config = config or IndexingConfig()
        self.logger = logger

    @abstractmethod
    def process_document(self, document: VectorDocument) -> VectorDocument:
        """
        Process a document through the full indexing pipeline.

        Args:
            document: Document to process

        Returns:
            Processed document with chunks and embeddings

        Raises:
            IndexingError: If processing fails
        """

    def index_document(self, document: VectorDocument) -> str:
        """
        Index a document and return collection name.

        Args:
            document: Document to index

        Returns:
            Collection name where document was indexed
        """
        # Process document (chunks + embeddings)
        self.process_document(document)

        # Note: Storage is handled by the VectorIndexingEngine
        # This method only processes the document for indexing
        return f"workspace_{document.workspace_id}"

    @abstractmethod
    def clean_content(self, content: str) -> str:
        """
        Clean and prepare content for processing.

        Args:
            content: Raw content to clean

        Returns:
            Cleaned content ready for chunking
        """

    @abstractmethod
    def chunk_content(
        self, content: str, document: VectorDocument
    ) -> list[VectorChunk]:
        """
        Chunk content into appropriate segments.

        Args:
            content: Cleaned content to chunk
            document: Original document for context

        Returns:
            List of content chunks
        """

    def generate_embeddings(self, chunks: list[VectorChunk]) -> list[VectorChunk]:
        """
        Generate embeddings for all chunks using configured vectors.

        Uses synchronous service with ThreadPoolExecutor for parallel batch processing.

        Args:
            chunks: List of chunks to generate embeddings for

        Returns:
            Chunks with embeddings added
        """
        from vector_engine.embeddings.service import EmbeddingService

        embedding_service = EmbeddingService()
        self.logger.debug("Using sync embedding service with parallel batching")
        return self._generate_embeddings_optimized(chunks, embedding_service)

    def _generate_embeddings_optimized(
        self, chunks: list[VectorChunk], embedding_service
    ) -> list[VectorChunk]:
        for vector_config in self.config.vectors:
            self.logger.info(
                f"Generating embeddings for {len(chunks)} chunks with {vector_config.embedding_model}"
            )

            all_content = [chunk.content for chunk in chunks]

            self.logger.debug(
                f"Starting parallel embedding generation for {len(all_content)} chunks..."
            )
            all_embeddings = embedding_service.generate_embeddings_batch(
                all_content, vector_config.embedding_model
            )
            self.logger.debug(
                f"Parallel embedding generation completed: {len(all_embeddings)} embeddings"
            )
            for chunk, embedding in zip(chunks, all_embeddings, strict=False):
                if chunk.embeddings is None:
                    chunk.embeddings = {}
                chunk.embeddings[vector_config.name] = embedding

            self.logger.info(
                f"Successfully generated {len(all_embeddings)} embeddings in optimized mode"
            )

        return chunks

    def validate_document(self, document: VectorDocument) -> None:
        """Validate document before processing."""
        if not document.content or not document.content.strip():
            raise IndexingError("Document content is empty")

        if len(document.content) < self.config.min_content_length:
            raise IndexingError(
                f"Content too short: {len(document.content)} < {self.config.min_content_length}"
            )

        if len(document.content) > self.config.max_content_length:
            raise IndexingError(
                f"Content too long: {len(document.content)} > {self.config.max_content_length}"
            )

        if not document.workspace_id:
            raise IndexingError("Invalid workspace_id")

        if not document.asset_id or document.asset_id <= 0:
            raise IndexingError("Invalid asset_id")

    def validate_chunks(self, chunks: list[VectorChunk]) -> None:
        """Validate generated chunks."""
        if not chunks:
            raise IndexingError("No chunks generated")

        for i, chunk in enumerate(chunks):
            if not chunk.content or not chunk.content.strip():
                raise IndexingError(f"Chunk {i} has empty content")

            if chunk.token_count <= 0:
                raise IndexingError(
                    f"Chunk {i} has invalid token count: {chunk.token_count}"
                )

            # Check that embeddings were generated for all configured vectors
            for vector_config in self.config.vectors:
                if not chunk.get_embedding(vector_config.name):
                    raise IndexingError(
                        f"Chunk {i} missing embedding for vector: {vector_config.name}"
                    )

    def create_document_metadata(self, document: VectorDocument) -> dict[str, Any]:
        """Create metadata for the document."""
        metadata = {
            "strategy_name": self.config.strategy_name,
            "content_type": self.config.content_type,
            "processing_timestamp": document.created_at.isoformat(),
            "workspace_id": document.workspace_id,
            "asset_id": document.asset_id,
            "asset_type": document.asset_type,
            "original_content_length": len(document.content),
            **self.config.default_metadata,
        }

        return metadata

    def create_chunk_metadata(
        self,
        chunk: VectorChunk,
        document: VectorDocument,
        additional_metadata: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        """Create metadata for a chunk."""
        metadata = {
            "document_id": document.document_id,
            "workspace_id": document.workspace_id,
            "asset_id": document.asset_id,
            "asset_type": document.asset_type,
            "content_type": document.content_type,
            "strategy_name": self.config.strategy_name,
            "chunk_token_count": chunk.token_count,
            "vectors_generated": list(chunk.embeddings.keys()),
            **self.config.default_metadata,
        }

        if additional_metadata:
            metadata.update(additional_metadata)

        return metadata

    def get_vector_configs(self) -> list[VectorConfig]:
        """Get vector configurations for this strategy."""
        return self.config.vectors

    def add_vector_config(self, vector_config: VectorConfig) -> None:
        """Add a new vector configuration."""
        # Check for duplicate names
        existing_names = {v.name for v in self.config.vectors}
        if vector_config.name in existing_names:
            raise ValueError(
                f"Vector config with name '{vector_config.name}' already exists"
            )

        self.config.vectors.append(vector_config)
        self.logger.info(f"Added vector config: {vector_config.name}")

    def remove_vector_config(self, vector_name: str) -> None:
        """Remove a vector configuration."""
        self.config.vectors = [v for v in self.config.vectors if v.name != vector_name]
        self.logger.info(f"Removed vector config: {vector_name}")

    def get_strategy_info(self) -> dict[str, Any]:
        """Get information about this strategy."""
        return {
            "strategy_name": self.config.strategy_name,
            "content_type": self.config.content_type,
            "vectors": [
                {
                    "name": v.name,
                    "model": v.embedding_model,
                    "dimension": v.dimension,
                    "description": v.description,
                }
                for v in self.config.vectors
            ],
            "enable_chunking": self.config.enable_chunking,
            "enable_content_cleaning": self.config.enable_content_cleaning,
            "batch_size": self.config.batch_size,
        }
