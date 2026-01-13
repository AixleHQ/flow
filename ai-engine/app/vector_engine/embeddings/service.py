from typing import cast

import tiktoken

from core.logging import logger
from openai import OpenAI

from config import settings


MAX_TOKENS_PER_REQUEST = 300_000
SAFETY_MARGIN_RATIO = 0.05
MIN_SAFETY_MARGIN = 1_000
MAX_ITEMS_PER_BATCH = 1000


class EmbeddingService:
    """Service for generating text embeddings using OpenAI (synchronous only)."""

    def __init__(
        self,
        openai_client: OpenAI | None = None,
    ) -> None:
        # Use OpenAI directly for embeddings (OpenRouter doesn't support embedding models)
        api_key = settings.openai.api_key
        if not api_key:
            raise ValueError("OpenAI API key is required for embedding operations")

        self.openai_client = openai_client or OpenAI(
            api_key=api_key,
            # Use OpenAI's official API endpoint for embeddings
        )

        # Modern embedding models with their dimensions
        self.embedding_models = {
            "text-embedding-3-small": 1536,
            "text-embedding-3-large": 3072,
            "text-embedding-ada-002": 1536,  # Legacy support
        }

        # Default to the most modern model
        self.default_model = "text-embedding-3-small"
        self.default_dimension = self.embedding_models[self.default_model]
        self.request_token_limits = {
            "text-embedding-3-small": MAX_TOKENS_PER_REQUEST,
            "text-embedding-3-large": MAX_TOKENS_PER_REQUEST,
            "text-embedding-ada-002": 8_192,
        }
        self._tokenizers: dict[str, tiktoken.Encoding] = {}

    def generate_embeddings_universal(
        self,
        texts: str | list[str],
        model: str = "text-embedding-3-small",
    ) -> list[float] | list[list[float]]:
        """Universal method for generating embeddings synchronously.

        Handles both single and batch operations.
        Uses text-embedding-3-small by default for best performance/cost ratio.
        """
        if isinstance(texts, str):
            texts = [texts]
            single_text = True
        else:
            single_text = False

        if not texts:
            return []

        # Validate model
        if model not in self.embedding_models:
            raise ValueError(
                f"Unsupported embedding model '{model}'. "
                f"Supported models: {list(self.embedding_models.keys())}"
            )

        # Preprocess texts for better embedding quality
        processed_texts = [self._preprocess_text(text) for text in texts]

        # Filter out empty texts
        valid_texts = [text for text in processed_texts if text.strip()]
        if not valid_texts:
            raise ValueError("No valid texts to embed after preprocessing")

        response = self.openai_client.embeddings.create(
            model=model,
            input=valid_texts,
            encoding_format="float",  # Explicit format for consistency
        )

        embeddings = [item.embedding for item in response.data]

        # Validate embedding dimensions
        expected_dimension = self.embedding_models[model]
        if embeddings:
            first_embedding_length = len(embeddings[0])
            last_embedding_length = len(embeddings[-1])
            if (
                first_embedding_length != expected_dimension
                or last_embedding_length != expected_dimension
            ):
                raise ValueError(
                    f"Embedding dimension mismatch expected {expected_dimension}, "
                    f"got {first_embedding_length} and {last_embedding_length}."
                )

        embedding_result = embeddings[0] if single_text else embeddings
        logger.info(f"Number of embeddings generated: {len(embeddings)}.")
        return embedding_result

    def _preprocess_text(self, text: str) -> str:
        """Preprocess text for better embedding quality."""
        if not text:
            return ""

        # Remove excessive whitespace
        text = " ".join(text.split())

        # Truncate if too long (embedding models have input limits)
        # Use conservative estimate: 3 chars per token instead of 4 for safety
        max_tokens = 7500  # Conservative limit for text-embedding-3-small (8192 max)
        estimated_max_chars = max_tokens * 3  # Conservative: 3 chars per token

        if len(text) > estimated_max_chars:
            text = text[:estimated_max_chars]
            logger.warning(
                f"Text truncated to {estimated_max_chars} characters (~{max_tokens} tokens) for embedding"
            )

        return text.strip()

    def generate_embeddings(
        self, texts: list[str], model: str = "text-embedding-3-small"
    ) -> list[list[float]]:
        """Generate embeddings for multiple texts synchronously."""
        result = self.generate_embeddings_universal(texts, model)
        return cast("list[list[float]]", result)

    def get_embedding(
        self, text: str, model: str = "text-embedding-3-small"
    ) -> list[float]:
        """Get embedding for text using modern default model."""
        if not text or not text.strip():
            raise ValueError("Empty text provided for embedding")

        result = self.generate_embeddings_universal(text, model)
        return cast("list[float]", result)

    def generate_embeddings_batch(
        self,
        texts: list[str],
        model: str = "text-embedding-3-small",
        max_batch_size: int | None = None,
    ) -> list[list[float]]:
        if not texts:
            return []

        from concurrent.futures import ThreadPoolExecutor, as_completed

        max_items = max_batch_size or MAX_ITEMS_PER_BATCH
        max_tokens = self._get_request_token_budget(model)
        token_safe_batches = self._build_token_safe_batches(
            texts=texts,
            model=model,
            max_items=max_items,
            max_tokens=max_tokens,
        )

        if len(token_safe_batches) == 1:
            batch_texts = token_safe_batches[0]
            result = self.generate_embeddings_universal(batch_texts, model)
            return cast("list[list[float]]", result)

        max_concurrent = settings.concurrency.embedding_generation
        logger.info(
            f"🚀 Processing {len(texts)} texts across {len(token_safe_batches)} batches "
            f"(max_concurrent: {max_concurrent}, max_items_per_batch: {max_items}, "
            f"token_budget: {max_tokens})"
        )

        batch_results = {}
        with ThreadPoolExecutor(max_workers=max_concurrent) as executor:
            future_to_index = {}
            for batch_idx, batch_texts in enumerate(token_safe_batches):
                future = executor.submit(
                    self.generate_embeddings_universal, batch_texts, model
                )
                future_to_index[future] = batch_idx

            for future in as_completed(future_to_index):
                batch_idx = future_to_index[future]
                batch_embeddings = future.result()
                batch_results[batch_idx] = batch_embeddings

        all_embeddings = []
        for idx in sorted(batch_results.keys()):
            all_embeddings.extend(cast("list[list[float]]", batch_results[idx]))

        logger.info(
            f"✅ Completed {len(token_safe_batches)} batches, generated {len(all_embeddings)} embeddings"
        )
        return all_embeddings

    def _get_request_token_budget(self, model: str) -> int:
        limit = self.request_token_limits.get(model, MAX_TOKENS_PER_REQUEST)
        safety_margin = max(int(limit * SAFETY_MARGIN_RATIO), MIN_SAFETY_MARGIN)
        if safety_margin >= limit:
            return max(1, limit // 2)
        return limit - safety_margin

    def _build_token_safe_batches(
        self,
        texts: list[str],
        model: str,
        max_items: int,
        max_tokens: int,
    ) -> list[list[str]]:
        tokenizer = self._get_tokenizer(model)
        batches: list[list[str]] = []
        current_batch: list[str] = []
        current_tokens = 0

        for text in texts:
            token_count = len(tokenizer.encode(text, disallowed_special=()))

            exceeds_items = len(current_batch) >= max_items
            exceeds_tokens = current_tokens + token_count > max_tokens

            if current_batch and (exceeds_items or exceeds_tokens):
                batches.append(current_batch)
                current_batch = []
                current_tokens = 0

            current_batch.append(text)
            current_tokens += token_count

        if current_batch:
            batches.append(current_batch)

        return batches

    def _get_tokenizer(self, model: str) -> tiktoken.Encoding:
        if model not in self._tokenizers:
            try:
                self._tokenizers[model] = tiktoken.encoding_for_model(model)
            except KeyError:
                logger.warning(
                    "Tokenizer for model %s not found, falling back to cl100k_base",
                    model,
                )
                self._tokenizers[model] = tiktoken.get_encoding("cl100k_base")
        return self._tokenizers[model]

    def get_model_dimension(self, model: str = "text-embedding-3-small") -> int:
        """Get the dimension for a specific embedding model."""
        return self.embedding_models.get(model, self.default_dimension)

    def validate_embedding(
        self, embedding: list[float], model: str = "text-embedding-3-small"
    ) -> bool:
        """Validate that embedding has correct dimension for model."""
        if not embedding:
            return False

        expected_dimension = self.embedding_models.get(model, self.default_dimension)
        actual_dimension = len(embedding)

        if actual_dimension != expected_dimension:
            logger.warning(
                f"Embedding dimension mismatch: expected {expected_dimension}, got {actual_dimension}"
            )
            return False

        return True

    def get_available_models(self) -> list[str]:
        """Get list of available embedding models."""
        return list(self.embedding_models.keys())

    def is_model_supported(self, model: str) -> bool:
        """Check if embedding model is supported."""
        return model in self.embedding_models
