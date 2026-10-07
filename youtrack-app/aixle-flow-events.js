const entities = require('@jetbrains/youtrack-scripting-api/entities');
const http = require('@jetbrains/youtrack-scripting-api/http');

const PAYLOAD_VERSION = 1;

function isConnected(ctx) {
  return Boolean(ctx.settings.eventsUrl && ctx.settings.secret);
}

function fieldName(ctx, key, fallback) {
  const name = ctx.settings[key];
  return name && String(name).trim() ? String(name).trim() : fallback;
}

function trackedFields(ctx) {
  return {
    status: fieldName(ctx, 'statusField', 'State'),
    assignee: fieldName(ctx, 'assigneeField', 'Assignee')
  };
}

// A project without the named field makes isChanged throw.
function changed(issue, name) {
  try {
    return Boolean(issue.isChanged(name));
  } catch (e) {
    return false;
  }
}

function isCollection(value) {
  return typeof value.forEach === 'function' && typeof value.isEmpty === 'function';
}

function valueName(value) {
  if (value === null || value === undefined) return null;
  if (typeof value !== 'object') return value;
  if (isCollection(value)) {
    const names = [];
    value.forEach((item) => names.push(valueName(item)));
    return names;
  }
  if (value.login) return value.login;
  if (value.name) return value.name;
  return String(value);
}

function change(issue, name) {
  return { from: valueName(issue.oldValue(name)), to: valueName(issue.fields[name]) };
}

function payload(ctx, event, extra) {
  return Object.assign({
    version: PAYLOAD_VERSION,
    event: event,
    issue: ctx.issue.id,
    project: ctx.issue.project.key,
    actor: ctx.currentUser.login,
    at: Date.now()
  }, extra);
}

function events(ctx) {
  const issue = ctx.issue;
  if (issue.becomesReported) return [payload(ctx, 'issue_created', {})];

  const result = [];
  const fields = trackedFields(ctx);
  const changes = {};
  if (changed(issue, fields.status)) changes.status = change(issue, fields.status);
  if (changed(issue, fields.assignee)) changes.assignee = change(issue, fields.assignee);
  if (Object.keys(changes).length) result.push(payload(ctx, 'issue_updated', { changes: changes }));
  if (issue.comments.added.isNotEmpty()) result.push(payload(ctx, 'comment_added', { comments: [] }));
  return result;
}

// The scripting API has no comment id property; the comment's URL carries it.
function commentId(comment) {
  const match = /#focus=Comments-(\d+-\d+)/.exec(String(comment.url || ''));
  return match ? match[1] : null;
}

// Read after commit: inside the transaction `created` is up to a few hundred
// milliseconds earlier than the value YouTrack stores.
function committedComments(ctx) {
  const comments = [];
  const count = Number(ctx.load('comments') || 0);
  for (let i = 0; i < count; i += 1) {
    const comment = ctx.load('comment' + i);
    if (comment) comments.push({ id: commentId(comment), author: comment.author.login, created: comment.created });
  }
  return comments;
}

// A script execution may schedule only one async call, so events leave one per
// step: the action schedules `deliver`, and each response schedules the next.
function sendNext(ctx) {
  if (!isConnected(ctx)) return;
  const queue = JSON.parse(ctx.load('queue') || '[]');
  let next = queue.shift();
  while (next && next.event === 'comment_added') {
    next.comments = committedComments(ctx);
    if (next.comments.length) break;
    next = queue.shift();
  }
  if (!next) return;
  ctx.store('queue', JSON.stringify(queue));
  const connection = new http.Connection(ctx.settings.eventsUrl);
  connection.addHeader('Content-Type', 'application/json');
  // A secret setting must reach addHeader as is: concatenating it yields the mask.
  connection.addHeader('X-Aixle-Token', ctx.settings.secret);
  connection.postAsync('', null, JSON.stringify(next), 'delivered');
}

exports.rule = entities.Issue.onChange({
  title: 'Aixle Flow: send issue events',
  guard: (ctx) => {
    try {
      if (!isConnected(ctx)) return false;
      const issue = ctx.issue;
      if (!issue.isReported) return false;
      if (issue.becomesReported || issue.comments.added.isNotEmpty()) return true;
      const fields = trackedFields(ctx);
      return changed(issue, fields.status) || changed(issue, fields.assignee);
    } catch (e) {
      console.error('Aixle Flow: could not check the change: ' + e);
      return false;
    }
  },
  // An exception here would reject the user's change, so nothing may escape.
  action: (ctx) => {
    try {
      const queue = events(ctx);
      if (!queue.length) return;
      let count = 0;
      ctx.issue.comments.added.forEach((comment) => {
        ctx.store('comment' + count, comment);
        count += 1;
      });
      ctx.store('comments', count);
      ctx.store('queue', JSON.stringify(queue));
      ctx.invokeAsync('deliver');
    } catch (e) {
      console.error('Aixle Flow: could not send an event for ' + ctx.issue.id + ': ' + e);
    }
  },
  asyncFunctions: {
    deliver: (ctx) => {
      try {
        sendNext(ctx);
      } catch (e) {
        console.error('Aixle Flow: could not send an event: ' + e);
      }
    },
    delivered: (ctx) => {
      try {
        const response = ctx.response;
        if (!response.isSuccess) {
          const body = response.body ? String(response.body).substring(0, 500) : '';
          console.warn('Aixle Flow: the events URL answered ' + (response.code || response.exception) + ' ' + body);
        }
        sendNext(ctx);
      } catch (e) {
        console.error('Aixle Flow: could not send an event: ' + e);
      }
    }
  }
});
