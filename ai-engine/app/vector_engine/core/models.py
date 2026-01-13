"""Core models for vector engine."""

from datetime import UTC, datetime
from typing import Any

from pydantic import BaseModel, Field

from config import settings


class VectorChunk(BaseModel):
    """Represents a chunk of content with vector embeddings."""

    chunk_id: str = Field(description="Unique identifier for the chunk")
    content: str = Field(description="Text content of the chunk")
    token_count: int = Field(description="Number of tokens in the chunk")
    start_position: int = Field(
        default=0, description="Start position in original content"
    )
    end_position: int = Field(default=0, description="End position in original content")

    # Vector embeddings for different strategies
    embeddings: dict[str, list[float]] = Field(
        default_factory=dict, description="Vector embeddings by strategy name"
    )

    # Metadata
    metadata: dict[str, Any] = Field(
        default_factory=dict, description="Additional metadata for the chunk"
    )

    def add_embedding(self, strategy_name: str, embedding: list[float]) -> None:
        """Add an embedding for a specific strategy."""
        self.embeddings[strategy_name] = embedding

    def get_embedding(self, strategy_name: str) -> list[float] | None:
        """Get embedding for a specific strategy."""
        return self.embeddings.get(strategy_name)


class VectorDocument(BaseModel):
    """Represents a document with multiple vector chunks."""

    document_id: str = Field(description="Unique identifier for the document")
    content: str = Field(description="Original content of the document")
    content_type: str = Field(description="Type of content (document, code, ui_image)")

    # Document metadata
    workspace_id: int = Field(description="Workspace this document belongs to")
    asset_id: int = Field(description="Asset this document represents")
    asset_type: str = Field(description="Type of asset")

    # Processing metadata
    created_at: datetime = Field(default_factory=lambda: datetime.now(UTC))
    updated_at: datetime = Field(default_factory=lambda: datetime.now(UTC))

    # Chunks
    chunks: list[VectorChunk] = Field(
        default_factory=list, description="List of content chunks"
    )

    # Global metadata
    metadata: dict[str, Any] = Field(
        default_factory=dict, description="Document-level metadata"
    )

    def add_chunk(self, chunk: VectorChunk) -> None:
        """Add a chunk to the document."""
        self.chunks.append(chunk)

    def get_all_embeddings(self, strategy_name: str) -> list[list[float]]:
        """Get all embeddings for a specific strategy from all chunks."""
        embeddings = []
        for chunk in self.chunks:
            embedding = chunk.get_embedding(strategy_name)
            if embedding:
                embeddings.append(embedding)
        return embeddings

    def update_timestamp(self) -> None:
        """Update the updated_at timestamp."""
        self.updated_at = datetime.now(UTC)


class VectorSearchFilter(BaseModel):
    """Filter for vector search operations."""

    workspace_id: int = Field(description="Workspace to search in")
    asset_ids: list[int] | None = Field(
        default=None, description="Specific assets to search"
    )
    asset_types: list[str] | None = Field(
        default=None, description="Asset types to include"
    )
    content_types: list[str] | None = Field(
        default=None, description="Content types to include"
    )

    # Date filters
    created_after: datetime | None = Field(
        default=None, description="Only include documents created after this date"
    )
    created_before: datetime | None = Field(
        default=None, description="Only include documents created before this date"
    )

    # Additional metadata filters
    metadata_filters: dict[str, Any] = Field(
        default_factory=dict, description="Additional metadata filters"
    )

    def to_qdrant_filter(self) -> dict[str, Any]:
        """Convert to Qdrant filter format."""
        conditions = []

        # Workspace filter - support both old (string) and new (int) formats
        workspace_conditions = [
            {"key": "workspace_id", "match": {"value": self.workspace_id}},
            {
                "key": "workspace_id",
                "match": {"value": f"{settings.env}_{self.workspace_id}"},
            },
        ]
        conditions.append({"should": workspace_conditions})

        # Asset ID filters
        if self.asset_ids:
            conditions.append({"key": "asset_id", "match": {"any": self.asset_ids}})

        # Asset type filters
        if self.asset_types:
            conditions.append({"key": "asset_type", "match": {"any": self.asset_types}})

        # Content type filters
        if self.content_types:
            conditions.append(
                {"key": "content_type", "match": {"any": self.content_types}}
            )

        # Date filters
        if self.created_after or self.created_before:
            date_conditions = {}
            if self.created_after:
                date_conditions["gte"] = self.created_after.isoformat()
            if self.created_before:
                date_conditions["lte"] = self.created_before.isoformat()

            conditions.append({"key": "created_at", "range": date_conditions})

        # Metadata filters
        for key, value in self.metadata_filters.items():
            conditions.append({"key": f"metadata.{key}", "match": {"value": value}})

        return {"must": conditions} if conditions else {}


class VectorSearchResult(BaseModel):
    """Result from vector search operation."""

    document_id: str = Field(description="Document ID")
    chunk_id: str = Field(description="Chunk ID")
    content: str = Field(description="Chunk content")
    score: float = Field(description="Similarity score")

    # Document metadata
    workspace_id: int = Field(description="Workspace ID")
    asset_id: int = Field(description="Asset ID")
    asset_type: str = Field(description="Asset type")
    content_type: str = Field(description="Content type")

    # Additional metadata
    metadata: dict[str, Any] = Field(
        default_factory=dict, description="Additional metadata from the chunk"
    )

    def to_dict(self) -> dict[str, Any]:
        """Convert to dictionary for API responses."""
        return {
            "document_id": self.document_id,
            "chunk_id": self.chunk_id,
            "content": self.content,
            "score": self.score,
            "workspace_id": self.workspace_id,
            "asset_id": self.asset_id,
            "asset_type": self.asset_type,
            "content_type": self.content_type,
            "metadata": self.metadata,
        }
