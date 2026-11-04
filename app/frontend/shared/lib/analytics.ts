import type { Page } from '@inertiajs/core';
import type { PostHog, PostHogConfig } from 'posthog-js/dist/module.full.no-external';

import { getCsrfToken } from 'shared/lib/apiFetch';
import { isTokenPath, scrubUrl } from 'shared/lib/urlScrub';
import { analyticsConsentPath } from 'shared/routes';
import type { AnalyticsConsent, SharedAnalytics } from 'shared/ui/types';

// Product analytics (PostHog). The only module that talks to posthog-js: pages
// call `analytics.track`, and every call is a no-op unless the server shared a
// config for this page and the person consented. The server decides where it
// may run at all (Analytics.browser_config): the hosted product only, never
// while impersonating, and never capturing on pages whose URL is a credential.

export const CONSENT_COOKIE = 'analytics_consent';
const CONSENT_COOKIE_MAX_AGE = 60 * 60 * 24 * 365;

type Props = Record<string, string | number | boolean | string[] | null | undefined>;

interface AnalyticsPage {
  component: string;
  url: string;
  props: { analytics?: SharedAnalytics | null; project?: unknown; [key: string]: unknown };
}

const FEATURE_AREAS: [RegExp, string][] = [
  [/^Projects\/Board\//, 'board'],
  [/^Projects\/(Workflows\/|WorkflowRuns|Triggers)/, 'workflows'],
  [/^Projects\/AixleBuilder\//, 'builder'],
  [/^(Projects|Company)\/Sessions\//, 'sessions'],
  [/^(Templates\/|Company\/WorkflowCatalog|Projects\/TemplateInstalls)/, 'templates'],
  [/^(Projects\/(Agents|Skills|Tools|McpServers|Repositories|Config|Assets)|Company\/Assets)/, 'resources'],
  [/^(Integrations\/|Projects\/(Integrations|Trackers))/, 'integrations'],
  [/^(Projects|Company)\/Analytics/, 'analytics'],
  [/^(Company\/(Members|Users)|Projects\/Members|Invitations)/, 'team'],
  [/^Company\/Settings\/BillingPage/, 'billing'],
  [/^(Company\/Settings\/|Projects\/Settings|Profile\/)/, 'settings'],
  [/^(Workspaces\/NewPage|Onboarding\/OnboardingPage)/, 'onboarding'],
  [/^Auth\//, 'auth'],
  [/^(Docs\/|HowItWorks)/, 'docs'],
  [/^Projects\/(IndexPage|Overview\/)/, 'projects'],
];

export const featureArea = (component: string): string | undefined =>
  FEATURE_AREAS.find(([pattern]) => pattern.test(component))?.[1];

const snakeCase = (key: string): string => key.replace(/[A-Z]/g, (letter) => `_${letter.toLowerCase()}`);

const snakeKeys = (object: Record<string, unknown>): Record<string, unknown> =>
  Object.fromEntries(Object.entries(object).map(([key, value]) => [snakeCase(key), value]));

const URL_PROPERTIES = [
  '$current_url',
  '$referrer',
  '$pathname',
  '$initial_referrer',
  '$initial_current_url',
  '$initial_pathname',
  '$prev_pageview_pathname',
];

const scrub = (value: string): string => scrubUrl(value, { placeholder: ':token', dropSecrets: true });

// The document title names projects and companies (`Billing — Acme`).
const TITLE_PROPERTIES = ['title', '$title', '$initial_title'];

const scrubProperties = (properties: Record<string, unknown> | undefined): void => {
  if (!properties) return;
  TITLE_PROPERTIES.forEach((key) => delete properties[key]);
  URL_PROPERTIES.forEach((key) => {
    if (typeof properties[key] === 'string') properties[key] = scrub(properties[key] as string);
  });
};

type CapturedEvent = Parameters<Extract<NonNullable<PostHogConfig['before_send']>, (...args: never[]) => unknown>>[0];

/** The second line of defence after not loading at all on token pages: no URL leaves with a token in it. */
export const sanitizeEvent = (event: CapturedEvent): CapturedEvent => {
  if (!event) return event;
  scrubProperties(event.properties);
  scrubProperties(event.$set as Record<string, unknown> | undefined);
  scrubProperties(event.$set_once as Record<string, unknown> | undefined);
  return event;
};

type NetworkRequest = Parameters<
  NonNullable<NonNullable<PostHogConfig['session_recording']>['maskCapturedNetworkRequestFn']>
>[0];

export const sanitizeRequest = (request: NetworkRequest): NetworkRequest => {
  if (typeof request.name === 'string') request.name = scrub(request.name);
  delete request.requestHeaders;
  delete request.responseHeaders;
  delete request.requestBody;
  delete request.responseBody;
  return request;
};

/** Everything on screen is masked unless it sits inside static navigation marked `data-ph-unmask`. */
export const maskText = (text: string, element?: HTMLElement | null): string =>
  element?.closest('[data-ph-unmask]') ? text : text.replace(/\S/g, '*');

export const privacySignalRefuses = (): boolean => {
  const nav = navigator as Navigator & { globalPrivacyControl?: boolean };
  const win = window as Window & { doNotTrack?: string };
  return nav.globalPrivacyControl === true || nav.doNotTrack === '1' || win.doNotTrack === '1';
};

const readCookie = (): AnalyticsConsent | null => {
  const match = document.cookie.match(new RegExp(`(?:^|; )${CONSENT_COOKIE}=([^;]*)`));
  const value = match?.[1];
  return value === 'granted' || value === 'denied' ? value : null;
};

const writeCookie = (choice: AnalyticsConsent): void => {
  const secure = window.location.protocol === 'https:' ? '; Secure' : '';
  document.cookie = `${CONSENT_COOKIE}=${choice}; Path=/; Max-Age=${CONSENT_COOKIE_MAX_AGE}; SameSite=Lax${secure}`;
};

let client: PostHog | null = null;
let loading: Promise<PostHog> | null = null;
let page: AnalyticsPage | null = null;
let suppressed = true;
let recording = false;
let lastPageview: string | null = null;
let lastComponent: string | null = null;

// Events a page sends as it mounts arrive before PostHog has loaded, and on a
// first visit before the person has answered the banner. They wait here
// briefly, and go once capture starts or are dropped once it is refused.
const PENDING_TTL_MS = 30_000;
const PENDING_LIMIT = 20;
let pending: { event: string; props: Props; at: number }[] = [];

type Listener = () => void;
const listeners = new Set<Listener>();
const notify = () => listeners.forEach((listener) => listener());

const config = (): SharedAnalytics | null => page?.props.analytics ?? null;

/** The answer that counts: a privacy signal refuses, then the account's answer, then this browser's. */
export const effectiveConsent = (): AnalyticsConsent | null => {
  const shared = config();
  if (!shared) return null;
  if (privacySignalRefuses()) return 'denied';
  return shared.consent ?? readCookie();
};

const mayCapture = (): boolean => {
  const shared = config();
  if (!shared || !page) return false;
  if (!shared.capture || page.component.startsWith('Admin/')) return false;
  if (isTokenPath(new URL(page.url, window.location.origin).pathname)) return false;
  return effectiveConsent() === 'granted';
};

const load = (shared: SharedAnalytics): Promise<PostHog> => {
  loading ??= import('posthog-js/dist/module.full.no-external').then(({ default: posthog }) => {
    posthog.init(shared.key, {
      api_host: shared.host,
      // The last snapshot before replay began streaming network bodies
      // (2026-06-25) and capturing JSON-LD (2026-08-30): both record content.
      defaults: '2026-05-30',
      // Sent by hand on Inertia's navigate event, after this page's properties
      // are registered; history_change would fire on pushState, before them.
      capture_pageview: false,
      capture_pageleave: true,
      autocapture: true,
      rageclick: true,
      capture_dead_clicks: true,
      person_profiles: 'identified_only',
      opt_out_capturing_by_default: true,
      respect_dnt: true,
      disable_external_dependency_loading: true,
      // Also stops the remote config fetch from PostHog's asset host, so a
      // project setting can never loosen what this file decides.
      advanced_disable_flags: true,
      mask_all_text: true,
      mask_all_element_attributes: true,
      // Otherwise the project setting decides, and console output carries API
      // error bodies.
      enable_recording_console_log: false,
      before_send: (event) => (suppressed ? null : sanitizeEvent(event)),
      session_recording: {
        maskAllInputs: true,
        maskTextSelector: '*',
        maskTextFn: maskText,
        blockSelector: 'iframe, img, video, [data-ph-block]',
        maskCapturedNetworkRequestFn: sanitizeRequest,
        recordHeaders: false,
        recordBody: false,
      },
    });
    client = posthog;
    return posthog;
  });
  return loading;
};

// Read back from PostHog's own storage rather than kept here, so a sign-out or a
// company switch is noticed after a full page load too.
const syncIdentity = (posthog: PostHog, shared: SharedAnalytics): void => {
  const identified = posthog.get_property('$user_state') === 'identified';
  if (!shared.distinctId) {
    if (identified) posthog.reset();
    return;
  }
  const companyId = shared.context.companyId ?? null;
  const previousCompany = posthog.get_property('company_id') ?? null;
  // A new person, or the same person in another company: start a fresh
  // identity so nothing from the last one carries over.
  if (identified && (posthog.get_distinct_id() !== shared.distinctId || previousCompany !== companyId)) {
    posthog.reset();
  }
  if (posthog.get_distinct_id() !== shared.distinctId) {
    posthog.identify(shared.distinctId, shared.signupDate ? { signup_date: shared.signupDate } : undefined);
  }
};

const projectIdOf = (props: AnalyticsPage['props']): number | undefined => {
  const project = props.project as { id?: unknown } | undefined;
  return typeof project?.id === 'number' ? project.id : undefined;
};

const report = async (current: AnalyticsPage): Promise<void> => {
  const shared = config();
  if (!shared) return;
  const posthog = await load(shared);
  if (page !== current || suppressed) return;

  // reset() inside syncIdentity puts consent back to the opted-out default, so
  // it runs first and the opt-in after it.
  syncIdentity(posthog, shared);
  posthog.opt_in_capturing({ captureEventName: false });
  posthog.unregister('project_id');
  posthog.register({
    ...snakeKeys(shared.context),
    via: 'ui',
    page_component: current.component,
    feature_area: featureArea(current.component),
    ...(projectIdOf(current.props) ? { project_id: projectIdOf(current.props) } : {}),
  });
  if (!recording) {
    posthog.startSessionRecording();
    recording = true;
  }

  const pageKey = `${current.component} ${new URL(current.url, window.location.origin).pathname}`;
  if (pageKey !== lastPageview) {
    lastPageview = pageKey;
    // PostHog puts the time on, and scroll depth of, the page just left on
    // this event as $prev_pageview_*; this says which page that was.
    posthog.capture('$pageview', lastComponent ? { prev_page_component: lastComponent } : {});
    lastComponent = current.component;
  }

  const now = Date.now();
  pending.splice(0).forEach(({ event, props, at }) => {
    if (now - at < PENDING_TTL_MS) posthog.capture(event, props);
  });
};

const stop = (): void => {
  const shared = config();
  if (!shared || !shared.capture || effectiveConsent() === 'denied') pending = [];
  if (!client) return;
  client.stopSessionRecording();
  recording = false;
  if (effectiveConsent() === 'denied') client.opt_out_capturing();
};

/** Called for every page Inertia shows, the first included. */
export const syncAnalytics = (next: Page | AnalyticsPage): void => {
  page = next as AnalyticsPage;
  const shared = config();

  // A browser saying no answers for the person, once, so the banner never asks.
  if (shared && privacySignalRefuses() && (shared.distinctId ? shared.consent === null : readCookie() === null)) {
    void recordConsent('denied');
  }

  suppressed = !mayCapture();
  if (suppressed) stop();
  else void report(page);
  notify();
};

const recordConsent = async (choice: AnalyticsConsent): Promise<void> => {
  writeCookie(choice);
  const shared = config();
  if (shared?.distinctId) {
    shared.consent = choice;
    await fetch(analyticsConsentPath(), {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json', Accept: 'application/json', 'X-CSRF-Token': getCsrfToken() },
      body: JSON.stringify({ consent: choice }),
      credentials: 'same-origin',
      redirect: 'manual',
    }).catch(() => undefined);
  }
};

/** The banner's and the Privacy toggle's answer. */
export const setConsent = async (choice: AnalyticsConsent): Promise<void> => {
  await recordConsent(choice);
  if (page) syncAnalytics(page);
};

/** Whether to ask: analytics may run here, nobody has answered, and the browser sent no refusal. */
export const consentPending = (): boolean => config() !== null && effectiveConsent() === null;

export const subscribe = (listener: Listener): (() => void) => {
  listeners.add(listener);
  return () => listeners.delete(listener);
};

export const analytics = {
  track(event: string, props: Props = {}): void {
    if (client && !suppressed) {
      client.capture(event, props);
      return;
    }
    if (config() && effectiveConsent() !== 'denied' && pending.length < PENDING_LIMIT) {
      pending.push({ event, props, at: Date.now() });
    }
  },
  /** The browser's anonymous id, for the signup form to carry across to the account. */
  anonymousId(): string | null {
    if (suppressed || !client) return null;
    return client.get_distinct_id();
  },
  reset(): void {
    client?.reset();
  },
};

// Web::Company::ApplicationController#user_not_authorized.
const NOT_AUTHORIZED = 'You are not authorized to perform this action.';

interface RouterLike {
  on(event: 'navigate', callback: (event: CustomEvent<{ page: Page }>) => void): () => void;
  on(event: 'error', callback: (event: CustomEvent<{ errors: Record<string, unknown> }>) => void): () => void;
  on(event: 'httpException', callback: (event: CustomEvent<{ response: { status: number } }>) => void): () => void;
  on(event: 'networkError', callback: () => void): () => void;
}

const isSearchField = (target: EventTarget | null): boolean =>
  target instanceof HTMLInputElement && (target.type === 'search' || /^search/i.test(target.placeholder));

/** Wires analytics to Inertia once, before the app mounts, so the initial page is seen too. */
export const installAnalytics = (router: RouterLike): void => {
  // Every list has its own search box; one listener reports the first search on
  // a page, and never what was typed.
  let searchedOnPage = false;
  document.addEventListener(
    'input',
    (event) => {
      if (searchedOnPage || !isSearchField(event.target)) return;
      searchedOnPage = true;
      analytics.track('search_used');
    },
    true,
  );

  router.on('navigate', (event) => {
    searchedOnPage = false;
    syncAnalytics(event.detail.page);
    const flash = (event.detail.page.props.flash ?? {}) as Record<string, unknown>;
    if (flash.alert === NOT_AUTHORIZED) analytics.track('permission_denied_shown');
  });
  // Every router.post/patch/put/delete that comes back with validation errors.
  router.on('error', (event) => {
    analytics.track('form_validation_failed', {
      form: page?.component,
      fields: Object.keys(event.detail.errors ?? {}),
    });
  });
  router.on('httpException', (event) => {
    analytics.track('request_failed', { status: event.detail.response.status });
  });
  router.on('networkError', () => analytics.track('request_failed', { status: 0 }));
};

/**
 * A stable name for a button or link in click analytics. Autocapture drops every
 * element attribute and all text here, but keeps `data-ph-capture-attribute-*`,
 * which arrives as the event's `ph_name` property.
 */
export const phName = (name: string) => ({ 'data-ph-name': name, 'data-ph-capture-attribute-ph_name': name });

export const phSlug = (label: string): string =>
  label
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_|_$/g, '');
