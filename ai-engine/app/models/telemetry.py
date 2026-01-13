"""Telemetry context models for tracing and observability."""

from dataclasses import dataclass
from typing import Any


@dataclass
class TelemetryContext:
    """Telemetry context for AI operations."""

    session_id: str
    tags: list[str]
    metadata: dict[str, Any]

    def to_langfuse_config(self) -> dict[str, Any]:
        """Convert to Langfuse-specific format."""
        return {
            "langfuse_session_id": self.session_id,
            "langfuse_tags": self.tags,
            **self.metadata,
        }

    def to_openai_metadata(self) -> dict[str, Any]:
        """Convert to OpenAI metadata format."""
        return {
            "langfuse_session_id": self.session_id,
            "langfuse_tags": self.tags,
            **self.metadata,
        }
