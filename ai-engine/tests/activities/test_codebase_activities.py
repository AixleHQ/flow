"""Tests for codebase activities."""

import pytest

from tests.test_helpers import (
    get_test_files,
    get_all_test_models,
    correct_naming,
    check_keys,
    use_cassette,
)
from models.activity_types.codebase_analyze_file import (
    CodebaseAnalyzeFileInput,
    CodebaseAnalyzeFileOutput,
)
from models.activity_types.codebase_index_file_in_vector_db import (
    CodebaseIndexFileInVectorDbInput,
)
from models.activity_types.codebase_generate_report_section import (
    CodebaseGenerateReportSectionInput,
    CodebaseGenerateReportSectionOutput,
)
from services import DumpService, PayloadService
from constants import get_section_types
import uuid
from app.temporal.activities import (
    codebase_analyze_file,
    codebase_generate_report_section,
    codebase_index_file_in_vector_db,
)

models = get_all_test_models()
files = get_test_files()


@pytest.mark.usefixtures("mock_redis")
class TestCodebaseAnalyzeFileActivity:
    def create_codebase_analyze_file_input(self, file, model):
        # Store file data in payload service
        file_data_key = PayloadService.store_json(file, f"test_file_{file['id']}")

        return CodebaseAnalyzeFileInput(
            file_data_key=file_data_key,
            file_id=file["id"],
            codebase_indexing_model=model,
        ).model_dump()

    @pytest.mark.parametrize(
        "file, model",
        [(file, model) for file in files for model in models],
        ids=correct_naming,
    )
    def test_codebase_analyze_file(self, file, model):
        with use_cassette("codebase_analyze_file", file["name"], model):
            input_dict = self.create_codebase_analyze_file_input(file, model)
            output_key = codebase_analyze_file(input_dict)

            # Load output from payload service
            output_dict = PayloadService.load_json(output_key)

            assert check_keys(output_dict, CodebaseAnalyzeFileOutput)
            output = CodebaseAnalyzeFileOutput(**output_dict)

            # Verify output structure
            assert output.file_name == file["name"]
            assert output.file_path == file["path"]
            assert output.file_size == file["size"]


class TestCodebaseIndexFileInVectorDbActivity:
    def codebase_analyze_file_from_dump(self, file_name, model):
        dict = DumpService.load("codebase_analyze_file", file_name, model.identifier)
        return CodebaseAnalyzeFileOutput(**dict)

    def create_codebase_index_file_in_vector_db_input(self, file, model):
        # Get analysis from dump
        analysis = self.codebase_analyze_file_from_dump(file["name"], model)

        # Store file data
        file_data_key = PayloadService.store_json(file, f"test_file_{file['id']}")

        # Store analysis
        analysis_key = PayloadService.store_json(
            analysis.model_dump(), f"test_analysis_{file['id']}"
        )

        return CodebaseIndexFileInVectorDbInput(
            file_id=file["id"],
            file_data_key=file_data_key,
            analysis_key=analysis_key,
            workspace_id=1,
            asset_id=1,
            codebase_id=1,
        ).model_dump()

    @pytest.mark.parametrize(
        "file, model",
        [(file, model) for file in files for model in models],
        ids=correct_naming,
    )
    def test_codebase_index_file_in_vector_db(self, file, model, mocker):
        mocker.patch(
            "uuid.uuid4",
            return_value=uuid.UUID(f"0000{file['id']}000-0000-0000-0000-000000000000"),
        )
        with use_cassette(
            "codebase_index_file_in_vector_db", file["name"], model
        ):
            input_dict = self.create_codebase_index_file_in_vector_db_input(file, model)
            document_id = codebase_index_file_in_vector_db(input_dict)

            # Verify we got a document ID back
            assert document_id is not None
            assert isinstance(document_id, str)
            assert len(document_id) > 0


class TestCodebaseGenerateReportSectionActivity:
    def create_files_data(self, model):
        files_data = []
        for file in files:
            files_data.append(
                {
                    "id": file["id"],
                    "name": file["name"],
                    "path": file["path"],
                    "content": file["content"],
                    "size": file["size"],
                    "metadata": DumpService.load(
                        "codebase_analyze_file", file["name"], model.identifier
                    ),
                }
            )
        return files_data

    def create_codebase_generate_report_section_input(self, section, model):
        files_data = self.create_files_data(model)

        # Store files data in payload service
        files_data_key = PayloadService.store_json(
            files_data, f"test_section_{section.order}"
        )

        return CodebaseGenerateReportSectionInput(
            prompt_name=section.prompt_name,
            categories=section.categories,
            codebase_reporting_model=model,
            section_id=section.order,
            files_data_key=files_data_key,
        ).model_dump()

    @pytest.mark.parametrize(
        "section, model",
        [(section, model) for section in get_section_types() for model in models],
        ids=correct_naming,
    )
    def test_codebase_generate_report_section(self, section, model):
        input_dict = self.create_codebase_generate_report_section_input(section, model)

        with use_cassette(
            "codebase_generate_report_section", section.title, model
        ):
            output_key = codebase_generate_report_section(input_dict)

            # Load output from payload service
            output_dict = PayloadService.load_json(output_key)

            output = CodebaseGenerateReportSectionOutput(**output_dict)
            assert output.description is not None
            assert len(output.description) > 0
            assert check_keys(output_dict, CodebaseGenerateReportSectionOutput)
