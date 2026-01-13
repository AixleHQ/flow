declare global {
  interface Window {
    Settings: {
      env: string;
      rollbarAccessToken: string;
      githubAuthUrl: string;
      bitbucketAuthUrl: string;
      gitlabAuthUrl: string;
      jiraAuthUrl: string;
      otpEnabled: boolean;
      domain: string;
      protocol: string;
    };
  }
}

export {};
