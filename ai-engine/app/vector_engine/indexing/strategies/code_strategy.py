"""Simple code indexing strategy."""

from typing import Any

from langchain_text_splitters import Language, RecursiveCharacterTextSplitter
from core.logging import logger
from pydantic import Field

from vector_engine.core.exceptions import IndexingError
from vector_engine.core.models import VectorChunk, VectorDocument

from .base_strategy import BaseIndexingStrategy, IndexingConfig, VectorConfig


class CodeIndexingConfig(IndexingConfig):
    """Configuration for code indexing strategy with support for large files."""

    strategy_name: str = Field(default="code_indexing")
    content_type: str = Field(default="code")

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
                description="Code semantic embedding",
            )
        ]
    )

    chunk_size: int = Field(default=2000, description="Maximum chunk size for code")
    chunk_overlap: int = Field(
        default=400, description="Overlap between code chunks (20%)"
    )

    large_file_threshold: int = Field(
        default=100_000, description="Threshold to consider file as large (100KB)"
    )
    large_file_chunk_size: int = Field(
        default=3000, description="Chunk size for large files"
    )
    large_file_chunk_overlap: int = Field(
        default=600, description="Overlap for large files"
    )


class CodeIndexingStrategy(BaseIndexingStrategy):
    """Simple code indexing strategy using LangChain."""

    def __init__(self, config: CodeIndexingConfig | None = None):
        """Initialize code indexing strategy."""
        self.config = config or CodeIndexingConfig()
        super().__init__(self.config)
        self.logger = logger

    def process_document(self, document: VectorDocument) -> VectorDocument:
        """Process code through simple indexing pipeline."""
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
            raise IndexingError(f"Code processing failed: {e}")

    def clean_content(self, content: str) -> str:
        """Clean code content."""
        # Basic cleaning - preserve code structure
        return content.strip()

    def chunk_content(
        self, content: str, document: VectorDocument
    ) -> list[VectorChunk]:
        """Chunk code content using LangChain language-specific splitters with large file optimization."""
        # Try to detect language from metadata
        language = self._detect_language(document.metadata)

        # Check if this is a large file and adjust parameters
        is_large_file = len(content) > self.config.large_file_threshold
        if is_large_file:
            self.logger.info(f"Processing large file: {len(content)} characters")

        # Use LangChain language-specific splitter if available
        splitter = self._get_language_splitter(language, is_large_file)
        chunks = splitter.split_text(content)

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
                chunk_id=f"code_chunk_{i}",
                content=stripped_text,
                token_count=token_count,
                start_position=i * self.config.chunk_size,
                end_position=(i + 1) * self.config.chunk_size,
                metadata={
                    "chunk_index": i,
                    "total_chunks": len(chunks),
                    "content_type": "code",
                    "detected_language": language,
                },
            )
            vector_chunks.append(vector_chunk)

        return vector_chunks

    def _detect_language(self, metadata: dict[str, Any]) -> str:
        """Simple language detection from file path."""
        file_path = metadata.get("file_path", "").lower()

        if file_path.endswith(".py"):
            return "python"
        if file_path.endswith((".js", ".jsx")):
            return "javascript"
        if file_path.endswith((".ts", ".tsx")):
            return "typescript"
        if file_path.endswith(".java"):
            return "java"
        if file_path.endswith((".cpp", ".cc", ".cxx")):
            return "cpp"
        if file_path.endswith(".c"):
            return "c"
        if file_path.endswith(".go"):
            return "go"
        if file_path.endswith(".rs"):
            return "rust"
        if file_path.endswith((".rb", ".rake")):
            return "ruby"
        if file_path.endswith(".php"):
            return "php"
        if file_path.endswith((".cob", ".cbl", ".cobol", ".pco", ".cpy")):
            return "cobol"
        if file_path.endswith((".f", ".f90", ".f95", ".for")):
            return "fortran"
        if file_path.endswith((".sh", ".bash")):
            return "shell"
        if file_path.endswith((".html", ".htm")):
            return "html"
        if file_path.endswith((".css", ".scss", ".sass")):
            return "css"
        return "generic"

    def _get_language_splitter(
        self, language: str, is_large_file: bool = False
    ) -> RecursiveCharacterTextSplitter:
        """Get language-specific splitter from LangChain with large file optimization."""
        # Choose chunk parameters based on file size
        if is_large_file:
            chunk_size = self.config.large_file_chunk_size
            chunk_overlap = self.config.large_file_chunk_overlap
        else:
            chunk_size = self.config.chunk_size
            chunk_overlap = self.config.chunk_overlap

        try:
            # Map to LangChain Language enum
            lang_mapping = {
                "python": Language.PYTHON,
                "javascript": Language.JS,
                "typescript": Language.TS,
                "java": Language.JAVA,
                "cpp": Language.CPP,
                "c": Language.C,
                "go": Language.GO,
                "rust": Language.RUST,
            }

            if language in lang_mapping:
                return RecursiveCharacterTextSplitter.from_language(
                    language=lang_mapping[language],
                    chunk_size=chunk_size,
                    chunk_overlap=chunk_overlap,
                )
        except Exception:
            # Fallback to generic if language-specific fails
            pass

        # Generic code splitter with appropriate separators for large files
        separators = ["\n\nclass ", "\n\ndef ", "\n\nfunction ", "\n\n", "\n", " ", ""]
        if is_large_file:
            # For large files, add more granular separators
            separators = [
                "\n\nclass ",
                "\n\ndef ",
                "\n\nfunction ",
                "\n\nif ",
                "\n\nfor ",
                "\n\nwhile ",
                "\n\ntry ",
                "\n\n",
                "\n",
                " ",
                "",
            ]

        return RecursiveCharacterTextSplitter(
            chunk_size=chunk_size,
            chunk_overlap=chunk_overlap,
            separators=separators,
            length_function=len,
        )

    def _count_tokens(self, text: str) -> int:
        """Estimate token count."""
        # Simple approximation: ~4 characters per token
        # Ensure minimum of 1 token for non-empty text
        token_count = len(text) // 4
        return max(1, token_count) if text.strip() else 0
