import { Head, usePage } from '@inertiajs/react';
import { IconArrowUpRight, IconBrandGithub } from '@tabler/icons-react';

import classes from './ChangelogPage.module.css';
import { DocsMdxContent } from './components/DocsMdxContent';
import { DocsShell } from './components/DocsShell';
import {
  type ChangelogChange,
  type ChangelogRelease,
  changeTone,
  entriesByArea,
  entriesMarkdown,
  formatReleaseDate,
  isUnreleased,
} from './data/changelog';

interface Props {
  [key: string]: unknown;
  releases: ChangelogRelease[];
  sourceUrl: string;
  settings?: { appVersion?: string };
}

const UNNAMED_AREA = 'Platform & repository';

const ChangelogPage = () => {
  const { releases, sourceUrl, settings } = usePage<Props>().props;
  const latest = releases.find((release) => !isUnreleased(release))?.version;

  return (
    <>
      <Head title="Changelog — Aixle Flow" />
      <DocsShell active="changelog">
        <main className={classes.main}>
          <div className={classes.inner}>
            <header className={classes.header}>
              <p className={classes.eyebrow}>Release notes</p>
              <h1 className={classes.title}>Changelog</h1>
              <p className={classes.lead}>
                What changed in Aixle Flow, release by release. Versions follow{' '}
                <a href="https://semver.org/" target="_blank" rel="noopener noreferrer">
                  Semantic Versioning
                </a>
                .
              </p>
              <a className={classes.sourceLink} href={sourceUrl} target="_blank" rel="noopener noreferrer">
                <IconBrandGithub size={14} />
                CHANGELOG.md on GitHub
              </a>
            </header>

            {releases.length === 0 ? (
              <p className={classes.empty}>No releases have been published yet.</p>
            ) : (
              releases.map((release) => (
                <ReleaseSection
                  key={release.version}
                  release={release}
                  latest={release.version === latest}
                  installed={release.version === settings?.appVersion}
                />
              ))
            )}
          </div>
        </main>
      </DocsShell>
    </>
  );
};

function ReleaseSection({
  release,
  latest,
  installed,
}: {
  release: ChangelogRelease;
  latest: boolean;
  installed: boolean;
}) {
  const unreleased = isUnreleased(release);
  const anchor = unreleased ? 'unreleased' : `v${release.version}`;

  return (
    <section
      id={anchor}
      className={classes.release}
      aria-labelledby={`${anchor}-heading`}
      data-latest={latest || undefined}
    >
      <div className={classes.releaseMeta}>
        <h2 id={`${anchor}-heading`} className={classes.version}>
          {unreleased ? 'Unreleased' : `v${release.version}`}
        </h2>
        {release.date && (
          <time className={classes.date} dateTime={release.date}>
            {formatReleaseDate(release.date)}
          </time>
        )}
        {(unreleased || latest || installed) && (
          <div className={classes.badges}>
            {unreleased && (
              <span className={classes.badge} data-tone="neutral">
                Not released yet
              </span>
            )}
            {latest && (
              <span className={classes.badge} data-tone="brand">
                Latest
              </span>
            )}
            {installed && (
              <span className={classes.badge} data-tone="success">
                Installed
              </span>
            )}
          </div>
        )}
        {release.url && (
          <a className={classes.releaseLink} href={release.url} target="_blank" rel="noopener noreferrer">
            View on GitHub
            <IconArrowUpRight size={12} />
          </a>
        )}
      </div>

      <div className={classes.releaseBody}>
        {release.summary && <DocsMdxContent content={release.summary} />}
        {release.changes.map((change) => (
          <ChangeBlock key={change.kind} change={change} />
        ))}
      </div>
    </section>
  );
}

function ChangeBlock({ change }: { change: ChangelogChange }) {
  const groups = entriesByArea(change.entries);

  return (
    <div className={classes.change}>
      <h3 className={classes.kind} data-tone={changeTone(change.kind)}>
        {change.kind}
      </h3>
      {change.note && (
        <div className={classes.note}>
          <DocsMdxContent content={change.note} />
        </div>
      )}
      {groups.map(({ area, entries }) => (
        <div key={area ?? UNNAMED_AREA} className={classes.area}>
          {(area ?? groups.length > 1) && <h4 className={classes.areaTitle}>{area ?? UNNAMED_AREA}</h4>}
          <DocsMdxContent content={entriesMarkdown(entries)} />
        </div>
      ))}
    </div>
  );
}

export default ChangelogPage;
