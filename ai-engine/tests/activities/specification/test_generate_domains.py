import pytest
from pydantic import ValidationError
from typing import Any

from tests.test_helpers import get_all_test_models, correct_naming, use_cassette
from tests.test_base import TestBase
from temporal.wrap_error import NonRetryableError
from agents.specification.domain_analysis_agent import DomainExtractionResult
from vector_engine.core.models import VectorSearchResult
from app.temporal.activities import generate_domains
from models.llm import ModelDefinition

models = [model for model in get_all_test_models() if "openai" not in model]

TEST_VERSION_ID = 1


class TestGenerateDomainsActivity(TestBase):
    def _create_activity_input(
        self, version_id: int, model: ModelDefinition
    ) -> dict[str, Any]:
        ruby_obj = self.ruby_client.specification_context.create(version_id=version_id)
        ruby_obj_key = self.payload_service.store_obj(
            ruby_obj, f"domain_context_{version_id}"
        )

        return {
            "domain_context_payload_key": ruby_obj_key,
            "domain_analysis_model": model,
        }

    def _mock_vector_search(self, mocker: Any) -> None:
        mocker.patch(
            "services.specification.domain_generation.service.VectorSearchEngine.search_by_text",
            return_value=[],
        )

    def _mock_clustering_service(self, mocker: Any) -> Any:
        mock_clustering = mocker.patch(
            "services.specification.domain_generation.service.FunctionalGroupClusteringService"
        )
        mock_clustering_instance = mock_clustering.return_value
        mock_embedding_service = mocker.patch.object(
            mock_clustering_instance, "_embedding_service"
        )
        mock_embedding_service.generate_embeddings.return_value = [
            [0.1, 0.2, 0.3],
            [0.4, 0.5, 0.6],
        ]
        mock_cluster = self.client.domain_clusters.create(
            cluster_id=1, avg_confidence=0.8, status="main"
        )
        mock_clustering_instance.process_domain_clusters.return_value = [mock_cluster]
        return mock_clustering_instance

    @pytest.mark.parametrize("model", [(model) for model in models], ids=correct_naming)
    @pytest.mark.vcr
    def test_generate_domains_with_vcr(self, model, mocker):
        self._mock_vector_search(mocker)
        activity_input = self._create_activity_input(TEST_VERSION_ID, model)

        with use_cassette("generate_domains", model):
            test_result = generate_domains(activity_input)

        stored_domains = self.payload_service.load(test_result)

        assert isinstance(stored_domains, list)
        assert len(stored_domains) > 0

    def test_generate_domains_full_flow(self, mocker):
        self._mock_vector_search(mocker)
        self._mock_clustering_service(mocker)
        activity_input = self._create_activity_input(TEST_VERSION_ID, models[0])

        fake_domains = self.client.domains.create_batch(2)
        fake_domain_result = DomainExtractionResult(domains=fake_domains)

        mocker.patch(
            "services.specification.domain_generation.service.DomainAnalysisAgent.analyze_domain",
            return_value=fake_domain_result,
        )

        test_result = generate_domains(activity_input)

        stored_domains = self.payload_service.load(test_result)

        assert len(stored_domains) == len(fake_domains)
        for i, domain in enumerate(stored_domains):
            assert domain["name"] == fake_domains[i].name
            assert domain["description"] == fake_domains[i].description
            assert domain["justification"] == fake_domains[i].justification

    def test_generate_domains_missing_context_in_redis(self):
        activity_input = {
            "domain_context_payload_key": "temporal:nonexistent_key:abc123",
            "domain_analysis_model": models[0],
        }

        with pytest.raises(NonRetryableError):
            generate_domains(activity_input)

    def test_generate_domains_invalid_ruby_object(self):
        invalid_ruby_obj = {
            "version_id": TEST_VERSION_ID,
            "workspace_id": 1,
        }
        ruby_obj_key = self.payload_service.store_obj(
            invalid_ruby_obj, f"domain_context_{TEST_VERSION_ID}"
        )
        activity_input = {
            "domain_context_payload_key": ruby_obj_key,
            "domain_analysis_model": models[0],
        }

        with pytest.raises(ValidationError) as exc_info:
            generate_domains(activity_input)

        errors = exc_info.value.errors()
        error_fields = {error["loc"][0] for error in errors}

        assert "asset_ids" in error_fields
        assert "codebase_files_data" in error_fields
        assert "non_code_asset_ids" in error_fields

    def test_generate_domains_empty_content_error(self, mocker):
        ruby_obj = self.ruby_client.specification_context.create(
            version_id=TEST_VERSION_ID, codebase_files_data=[], non_code_asset_ids=[]
        )
        ruby_obj_key = self.payload_service.store_obj(
            ruby_obj, f"domain_context_{TEST_VERSION_ID}"
        )

        activity_input = {
            "domain_context_payload_key": ruby_obj_key,
            "domain_analysis_model": models[0],
        }

        with pytest.raises(NonRetryableError) as exc_info:
            generate_domains(activity_input)

        assert (
            "No specification or codebase content found for domain generation"
            in str(exc_info.value)
        )

    def test_generate_domains_no_domains_generated_error(self, mocker):
        self._mock_vector_search(mocker)
        self._mock_clustering_service(mocker)
        activity_input = self._create_activity_input(TEST_VERSION_ID, models[0])

        mock_agent = mocker.patch(
            "services.specification.domain_generation.service.DomainAnalysisAgent"
        )
        mock_agent.return_value.analyze_domain.return_value.domains = []

        with pytest.raises(NonRetryableError) as exc_info:
            generate_domains(activity_input)

        assert "No domains generated" in str(exc_info.value)

    def test_generate_domains_with_codebase_uses_clustering(self, mocker):
        activity_input = self._create_activity_input(TEST_VERSION_ID, models[0])

        fake_domains = self.client.domains.create_batch(2)
        fake_domain_result = DomainExtractionResult(domains=fake_domains)

        mock_clustering_service = mocker.patch(
            "services.specification.domain_generation.service.FunctionalGroupClusteringService"
        )
        mock_clustering_instance = mock_clustering_service.return_value

        mock_cluster = self.client.domain_clusters.create(
            cluster_id=1, avg_confidence=0.8, status="main"
        )
        mock_clustering_instance.process_domain_clusters.return_value = [mock_cluster]

        mock_agent = mocker.patch(
            "services.specification.domain_generation.service.DomainAnalysisAgent"
        )
        mock_agent.return_value.analyze_domain.return_value = fake_domain_result

        generate_domains(activity_input)

        assert mock_clustering_service.called
        assert mock_clustering_instance.process_domain_clusters.called

    def test_generate_domains_without_codebase_uses_vector_search(self, mocker):
        ruby_obj = self.ruby_client.specification_context.create(
            version_id=TEST_VERSION_ID,
            codebase_files_data=[],
            non_code_asset_ids=[1, 2, 3],
        )
        ruby_obj_key = self.payload_service.store_obj(
            ruby_obj, f"domain_context_{TEST_VERSION_ID}"
        )

        activity_input = {
            "domain_context_payload_key": ruby_obj_key,
            "domain_analysis_model": models[0],
        }

        fake_domains = self.client.domains.create_batch(1)
        fake_domain_result = DomainExtractionResult(domains=fake_domains)

        mock_vector_search = mocker.patch(
            "services.specification.domain_generation.service.VectorSearchEngine"
        )

        mock_search_result = VectorSearchResult(
            document_id="doc_1",
            chunk_id="chunk_1",
            content="Business requirements specification",
            score=0.9,
            workspace_id=1,
            asset_id=1,
            asset_type="document",
            content_type="text",
        )
        mock_vector_search.return_value.search_by_text.return_value = [
            mock_search_result
        ]

        mock_agent = mocker.patch(
            "services.specification.domain_generation.service.DomainAnalysisAgent"
        )
        mock_agent.return_value.analyze_domain.return_value = fake_domain_result

        generate_domains(activity_input)

        assert mock_vector_search.called
        assert mock_vector_search.return_value.search_by_text.called

    def test_generate_domains_vector_search_called_multiple_times(self, mocker):
        ruby_obj = self.ruby_client.specification_context.create(
            version_id=TEST_VERSION_ID,
            codebase_files_data=[],
            non_code_asset_ids=[1, 2, 3],
        )
        ruby_obj_key = self.payload_service.store_obj(
            ruby_obj, f"domain_context_{TEST_VERSION_ID}"
        )

        activity_input = {
            "domain_context_payload_key": ruby_obj_key,
            "domain_analysis_model": models[0],
        }

        mock_vector_search = mocker.patch(
            "services.specification.domain_generation.service.VectorSearchEngine"
        )
        mock_search_result = VectorSearchResult(
            document_id="doc_1",
            chunk_id="chunk_1",
            content="Test specification content",
            score=0.8,
            workspace_id=1,
            asset_id=1,
            asset_type="document",
            content_type="text",
        )
        mock_vector_search.return_value.search_by_text.return_value = [
            mock_search_result
        ]

        fake_domains = self.client.domains.create_batch(size=1)
        fake_domain_result = DomainExtractionResult(domains=fake_domains)
        mocker.patch(
            "services.specification.domain_generation.service.DomainAnalysisAgent.analyze_domain",
            return_value=fake_domain_result,
        )

        generate_domains(activity_input)

        assert mock_vector_search.return_value.search_by_text.call_count == 5

    def test_generate_domains_only_non_code_assets(self, mocker):
        ruby_obj = self.ruby_client.specification_context.create(
            version_id=TEST_VERSION_ID,
            codebase_files_data=[],
            non_code_asset_ids=[1, 2, 3],
        )
        ruby_obj_key = self.payload_service.store_obj(
            ruby_obj, f"domain_context_{TEST_VERSION_ID}"
        )

        activity_input = {
            "domain_context_payload_key": ruby_obj_key,
            "domain_analysis_model": models[0],
        }

        mock_search_result = VectorSearchResult(
            document_id="doc_2",
            chunk_id="chunk_2",
            content="Specification content from documents",
            score=0.9,
            workspace_id=1,
            asset_id=2,
            asset_type="document",
            content_type="text",
        )
        mocker.patch(
            "services.specification.domain_generation.service.VectorSearchEngine"
        ).return_value.search_by_text.return_value = [mock_search_result]

        fake_domains = self.client.domains.create_batch(1)
        fake_domain_result = DomainExtractionResult(domains=fake_domains)
        mocker.patch(
            "services.specification.domain_generation.service.DomainAnalysisAgent.analyze_domain",
            return_value=fake_domain_result,
        )

        test_result = generate_domains(activity_input)

        stored_domains = self.payload_service.load(test_result)
        assert len(stored_domains) == 1
