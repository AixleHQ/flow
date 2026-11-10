import { describe, expect, it } from 'vitest';

import { detectPreviewType, getPreviewType, isCarouselPreviewable } from './previewType';

describe('getPreviewType', () => {
  it('trusts the content type first', () => {
    expect(getPreviewType('image/svg+xml', 'x.png')).toBe('svg');
    expect(getPreviewType('image/png', 'x.md')).toBe('image');
    expect(getPreviewType('text/markdown', 'notes')).toBe('markdown');
    expect(getPreviewType('application/pdf', 'x.png')).toBe('pdf');
  });

  it.each([null, undefined, 'application/octet-stream'])('falls back to the extension when the type is %s', (ct) => {
    expect(getPreviewType(ct, 'photo.avif')).toBe('image');
    expect(getPreviewType(ct, 'logo.svg')).toBe('svg');
    expect(getPreviewType(ct, 'readme.md')).toBe('markdown');
    expect(getPreviewType(ct, 'page.mdx')).toBe('markdown');
    expect(getPreviewType(ct, 'page.markdown')).toBe('markdown');
    expect(getPreviewType(ct, 'archive.zip')).toBe('unsupported');
    expect(getPreviewType(ct, 'no-extension')).toBe('unsupported');
  });

  it('matches extensions case-insensitively', () => {
    expect(getPreviewType(null, 'SHOT.PNG')).toBe('image');
    expect(getPreviewType(null, 'README.MD')).toBe('markdown');
  });

  it('upgrades text/plain to markdown for a markdown extension', () => {
    expect(getPreviewType('text/plain', 'spec.md')).toBe('markdown');
    expect(getPreviewType('text/plain', 'spec.txt')).toBe('text');
  });

  it('classes unknown content types as unsupported', () => {
    expect(detectPreviewType('application/zip')).toBe('unsupported');
  });
});

describe('isCarouselPreviewable', () => {
  it('admits images, svg and markdown only', () => {
    expect(['image', 'svg', 'markdown'].every((t) => isCarouselPreviewable(t as never))).toBe(true);
    for (const type of ['pdf', 'text', 'video', 'audio', 'unsupported'] as const) {
      expect(isCarouselPreviewable(type)).toBe(false);
    }
    expect(isCarouselPreviewable(getPreviewType('application/pdf', 'a.pdf'))).toBe(false);
    expect(isCarouselPreviewable(getPreviewType('application/vnd.openxmlformats-officedocument', 'a.docx'))).toBe(
      false,
    );
  });
});
