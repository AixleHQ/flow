import { router } from '@inertiajs/react';
import { Progress } from '@mantine/core';
import { useEffect, useState } from 'react';

import classes from './InertiaRouteIndicator.module.css';

interface VisitShape {
  only: string[];
  except: string[];
  async: boolean;
  prefetch: boolean;
  showProgress: boolean;
}

// A partial reload (a cable refresh, a poll, a filter's `only:`) or a prefetch
// is the page updating itself, not the user going somewhere, so it shows no bar.
export const isNavigation = (visit: VisitShape) =>
  visit.showProgress !== false &&
  !visit.prefetch &&
  !visit.async &&
  visit.only.length === 0 &&
  visit.except.length === 0;

export const InertiaRouteIndicator = () => {
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    const removeStart = router.on('start', (event) => {
      if (isNavigation(event.detail.visit)) setLoading(true);
    });
    const removeFinish = router.on('finish', () => setLoading(false));
    return () => {
      removeStart();
      removeFinish();
    };
  }, []);

  if (!loading) return null;

  return (
    <div className={classes.indicator}>
      <Progress value={100} size={2} color="blue" animated />
    </div>
  );
};
