from typing import Any
import asyncio

from temporalio import workflow
from temporalio.exceptions import FailureError
from temporal.workflows.base import BaseWorkflow

from constants import Workflows
from temporal.workflows.helpers import execute_activity
from temporal.workflow_types.specification import (
    SpecificationContext,
    LLMModelsDict,
)

MIN_BL_FACTOR = 0.8


@workflow.defn(name=Workflows.specification_processing.name)
class SpecificationProcessingWorkflow(BaseWorkflow):
    @workflow.run
    async def run(self, specification_id: int) -> dict[str, Any]:
        workflow.logger.info(
            f"Starting specification processing: specification_id={specification_id}"
        )
        spec_data = None

        try:
            spec_data = await self._create_specification_version(specification_id)

            await asyncio.gather(
                *[
                    self.process_diagrams(spec_data),
                    self.process_entities(spec_data),
                ]
            )

            final_result = await self._finalize_specification(spec_data)

            workflow.logger.info("Specification processing completed successfully")
            return final_result

        except FailureError as error:
            workflow.logger.error(f"Specification processing failed: {error}")
            await self._fail_specification(
                specification_id=specification_id,
                version_id=spec_data["version_id"] if spec_data else None,
            )
            raise error

    async def _create_specification_version(
        self, specification_id: int
    ) -> SpecificationContext:
        spec_data: SpecificationContext = await execute_activity(
            Workflows.specification_processing.activities.specification_create_specification_version,
            {"specification_id": specification_id},
        )
        return spec_data

    async def process_entities(self, spec_data: SpecificationContext) -> None:
        models: LLMModelsDict = spec_data["models"]
        version_id = spec_data["version_id"]

        domain_ids = await self._generate_domains(
            version_id, models["domain_analysis_model"]
        )

        domain_tasks = [
            self._process_domain_tree(domain_id=domain_id, models=models)
            for domain_id in domain_ids
        ]

        await asyncio.gather(*domain_tasks)

    async def _generate_domains(
        self, version_id: int, domain_analysis_model: str
    ) -> list[int]:
        context_payload_key = await execute_activity(
            Workflows.specification_processing.activities.specification_prepare_domain_context,
            {"version_id": version_id, "min_bl_factor": MIN_BL_FACTOR},
        )

        generated_domains_key = await execute_activity(
            Workflows.specification_processing.activities.generate_domains,
            {
                "domain_context_payload_key": context_payload_key,
                "domain_analysis_model": domain_analysis_model,
            },
        )

        domain_ids = await execute_activity(
            Workflows.specification_processing.activities.specification_save_domains,
            {
                "version_id": version_id,
                "domains_payload_key": generated_domains_key,
            },
        )

        return domain_ids

    async def _process_domain_tree(self, domain_id: int, models: LLMModelsDict) -> None:
        feature_ids = await self._generate_features_for_domain(
            domain_id=domain_id,
            feature_extraction_model=models["feature_extraction_model"],
        )

        if not feature_ids:
            return

        feature_tasks = [
            self._process_feature_tree(feature_id=feature_id, models=models)
            for feature_id in feature_ids
        ]

        await asyncio.gather(*feature_tasks)

    async def _generate_features_for_domain(
        self, domain_id: int, feature_extraction_model: str
    ) -> list[int] | None:
        context_key = await execute_activity(
            Workflows.specification_processing.activities.specification_prepare_feature_context,
            domain_id,
        )

        generated_features_key = await execute_activity(
            Workflows.specification_processing.activities.generate_features,
            {
                "domain_context_payload_key": context_key,
                "feature_extraction_model": feature_extraction_model,
            },
        )

        if generated_features_key is None:
            return None

        feature_ids = await execute_activity(
            Workflows.specification_processing.activities.specification_save_features,
            generated_features_key,
        )

        return feature_ids

    async def _process_feature_tree(
        self, feature_id: int, models: LLMModelsDict
    ) -> None:
        user_story_ids = await self._generate_user_stories_for_feature(
            feature_id=feature_id, user_story_model=models["user_story_model"]
        )

        if not user_story_ids:
            return

        story_tasks = [
            self._generate_use_cases_for_user_story(
                user_story_id=story_id, use_case_model=models["use_case_model"]
            )
            for story_id in user_story_ids
        ]

        await asyncio.gather(*story_tasks)

    async def _generate_user_stories_for_feature(
        self, feature_id: int, user_story_model: str
    ) -> list[int] | None:
        context_key = await execute_activity(
            Workflows.specification_processing.activities.specification_prepare_user_story_context,
            feature_id,
        )

        generated_user_stories_key = await execute_activity(
            Workflows.specification_processing.activities.generate_user_stories,
            {
                "feature_context_payload_key": context_key,
                "user_story_extraction_model": user_story_model,
            },
        )

        if generated_user_stories_key is None:
            return None

        user_story_ids = await execute_activity(
            Workflows.specification_processing.activities.specification_save_user_stories,
            generated_user_stories_key,
        )
        return user_story_ids

    async def _generate_use_cases_for_user_story(
        self, user_story_id: int, use_case_model: str
    ) -> list[int] | None:
        context_key = await execute_activity(
            Workflows.specification_processing.activities.specification_prepare_use_case_context,
            user_story_id,
        )

        generated_use_cases_key = await execute_activity(
            Workflows.specification_processing.activities.generate_use_cases,
            {
                "user_story_context_payload_key": context_key,
                "use_case_extraction_model": use_case_model,
            },
        )

        if generated_use_cases_key is None:
            return None

        await execute_activity(
            Workflows.specification_processing.activities.specification_save_use_cases,
            generated_use_cases_key,
        )

    async def process_diagrams(
        self,
        spec_data: SpecificationContext,
    ) -> None:
        diagram_context_payload_key = await execute_activity(
            Workflows.specification_processing.activities.specification_prepare_diagram_context,
            {"version_id": spec_data["version_id"]},
        )

        diagram_tasks = [
            self._generate_erd_diagram_async(diagram_context_payload_key, spec_data),
            self._generate_dataflow_diagram_async(
                diagram_context_payload_key, spec_data
            ),
        ]

        await asyncio.gather(*diagram_tasks)

    async def _generate_erd_diagram_async(
        self, diagram_context_payload_key: str, spec_data: SpecificationContext
    ) -> None:
        erd_result_key = await execute_activity(
            Workflows.specification_processing.activities.generate_erd_diagram,
            {
                "diagram_context_payload_key": diagram_context_payload_key,
                "erd_model": spec_data["models"]["diagram_model"],
            },
        )

        if erd_result_key is None:
            return

        await execute_activity(
            Workflows.specification_processing.activities.specification_save_erd_diagram,
            {
                "version_id": spec_data["version_id"],
                "erd_diagram_payload_key": erd_result_key,
            },
        )

    async def _generate_dataflow_diagram_async(
        self, diagram_context_payload_key: str, spec_data: SpecificationContext
    ) -> None:
        dataflow_result_key = await execute_activity(
            Workflows.specification_processing.activities.generate_dataflow_diagram,
            {
                "diagram_context_payload_key": diagram_context_payload_key,
                "dataflow_model": spec_data["models"]["data_flow_model"],
            },
        )

        if dataflow_result_key is None:
            return

        await execute_activity(
            Workflows.specification_processing.activities.specification_save_dataflow_diagram,
            {
                "version_id": spec_data["version_id"],
                "dataflow_diagram_payload_key": dataflow_result_key,
            },
        )

    async def _finalize_specification(
        self,
        spec_data: SpecificationContext,
    ) -> dict[str, Any]:
        workflow.logger.info("Finalizing specification")

        finalized_result = await execute_activity(
            Workflows.specification_processing.activities.specification_finalize_specification,
            spec_data["version_id"],
        )

        return {
            "specification_id": spec_data["specification_id"],
            "version_id": spec_data["version_id"],
            "workspace_id": spec_data["workspace_id"],
            "artifacts_created": finalized_result["artifacts_created"],
            "status": finalized_result["status"],
        }

    async def _fail_specification(
        self,
        specification_id: int,
        version_id: int | None = None,
    ) -> dict[str, Any]:
        return await execute_activity(
            Workflows.specification_processing.activities.specification_fail_specification,
            {
                "specification_id": specification_id,
                "version_id": version_id,
            },
        )
