import { useComputedColorScheme } from '@mantine/core';

import { LOGO_TILE_BG } from 'shared/theme/vendorColors';

import { agentLogoSrc } from '../agentLogos';

interface AgentLogoProps {
  agentType: string | null | undefined;
  size?: number;
}

/**
 * The runtime mark that precedes an agent name. Renders nothing for an agent type
 * outside the registry, so the label carries identity on its own.
 */
export function AgentLogo({ agentType, size = 18 }: AgentLogoProps) {
  const scheme = useComputedColorScheme('dark');
  const src = agentLogoSrc(agentType);
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
