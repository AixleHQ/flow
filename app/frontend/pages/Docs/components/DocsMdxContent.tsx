import { IconExternalLink } from '@tabler/icons-react';
import { type Element } from 'hast';
import type { Blockquote, Root } from 'mdast';
import ReactMarkdown from 'react-markdown';
import rehypeRaw from 'rehype-raw';
import rehypeSanitize from 'rehype-sanitize';
import remarkGfm from 'remark-gfm';
import type { Plugin } from 'unified';
import { visit } from 'unist-util-visit';

import classes from '../DocsPage.module.css';

import { DocsCallout } from './DocsCallout';
import { DocsCodeBlock } from './DocsCodeBlock';

interface Props {
  content: string;
}

const CALLOUT_TYPES = ['warning', 'danger', 'tip', 'info'] as const;
type CalloutType = (typeof CALLOUT_TYPES)[number];

/**
 * Remark plugin: for each blockquote whose first paragraph starts with a callout
 * keyword (plain text or inside <strong>), attach `data-callout-type` to the node
 * and remove the keyword token so it never reaches React children.
 */
const remarkCalloutType: Plugin<[], Root> = () => (tree) => {
  visit(tree, 'blockquote', (node: Blockquote) => {
    const firstParagraph = node.children.find((c) => c.type === 'paragraph');
    if (!firstParagraph || firstParagraph.type !== 'paragraph') return;

    const firstChild = firstParagraph.children[0];
    let rawText = '';
    if (firstChild.type === 'text') {
      rawText = firstChild.value;
    } else if (firstChild.type === 'strong') {
      const inner = firstChild.children[0];
      if (inner.type === 'text') rawText = inner.value;
    }

    const lower = rawText.toLowerCase().trim();
    const match = CALLOUT_TYPES.find((t) => lower === t || lower.startsWith(t));
    if (!match) return;

    // Propagate type as an HTML attribute through the pipeline
    if (!node.data) node.data = {};
    node.data.hProperties = {
      ...(node.data.hProperties as object | undefined),
      'data-callout-type': match,
    };

    // Strip the keyword token so it never appears in rendered text
    if (firstChild.type === 'text') {
      firstChild.value = firstChild.value.replace(new RegExp(`^${match}\\s*`, 'i'), '');
    } else if (firstChild.type === 'strong') {
      const inner = firstChild.children[0];
      if (inner.type === 'text') {
        inner.value = inner.value.replace(new RegExp(`^${match}\\s*`, 'i'), '');
        if (!inner.value.trim()) {
          // Remove the now-empty <strong> node
          firstParagraph.children.splice(0, 1);
          // Trim a leading space off the next text node
          const next = firstParagraph.children[0];
          if (next?.type === 'text') {
            (next as { value: string }).value = (next as { value: string }).value.trimStart();
          }
        }
      }
    }
  });
};

function slugify(text: string): string {
  return text
    .toLowerCase()
    .replace(/[^a-z0-9\s-]/g, '')
    .replace(/\s+/g, '-')
    .replace(/-+/g, '-');
}

export function DocsMdxContent({ content }: Props) {
  return (
    <ReactMarkdown
      remarkPlugins={[remarkGfm, remarkCalloutType]}
      rehypePlugins={[rehypeRaw, rehypeSanitize]}
      components={{
        code: ({ className, children, node, ...props }) => {
          const isInline =
            !(node as Element | undefined)?.properties?.['data-language'] &&
            node?.position?.start.line === node?.position?.end.line;
          return (
            <DocsCodeBlock inline={isInline} className={className} {...props}>
              {children}
            </DocsCodeBlock>
          );
        },
        blockquote: ({ children, ...props }) => {
          const calloutType = (props as Record<string, unknown>)['data-callout-type'] as CalloutType | undefined;
          return <DocsCallout variant={calloutType}>{children}</DocsCallout>;
        },
        h1: ({ children }) => {
          const text = String(children);
          return (
            <h1 id={slugify(text)} className={classes.mdH1}>
              {children}
            </h1>
          );
        },
        h2: ({ children }) => {
          const text = String(children);
          return (
            <h2 id={slugify(text)} className={classes.mdH2}>
              {children}
            </h2>
          );
        },
        h3: ({ children }) => {
          const text = String(children);
          return (
            <h3 id={slugify(text)} className={classes.mdH3}>
              {children}
            </h3>
          );
        },
        a: ({ href, children, className }) => {
          // Pass through raw-HTML elements that already have custom docs classes
          if (className?.startsWith('docs')) {
            return (
              <a href={href} className={className}>
                {children}
              </a>
            );
          }
          const isExternal = href?.startsWith('http');
          return (
            <a
              href={href}
              className={classes.mdLink}
              target={isExternal ? '_blank' : undefined}
              rel={isExternal ? 'noopener noreferrer' : undefined}
            >
              {children}
              {isExternal && <IconExternalLink size={12} className={classes.externalLinkIcon} />}
            </a>
          );
        },
        table: ({ children }) => (
          <div className={classes.tableWrapper}>
            <table className={classes.mdTable}>{children}</table>
          </div>
        ),
        details: ({ children }) => <details className={classes.mdDetails}>{children}</details>,
        summary: ({ children }) => <summary className={classes.mdSummary}>{children}</summary>,
        p: ({ children }) => <p className={classes.mdParagraph}>{children}</p>,
        ul: ({ children }) => <ul className={classes.mdList}>{children}</ul>,
        ol: ({ children }) => <ol className={classes.mdOrderedList}>{children}</ol>,
        li: ({ children }) => <li className={classes.mdListItem}>{children}</li>,
        hr: () => <hr className={classes.mdHr} />,
      }}
    >
      {content}
    </ReactMarkdown>
  );
}
