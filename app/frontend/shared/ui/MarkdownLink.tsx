import type { ComponentPropsWithoutRef } from 'react';
import type { ExtraProps } from 'react-markdown';

type Props = ComponentPropsWithoutRef<'a'> & ExtraProps;

function isExternalHref(href: string | undefined): boolean {
  if (!href) return false;
  try {
    const url = new URL(href, window.location.href);
    return (url.protocol === 'http:' || url.protocol === 'https:') && url.origin !== window.location.origin;
  } catch {
    return false;
  }
}

// eslint-disable-next-line @typescript-eslint/no-unused-vars -- react-markdown always passes its hast `node`; it must not reach the DOM
export function MarkdownLink({ node, onClick, ...props }: Props) {
  const external = isExternalHref(props.href);
  return (
    <a
      {...props}
      target={external ? '_blank' : undefined}
      rel={external ? 'noopener noreferrer' : undefined}
      onClick={(event) => {
        // Markdown sits inside click-to-edit containers (the task description);
        // following a link must not also open the editor.
        event.stopPropagation();
        onClick?.(event);
      }}
    />
  );
}
