"""Tests for document activities."""

import pytest

from tests.test_helpers import (
    get_test_document,
    get_all_test_models,
    correct_naming,
    check_keys,
    use_cassette,
)
from models.activity_types.document_analyze import (
    DocumentAnalyzeInput,
    DocumentAnalyzeOutput,
)
from models.activity_types.document_index_in_vector_db import (
    DocumentIndexInVectorDbInput,
)
from utils import dict_except
from services import DumpService, PayloadService
import uuid
from app.temporal.activities import (
    document_analyze_file,
    document_index_in_vector_db,
)

models = get_all_test_models()
document = get_test_document()


@pytest.mark.usefixtures("mock_redis")
class TestDocumentAnalyzeFileActivity:
    def create_document_analyze_input(self, document, model):
        document_content_key = PayloadService.store_bytes(
            document["content"], f"test_document_content_{document['id']}"
        )
        document["content_key"] = document_content_key
        document_data_key = PayloadService.store_json(
            dict_except(document, ["content"]), f"test_document_{document['id']}"
        )

        return DocumentAnalyzeInput(
            document_data_key=document_data_key,
            asset_id=document["id"],
            document_analysis_model=model,
        ).model_dump()

    @pytest.mark.parametrize("model", [(model) for model in models], ids=correct_naming)
    def test_document_analyze_file(self, model):
        with use_cassette("document_analyze_file", document["name"], model):
            input_dict = self.create_document_analyze_input(document, model)
            output_key = document_analyze_file(input_dict)

            # Load output from payload service
            output_dict = PayloadService.load_json(output_key)

            assert check_keys(output_dict, DocumentAnalyzeOutput)
            output = DocumentAnalyzeOutput(**output_dict)

            # Verify output structure
            assert output.file_name == document["name"]
            assert output.file_path == document["path"]
            assert output.file_size == document["size"]
            assert len(output.summary) > 0
            assert len(output.key_points) > 0
            assert len(output.document_type) > 0
            assert 1 <= output.content_quality <= 10
            assert 1 <= output.business_value <= 10
            assert 1 <= output.technical_value <= 10


@pytest.mark.usefixtures("mock_redis")
class TestDocumentIndexInVectorDbActivity:
    def document_analyze_from_dump(self, file_name, model):
        dict = DumpService.load("document_analysis", file_name, model.identifier)
        return DocumentAnalyzeOutput(**dict)

    def create_document_index_in_vector_db_input(self, document, model):
        analysis = self.document_analyze_from_dump(document["name"], model)
        analysis_key = PayloadService.store_json(
            analysis.model_dump(), f"test_analysis_{document['id']}"
        )

        return DocumentIndexInVectorDbInput(
            asset_id=document["id"],
            workspace_id=1,
            analysis_key=analysis_key,
        ).model_dump()

    @pytest.mark.parametrize("model", [(model) for model in models], ids=correct_naming)
    def test_document_index_in_vector_db(self, model, mocker):
        mocker.patch(
            "uuid.uuid4",
            return_value=uuid.UUID(
                f"0000{document['id']}000-0000-0000-0000-000000000000"
            ),
        )
        with use_cassette("document_index_in_vector_db", document["name"], model):
            input_dict = self.create_document_index_in_vector_db_input(document, model)
            document_id = document_index_in_vector_db(input_dict)

            # Verify we got a document ID back
            assert document_id is not None
            assert isinstance(document_id, str)
            assert len(document_id) > 0
