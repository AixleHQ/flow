import { type IframeHTMLAttributes, useState } from 'react';

import { stripContainerTicket } from 'shared/lib/terminalPageUrl';

type ContainerFrameProps = Omit<IframeHTMLAttributes<HTMLIFrameElement>, 'src' | 'title'> & {
  src: string;
  title: string;
};

/**
 * A frame onto an agent container (terminal, IDE). Every serialization of the page's props
 * mints the container URL a fresh pass, and a new `src` would reload the terminal, so the
 * frame keeps the URL it loaded until the route itself changes; once that pass expires the
 * gate admits the frame by the cookie it traded the pass for.
 */
export function ContainerFrame({ src, title, ...props }: ContainerFrameProps) {
  const [frameSrc, setFrameSrc] = useState(src);
  const current = stripContainerTicket(frameSrc) === stripContainerTicket(src) ? frameSrc : src;
  if (current !== frameSrc) setFrameSrc(current);

  return <iframe src={current} title={title} {...props} />;
}
