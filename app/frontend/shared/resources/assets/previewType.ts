export type PreviewType = 'image' | 'video' | 'audio' | 'pdf' | 'text' | 'markdown' | 'svg' | 'unsupported';

const MARKDOWN_EXTS = ['md', 'mdx', 'markdown'];

export function detectPreviewType(contentType: string | null | undefined): PreviewType {
  if (!contentType) return 'unsupported';
  const ct = contentType.toLowerCase();

  if (ct.startsWith('image/svg')) return 'svg';
  if (ct.startsWith('image/')) return 'image';
  if (ct.startsWith('video/')) return 'video';
  if (ct.startsWith('audio/')) return 'audio';
  if (ct === 'application/pdf') return 'pdf';

  if (
    ct.startsWith('text/') ||
    ct.includes('json') ||
    ct.includes('xml') ||
    ct.includes('yaml') ||
    ct.includes('yml') ||
    ct.includes('javascript') ||
    ct.includes('typescript') ||
    ct.includes('css') ||
    ct.includes('html') ||
    ct.includes('sql') ||
    ct.includes('ruby') ||
    ct.includes('python') ||
    ct.includes('shell') ||
    ct.includes('sh') ||
    ct.includes('bash') ||
    ct.includes('csv') ||
    ct.includes('log')
  ) {
    if (ct.includes('markdown') || ct.includes('md')) return 'markdown';
    return 'text';
  }

  return 'unsupported';
}

export function extensionFromName(name: string): string {
  const idx = name.lastIndexOf('.');
  return idx > 0 ? name.substring(idx + 1).toLowerCase() : '';
}

export function detectPreviewTypeFromExt(name: string): PreviewType {
  const ext = extensionFromName(name);
  const imageExts = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'ico', 'avif'];
  const videoExts = ['mp4', 'webm', 'ogg', 'mov'];
  const audioExts = ['mp3', 'wav', 'ogg', 'aac', 'flac', 'opus', 'wma', 'm4a'];
  const textExts = [
    'txt',
    'log',
    'json',
    'xml',
    'yaml',
    'yml',
    'csv',
    'tsv',
    'js',
    'jsx',
    'ts',
    'tsx',
    'css',
    'scss',
    'less',
    'html',
    'htm',
    'sql',
    'rb',
    'py',
    'go',
    'rs',
    'java',
    'kt',
    'swift',
    'c',
    'cpp',
    'h',
    'hpp',
    'cs',
    'php',
    'sh',
    'bash',
    'zsh',
    'fish',
    'toml',
    'ini',
    'cfg',
    'env',
    'gitignore',
    'dockerignore',
    'makefile',
    'rake',
    'gemfile',
    'lock',
    'dockerfile',
  ];

  if (ext === 'svg') return 'svg';
  if (imageExts.includes(ext)) return 'image';
  if (videoExts.includes(ext)) return 'video';
  if (audioExts.includes(ext)) return 'audio';
  if (ext === 'pdf') return 'pdf';
  if (MARKDOWN_EXTS.includes(ext)) return 'markdown';
  if (textExts.includes(ext)) return 'text';
  return 'unsupported';
}

export function getPreviewType(contentType: string | null | undefined, name: string): PreviewType {
  const fromCt = detectPreviewType(contentType);
  // Uploads are often sniffed as text/plain, which would hide a .md from the markdown renderer.
  if (fromCt === 'text' && MARKDOWN_EXTS.includes(extensionFromName(name))) return 'markdown';
  if (fromCt !== 'unsupported') return fromCt;
  return detectPreviewTypeFromExt(name);
}

export const MAX_TEXT_SIZE = 2 * 1024 * 1024;

export function isCarouselPreviewable(type: PreviewType): boolean {
  return type === 'image' || type === 'svg' || type === 'markdown';
}
