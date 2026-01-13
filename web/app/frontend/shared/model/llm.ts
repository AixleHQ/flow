export interface LlmPreset {
  name: string;
  description: string;
  config: Record<string, string>;
}

export interface LlmModelConfig {
  codebaseIndexingModel?: string;
  codebaseReportingModel?: string;
  documentAnalysisModel?: string;
  uiVisionModel?: string;
  uiCriticModel?: string;
  uiSummaryModel?: string;
  domainAnalysisModel?: string;
  featureExtractionModel?: string;
  userStoryModel?: string;
  useCaseModel?: string;
  diagramModel?: string;
  dataFlowModel?: string;
}

export interface WorkspaceLlmConfig {
  availableLlms: string[];
  assetLlmPresets: Record<string, LlmPreset>;
  specificationLlmPresets: Record<string, LlmPreset>;
}
