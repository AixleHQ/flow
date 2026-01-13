"""General content search configuration."""

from pydantic import BaseModel, Field


class ContentSearchConfig(BaseModel):
    """Pre-configured settings for general content search."""

    # Search parameters
    limit: int = Field(default=10, description="Maximum number of results")
    score_threshold: float = Field(default=0.7, description="Minimum similarity score")
    vector_name: str = Field(
        default="semantic_description", description="Vector field to search"
    )

    # Content filtering
    asset_types: list[str] | None = Field(
        default=None, description="Asset types to include"
    )
    content_types: list[str] | None = Field(
        default=None, description="Content types to include"
    )
    asset_ids: list[int] | None = Field(
        default=None, description="Specific assets to search"
    )

    # Search modes
    semantic_search: bool = Field(default=True, description="Use semantic similarity")
    keyword_boost: bool = Field(
        default=False, description="Boost exact keyword matches"
    )
    fuzzy_matching: bool = Field(default=False, description="Enable fuzzy matching")

    # Result enhancement
    include_context: bool = Field(
        default=True, description="Include surrounding context"
    )
    context_window: int = Field(
        default=200, description="Context window size in characters"
    )
    deduplicate_results: bool = Field(
        default=True, description="Remove duplicate content"
    )

    # Quality filtering
    min_content_length: int = Field(default=50, description="Minimum content length")
    max_content_age_days: int | None = Field(
        default=None, description="Maximum content age in days"
    )

    @classmethod
    def for_asset(cls, asset_id: int) -> "ContentSearchConfig":
        """Search within specific asset."""
        return cls(
            asset_ids=[asset_id],
            limit=20,
            include_context=True,
            deduplicate_results=True,
        )

    @classmethod
    def for_assets(cls, asset_ids: list[int]) -> "ContentSearchConfig":
        """Search across multiple assets."""
        return cls(
            asset_ids=asset_ids,
            limit=25,
            score_threshold=0.65,
            include_context=True,
        )

    @classmethod
    def quick_search(cls) -> "ContentSearchConfig":
        """Quick search with minimal processing."""
        return cls(
            limit=5,
            score_threshold=0.6,
            include_context=False,
            deduplicate_results=False,
        )

    @classmethod
    def comprehensive(cls) -> "ContentSearchConfig":
        """Comprehensive search across all content."""
        return cls(
            limit=30,
            score_threshold=0.6,
            semantic_search=True,
            keyword_boost=True,
            include_context=True,
            deduplicate_results=True,
        )

    @classmethod
    def recent_content(cls, days: int = 30) -> "ContentSearchConfig":
        """Search only recent content."""
        return cls(
            max_content_age_days=days,
            limit=15,
            include_context=True,
            deduplicate_results=True,
        )
