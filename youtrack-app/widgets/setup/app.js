'use strict';

const APP_NAME = 'aixle-flow';
const SERVICE_LOGIN = 'aixle-flow';
const SERVICE_NAME = 'Aixle Flow';
const DEFAULT_FLOW_URL = 'https://flow.aixle.com';
const HUB_SERVICE_ID = '0-0-0-0-0';

const root = document.getElementById('root');
let host = null;

// ---------- DOM ----------

function h(tag, attrs, ...children) {
  const el = document.createElement(tag);
  Object.entries(attrs || {}).forEach(([name, value]) => {
    if (value === null || value === undefined || value === false) return;
    if (name.startsWith('on')) el.addEventListener(name.slice(2), value);
    else if (name === 'class') el.className = value;
    else if (name === 'disabled') el[name] = value;
    else el.setAttribute(name, value === true ? '' : value);
  });
  children.flat(Infinity).forEach((child) => {
    if (child === null || child === undefined || child === false) return;
    el.append(child instanceof Node ? child : String(child));
  });
  return el;
}

function show(...nodes) {
  root.replaceChildren(...nodes.flat(Infinity).filter((node) => node !== null && node !== undefined && node !== false));
}

function notice(kind, text) {
  return text ? h('div', { class: 'notice ' + kind, role: kind === 'error' ? 'alert' : 'status' }, text) : null;
}

// ---------- errors ----------

class Problem extends Error {
  constructor(message, status) {
    super(message);
    this.status = status;
  }
}

function describe(error) {
  if (!error) return 'Unknown error';
  if (error instanceof Problem) return error.message;
  const data = error.data || {};
  const detail = data.error_description || data.error_message || data.message || data.error;
  const status = error.status ? 'HTTP ' + error.status : '';
  const text = [detail, error.message].filter(Boolean).filter((v, i, all) => all.indexOf(v) === i).join(' — ');
  return [status, text].filter(Boolean).join(': ') || String(error);
}

// ---------- helpers ----------

function yt(path, query, options) {
  return host.fetchYouTrack(path, Object.assign({ query: query || {} }, options || {}));
}

function hub(path, options) {
  return host.fetchHub(path, options || {});
}

function normalizeUrl(value) {
  try {
    const url = new URL(String(value).trim());
    return (url.origin + url.pathname).replace(/\/+$/, '');
  } catch (e) {
    return null;
  }
}

