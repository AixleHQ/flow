const rollbarConfig = {
  accessToken: window.Settings.rollbarAccessToken,
  enabled: window.Settings.env !== 'development',
  environment: window.Settings.env,
  captureUncaught: true,
  captureUnhandledRejections: true,
  payload: {
    client: {
      javascript: {
        source_map_enabled: true,
      },
    },
  },
};

export { rollbarConfig };
