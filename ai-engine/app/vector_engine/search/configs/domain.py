"""Domain-based search configuration."""

from pydantic import BaseModel, Field


class DomainSearchConfig(BaseModel):
    """Pre-configured settings for domain-specific search."""

    # Search parameters
    limit: int = Field(default=10, description="Maximum number of results")
    score_threshold: float = Field(default=0.7, description="Minimum similarity score")
    vector_name: str = Field(
        default="semantic_description", description="Vector field to search"
    )

    # Domain targeting
    target_domains: list[str] = Field(description="Specific domains to search within")
    domain_weight: float = Field(
        default=1.2, description="Weight boost for domain matches"
    )

    # Content type preferences
    preferred_content_types: list[str] = Field(
        default=["code", "document"],
        description="Preferred content types for domain search",
    )

    # Cross-domain search
    include_related_domains: bool = Field(
        default=True, description="Include related domains"
    )
    domain_relationships: dict[str, list[str]] = Field(
        default={
            "authentication": ["security", "api", "user_management"],
            "infrastructure": ["deployment", "configuration", "monitoring"],
            "business_logic": ["workflow", "validation", "processing"],
            "api": ["authentication", "documentation", "integration"],
            "database": ["migration", "schema", "query"],
            "utils": ["helpers", "common", "shared"],
        },
        description="Domain relationship mapping",
    )

    # Search enhancement
    boost_exact_domain: bool = Field(
        default=True, description="Boost exact domain matches"
    )
    expand_domain_terms: bool = Field(
        default=True, description="Expand with domain-specific terms"
    )

    @classmethod
    def for_authentication(cls) -> "DomainSearchConfig":
        """Search within authentication domain."""
        return cls(
            target_domains=["authentication"],
            include_related_domains=True,
            boost_exact_domain=True,
            limit=15,
        )

    @classmethod
    def for_infrastructure(cls) -> "DomainSearchConfig":
        """Search within infrastructure domain."""
        return cls(
            target_domains=["infrastructure"],
            include_related_domains=True,
            preferred_content_types=["code", "document", "configuration"],
            limit=20,
        )

    @classmethod
    def for_business_logic(cls) -> "DomainSearchConfig":
        """Search within business logic domain."""
        return cls(
            target_domains=["business_logic"],
            include_related_domains=True,
            boost_exact_domain=True,
            expand_domain_terms=True,
            limit=15,
        )

    @classmethod
    def cross_domain(cls, domains: list[str]) -> "DomainSearchConfig":
        """Search across multiple domains."""
        return cls(
            target_domains=domains,
            include_related_domains=True,
            domain_weight=1.0,  # Equal weight for all domains
            limit=25,
            score_threshold=0.65,
        )
