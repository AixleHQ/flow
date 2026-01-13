"""Batch Text Agent implementation for processing content in chunks."""

from collections.abc import Callable
from typing import Any

from core.logging import logger
from pydantic import BaseModel

from agents.common.base_openrouter_agent import BaseOpenRouterAgent
from models.telemetry import TelemetryContext

from .configuration import BatchTextAgentConfig


class BatchTextAgent[T](BaseOpenRouterAgent[T]):
    """
    Agent that processes content in batches with chunking and aggregation.

    Features:
    - Smart file-aware chunking
    - Batch processing with structured outputs
    - Multiple aggregation strategies
    - Data-driven processing (no LLM for simple aggregation)
    """

    def __init__(
        self,
        agent_name: str,
        telemetry: TelemetryContext,
        config: BatchTextAgentConfig | None = None,
        structured_output_type: type[T] | None = None,
    ):
        super().__init__(agent_name, telemetry, config, structured_output_type)

        if config is None:
            config = BatchTextAgentConfig()

        self.max_chunk_size = config.max_chunk_size
        self.max_concurrent_chunks = config.max_concurrent_chunks

    def invoke_batch(
        self,
        system_prompt: str,
        content_chunks: list[str],
        structured_output_schema: type[T],
        metadata: dict[str, Any] | None = None,
        aggregation_fn: Callable[[list[T]], T] | None = None,
    ) -> T:
        """
        Process multiple content chunks in parallel and aggregate results.

        Uses async gather with semaphore to process chunks concurrently
        while respecting rate limits and avoiding thread pool starvation.

        Args:
            system_prompt: System prompt for the LLM
            content_chunks: List of content strings to process
            structured_output_schema: Pydantic model for structured output
            metadata: Additional metadata for telemetry
            aggregation_fn: Optional custom aggregation function

        Returns:
            Aggregated result of type T
        """
        logger.info(
            f"{self.agent_name}: Processing {len(content_chunks)} chunks with async batch processing"
        )

        if not content_chunks:
            raise ValueError("No content chunks provided for batch processing")

        # Process chunks sequentially (sync for threads pool)
        chunk_results = []
        for i, chunk_content in enumerate(content_chunks):
            chunk_metadata = {
                **(metadata or {}),
                "chunk_number": i + 1,
                "total_chunks": len(content_chunks),
                "chunk_size": len(chunk_content),
            }

            logger.info(f"Processing chunk {i + 1}/{len(content_chunks)}")

            messages = [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": chunk_content},
            ]

            result = self.invoke_openrouter(
                llm=self.config.llm,
                messages=messages,
                metadata=chunk_metadata,
                structured_output_schema=structured_output_schema,
            )

            chunk_results.append(result)
            logger.info(f"Chunk {i + 1}/{len(content_chunks)} processed successfully")

        # Aggregate results
        if len(chunk_results) == 1:
            return chunk_results[0]

        if aggregation_fn:
            return aggregation_fn(chunk_results)

        # Default aggregation - return first result (can be overridden in subclasses)
        logger.warning(
            "No aggregation function provided, returning first result. "
            "Consider implementing custom aggregation."
        )
        return chunk_results[0]

    def chunk_files(
        self, files: list[dict], max_chunk_size: int | None = None
    ) -> list[dict]:
        """
        Create smart chunks based on file boundaries and size limits.

        Args:
            files: List of file dictionaries with 'path' and 'content'
            max_chunk_size: Maximum size per chunk (defaults to config)

        Returns:
            List of chunk dictionaries with content and metadata
        """
        if max_chunk_size is None:
            max_chunk_size = self.max_chunk_size

        chunks = []
        current_chunk_content = ""
        current_chunk_files = []
        current_size = 0

        # Sort files by size (process smaller files first)
        sorted_files = sorted(files, key=lambda f: len(f.get("content", "")))

        for file in sorted_files:
            file_content = file.get("content", "")
            if not file_content.strip():
                continue

            file_section = f"\n\n=== {file['path']} ===\n{file_content}"
            file_size = len(file_section)

            # If adding this file would exceed chunk size, finalize current chunk
            if current_size + file_size > max_chunk_size and current_chunk_content:
                chunks.append(
                    {
                        "content": current_chunk_content,
                        "files": current_chunk_files.copy(),
                        "size": current_size,
                    }
                )
                current_chunk_content = ""
                current_chunk_files = []
                current_size = 0

            # If single file is too large, split it
            if file_size > max_chunk_size:
                # Process any accumulated content first
                if current_chunk_content:
                    chunks.append(
                        {
                            "content": current_chunk_content,
                            "files": current_chunk_files.copy(),
                            "size": current_size,
                        }
                    )
                    current_chunk_content = ""
                    current_chunk_files = []
                    current_size = 0

                # Split large file
                file_chunks = self._chunk_text_content(file_content, max_chunk_size)
                for j, file_chunk in enumerate(file_chunks):
                    chunk_content = f"\n\n=== {file['path']} (part {j + 1}/{len(file_chunks)}) ===\n{file_chunk}"
                    chunks.append(
                        {
                            "content": chunk_content,
                            "files": [file],
                            "size": len(chunk_content),
                        }
                    )
            else:
                # Add file to current chunk
                current_chunk_content += file_section
                current_chunk_files.append(file)
                current_size += file_size

        # Add final chunk if any content remains
        if current_chunk_content:
            chunks.append(
                {
                    "content": current_chunk_content,
                    "files": current_chunk_files,
                    "size": current_size,
                }
            )

        logger.info(f"Created {len(chunks)} chunks from {len(files)} files")
        return chunks

    def _chunk_text_content(self, content: str, max_size: int) -> list[str]:
        """
        Split text content into chunks that fit within size limit.

        Args:
            content: Content to chunk
            max_size: Maximum size per chunk

        Returns:
            List of content chunks
        """
        if len(content) <= max_size:
            return [content]

        chunks = []
        current_chunk = ""

        # Split by lines for better chunk boundaries
        lines = content.split("\n")

        for line in lines:
            line_with_newline = line + "\n"

            # If adding this line would exceed chunk size
            if len(current_chunk) + len(line_with_newline) > max_size:
                if current_chunk:
                    chunks.append(current_chunk.rstrip())
                    current_chunk = ""

                # If single line is too long, split it
                if len(line_with_newline) > max_size:
                    for i in range(0, len(line), max_size):
                        chunks.append(line[i : i + max_size])
                else:
                    current_chunk = line_with_newline
            else:
                current_chunk += line_with_newline

        # Add final chunk
        if current_chunk:
            chunks.append(current_chunk.rstrip())

        return chunks

    def aggregate_by_merging_lists(self, results: list[BaseModel]) -> BaseModel:
        """
        Aggregate results by merging list fields and summing numeric fields.

        Args:
            results: List of Pydantic model instances

        Returns:
            Single aggregated model instance
        """
        if not results:
            raise ValueError("No results to aggregate")

        if len(results) == 1:
            return results[0]

        # Get model class from first result
        model_class = type(results[0])

        # Start with first result as base
        aggregated_data = results[0].model_dump()

        # Merge remaining results
        for result in results[1:]:
            result_data = result.model_dump()

            for key, value in result_data.items():
                if isinstance(value, list):
                    # Extend lists
                    if key in aggregated_data:
                        aggregated_data[key].extend(value)
                    else:
                        aggregated_data[key] = value
                elif isinstance(value, (int, float)):
                    # Sum numeric values
                    if key in aggregated_data:
                        aggregated_data[key] += value
                    else:
                        aggregated_data[key] = value
                elif isinstance(value, dict):
                    # Merge dicts recursively (simple merge)
                    if key in aggregated_data and isinstance(
                        aggregated_data[key], dict
                    ):
                        aggregated_data[key].update(value)
                    else:
                        aggregated_data[key] = value
                # For other types, keep the value from the first result

        return model_class.model_validate(aggregated_data)

    def aggregate_by_averaging_scores(self, results: list[BaseModel]) -> BaseModel:
        """
        Aggregate results by averaging score fields and merging lists.

        Useful for quality assessment or grading aggregation.

        Args:
            results: List of Pydantic model instances with score fields

        Returns:
            Single aggregated model instance
        """
        if not results:
            raise ValueError("No results to aggregate")

        if len(results) == 1:
            return results[0]

        model_class = type(results[0])
        aggregated_data = {}

        # Get all fields from first result
        base_data = results[0].model_dump()

        for field_name, field_value in base_data.items():
            # Check if this looks like a score field (dict with 'score' key)
            if isinstance(field_value, dict) and "score" in field_value:
                scores = []
                all_evidence = []
                all_issues = []
                all_recommendations = []

                for result in results:
                    result_data = result.model_dump()
                    if field_name in result_data:
                        field_data = result_data[field_name]
                        if "score" in field_data:
                            scores.append(field_data["score"])
                        all_evidence.extend(field_data.get("evidence", []))
                        all_issues.extend(field_data.get("issues", []))
                        all_recommendations.extend(
                            field_data.get("recommendations", [])
                        )

                aggregated_data[field_name] = {
                    "score": round(sum(scores) / len(scores)) if scores else 1,
                    "evidence": list(set(all_evidence)),  # Remove duplicates
                    "issues": list(set(all_issues)),
                    "recommendations": list(set(all_recommendations)),
                }
            elif isinstance(field_value, list):
                # Merge lists from all results
                merged_list = []
                for result in results:
                    result_data = result.model_dump()
                    if field_name in result_data:
                        merged_list.extend(result_data[field_name])
                aggregated_data[field_name] = merged_list
            else:
                # Use value from first result
                aggregated_data[field_name] = field_value

        return model_class.model_validate(aggregated_data)
