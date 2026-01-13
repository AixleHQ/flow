"""Document search configuration."""

from pydantic import BaseModel, Field


class DocumentSearchConfig(BaseModel):
    """Pre-configured settings for document search."""

    # Search parameters
    limit: int = Field(default=10, description="Maximum number of results")
    score_threshold: float = Field(default=0.75, description="Minimum similarity score")
    vector_name: str = Field(
        default="semantic_description", description="Vector field to search"
    )

    # Document-specific filters
    asset_types: list[str] = Field(
        default=["document"], description="Asset types to search"
    )
    content_types: list[str] = Field(
        default=["document", "pdf", "markdown", "text"], description="Content types"
    )

    # Document type filtering
    document_types: list[str] | None = Field(
        default=None, description="Specific document types"
    )
    exclude_types: list[str] | None = Field(
        default=None, description="Document types to exclude"
    )

    # Content filtering
    include_summaries: bool = Field(
        default=True, description="Include document summaries"
    )
    include_headers: bool = Field(default=True, description="Include document headers")
    include_metadata: bool = Field(default=False, description="Search in metadata")

    # Search enhancement
    semantic_expansion: bool = Field(
        default=True, description="Expand query semantically"
    )
    boost_recent: bool = Field(default=True, description="Boost more recent documents")

    # Quality filtering
    min_quality_score: float | None = Field(
        default=None, description="Minimum content quality score"
    )

    @classmethod
    def for_technical_docs(cls) -> "DocumentSearchConfig":
        """Search specifically in technical documentation."""
        return cls(
            document_types=["technical", "specification", "api"],
            include_summaries=True,
            include_headers=True,
            semantic_expansion=True,
            limit=15,
        )

    @classmethod
    def for_business_docs(cls) -> "DocumentSearchConfig":
        """Search in business documents."""
        return cls(
            document_types=["business", "requirements", "proposal"],
            include_summaries=True,
            boost_recent=True,
            limit=10,
            score_threshold=0.8,
        )

    @classmethod
    def quick_search(cls) -> "DocumentSearchConfig":
        """Quick search with relaxed parameters."""
        return cls(
            limit=5,
            score_threshold=0.6,
            include_summaries=True,
            semantic_expansion=False,
        )

    @classmethod
    def comprehensive(cls) -> "DocumentSearchConfig":
        """Comprehensive document search."""
        return cls(
            limit=25,
            score_threshold=0.65,
            include_summaries=True,
            include_headers=True,
            include_metadata=True,
            semantic_expansion=True,
        )
