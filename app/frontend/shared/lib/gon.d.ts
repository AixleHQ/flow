declare global {
  interface Window {
    Settings: {
      env: string;
      sentryFrontendDsn: string;
      appVersion: string;
      domain: string;
      protocol: string;
      githubAppSlug: string | null;
    };
  }
}

export {};
