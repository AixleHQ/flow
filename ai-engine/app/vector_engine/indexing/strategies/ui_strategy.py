"""Simple UI content indexing strategy."""

from langchain_text_splitters import RecursiveCharacterTextSplitter
from pydantic import Field

from vector_engine.core.exceptions import IndexingError
from vector_engine.core.models import VectorChunk, VectorDocument

from .base_strategy import BaseIndexingStrategy, IndexingConfig, VectorConfig


class UIIndexingConfig(IndexingConfig):
    """Simple configuration for UI content indexing strategy."""

    strategy_name: str = Field(default="ui_indexing")
    content_type: str = Field(default="ui_content")

    # Single vector - keep it simple
    vectors: list[VectorConfig] = Field(
        default_factory=lambda: [
            VectorConfig(
                name="semantic_description",
                embedding_model="text-embedding-3-small",
                dimension=1536,
                description="UI content semantic embedding",
            )
        ]
    )

    # Simple chunking configuration
    chunk_size: int = Field(
        default=800, description="Maximum chunk size for UI content"
    )
    chunk_overlap: int = Field(
        default=160, description="Overlap between UI chunks (20%)"
    )


class UIIndexingStrategy(BaseIndexingStrategy):
    """Simple UI content indexing strategy."""

    def __init__(self, config: UIIndexingConfig | None = None):
        """Initialize UI indexing strategy."""
        self.config = config or UIIndexingConfig()
        super().__init__(self.config)

        # Simple splitter for UI content
        self.splitter = RecursiveCharacterTextSplitter(
            chunk_size=self.config.chunk_size,
            chunk_overlap=self.config.chunk_overlap,
            separators=["\n\n## ", "\n\n### ", "\n\n", "\n", ". ", " ", ""],
            length_function=len,
        )

    def process_document(self, document: VectorDocument) -> VectorDocument:
        """Process UI content through simple indexing pipeline."""
        self.validate_document(document)

        try:
            # Clean content
            cleaned_content = self.clean_content(document.content)

            # Chunk content
            chunks = self.chunk_content(cleaned_content, document)

            # Generate embeddings
            final_chunks = self.generate_embeddings(chunks)

            # Validate results
            self.validate_chunks(final_chunks)

            # Update document
            document.chunks = final_chunks
            document.update_timestamp()

            return document

        except Exception as e:
            raise IndexingError(f"UI content processing failed: {e}")

    def clean_content(self, content: str) -> str:
        """Clean UI content."""
        # Basic cleaning
        content = content.strip()
        # Normalize whitespace but preserve structure
        import re

        content = re.sub(r"\n\s*\n", "\n\n", content)
        return content

    def chunk_content(
        self, content: str, document: VectorDocument
    ) -> list[VectorChunk]:
        """Chunk UI content using simple text splitting."""
        try:
            chunks = self.splitter.split_text(content)

            # Create VectorChunk objects
            vector_chunks = []
            for i, chunk_text in enumerate(chunks):
                # Skip empty or too short chunks
                stripped_text = chunk_text.strip()
                if not stripped_text or len(stripped_text) < 3:
                    continue

                token_count = self._count_tokens(stripped_text)
                if token_count <= 0:
                    continue

                vector_chunk = VectorChunk(
                    chunk_id=f"ui_chunk_{i}",
                    content=stripped_text,
                    token_count=token_count,
                    start_position=i * self.config.chunk_size,
                    end_position=(i + 1) * self.config.chunk_size,
                    metadata={
                        "chunk_index": i,
                        "total_chunks": len(chunks),
                        "content_type": "ui_content",
                    },
                )
                vector_chunks.append(vector_chunk)

            return vector_chunks

        except Exception as e:
            raise IndexingError(f"UI content chunking failed: {e}")

    def _count_tokens(self, text: str) -> int:
        """Estimate token count."""
        # Simple approximation: ~4 characters per token
        # Ensure minimum of 1 token for non-empty text
        token_count = len(text) // 4
        return max(1, token_count) if text.strip() else 0
