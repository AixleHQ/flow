"""Codebase search configuration."""

from pydantic import BaseModel, Field


class CodebaseSearchConfig(BaseModel):
    """Pre-configured settings for codebase search."""

    # Search parameters
    limit: int = Field(default=10, description="Maximum number of results")
    score_threshold: float = Field(default=0.7, description="Minimum similarity score")
    vector_name: str = Field(
        default="semantic_description", description="Vector field to search"
    )

    # Codebase-specific filters
    asset_types: list[str] = Field(
        default=["codebase"], description="Asset types to search"
    )
    content_types: list[str] = Field(
        default=["code"], description="Content types to search"
    )

    # Programming language filters
    languages: list[str] | None = Field(
        default=None, description="Programming languages to include"
    )
    exclude_languages: list[str] | None = Field(
        default=None, description="Languages to exclude"
    )

    # Domain-based filtering
    domains: list[str] | None = Field(
        default=None, description="Code domains to search"
    )
    available_domains: list[str] = Field(
        default=[
            "authentication",
            "infrastructure",
            "business_logic",
            "api",
            "database",
            "utils",
        ],
        description="Available domain categories",
    )

    # Function/class filtering
    include_functions: bool = Field(
        default=True, description="Include function definitions"
    )
    include_classes: bool = Field(default=True, description="Include class definitions")
    include_comments: bool = Field(default=False, description="Include code comments")

    # Search enhancement
    expand_query: bool = Field(
        default=True, description="Expand query with code-related terms"
    )
    boost_recent: bool = Field(default=False, description="Boost more recent code")

    @classmethod
    def for_functions(cls, domains: list[str] | None = None) -> "CodebaseSearchConfig":
        """Search specifically for function definitions."""
        return cls(
            include_functions=True,
            include_classes=False,
            include_comments=False,
            domains=domains,
            limit=15,
        )

    @classmethod
    def for_domain(cls, domain: str) -> "CodebaseSearchConfig":
        """Search within specific code domain."""
        return cls(
            domains=[domain],
            include_functions=True,
            include_classes=True,
            expand_query=True,
            limit=20,
        )

    @classmethod
    def for_language(cls, language: str) -> "CodebaseSearchConfig":
        """Search within specific programming language."""
        return cls(
            languages=[language],
            include_functions=True,
            include_classes=True,
            limit=15,
        )

    @classmethod
    def comprehensive(cls) -> "CodebaseSearchConfig":
        """Comprehensive search across entire codebase."""
        return cls(
            include_functions=True,
            include_classes=True,
            include_comments=True,
            expand_query=True,
            limit=25,
            score_threshold=0.6,
        )
