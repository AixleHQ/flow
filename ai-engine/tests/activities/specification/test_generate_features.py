import pytest
from pydantic import ValidationError
from typing import Any

from tests.test_helpers import (
    get_all_test_models,
    correct_naming,
    use_cassette,
    mock_rag_retriever,
)
from tests.test_base import TestBase
from temporal.wrap_error import NonRetryableError
from agents.specification.feature_extraction_agent import FeatureExtractionResult
from agents.common.rag import NoDocumentsFoundError
from app.temporal.activities import generate_features
from models.llm import ModelDefinition

TEST_VERSION_ID = 1
TEST_DOMAIN_ID = 1001
TEST_DOMAIN_NAME = "Test Domain Name"
UNEXPECTED_RETURN_OBJECT = {"invalid_field": "invalid_value"}
NON_EXISTENT_KEY = "temporal:nonexistent_key:abc123"

models = get_all_test_models()


class TestGenerateFeaturesActivity(TestBase):
    def _create_activity_input(
        self,
        model: ModelDefinition,
        version_id: int | None = None,
        domain_id: int | None = None,
        domain_name: str | None = None,
        domain_description: str | None = None,
    ) -> dict[str, Any]:
        version_id = version_id or TEST_VERSION_ID
        domain_id = domain_id or TEST_DOMAIN_ID

        ruby_obj = self.ruby_client.domain_context.create(
            version_id=version_id,
            domain_id=domain_id,
            domain_name=domain_name,
            domain_description=domain_description,
        )
        ruby_obj_key = self.payload_service.store_obj(
            ruby_obj, f"feature_context_v{version_id}_d{domain_id}"
        )

        return {
            "domain_context_payload_key": ruby_obj_key,
            "feature_extraction_model": model,
        }

    def _mock_rag_retriever(
        self, mocker: Any, domain_name: str, domain_description: str
    ) -> None:
        mock_rag_retriever(mocker, domain_name, domain_description)

    @pytest.mark.parametrize(
        "model",
        [(model) for model in models],
        ids=correct_naming,
    )
    @pytest.mark.vcr
    def test_generate_features_with_vcr(self, model, mocker):
        domain_name = "User Authentication"
        domain_description = "Manages user accounts, authentication, authorization, and session management"

        self._mock_rag_retriever(mocker, domain_name, domain_description)
        activity_input = self._create_activity_input(
            model, domain_name=domain_name, domain_description=domain_description
        )

        with use_cassette("generate_features", model):
            activity_result = generate_features(activity_input)
        assert activity_result is not None

        stored_result = self.payload_service.load(activity_result)
        assert isinstance(stored_result, dict)
        assert "domain_id" in stored_result
        assert "features" in stored_result
        assert isinstance(stored_result["features"], list)

    def test_generate_features_full_flow(self, mocker):
        activity_input = self._create_activity_input(
            models[0], domain_id=TEST_DOMAIN_ID
        )
        fake_features = self.client.features.create_batch(3)
        fake_feature_result = FeatureExtractionResult(features=fake_features)

        mocker.patch(
            "agents.common.rag.tools.create_dynamic_retriever_tool",
            return_value=mocker.MagicMock(),
        )

        mock_agent = mocker.MagicMock()
        mock_agent.execute_task.return_value = fake_feature_result
        mocker.patch(
            "services.specification.feature_generation_service.TaskRAGAgent",
            return_value=mock_agent,
        )

        activity_result = generate_features(activity_input)

        stored_result = self.payload_service.load(activity_result)

        assert stored_result["domain_id"] == TEST_DOMAIN_ID
        assert len(stored_result["features"]) == len(fake_features)
        for i, feature in enumerate(stored_result["features"]):
            assert feature["name"] == fake_features[i].name
            assert feature["description"] == fake_features[i].description
            assert feature["justification"] == fake_features[i].justification

    def test_generate_features_missing_context_in_redis(self):
        activity_input = {
            "domain_context_payload_key": NON_EXISTENT_KEY,
            "feature_extraction_model": models[0],
        }

        with pytest.raises(NonRetryableError) as exc_info:
            generate_features(activity_input)

        assert "No context provided for feature generation" in str(exc_info.value)

    def test_generate_features_invalid_ruby_object(self):
        invalid_ruby_obj = {
            "version_id": TEST_VERSION_ID,
            "workspace_id": "invalid_workspace_id",
        }
        ruby_obj_key = self.payload_service.store_obj(
            invalid_ruby_obj, f"feature_context_{TEST_VERSION_ID}"
        )

        activity_input = {
            "domain_context_payload_key": ruby_obj_key,
            "feature_extraction_model": models[0],
        }

        with pytest.raises(ValidationError) as exc_info:
            generate_features(activity_input)

        errors = exc_info.value.errors()
        error_fields = {error["loc"][0] for error in errors}

        assert "asset_ids" in error_fields
        assert "domain_id" in error_fields
        assert "domain_name" in error_fields

    def test_generate_features_no_context_error(self, mocker):
        activity_input = self._create_activity_input(models[0])

        mocker.patch(
            "services.payload_service.PayloadService.load_object", return_value=None
        )

        with pytest.raises(NonRetryableError) as exc_info:
            generate_features(activity_input)

        assert "No context provided for feature generation" in str(exc_info.value)

    def test_generate_features_no_documents_found(self, mocker):
        activity_input = self._create_activity_input(models[0])

        mocker.patch(
            "agents.common.rag.tools.create_dynamic_retriever_tool",
            return_value=mocker.MagicMock(),
        )

        mock_agent = mocker.MagicMock()
        mock_agent.execute_task.side_effect = NoDocumentsFoundError(
            "No documents found"
        )
        mocker.patch(
            "services.specification.feature_generation_service.TaskRAGAgent",
            return_value=mock_agent,
        )

        activity_result = generate_features(activity_input)

        assert activity_result is None

    def test_generate_features_returns_none_when_empty(self, mocker):
        activity_input = self._create_activity_input(models[0])

        mock_agent = mocker.MagicMock()
        mock_agent.execute_task.return_value = FeatureExtractionResult(features=[])
        mocker.patch(
            "services.specification.feature_generation_service.TaskRAGAgent",
            return_value=mock_agent,
        )

        activity_result = generate_features(activity_input)

        assert activity_result is None

    def test_generate_features_task_rag_agent_called_correctly(self, mocker):
        activity_input = self._create_activity_input(
            models[0], domain_name=TEST_DOMAIN_NAME
        )
        fake_features = self.client.features.create_batch(2)
        fake_feature_result = FeatureExtractionResult(features=fake_features)

        mock_agent = mocker.MagicMock()
        mock_agent.execute_task.return_value = fake_feature_result
        mocker.patch(
            "services.specification.feature_generation_service.TaskRAGAgent",
            return_value=mock_agent,
        )
        mock_execute = mock_agent.execute_task

        generate_features(activity_input)

        mock_execute.assert_called_once()

        call_kwargs = mock_execute.call_args.kwargs
        context_params = call_kwargs.get("context_params", {})
        assert context_params["domain_name"] == TEST_DOMAIN_NAME
        assert "domain_description" in context_params

    def test_generate_features_structured_output_validation(self, mocker):
        activity_input = self._create_activity_input(models[0])

        mock_agent = mocker.MagicMock()
        mock_agent.execute_task.return_value = UNEXPECTED_RETURN_OBJECT
        mocker.patch(
            "services.specification.feature_generation_service.TaskRAGAgent",
            return_value=mock_agent,
        )

        with pytest.raises(ValueError) as exc_info:
            generate_features(activity_input)

        assert str(exc_info.value) == (
            f"Expected FeatureExtractionResult, got {type(UNEXPECTED_RETURN_OBJECT)}"
        )
