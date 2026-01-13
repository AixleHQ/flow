import os

# Must be set BEFORE any other imports that load settings
os.environ["ENVIRONMENT"] = "test"

import pytest
import fakeredis
from tests.fixtures.tokenizer import TokenizerStub
from app.vector_engine.embeddings import service as embedding_service_module

from tests.test_base import TestClient, RubyTestClient


@pytest.fixture
def mock_redis(mocker):
    mocker.patch("redis.from_url", return_value=fakeredis.FakeRedis())


@pytest.fixture
def test_client():
    return TestClient()


@pytest.fixture
def ruby_test_client():
    return RubyTestClient()


@pytest.fixture(scope="session")
def tokenizer_stub():
    return TokenizerStub()


@pytest.fixture(autouse=True)
def mock_tiktoken(monkeypatch, tokenizer_stub):
    monkeypatch.setattr(
        embedding_service_module.tiktoken,
        "encoding_for_model",
        lambda model: tokenizer_stub,
    )
    monkeypatch.setattr(
        embedding_service_module.tiktoken,
        "get_encoding",
        lambda name: tokenizer_stub,
    )
