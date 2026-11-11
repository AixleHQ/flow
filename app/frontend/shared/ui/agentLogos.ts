import antigravityLogo from './agent-logos/antigravity.svg';
import claudeLogo from './agent-logos/claude.png';
import codexLogo from './agent-logos/codex.png';
import copilotLogo from './agent-logos/copilot.svg';
import cursorLogo from './agent-logos/cursor.png';
import geminiLogo from './agent-logos/gemini.png';
import grokLogo from './agent-logos/grok.svg';
import kiroLogo from './agent-logos/kiro.svg';
import { isAgentType } from './agentRuntimes';
import type { AgentType } from './types';

/**
 * Each runtime's own product mark, as its vendor publishes it. Keyed by AgentType,
 * so a runtime added to the registry does not compile until it has artwork.
 */
export const AGENT_LOGOS: Record<AgentType, string> = {
  claude_code: claudeLogo,
  cursor_cli: cursorLogo,
  codex: codexLogo,
  gemini_cli: geminiLogo,
  antigravity_cli: antigravityLogo,
  grok: grokLogo,
  kiro_cli: kiroLogo,
  copilot_cli: copilotLogo,
};

export function agentLogoSrc(agentType: string | null | undefined): string | undefined {
  return isAgentType(agentType) ? AGENT_LOGOS[agentType] : undefined;
}
