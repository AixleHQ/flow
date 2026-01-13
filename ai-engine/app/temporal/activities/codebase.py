"""CodeBase processing activities - clean interface using services."""

from temporalio import activity

from services.codebase import (
    FileAnalysisService,
    CodeReportSectionService,
    VectorIndexingService,
)
from models.activity_types.codebase_analyze_file import CodebaseAnalyzeFileInput
from models.activity_types.codebase_index_file_in_vector_db import (
    CodebaseIndexFileInVectorDbInput,
)
from models.activity_types.codebase_generate_report_section import (
    CodebaseGenerateReportSectionInput,
)


@activity.defn
def codebase_analyze_file(input_dict: dict) -> dict:
    input = CodebaseAnalyzeFileInput(**input_dict)
    activity.logger.info(f"Starting to analyze file {input.file_id}")

    output_key = FileAnalysisService.analyze_file(input)
    activity.logger.info(f"Analyzed file {input.file_id}")

    return output_key


@activity.defn
def codebase_index_file_in_vector_db(input_dict: dict) -> dict:
    input = CodebaseIndexFileInVectorDbInput(**input_dict)
    activity.logger.info(f"Starting to index file {input.file_id}")

    output_key = VectorIndexingService.index_file(input)
    activity.logger.info(f"Indexed file {input.file_id}")

    return output_key


@activity.defn
def codebase_generate_report_section(input_dict: dict) -> dict:
    input = CodebaseGenerateReportSectionInput(**input_dict)
    activity.logger.info(f"Input: {input.model_dump()}")
    activity.logger.info(f"Generating section '{input.prompt_name}'")

    output_key = CodeReportSectionService.generate_section(input)
    activity.logger.info(f"Generated section '{input.prompt_name}'")

    return output_key
