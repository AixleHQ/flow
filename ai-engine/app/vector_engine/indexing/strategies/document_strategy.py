"""Simple document indexing strategy."""

from langchain_text_splitters import (
    MarkdownHeaderTextSplitter,
    RecursiveCharacterTextSplitter,
)
from pydantic import Field

from core.logging import logger
from vector_engine.core.exceptions import IndexingError
from vector_engine.core.models import VectorChunk, VectorDocument

from .base_strategy import BaseIndexingStrategy, IndexingConfig, VectorConfig


class DocumentIndexingConfig(IndexingConfig):
    """Simple configuration for document indexing strategy."""

    strategy_name: str = Field(default="document_indexing")
    content_type: str = Field(default="document")

    max_content_length: int = Field(
        default=50_000_000,  # 50MB
        description="Maximum content length to process",
    )

    # Single vector - keep it simple
    vectors: list[VectorConfig] = Field(
        default_factory=lambda: [
            VectorConfig(
                name="semantic_description",
                embedding_model="text-embedding-3-small",
                dimension=1536,
                description="Semantic content embedding",
            )
        ]
    )

    # Simple chunking configuration
    chunk_size: int = Field(
        default=1000, description="Maximum chunk size in characters"
    )
    chunk_overlap: int = Field(default=200, description="Overlap between chunks")


class DocumentIndexingStrategy(BaseIndexingStrategy):
    """Simple document indexing strategy using LangChain."""

    def __init__(self, config: DocumentIndexingConfig | None = None):
        """Initialize document indexing strategy."""
        self.config = config or DocumentIndexingConfig()
        super().__init__(self.config)

        # Initialize splitters
        self.recursive_splitter = RecursiveCharacterTextSplitter(
            chunk_size=self.config.chunk_size,
            chunk_overlap=self.config.chunk_overlap,
            separators=["\n\n", "\n", ". ", "! ", "? ", " ", ""],
            length_function=len,
        )

        self.markdown_splitter = MarkdownHeaderTextSplitter(
            headers_to_split_on=[
                ("#", "Header 1"),
                ("##", "Header 2"),
                ("###", "Header 3"),
            ],
            strip_headers=False,
        )

    def process_document(self, document: VectorDocument) -> VectorDocument:
        """Process document through simple indexing pipeline."""
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
            raise IndexingError(f"Document processing failed: {e}")

    def clean_content(self, content: str) -> str:
        """Clean document content."""
        # Basic cleaning
        content = content.strip()
        # Remove excessive whitespace
        import re

        content = re.sub(r"\n\s*\n", "\n\n", content)  # Normalize line breaks
        content = re.sub(r" +", " ", content)  # Normalize spaces
        return content

    def chunk_content(
        self, content: str, document: VectorDocument
    ) -> list[VectorChunk]:
        """Chunk document content using LangChain splitters."""
        try:
            # Detect if content is markdown
            if self._is_markdown(content):
                logger.info("Document chunking -  markdown splitting.")
                texts = self.markdown_splitter.split_text(content)
                chunks = []
                for text in texts:
                    text_content = (
                        text.page_content
                        if hasattr(text, "page_content")
                        else str(text)
                    )
                    if len(text_content) > self.config.chunk_size:
                        sub_chunks = self.recursive_splitter.split_text(text_content)
                        chunks.extend(sub_chunks)
                    else:
                        chunks.append(text_content)
            else:
                logger.info("Document chunking - fallback to recursive splitter.")
                chunks = self.recursive_splitter.split_text(content)

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
                    chunk_id=f"doc_chunk_{i}",
                    content=stripped_text,
                    token_count=token_count,
                    start_position=i * self.config.chunk_size,
                    end_position=(i + 1) * self.config.chunk_size,
                    metadata={
                        "chunk_index": i,
                        "total_chunks": len(chunks),
                        "content_type": "document",
                    },
                )
                vector_chunks.append(vector_chunk)

            return vector_chunks

        except Exception as e:
            raise IndexingError(f"Document chunking failed: {e}")

    def _is_markdown(self, content: str) -> bool:
        """Simple markdown detection."""
        return any(
            marker in content for marker in ["# ", "## ", "### ", "**", "*", "[", "]("]
        )

    def _count_tokens(self, text: str) -> int:
        """Estimate token count."""
        # Simple approximation: ~4 characters per token
        # Ensure minimum of 1 token for non-empty text
        token_count = len(text) // 4
        return max(1, token_count) if text.strip() else 0