function parseJson(value, fallback) {
  try {
    return JSON.parse(value) || fallback;
  } catch (e) {
    return fallback;
  }
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function sameOrigin(value, base) {
  try {
    const url = new URL(value);
    return (url.protocol === 'https:' || url.protocol === 'http:') && url.origin === new URL(base).origin ? url.href : null;
  } catch (e) {
    return null;
  }
}

async function aixle(ctx, method, path, body) {
  const headers = { Accept: 'application/json', Authorization: 'Bearer ' + ctx.ref.secret };
  if (body) headers['Content-Type'] = 'application/json';
  let response;
  try {
    response = await fetch(ctx.flowUrl + path, {
      method: method,
      headers: headers,
      body: body ? JSON.stringify(body) : undefined,
      credentials: 'omit',
      cache: 'no-store'
    });
  } catch (e) {
    throw new Problem('Could not reach Aixle Flow at ' + ctx.flowUrl + '.');
  }
  let data = null;
  try {
    data = await response.json();
  } catch (e) {
    data = null;
  }
  if (!response.ok) {
    const message = data && (data.message || data.error);
    throw new Problem('Aixle Flow answered HTTP ' + response.status + (message ? ': ' + message : '.'), response.status);
  }
  return data;
}

// ---------- hand-over from the connect page ----------

async function readHandover() {
  const config = await host.readConfig();
  const handover = parseJson(config && config.handover, null);
  if (!handover || typeof handover.pairing !== 'string' || !Array.isArray(handover.projects)) return null;
  const dot = handover.pairing.indexOf('.');
  if (dot < 1) return null;
  return {
    ref: { id: handover.pairing.slice(0, dot), secret: handover.pairing.slice(dot + 1) },
    projectIds: handover.projects.map(String)
  };
}

async function clearHandover(ctx) {
  if (ctx.cleared) return;
  await host.storeConfig({});
  ctx.cleared = true;
}

// ---------- steps ----------

const STEPS = [
  { key: 'request', title: 'Check the request with Aixle Flow', run: checkRequest },
  { key: 'user', title: 'Create or reuse the service user ' + SERVICE_LOGIN, run: ensureServiceUser },
  { key: 'teams', title: 'Add it to the projects’ teams', run: addToTeams },
  { key: 'attach', title: 'Turn the app on in the projects', run: attachApp },
  { key: 'token', title: 'Create a permanent token for ' + SERVICE_LOGIN, run: mintToken },
  { key: 'complete', title: 'Hand the token to Aixle Flow', run: completePairing },
  { key: 'settings', title: 'Save the projects’ event settings', run: saveSettings }
];

async function findAppId() {
  if (window.YTApp && YTApp.widget && YTApp.widget.appId) return YTApp.widget.appId;
  const apps = await yt('admin/apps', { fields: 'id,name', $top: 1000 });
  const found = apps.find((app) => app.name === APP_NAME);
  if (!found) throw new Problem('The app “' + APP_NAME + '” is not installed here.');
  return found.id;
}

async function checkRequest(ctx) {
  const [appId, system, config, projects] = await Promise.all([
    findAppId(),
    yt('admin/globalSettings/systemSettings', { fields: 'baseUrl' }).catch(() => ({})),
    yt('config', { fields: 'contextPath' }).catch(() => ({})),
    yt('admin/projects', { fields: 'id,shortName,name,archived', $top: 5000 })
  ]);
  ctx.app = await yt('admin/apps/' + appId, { fields: 'id,name,version,globalConfig(globalSettings)' });
  const global = parseJson(ctx.app.globalConfig && ctx.app.globalConfig.globalSettings, {});
  ctx.flowUrl = normalizeUrl(global.flowUrl) || DEFAULT_FLOW_URL;

  const ancestor = (location.ancestorOrigins && location.ancestorOrigins[0]) || '';
  const browserHome = ancestor ? normalizeUrl(ancestor + (config.contextPath || '')) : null;
  const own = [normalizeUrl(system.baseUrl), browserHome].filter(Boolean).map((url) => url.toLowerCase());

  ctx.projects = ctx.projectIds.map((id) => {
    const project = projects.find((item) => item.id === id);
    if (!project) throw new Problem('A chosen project no longer exists (' + id + ').');
    return project;
  });

  if (ctx.result) return ctx.pairing.company.name + ' / ' + ctx.pairing.project.name;

  const pairing = await aixle(ctx, 'GET', '/integrations/youtrack/pairings/' + encodeURIComponent(ctx.ref.id));
  const instance = normalizeUrl(pairing.instance_url);
  if (!instance || own.indexOf(instance.toLowerCase()) === -1) {
    throw new Problem('This request is for ' + pairing.instance_url + ', not for this YouTrack.');
  }
  if (pairing.status === 'completed') throw new Problem('This request has already been used. Start again from Aixle Flow.');
  if (pairing.status === 'expired') throw new Problem('This request has expired. Start again from Aixle Flow.');
  if (pairing.status !== 'approved' || !pairing.company || !pairing.project) {
    throw new Problem('This request has not been approved in Aixle Flow.');
  }
  ctx.pairing = pairing;
  return pairing.company.name + ' / ' + pairing.project.name;
}

async function findHubUser() {
  const query = encodeURIComponent('login: ' + SERVICE_LOGIN);
  const page = await hub('api/rest/users?fields=id,login,name,banned&query=' + query);
  return (page.users || []).find((user) => user.login === SERVICE_LOGIN) || null;
}

async function ensureServiceUser(ctx) {
  let created = false;
  let hubUser = await findHubUser();
  if (!hubUser) {
    hubUser = await hub('api/rest/users?fields=id,login,name,banned', {
      method: 'POST',
      body: { login: SERVICE_LOGIN, name: SERVICE_NAME }
    });
    created = true;
  }
  if (hubUser.banned) throw new Problem('The user ' + SERVICE_LOGIN + ' is banned. Unban it in Users, then retry.');
  ctx.hubUser = hubUser;

  // YouTrack picks a Hub user up a moment after Hub creates it, and resolves it by its Hub id.
  // Its YouTrack login can differ (a leftover YouTrack record may still hold "aixle-flow").
  for (let attempt = 0; attempt < 20; attempt += 1) {
    try {
      const user = await yt('users/' + encodeURIComponent(hubUser.id), { fields: 'id,login,ringId' });
      ctx.user = user;
      const note = user.login === SERVICE_LOGIN ? '' : ' (in YouTrack: ' + user.login + ')';
      return (created ? 'Created ' : 'Reused ') + SERVICE_LOGIN + note;
    } catch (e) {
      if (e.status !== 404) throw e;
    }
    await sleep(1000);
  }
  throw new Problem('YouTrack has not picked up the user ' + SERVICE_LOGIN + ' yet. Retry in a minute.');
}

async function addToTeams(ctx) {
  for (const project of ctx.projects) {
    await yt('admin/projects/' + project.id + '/team/ownUsers', { fields: 'id' }, {
      method: 'POST',
      body: { id: ctx.user.id }
    });
  }
  return ctx.projects.map((project) => project.shortName).join(', ');
}

async function attachApp(ctx) {
  ctx.usages = {};
  for (const project of ctx.projects) {
    const usage = await yt('admin/projects/' + project.id + '/appConfigurations', { fields: 'id,app(id)' }, {
      method: 'POST',
      body: { app: { id: ctx.app.id } }
    });
    ctx.usages[project.id] = usage.id;
  }
  return ctx.projects.map((project) => project.shortName).join(', ');
}

async function mintToken(ctx) {
  if (ctx.token) return 'Created';
  const page = await hub('api/rest/services?fields=id,name,applicationName&$top=500');
  const services = page.services || [];
  const youtrack = services.find((service) => service.applicationName === 'YouTrack') ||
    services.find((service) => service.name === 'YouTrack');
  if (!youtrack) throw new Problem('Could not find the YouTrack service in Hub.');
  const name = (SERVICE_NAME + ' — ' + ctx.pairing.company.name + ' / ' + ctx.pairing.project.name).slice(0, 100);
  const token = await hub('api/rest/users/' + encodeURIComponent(ctx.hubUser.id) + '/permanenttokens?fields=id,name,token', {
    method: 'POST',
    body: { name: name, scope: [{ id: youtrack.id }, { id: HUB_SERVICE_ID }] }
  });
  if (!token || !token.token) throw new Problem('Hub did not return the token.');
  ctx.token = { id: token.id, value: token.token };
  return 'Created';
}

async function revokeToken(ctx) {
  if (!ctx.token) return;
  try {
    await hub('api/rest/users/' + encodeURIComponent(ctx.hubUser.id) + '/permanenttokens/' + encodeURIComponent(ctx.token.id), { method: 'DELETE' });
  } catch (e) {
    console.warn('Aixle Flow: could not revoke the unused token', e);
  }
  ctx.token = null;
}

async function completePairing(ctx) {
  if (ctx.result) return 'Done';
  let result;
  try {
    result = await aixle(ctx, 'POST', '/integrations/youtrack/pairings/' + encodeURIComponent(ctx.ref.id) + '/complete', {
      app_version: ctx.app.version,
      instance_url: ctx.pairing.instance_url,
      token: ctx.token.value,
      service_user: { id: ctx.user.id, login: ctx.user.login },
      projects: ctx.projects.map((project) => ({ id: project.id, key: project.shortName, name: project.name }))
    });
  } catch (e) {
    // Without an answer Aixle may have kept the token, so only a refusal revokes it.
    if (e instanceof Problem && e.status) await revokeToken(ctx);
    throw e;
  }
  ctx.token.value = null;
  ctx.result = result || {};
  await clearHandover(ctx);
  return 'Done';
}

async function saveSettings(ctx) {
  const returned = Array.isArray(ctx.result.projects) ? ctx.result.projects : [];
  const missing = [];
  for (const project of ctx.projects) {
    const settings = returned.find((item) => String(item.id) === project.id);
    if (!settings || !settings.events_url || !settings.secret) {
      missing.push(project.shortName);
      continue;
    }
    const projectSettings = { eventsUrl: settings.events_url, secret: settings.secret };
    if (settings.status_field) projectSettings.statusField = settings.status_field;
    if (settings.assignee_field) projectSettings.assigneeField = settings.assignee_field;
    await yt('admin/projects/' + project.id + '/appConfigurations/' + ctx.usages[project.id], { fields: 'id' }, {
      method: 'POST',
      body: { projectSettings: JSON.stringify(projectSettings) }
    });
  }
  if (missing.length) throw new Problem('Aixle Flow sent no event settings for ' + missing.join(', ') + '.');
  return ctx.projects.map((project) => project.shortName).join(', ');
}

// ---------- screens ----------

function renderSteps(progress, options) {
  const opts = options || {};
  show(
    h('h1', null, opts.title || 'Connecting to Aixle Flow'),
    notice('ok', opts.ok),
    notice('error', opts.error),
    opts.title || opts.error ? null : h('p', { class: 'muted small' }, 'If YouTrack asks whether to allow a request from Aixle Flow, allow it.'),
    h('ol', { class: 'steps' }, STEPS.map((step) => {
      const entry = progress[step.key] || { state: 'pending' };
      const mark = { pending: '○', running: h('span', { class: 'spinner' }), done: '✓', failed: '✕' }[entry.state];
      return h('li', { class: entry.state },
        h('span', { class: 'mark', 'aria-hidden': 'true' }, mark),
        h('span', { class: 'title' }, step.title),
        entry.detail ? h('span', { class: 'detail' }, entry.detail) : null);
    })),
    opts.actions ? h('div', { class: 'actions' }, opts.actions) : null
  );
}

async function run(ctx) {
  const progress = {};
  for (const step of STEPS) {
    progress[step.key] = { state: 'running' };
    renderSteps(progress);
    try {
      progress[step.key] = { state: 'done', detail: await step.run(ctx) };
    } catch (e) {
      progress[step.key] = { state: 'failed', detail: describe(e) };
      const fatal = step.key === 'request' && !ctx.result;
      if (fatal) await clearHandover(ctx).catch(() => {});
      return renderSteps(progress, {
        error: fatal ? 'This request cannot be used. Start again.' : 'The setup stopped. Fix the problem, then retry: the steps that are done are safe to repeat.',
        actions: [
          fatal ? null : h('button', { class: 'primary', type: 'button', onclick: () => run(ctx) }, 'Retry'),
          h('button', { type: 'button', onclick: () => navigateTop(ctx.home + '/admin/app/' + APP_NAME + '/connect') }, 'Back to Aixle Flow settings')
        ]
      });
    }
  }
  await clearHandover(ctx).catch(() => {});
  renderDone(ctx, progress);
}

function renderDone(ctx, progress) {
  const returnUrl = sameOrigin(ctx.result.return_url, ctx.flowUrl);
  const names = ctx.projects.map((project) => project.name).join(', ');
  renderSteps(progress, {
    title: 'Connected to Aixle Flow',
    ok: names + (ctx.projects.length === 1 ? ' now sends' : ' now send') + ' issue events to ' + ctx.pairing.project.name + ' in Aixle Flow.',
    actions: [
      returnUrl ? h('button', { class: 'primary', type: 'button', onclick: () => navigateTop(returnUrl) }, 'Return to Aixle Flow') : null,
      h('button', { type: 'button', onclick: () => navigateTop(ctx.home + '/admin/app/' + APP_NAME + '/connect') }, 'Aixle Flow settings')
    ]
  });
}

function navigateTop(url) {
  window.top.location.href = url;
}

function renderIdle(home) {
  show(
    h('h1', null, 'Aixle Flow setup'),
    h('p', null, 'Nothing to set up. To connect YouTrack to Aixle Flow, open Administration › Integrations › Aixle Flow.'),
    h('div', { class: 'actions' },
      h('button', { type: 'button', onclick: () => navigateTop(home + '/admin/app/' + APP_NAME + '/connect') }, 'Open Aixle Flow settings')));
}

// ---------- start ----------

async function start() {
  try {
    host = await YTApp.register();
  } catch (e) {
    show(notice('error', 'This widget must be opened on a YouTrack dashboard.'));
    return;
  }
  if (host.setTitle) host.setTitle(SERVICE_NAME + ' setup');
  const ancestor = (location.ancestorOrigins && location.ancestorOrigins[0]) || '';
  let home = normalizeUrl(ancestor) || '';
  try {
    const config = await yt('config', { fields: 'contextPath' });
    home = normalizeUrl(ancestor + (config.contextPath || '')) || home;
  } catch (e) {
    // The instance origin is enough without a context path.
  }
  let handover = null;
  try {
    handover = await readHandover();
  } catch (e) {
    show(h('h1', null, 'Aixle Flow setup'), notice('error', 'Could not read the setup: ' + describe(e)));
    return;
  }
  if (!handover) return renderIdle(home);
  run({ ref: handover.ref, projectIds: handover.projectIds, home: home });
}

start();
