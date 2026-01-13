"""Exceptions for vector engine operations."""


class VectorEngineError(Exception):
    """Base exception for vector engine operations."""


class IndexingError(VectorEngineError):
    """Exception raised during indexing operations."""


class SearchError(VectorEngineError):
    """Exception raised during search operations."""


class ChunkingError(VectorEngineError):
    """Exception raised during content chunking."""


class ValidationError(VectorEngineError):
    """Exception raised when content validation fails."""
