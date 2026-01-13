"""Core configuration for vector engine."""

from pydantic import BaseModel, Field

from config import settings


class VectorCoreConfig(BaseModel):
    """Core configuration for vector engine operations."""

    # Qdrant connection settings
    qdrant_url: str = Field(
        default=settings.qdrant.url,
        description="Qdrant server URL",
    )
    connection_timeout: int = Field(
        default=300,
        description="Connection timeout in seconds (5 minutes for large files)",
    )
    write_timeout: int = Field(
        default=300,
        description="Write timeout in seconds (5 minutes for large uploads)",
    )
    read_timeout: int = Field(
        default=120, description="Read timeout in seconds (2 minutes)"
    )

    # Collection settings
    collection_prefix: str = Field(
        default="workspace", description="Prefix for collection names"
    )
    default_vector_size: int = Field(
        default=1536, description="Default vector size (text-embedding-3-small)"
    )

    # Performance settings
    batch_size: int = Field(
        default=200,
        description="Default batch size for Qdrant operations (optimized for throughput)",
    )
    max_concurrent_operations: int = Field(
        default=10, description="Maximum concurrent operations"
    )

    # Retry settings
    default_max_retries: int = Field(
        default=3, description="Default maximum retry attempts"
    )
    default_retry_delay: float = Field(
        default=1.0, description="Default delay between retries in seconds"
    )

    # Embedding model settings
    default_embedding_model: str = Field(
        default="text-embedding-3-small", description="Default embedding model"
    )

    # Validation settings
    max_content_length: int = Field(
        default=1_000_000,  # 1MB
        description="Maximum content length for processing",
    )
    min_content_length: int = Field(
        default=10, description="Minimum content length for processing"
    )

    def get_collection_name(self, workspace_id: int) -> str:
        """Generate collection name for workspace."""
        return f"{self.collection_prefix}_{settings.env}_{workspace_id}"
