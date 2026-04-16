import { router } from '@inertiajs/react';
import { Progress } from '@mantine/core';
import { useEffect, useState } from 'react';

import classes from './InertiaRouteIndicator.module.css';

export const InertiaRouteIndicator = () => {
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    const removeStart = router.on('start', () => setLoading(true));
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
