import { z } from 'zod';

// zod 4 probes `new Function` for its JIT on the first object parse, and the
// Content-Security-Policy (no 'unsafe-eval') reports that probe on every page.
// The non-JIT path runs the same validation.
z.config({ jitless: true });
