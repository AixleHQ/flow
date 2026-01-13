import threading

import pytest

from app.vector_engine.embeddings.service import EmbeddingService


class DummyEmbeddings:
    def create(self, *args, **kwargs):
        raise AssertionError("Embedding API should not be invoked in unit tests")


class DummyOpenAI:
    def __init__(self) -> None:
        self.embeddings = DummyEmbeddings()


class PerTextTokenizer:
    def __init__(self, token_map: dict[str, int]) -> None:
        self.token_map = token_map

    def encode(self, text: str, disallowed_special: tuple[str, ...] = ()) -> list[int]:
        return [0] * self.token_map[text]


@pytest.fixture
def embedding_service(monkeypatch: pytest.MonkeyPatch) -> EmbeddingService:
    from app.vector_engine.embeddings import service as service_module

    monkeypatch.setenv("OPENAI_API_KEY", "test-api-key")
    monkeypatch.setattr(
        service_module.settings.openai,
        "api_key",
        "test-api-key",
        raising=False,
    )
    monkeypatch.setattr(
        service_module.settings.concurrency,
        "embedding_generation",
        1,
        raising=False,
    )
    return service_module.EmbeddingService(openai_client=DummyOpenAI())


def test_build_batches_respects_token_limit(
    embedding_service: EmbeddingService, monkeypatch: pytest.MonkeyPatch
) -> None:
    texts = ["short", "medium", "long"]
    token_map = {"short": 50, "medium": 120, "long": 90}
    tokenizer = PerTextTokenizer(token_map)
    monkeypatch.setattr(embedding_service, "_get_tokenizer", lambda model: tokenizer)

    batches = embedding_service._build_token_safe_batches(
        texts=texts,
        model="text-embedding-3-small",
        max_items=3,
        max_tokens=220,
    )

    assert len(batches) == 2
    assert batches[0] == ["short", "medium"]
    assert batches[1] == ["long"]


def test_build_batches_respects_item_limit(
    embedding_service: EmbeddingService, monkeypatch: pytest.MonkeyPatch
) -> None:
    texts = ["first", "second", "third"]
    token_map = {"first": 10, "second": 10, "third": 10}
    tokenizer = PerTextTokenizer(token_map)
    monkeypatch.setattr(embedding_service, "_get_tokenizer", lambda model: tokenizer)

    batches = embedding_service._build_token_safe_batches(
        texts=texts,
        model="text-embedding-3-small",
        max_items=2,
        max_tokens=1_000,
    )

    assert len(batches) == 2
    assert batches[0] == ["first", "second"]
    assert batches[1] == ["third"]


def test_generate_embeddings_batch_uses_token_safe_batches(
    embedding_service: EmbeddingService, monkeypatch: pytest.MonkeyPatch
) -> None:
    texts = ["alpha", "beta", "gamma"]
    expected_batches = [
        ["alpha", "beta"],
        ["gamma"],
    ]

    def fake_build_token_safe_batches(
        *,
        texts: list[str],
        model: str,
        max_items: int,
        max_tokens: int,
    ) -> list[list[str]]:
        assert texts == ["alpha", "beta", "gamma"]
        assert max_items == 2000
        assert max_tokens == embedding_service._get_request_token_budget(model)
        return expected_batches

    lock = threading.Lock()
    call_order: list[list[str]] = []

    def fake_generate(batch_texts: list[str], model: str) -> list[list[float]]:
        with lock:
            call_order.append(list(batch_texts))
        return [[float(len(text))] for text in batch_texts]

    monkeypatch.setattr(
        embedding_service,
        "_build_token_safe_batches",
        fake_build_token_safe_batches,
    )
    monkeypatch.setattr(
        embedding_service,
        "generate_embeddings_universal",
        fake_generate,
    )

    embeddings = embedding_service.generate_embeddings_batch(
        texts=texts,
        model="text-embedding-3-small",
        max_batch_size=2000,
    )

    assert call_order == [["alpha", "beta"], ["gamma"]]
    assert embeddings == [[5.0], [4.0], [5.0]]
