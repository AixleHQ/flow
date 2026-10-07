'use strict';

const APP_NAME = 'aixle-flow';
const SERVICE_LOGIN = 'aixle-flow';
const SETUP_WIDGET_KEY = 'setup';
const DASHBOARD_NAME = 'Aixle Flow setup';
const DEFAULT_FLOW_URL = 'https://flow.aixle.com';
const POLL_MS = 2500;

const root = document.getElementById('root');
const state = {
  host: null,
  app: null,
  me: null,
  instance: null,
  home: null,
  flowUrl: DEFAULT_FLOW_URL,
  projects: [],
  connected: new Set(),
  ref: null,
  pollTimer: null,
  expiresAt: null
};

// ---------- DOM ----------

function h(tag, attrs, ...children) {
  const el = document.createElement(tag);
  Object.entries(attrs || {}).forEach(([name, value]) => {
    if (value === null || value === undefined || value === false) return;
    if (name.startsWith('on')) el.addEventListener(name.slice(2), value);
    else if (name === 'class') el.className = value;
    else if (name === 'checked' || name === 'disabled' || name === 'value') el[name] = value;
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

function header() {
  return [
    h('h1', null, 'Aixle Flow'),
    h('p', { class: 'lead' },
      'Aixle Flow runs AI agents on your YouTrack issues. Connecting creates the password-less service user ',
      h('code', null, SERVICE_LOGIN),
      ', adds it to the projects you choose, hands its token to Aixle Flow and sends those projects’ issue events there.')
  ];
}

function loading(text) {
  show(...header(), h('p', { class: 'muted' }, h('span', { class: 'spinner' }), text));
}

function notice(kind, text) {
  return text ? h('div', { class: 'notice ' + kind, role: kind === 'error' ? 'alert' : 'status' }, text) : null;
}

// ---------- errors ----------

class Problem extends Error {}

function describe(error) {
  if (!error) return 'Unknown error';
  if (error instanceof Problem) return error.message;
  const data = error.data || {};
  const detail = data.error_description || data.error_message || data.message || data.error;
  const status = error.status ? 'HTTP ' + error.status : '';
  const text = [detail, error.message].filter(Boolean).filter((v, i, all) => all.indexOf(v) === i).join(' — ');
  return [status, text].filter(Boolean).join(': ') || String(error);
}

// ---------- YouTrack ----------

function yt(path, query, options) {
  return state.host.fetchYouTrack(path, Object.assign({ query: query || {} }, options || {}));
}

function normalizeUrl(value) {
  try {
    const url = new URL(String(value).trim());
    return (url.origin + url.pathname).replace(/\/+$/, '');
  } catch (e) {
    return null;
  }
}

function parseSettings(json) {
  try {
    return JSON.parse(json || '{}') || {};
  } catch (e) {
    return {};
  }
}

async function findAppId() {
  if (window.YTApp && YTApp.widget && YTApp.widget.appId) return YTApp.widget.appId;
  const apps = await yt('admin/apps', { fields: 'id,name', $top: 1000 });
  const found = apps.find((app) => app.name === APP_NAME);
  if (!found) throw new Problem('The app “' + APP_NAME + '” is not installed here.');
  return found.id;
}

async function loadContext() {
  const [appId, me, system, config, projects] = await Promise.all([
    findAppId(),
    yt('users/me', { fields: 'id,login' }),
    yt('admin/globalSettings/systemSettings', { fields: 'baseUrl' }).catch(() => ({})),
    yt('config', { fields: 'contextPath' }).catch(() => ({})),
    yt('admin/projects', { fields: 'id,shortName,name,archived', $top: 5000 })
  ]);
  state.app = await yt('admin/apps/' + appId, {
    fields: 'id,name,version,globalConfig(globalSettings),usages(id,projectSettings,project(id)),widgets(id,key)'
  });
  state.me = me;
  const ancestor = (location.ancestorOrigins && location.ancestorOrigins[0]) || '';
  const browserHome = ancestor ? normalizeUrl(ancestor + (config.contextPath || '')) : null;
  state.instance = normalizeUrl(system.baseUrl) || browserHome;
  state.home = browserHome || state.instance;
  const global = parseSettings(state.app.globalConfig && state.app.globalConfig.globalSettings);
  state.flowUrl = normalizeUrl(global.flowUrl) || DEFAULT_FLOW_URL;
  state.projects = projects
    .filter((project) => !project.archived)
    .sort((a, b) => a.name.localeCompare(b.name));
  state.connected = new Set(
    (state.app.usages || [])
      .filter((usage) => usage.project && parseSettings(usage.projectSettings).eventsUrl)
      .map((usage) => usage.project.id)
  );
}

function isThisInstance(url) {
  const candidate = normalizeUrl(url);
  return Boolean(candidate) && [state.instance, state.home].some((own) => own && own.toLowerCase() === candidate.toLowerCase());
}

// ---------- Aixle ----------

async function aixle(method, path, secret, body) {
  const headers = { Accept: 'application/json' };
  if (secret) headers.Authorization = 'Bearer ' + secret;
  if (body) headers['Content-Type'] = 'application/json';
  let response;
  try {
    response = await fetch(state.flowUrl + path, {
      method: method,
      headers: headers,
      body: body ? JSON.stringify(body) : undefined,
      credentials: 'omit',
      cache: 'no-store'
    });
  } catch (e) {
    throw new Problem('Could not reach Aixle Flow at ' + state.flowUrl + '. Check the Aixle Flow URL and your network.');
  }
  let data = null;
  try {
    data = await response.json();
  } catch (e) {
    data = null;
  }
  if (!response.ok) {
    const message = data && (data.message || data.error);
    if (response.status === 404 || response.status === 401) {
      throw new Problem(message || 'Aixle Flow does not know this request any more. Start again from Aixle Flow.');
    }
    throw new Problem('Aixle Flow answered HTTP ' + response.status + (message ? ': ' + message : '.'));
  }
  return data;
}

function readPairing(ref) {
  return aixle('GET', '/integrations/youtrack/pairings/' + encodeURIComponent(ref.id), ref.secret);
}

function flowLink(value) {
  try {
    const url = new URL(value);
    return url.origin === new URL(state.flowUrl).origin ? url.href : null;
  } catch (e) {
    return null;
  }
}

// ---------- pairing reference in the URL ----------

function parseRef(value) {
  if (!value) return null;
  const dot = value.indexOf('.');
  if (dot < 1 || dot === value.length - 1) return null;
  return { id: value.slice(0, dot), secret: value.slice(dot + 1) };
}

async function takeRefFromLocation() {
  if (!state.host.navigation) return null;
  let place;
  try {
    place = await state.host.navigation.getAppLocation();
  } catch (e) {
    return null;
  }
  const fromHash = new URLSearchParams(place.hash || '');
  const fromSearch = new URLSearchParams(place.search || '');
  const value = fromHash.get('pairing') || fromSearch.get('pairing');
  if (!value) return null;
  fromHash.delete('pairing');
  fromSearch.delete('pairing');
  try {
    await state.host.navigation.replaceAppLocation({ hash: fromHash.toString(), search: fromSearch.toString() });
  } catch (e) {
    // The secret stays in the address bar; the pairing is single-use and short-lived.
  }
  return parseRef(value);
}

// ---------- screens ----------

function stopPolling() {
  clearTimeout(state.pollTimer);
  state.pollTimer = null;
}

function renderStatus(message) {
  stopPolling();
  state.ref = null;
  const connected = state.projects.filter((project) => state.connected.has(project.id));
  show(
    ...header(),
    notice('error', message),
    h('section', { class: 'card' },
      h('h2', null, 'Connected projects'),
      connected.length
        ? h('ul', { class: 'projects' }, connected.map((project) =>
          h('li', null,
            h('span', { class: 'name' }, project.name, ' ', h('span', { class: 'key' }, project.shortName)),
            h('span', { class: 'badge ok' }, 'Connected'))))
        : h('p', { class: 'muted' }, 'No project is connected yet.'),
      h('div', { class: 'actions' },
        h('button', { class: 'primary', type: 'button', onclick: startPairing }, 'Connect to Aixle Flow')),
      h('p', { class: 'muted small' },
        'You can also start in Aixle Flow: open a project’s Trackers page and choose Connect YouTrack.')),
    flowUrlCard()
  );
}

function flowUrlCard() {
  return h('section', { class: 'card' },
    h('h2', null, 'Aixle Flow URL'),
    h('p', null, h('code', null, state.flowUrl)),
    h('p', { class: 'muted small' }, 'The Aixle Flow deployment this YouTrack connects to. Change it only for a self-hosted or staging Aixle Flow.'),
    h('div', { class: 'actions' }, h('button', { type: 'button', onclick: renderFlowUrlEditor }, 'Change')));
}

function renderFlowUrlEditor(_event, message, draft) {
  stopPolling();
  const input = h('input', { type: 'url', id: 'flow-url', value: draft === undefined ? state.flowUrl : draft, placeholder: DEFAULT_FLOW_URL, autocomplete: 'off' });
  const save = async () => {
    const raw = input.value.trim();
    const value = raw ? normalizeUrl(raw) : DEFAULT_FLOW_URL;
    const problem = validateFlowUrl(value);
    if (problem) return renderFlowUrlEditor(null, problem, raw);
    loading('Saving…');
    try {
      const settings = value === DEFAULT_FLOW_URL ? {} : { flowUrl: value };
      await yt('admin/apps/' + state.app.id + '/globalConfig', { fields: 'id' }, {
        method: 'POST',
        body: { globalSettings: JSON.stringify(settings) }
      });
      state.flowUrl = value;
      renderStatus();
    } catch (e) {
      renderFlowUrlEditor(null, 'Could not save: ' + describe(e), raw);
    }
  };
  show(
    ...header(),
    h('section', { class: 'card' },
      h('h2', null, 'Aixle Flow URL'),
      notice('error', message),
      h('p', null, h('label', { for: 'flow-url' }, 'The address of your Aixle Flow, for example ', h('code', null, DEFAULT_FLOW_URL), '.')),
      input,
      h('p', { class: 'muted small' }, 'Projects that are already connected keep sending events to the Aixle Flow they were connected to.'),
      h('div', { class: 'actions' },
        h('button', { class: 'primary', type: 'button', onclick: save }, 'Save'),
        h('button', { type: 'button', onclick: () => renderStatus() }, 'Cancel'))));
  input.focus();
}

function validateFlowUrl(value) {
  if (!value) return 'Enter a full URL, such as ' + DEFAULT_FLOW_URL + '.';
  const url = new URL(value);
  const local = url.hostname === 'localhost' || url.hostname === '127.0.0.1';
  if (url.protocol !== 'https:' && !(url.protocol === 'http:' && local)) return 'The Aixle Flow URL must use https.';
  if (url.search || url.hash) return 'The Aixle Flow URL cannot have a query or a fragment.';
  return null;
}

function renderRefused(message) {
  stopPolling();
  state.ref = null;
  show(
    ...header(),
    h('section', { class: 'card' },
      h('h2', null, 'This request cannot be used'),
      notice('error', message),
      h('div', { class: 'actions' }, h('button', { type: 'button', onclick: () => renderStatus() }, 'Back'))));
}

async function startPairing() {
  stopPolling();
  // Opened inside the click so the popup blocker lets it through; it is pointed at Aixle once the pairing exists.
  const popup = window.open('', 'aixle-flow-connect', 'popup,width=560,height=760');
  loading('Starting the connection…');
  let pairing;
  try {
    pairing = await aixle('POST', '/integrations/youtrack/pairings', null, { instance_url: state.instance });
  } catch (e) {
    if (popup) popup.close();
    return renderStatus(describe(e));
  }
  state.ref = { id: pairing.id, secret: pairing.secret };
  state.expiresAt = pairing.expires_at ? new Date(pairing.expires_at) : null;
  const approveUrl = flowLink(pairing.approve_url);
  if (popup && approveUrl) {
    try {
      popup.opener = null;
      popup.location.href = approveUrl;
    } catch (e) {
      popup.close();
    }
  } else if (popup) {
    popup.close();
  }
  renderCode(pairing.code, approveUrl);
  poll();
}

function renderCode(code, approveUrl) {
  const open = () => {
    const popup = window.open(approveUrl, 'aixle-flow-connect', 'popup,width=560,height=760');
    if (popup) popup.opener = null;
  };
  show(
    ...header(),
    h('section', { class: 'card' },
      h('h2', null, 'Enter this code in Aixle Flow'),
      h('div', { class: 'code', 'aria-label': 'Connection code' }, code),
      h('p', null, 'Sign in to Aixle Flow in the window that opened, enter the code, choose the Aixle project and approve. This page continues by itself.'),
      state.expiresAt ? h('p', { class: 'muted small' }, 'The code expires at ' + state.expiresAt.toLocaleTimeString() + '.') : null,
      h('p', { class: 'muted' }, h('span', { class: 'spinner' }), 'Waiting for approval in Aixle Flow…'),
      h('div', { class: 'actions' },
        approveUrl ? h('button', { type: 'button', onclick: open }, 'Open Aixle Flow') : null,
        h('button', { type: 'button', onclick: () => renderStatus() }, 'Cancel'))));
}

function poll() {
  stopPolling();
  state.pollTimer = setTimeout(async () => {
    const ref = state.ref;
    if (!ref) return;
    if (state.expiresAt && Date.now() > state.expiresAt.getTime()) {
      return renderRefused('The code expired before it was approved. Start again.');
    }
    try {
      const pairing = await readPairing(ref);
      if (state.ref !== ref) return;
      if (pairing.status === 'pending') return poll();
      handlePairing(pairing);
    } catch (e) {
      if (state.ref !== ref) return;
      if (e instanceof Problem && /Could not reach/.test(e.message)) return poll();
      renderRefused(describe(e));
    }
  }, POLL_MS);
}

async function openPairing(ref) {
  state.ref = ref;
  state.expiresAt = null;
  loading('Reading the request from Aixle Flow…');
  try {
    handlePairing(await readPairing(ref));
  } catch (e) {
    renderRefused(describe(e));
  }
}

function handlePairing(pairing) {
  if (!isThisInstance(pairing.instance_url)) {
    return renderRefused('This request is for ' + pairing.instance_url + ', but this YouTrack is ' + state.instance + '.');
  }
  switch (pairing.status) {
    case 'approved':
      if (!pairing.company || !pairing.project) return renderRefused('Aixle Flow did not say which project this connects to.');
      return renderConsent(pairing);
    case 'pending':
      show(...header(), h('section', { class: 'card' },
        h('p', { class: 'muted' }, h('span', { class: 'spinner' }), 'Waiting for the request to be approved in Aixle Flow…'),
        pairing.code ? h('p', null, 'Code: ', h('strong', null, pairing.code)) : null,
        h('div', { class: 'actions' }, h('button', { type: 'button', onclick: () => renderStatus() }, 'Cancel'))));
      return poll();
    case 'completed':
      return renderRefused('This request has already been used. Start again from Aixle Flow if you want to connect again.');
    case 'expired':
      return renderRefused('This request has expired. Start again from Aixle Flow.');
    default:
      return renderRefused('Aixle Flow answered with an unknown status “' + pairing.status + '”.');
  }
}

function renderConsent(pairing, message) {
  stopPolling();
  const ref = state.ref;
  const boxes = state.projects.map((project) => h('input', { type: 'checkbox', value: project.id }));
  const approve = h('button', { class: 'primary', type: 'button', disabled: true }, 'Approve');
  const selected = () => boxes.filter((box) => box.checked).map((box) => box.value);
  const sync = () => { approve.disabled = selected().length === 0; };
  boxes.forEach((box) => box.addEventListener('change', sync));
  const all = h('input', {
    type: 'checkbox',
    onchange: (event) => { boxes.forEach((box) => { box.checked = event.target.checked; }); sync(); }
  });
  approve.addEventListener('click', () => stageSetup(pairing, ref, selected()));

  show(
    ...header(),
    h('section', { class: 'card' },
      notice('error', message),
      h('h2', null, 'Connect this YouTrack to'),
      h('div', { class: 'target' },
        h('div', { class: 'label' }, 'Aixle company'),
        h('div', { class: 'company' }, pairing.company.name),
        h('div', { class: 'label' }, 'Aixle project'),
        h('div', { class: 'project' }, pairing.project.name)),
      h('dl', { class: 'facts' },
        h('dt', null, 'Requested by'), h('dd', null, pairing.approved_by ? pairing.approved_by.name : 'unknown'),
        h('dt', null, 'This YouTrack'), h('dd', null, state.instance),
        h('dt', null, 'Aixle Flow'), h('dd', null, state.flowUrl)),
      h('p', null,
        'Approve only if you expect this. Aixle Flow will act in the projects you choose as the service user ',
        h('code', null, SERVICE_LOGIN),
        ', and receive their issue events: new issues, state and assignee changes, and who commented when (never the comment text).'),
      h('h2', null, 'YouTrack projects'),
      state.projects.length
        ? [
          h('label', { class: 'muted small' }, all, ' Select all'),
          h('ul', { class: 'projects' }, state.projects.map((project, index) =>
            h('li', null,
              h('label', null, boxes[index],
                h('span', null, project.name, ' ', h('span', { class: 'key' }, project.shortName))),
              state.connected.has(project.id) ? h('span', { class: 'badge ok', title: 'Approving moves it to this Aixle project' }, 'Connected') : null)))
        ]
        : h('p', { class: 'muted' }, 'There are no projects to connect.'),
      h('p', { class: 'muted small' },
        'YouTrack will ask you to allow the changes this makes: the setup dashboard, the service user and its token, and the projects’ teams and settings. Allow them, or the setup stops.'),
      h('div', { class: 'actions' },
        approve,
        h('button', { type: 'button', onclick: () => renderStatus() }, 'Cancel'))));
}

async function stageSetup(pairing, ref, projectIds) {
  if (!projectIds.length) return;
  loading('Preparing the setup…');
  try {
    const widget = (state.app.widgets || []).find((item) => item.key === SETUP_WIDGET_KEY);
    if (!widget) throw new Problem('The setup widget is missing from this app version.');
    const embedding = {
      key: 'aixle-flow-setup',
      widget: { id: widget.id },
      x: 0,
      y: 0,
      width: 8,
      height: 10,
      settings: JSON.stringify({ handover: JSON.stringify({ pairing: ref.id + '.' + ref.secret, projects: projectIds }) })
    };
    const dashboards = await yt('dashboards', { fields: 'id,name,owner(id)', $top: 1000 });
    const existing = dashboards.find((board) => board.name === DASHBOARD_NAME && board.owner && board.owner.id === state.me.id);
    const board = existing
      ? await yt('dashboards/' + existing.id, { fields: 'id' }, { method: 'POST', body: { widgets: [embedding] } })
      : await yt('dashboards', { fields: 'id' }, { method: 'POST', body: { name: DASHBOARD_NAME, widgets: [embedding] } });
    window.top.location.href = state.home + '/dashboard?id=' + encodeURIComponent(board.id);
  } catch (e) {
    renderConsent(pairing, 'Could not prepare the setup: ' + describe(e));
  }
}

// ---------- start ----------

async function boot() {
  loading('Loading…');
  try {
    await loadContext();
  } catch (e) {
    show(...header(), notice('error', 'Could not load the app: ' + describe(e)),
      h('div', { class: 'actions' }, h('button', { type: 'button', onclick: boot }, 'Retry')));
    return;
  }
  const ref = await takeRefFromLocation();
  if (ref) openPairing(ref);
  else renderStatus();
}

async function start() {
  try {
    state.host = await YTApp.register();
  } catch (e) {
    show(notice('error', 'This page must be opened inside YouTrack.'));
    return;
  }
  boot();
}

start();
