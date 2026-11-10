import type { ComponentPropsWithoutRef } from 'react';
import Markdown, { type ExtraProps } from 'react-markdown';
import rehypeSanitize, { defaultSchema } from 'rehype-sanitize';
import remarkGfm from 'remark-gfm';

import { MarkdownLink } from 'shared/ui/MarkdownLink';

import classes from './MarkdownPreview.module.css';

function parseUrl(value: string | undefined): URL | null {
  if (!value) return null;
  try {
    // No base: a relative URL cannot be resolved against an uploaded file, so it throws.
    return new URL(value);
  } catch {
    return null;
  }
}

function PreviewLink({ href, children, ...props }: ComponentPropsWithoutRef<'a'> & ExtraProps) {
  const url = parseUrl(href);
  if (!url || !['http:', 'https:', 'mailto:'].includes(url.protocol)) {
    return <span className={classes.unresolved}>{children}</span>;
  }
  return (
    <MarkdownLink {...props} href={href}>
      {children}
    </MarkdownLink>
  );
}

function PreviewImage({ src, alt }: ComponentPropsWithoutRef<'img'> & ExtraProps) {
  if (typeof src !== 'string' || parseUrl(src)?.protocol !== 'https:') {
    return <span className={classes.unresolved}>{alt}</span>;
  }
  return <img src={src} alt={alt ?? ''} loading="lazy" style={{ maxWidth: '100%' }} />;
}

export function MarkdownPreview({ source }: { source: string }) {
  return (
    <div className={classes.root}>
      <Markdown
        remarkPlugins={[remarkGfm]}
        rehypePlugins={[[rehypeSanitize, defaultSchema]]}
        components={{ a: PreviewLink, img: PreviewImage }}
      >
        {source}
      </Markdown>
    </div>
  );
}
