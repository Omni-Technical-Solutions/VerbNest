/// The JavaScript runtime that gives scripts `pm`, `console` and a Chai-style
/// `pm.expect` (FR-SCR-002/003). It has no access to files or sockets: the
/// engine is created without any host modules, so everything a script can
/// touch is defined here.
const scriptPrelude = r'''
"use strict";
var __UNSUPPORTED = ['sendRequest', 'cookies', 'visualizer', 'execution',
  'iterationData', 'vault', 'require'];

function __fail(msg) { var e = new Error(msg); e.__assertion = true; throw e; }
function __str(v) {
  if (typeof v === 'string') return JSON.stringify(v);
  if (v === undefined) return 'undefined';
  if (typeof v === 'function') return '[Function]';
  try { var s = JSON.stringify(v); return s === undefined ? String(v) : s; }
  catch (e) { return String(v); }
}
function __typeOf(v) {
  if (v === null) return 'null';
  if (Array.isArray(v)) return 'array';
  if (v instanceof Date) return 'date';
  if (v instanceof RegExp) return 'regexp';
  return typeof v;
}
function __deepEqual(a, b) {
  if (a === b) return true;
  if (typeof a !== typeof b) return false;
  if (a !== a && b !== b) return true;
  if (a && b && typeof a === 'object') {
    if (Array.isArray(a) !== Array.isArray(b)) return false;
    if (a instanceof Date && b instanceof Date) return a.getTime() === b.getTime();
    var ka = Object.keys(a), kb = Object.keys(b);
    if (ka.length !== kb.length) return false;
    for (var i = 0; i < ka.length; i++) {
      if (!Object.prototype.hasOwnProperty.call(b, ka[i])) return false;
      if (!__deepEqual(a[ka[i]], b[ka[i]])) return false;
    }
    return true;
  }
  return false;
}

function Assertion(obj, flags) { this._obj = obj; this._not = !!(flags && flags.not); this._deep = !!(flags && flags.deep); }
['to', 'be', 'been', 'is', 'that', 'which', 'and', 'has', 'have', 'with', 'at', 'of', 'same', 'but', 'does', 'still', 'also'].forEach(function (w) {
  Object.defineProperty(Assertion.prototype, w, { get: function () { return this; } });
});
Object.defineProperty(Assertion.prototype, 'not', { get: function () { this._not = !this._not; return this; } });
Object.defineProperty(Assertion.prototype, 'deep', { get: function () { this._deep = true; return this; } });
Assertion.prototype._assert = function (ok, msg, negMsg) {
  if (this._not ? ok : !ok) __fail(this._not ? negMsg : msg);
  return this;
};
function __getter(name, fn) {
  Object.defineProperty(Assertion.prototype, name, { get: function () { fn.call(this); return this; } });
}
function __method(names, fn) {
  names.forEach(function (n) { Assertion.prototype[n] = fn; });
}
__getter('ok', function () { this._assert(!!this._obj, 'expected ' + __str(this._obj) + ' to be truthy', 'expected ' + __str(this._obj) + ' to be falsy'); });
__getter('true', function () { this._assert(this._obj === true, 'expected ' + __str(this._obj) + ' to be true', 'expected ' + __str(this._obj) + ' not to be true'); });
__getter('false', function () { this._assert(this._obj === false, 'expected ' + __str(this._obj) + ' to be false', 'expected ' + __str(this._obj) + ' not to be false'); });
__getter('null', function () { this._assert(this._obj === null, 'expected ' + __str(this._obj) + ' to be null', 'expected value not to be null'); });
__getter('undefined', function () { this._assert(this._obj === undefined, 'expected ' + __str(this._obj) + ' to be undefined', 'expected value not to be undefined'); });
__getter('NaN', function () { this._assert(this._obj !== this._obj, 'expected ' + __str(this._obj) + ' to be NaN', 'expected value not to be NaN'); });
__getter('exist', function () { this._assert(this._obj !== null && this._obj !== undefined, 'expected value to exist', 'expected ' + __str(this._obj) + ' not to exist'); });
__getter('empty', function () {
  var o = this._obj, n;
  if (typeof o === 'string' || Array.isArray(o)) n = o.length; else if (o && typeof o === 'object') n = Object.keys(o).length; else __fail('.empty needs a string, array or object');
  this._assert(n === 0, 'expected ' + __str(o) + ' to be empty', 'expected ' + __str(o) + ' not to be empty');
});
__getter('arguments', function () {});
__method(['equal', 'equals', 'eq'], function (v) {
  var ok = this._deep ? __deepEqual(this._obj, v) : this._obj === v;
  return this._assert(ok, 'expected ' + __str(this._obj) + ' to equal ' + __str(v), 'expected ' + __str(this._obj) + ' not to equal ' + __str(v));
});
__method(['eql', 'eqls'], function (v) {
  return this._assert(__deepEqual(this._obj, v), 'expected ' + __str(this._obj) + ' to deeply equal ' + __str(v), 'expected ' + __str(this._obj) + ' not to deeply equal ' + __str(v));
});
__method(['a', 'an'], function (t) {
  var actual = __typeOf(this._obj);
  return this._assert(actual === String(t).toLowerCase(), 'expected ' + __str(this._obj) + ' to be a ' + t + ' but it is ' + actual, 'expected ' + __str(this._obj) + ' not to be a ' + t);
});
__method(['include', 'includes', 'contain', 'contains'], function (v) {
  var o = this._obj, ok;
  if (typeof o === 'string') ok = o.indexOf(v) !== -1;
  else if (Array.isArray(o)) ok = this._deep ? o.some(function (x) { return __deepEqual(x, v); }) : o.indexOf(v) !== -1;
  else if (o && typeof o === 'object' && v && typeof v === 'object') ok = Object.keys(v).every(function (k) { return __deepEqual(o[k], v[k]); });
  else __fail('.include needs a string, array or object');
  return this._assert(ok, 'expected ' + __str(o) + ' to include ' + __str(v), 'expected ' + __str(o) + ' not to include ' + __str(v));
});
__method(['property'], function (name, value) {
  var o = this._obj;
  var has = o !== null && o !== undefined && Object(o).hasOwnProperty(name) || (o !== null && o !== undefined && name in Object(o));
  if (arguments.length > 1) {
    var same = has && (this._deep ? __deepEqual(o[name], value) : o[name] === value);
    this._assert(same, 'expected ' + __str(o) + ' to have property ' + __str(name) + ' of ' + __str(value), 'expected ' + __str(o) + ' not to have property ' + __str(name) + ' of ' + __str(value));
  } else {
    this._assert(has, 'expected ' + __str(o) + ' to have property ' + __str(name), 'expected ' + __str(o) + ' not to have property ' + __str(name));
  }
  if (has) this._obj = o[name];
  return this;
});
__method(['keys', 'key'], function () {
  var want = Array.prototype.slice.call(arguments);
  if (want.length === 1 && Array.isArray(want[0])) want = want[0];
  var have = Object.keys(this._obj);
  var ok = want.every(function (k) { return have.indexOf(k) !== -1; });
  return this._assert(ok, 'expected ' + __str(this._obj) + ' to have keys ' + __str(want), 'expected ' + __str(this._obj) + ' not to have keys ' + __str(want));
});
__method(['lengthOf', 'length', 'lengthof'], function (n) {
  var len = this._obj === null || this._obj === undefined ? undefined : this._obj.length;
  return this._assert(len === n, 'expected length ' + len + ' to equal ' + n, 'expected length not to equal ' + n);
});
__method(['above', 'gt', 'greaterThan'], function (n) { return this._assert(this._obj > n, 'expected ' + __str(this._obj) + ' to be above ' + n, 'expected ' + __str(this._obj) + ' not to be above ' + n); });
__method(['least', 'gte'], function (n) { return this._assert(this._obj >= n, 'expected ' + __str(this._obj) + ' to be at least ' + n, 'expected ' + __str(this._obj) + ' not to be at least ' + n); });
__method(['below', 'lt', 'lessThan'], function (n) { return this._assert(this._obj < n, 'expected ' + __str(this._obj) + ' to be below ' + n, 'expected ' + __str(this._obj) + ' not to be below ' + n); });
__method(['most', 'lte'], function (n) { return this._assert(this._obj <= n, 'expected ' + __str(this._obj) + ' to be at most ' + n, 'expected ' + __str(this._obj) + ' not to be at most ' + n); });
__method(['within'], function (a, b) { return this._assert(this._obj >= a && this._obj <= b, 'expected ' + __str(this._obj) + ' to be within ' + a + '..' + b, 'expected ' + __str(this._obj) + ' not to be within ' + a + '..' + b); });
__method(['match', 'matches'], function (re) { return this._assert(re.test(this._obj), 'expected ' + __str(this._obj) + ' to match ' + re, 'expected ' + __str(this._obj) + ' not to match ' + re); });
__method(['string'], function (s) { return this._assert(typeof this._obj === 'string' && this._obj.indexOf(s) !== -1, 'expected ' + __str(this._obj) + ' to contain ' + __str(s), 'expected ' + __str(this._obj) + ' not to contain ' + __str(s)); });
__method(['oneOf'], function (list) { return this._assert(list.indexOf(this._obj) !== -1, 'expected ' + __str(this._obj) + ' to be one of ' + __str(list), 'expected ' + __str(this._obj) + ' not to be one of ' + __str(list)); });
__method(['instanceOf', 'instanceof'], function (c) { return this._assert(this._obj instanceof c, 'expected value to be an instance of ' + (c && c.name), 'expected value not to be an instance of ' + (c && c.name)); });
__method(['throw', 'throws', 'Throw'], function (matcher) {
  var threw = false, err;
  try { this._obj(); } catch (e) { threw = true; err = e; }
  var ok = threw;
  if (threw && matcher !== undefined) {
    var msg = err && err.message !== undefined ? err.message : String(err);
    ok = matcher instanceof RegExp ? matcher.test(msg) : (typeof matcher === 'string' ? msg.indexOf(matcher) !== -1 : true);
  }
  return this._assert(ok, 'expected function to throw', 'expected function not to throw');
});

function __makeExpect() {
  var expect = function (v) { return new Assertion(v); };
  expect.fail = function (m) { __fail(m || 'expect.fail()'); };
  return expect;
}

function __run(inputText, code) {
  var input = JSON.parse(inputText);
  var logs = [], tests = [];
  var changes = { local: {}, environment: {}, collection: {}, globals: {} };
  var request = input.request;
  var isPre = input.phase === 'pre';

  function fmt(args) {
    return Array.prototype.map.call(args, function (a) {
      return typeof a === 'string' ? a : __str(a);
    }).join(' ');
  }
  var console = {};
  ['log', 'info', 'warn', 'error', 'debug'].forEach(function (lvl) {
    console[lvl] = function () { if (logs.length < 1000) logs.push({ level: lvl, text: fmt(arguments) }); };
  });

  function scope(name) {
    var vals = input.variables[name] || {};
    var s = {
      get: function (k) { return Object.prototype.hasOwnProperty.call(vals, k) ? vals[k] : undefined; },
      has: function (k) { return Object.prototype.hasOwnProperty.call(vals, k); },
      set: function (k, v) { vals[k] = v === undefined ? 'undefined' : (typeof v === 'string' ? v : (typeof v === 'object' && v !== null ? JSON.stringify(v) : String(v))); changes[name][k] = vals[k]; },
      unset: function (k) { delete vals[k]; changes[name][k] = null; },
      clear: function () { Object.keys(vals).forEach(function (k) { s.unset(k); }); },
      toObject: function () { var o = {}; Object.keys(vals).forEach(function (k) { o[k] = vals[k]; }); return o; },
      replaceIn: function (t) { return replaceIn(t); }
    };
    return s;
  }
  var scopes = { local: scope('local'), environment: scope('environment'), collection: scope('collection'), globals: scope('globals') };
  function lookup(k) {
    var order = ['local', 'environment', 'collection', 'globals'];
    for (var i = 0; i < order.length; i++) if (scopes[order[i]].has(k)) return scopes[order[i]].get(k);
    return undefined;
  }
  function replaceIn(t) {
    if (typeof t !== 'string') return t;
    return t.replace(/\{\{\s*([^{}\s]+)\s*\}\}/g, function (m, k) { var v = lookup(k); return v === undefined ? m : v; });
  }
  var variables = {
    get: lookup,
    has: function (k) { return lookup(k) !== undefined; },
    set: scopes.local.set, unset: scopes.local.unset, clear: scopes.local.clear,
    replaceIn: replaceIn,
    toObject: function () {
      var o = {};
      ['globals', 'collection', 'environment', 'local'].forEach(function (n) { var t = scopes[n].toObject(); Object.keys(t).forEach(function (k) { o[k] = t[k]; }); });
      return o;
    }
  };
  var environment = Object.assign({}, scopes.environment, { name: input.environmentName });

  function headerList(list) {
    return {
      get: function (n) { var l = String(n).toLowerCase(); for (var i = 0; i < list.length; i++) if (list[i].key.toLowerCase() === l) return list[i].value; return undefined; },
      has: function (n) { return this.get(n) !== undefined; },
      add: function (h) { list.push({ key: String(h.key), value: String(h.value) }); },
      upsert: function (h) {
        var l = String(h.key).toLowerCase();
        for (var i = 0; i < list.length; i++) if (list[i].key.toLowerCase() === l) { list[i].value = String(h.value); return; }
        list.push({ key: String(h.key), value: String(h.value) });
      },
      remove: function (n) { var l = String(n).toLowerCase(); for (var i = list.length - 1; i >= 0; i--) if (list[i].key.toLowerCase() === l) list.splice(i, 1); },
      toObject: function () { var o = {}; list.forEach(function (h) { o[h.key] = h.value; }); return o; },
      all: function () { return list.map(function (h) { return { key: h.key, value: h.value }; }); },
      each: function (fn) { list.forEach(fn); },
      get length() { return list.length; }
    };
  }

  function urlObject(raw) {
    var m = /^(?:([a-zA-Z][a-zA-Z0-9+.-]*):\/\/)?([^\/?#]*)([^?#]*)(?:\?([^#]*))?(?:#.*)?$/.exec(raw) || [];
    return {
      raw: raw,
      protocol: m[1],
      host: m[2] ? m[2].split('.') : [],
      path: m[3] ? m[3].split('/').filter(function (p) { return p; }) : [],
      getHost: function () { return m[2] || ''; },
      getPath: function () { return m[3] || '/'; },
      getQueryString: function () { return m[4] || ''; },
      toString: function () { return raw; }
    };
  }

  var pmRequest = {
    get method() { return request.method; },
    set method(v) { request.method = String(v); },
    get url() { return urlObject(request.url); },
    set url(v) { request.url = String(v); },
    headers: headerList(request.headers),
    body: {
      get raw() { return request.body; },
      set raw(v) { request.body = String(v); },
      toString: function () { return request.body || ''; }
    },
    name: input.requestName,
    id: input.requestId
  };

  var pmResponse;
  if (!isPre && input.response) {
    var r = input.response;
    var rh = headerList(r.headers);
    pmResponse = {
      code: r.code, status: r.status, headers: rh,
      responseTime: r.time, responseSize: r.size,
      text: function () { return r.body; },
      json: function () { return JSON.parse(r.body); },
      reason: function () { return r.status; }
    };
    function range(lo, hi) { return r.code >= lo && r.code < hi; }
    var respAssert = {
      status: function (v) {
        var ok = typeof v === 'number' ? r.code === v : r.status === v;
        if (!ok) __fail('expected response to have status code ' + v + ' but got ' + r.code);
      },
      header: function (n, v) {
        var got = rh.get(n);
        if (got === undefined) __fail('expected response to have header ' + n);
        if (v !== undefined && got !== v) __fail('expected header ' + n + ' to be ' + v + ' but got ' + got);
      },
      jsonBody: function (path, v) {
        var j = JSON.parse(r.body);
        if (path === undefined) return;
        if (typeof path === 'object') { if (!__deepEqual(j, path)) __fail('expected JSON body to match'); return; }
        if (!(path in j)) __fail('expected JSON body to have ' + path);
        if (v !== undefined && !__deepEqual(j[path], v)) __fail('expected JSON ' + path + ' to be ' + __str(v));
      },
      body: function (v) {
        if (v instanceof RegExp ? !v.test(r.body) : r.body !== v) __fail('expected response body to match');
      }
    };
    var chain = { have: respAssert, be: {} };
    Object.defineProperty(chain.be, 'ok', { get: function () { if (!range(200, 300)) __fail('expected response to be ok'); } });
    Object.defineProperty(chain.be, 'success', { get: function () { if (!range(200, 300)) __fail('expected response to be success'); } });
    Object.defineProperty(chain.be, 'error', { get: function () { if (!range(400, 600)) __fail('expected response to be an error'); } });
    Object.defineProperty(chain.be, 'clientError', { get: function () { if (!range(400, 500)) __fail('expected response to be a client error'); } });
    Object.defineProperty(chain.be, 'serverError', { get: function () { if (!range(500, 600)) __fail('expected response to be a server error'); } });
    pmResponse.to = chain;
  }

  function test(name, fn) {
    try { fn(); tests.push({ name: String(name), status: 'pass' }); }
    catch (e) { tests.push({ name: String(name), status: 'fail', message: e && e.message !== undefined ? String(e.message) : String(e) }); }
  }
  test.skip = function (name) { tests.push({ name: String(name), status: 'skip' }); };

  var pmCore = {
    variables: variables,
    environment: environment,
    collectionVariables: scopes.collection,
    globals: scopes.globals,
    request: pmRequest,
    response: pmResponse,
    info: { eventName: isPre ? 'prerequest' : 'test', requestName: input.requestName, requestId: input.requestId },
    test: test,
    expect: __makeExpect()
  };
  var pm = new Proxy(pmCore, {
    get: function (t, k) {
      if (typeof k === 'string' && __UNSUPPORTED.indexOf(k) !== -1) throw new Error('pm.' + k + ' is not supported yet');
      if (k === 'response' && t.response === undefined) throw new Error('pm.response is only available in post-response scripts');
      return t[k];
    }
  });

  var legacyTests = new Proxy({}, {
    set: function (t, k, v) { tests.push({ name: String(k), status: v ? 'pass' : 'fail', message: v ? undefined : 'assertion was false' }); return true; }
  });
  var postman = {
    setEnvironmentVariable: function (k, v) { scopes.environment.set(k, v); },
    getEnvironmentVariable: function (k) { return scopes.environment.get(k); },
    clearEnvironmentVariable: function (k) { scopes.environment.unset(k); },
    setGlobalVariable: function (k, v) { scopes.globals.set(k, v); },
    getGlobalVariable: function (k) { return scopes.globals.get(k); },
    clearGlobalVariable: function (k) { scopes.globals.unset(k); }
  };

  var error = null;
  try {
    var fn = new Function('pm', 'console', 'postman', 'tests', 'require', code);
    fn(pm, console, postman, legacyTests, function (n) { throw new Error("require('" + n + "') is not supported"); });
  } catch (e) {
    error = (e && e.name && e.name !== 'Error' ? e.name + ': ' : '') + (e && e.message !== undefined ? e.message : String(e));
  }
  return JSON.stringify({ tests: tests, logs: logs, changes: changes, request: isPre ? request : null, error: error });
}
''';
