import { router } from '@inertiajs/react';
import { Modal, TextInput } from '@mantine/core';
import { IconSearch } from '@tabler/icons-react';
import { useEffect, useRef, useState } from 'react';

import { searchDocs, type SearchResult } from '../data/searchIndex';
import classes from '../DocsPage.module.css';

interface Props {
  open: boolean;
  onClose: () => void;
}

export function DocsSearchModal({ open, onClose }: Props) {
  const [query, setQuery] = useState('');
  const [results, setResults] = useState<SearchResult[]>([]);
  const [activeIndex, setActiveIndex] = useState(0);
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (open) {
      setQuery('');
      setResults([]);
      setActiveIndex(0);
      setTimeout(() => inputRef.current?.focus(), 50);
    }
  }, [open]);

  useEffect(() => {
    const res = searchDocs(query);
    setResults(res);
    setActiveIndex(0);
  }, [query]);

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'ArrowDown') {
      e.preventDefault();
      setActiveIndex((i) => Math.min(i + 1, results.length - 1));
    } else if (e.key === 'ArrowUp') {
      e.preventDefault();
      setActiveIndex((i) => Math.max(i - 1, 0));
    } else if (e.key === 'Enter' && results[activeIndex]) {
      navigateTo(results[activeIndex].slug);
    }
  };

  const navigateTo = (slug: string) => {
    onClose();
    router.visit(`/docs/${slug}`);
  };

  return (
    <Modal
      opened={open}
      onClose={onClose}
      withCloseButton={false}
      size="lg"
      padding={0}
      classNames={{
        content: classes.searchModalContent,
        overlay: classes.searchModalOverlay,
      }}
    >
      <div className={classes.searchInputRow} onKeyDown={handleKeyDown}>
        <IconSearch size={16} className={classes.searchInputIcon} />
        <TextInput
          ref={inputRef}
          value={query}
          onChange={(e) => setQuery(e.currentTarget.value)}
          placeholder="Search documentation…"
          variant="unstyled"
          classNames={{ input: classes.searchInput }}
          aria-label="Search documentation"
        />
      </div>

      {results.length > 0 && (
        <ul className={classes.searchResults} role="listbox">
          {results.map((result, i) => (
            <li key={result.slug} role="option" aria-selected={i === activeIndex}>
              <button
                type="button"
                className={`${classes.searchResultItem} ${i === activeIndex ? classes.searchResultItemActive : ''}`}
                onClick={() => navigateTo(result.slug)}
                onMouseEnter={() => setActiveIndex(i)}
              >
                <span className={classes.searchResultTitle}>{result.title}</span>
                <span className={classes.searchResultSection}>{result.section}</span>
                <p className={classes.searchResultDesc}>{result.desc}</p>
              </button>
            </li>
          ))}
        </ul>
      )}

      {query.length > 0 && results.length === 0 && (
        <p className={classes.searchNoResults}>No results for &ldquo;{query}&rdquo;</p>
      )}
    </Modal>
  );
}
