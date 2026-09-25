import { useComputedColorScheme } from '@mantine/core';

import { LOGO_TILE_BG } from 'shared/theme/vendorColors';

import claudeLogo from '../agent-logos/claude.png';
import codexLogo from '../agent-logos/codex.png';
import cursorLogo from '../agent-logos/cursor.png';
import geminiLogo from '../agent-logos/gemini.png';

const LOGOS: Record<string, string> = {
  claude_code: claudeLogo,
  cursor_cli: cursorLogo,
  codex: codexLogo,
  gemini_cli: geminiLogo,
  antigravity_cli: geminiLogo,
};

interface AgentLogoProps {
  agentType: string | null | undefined;
  size?: number;
}

/**
 * The runtime mark that precedes an agent name. Renders nothing for a runtime
 * we have no artwork for, so the label carries identity on its own.
 */
export function AgentLogo({ agentType, size = 18 }: AgentLogoProps) {
  const scheme = useComputedColorScheme('dark');
  const src = LOGOS[agentType ?? ''];
  if (!src) return null;

  return (
    <img
      src={src}
      alt=""
      width={size}
      height={size}
      style={{
        borderRadius: 4,
        flex: 'none',
        objectFit: 'contain',
        backgroundColor: scheme === 'dark' ? LOGO_TILE_BG.dark : LOGO_TILE_BG.light,
      }}
    />
  );
}
