// Run with node Tests/password_autofill_checks.js. No packages required.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('LANBrowser/PasswordAutofill.swift', 'utf8').split('static let script = #"""')[1].split('"""#')[0];
function harness(reply = () => ({username: 'alice', password: 'saved-test-value'})) {
  const handlers = {}, requests = [];
  let timer, mutation;
  class Input {
    constructor(type, value = '', autocomplete = '') {
      Object.assign(this, {type, _value: value, autocomplete, isConnected: true, events: [], disabled: false, readOnly: false});
    }
    get value() { return this._value; }
    set value(value) { this._value = value; }
    getClientRects() { return this.hidden ? [] : [{}]; }
    dispatchEvent(event) { this.events.push(event.type); handlers[event.type]?.({...event, target: this, isTrusted: false}); }
  }
  const username = new Input('text', '', 'username'), password = new Input('password');
  let fields = [username, password];
  const form = {querySelectorAll(selector) { return selector.includes('password') ? fields.filter(f => f.type === 'password') : fields; }};
  username.form = password.form = form;
  const document = {visibilityState: 'visible', ...form, addEventListener(name, fn) { handlers[name] = fn; }};
  const location = {origin: 'http://192.0.2.1:8080'};
  vm.runInNewContext(source, {
    document, location, HTMLInputElement: Input,
    Event: class { constructor(type) { this.type = type; } },
    MutationObserver: class { constructor(callback) { mutation = callback; } observe() {} },
    setTimeout: fn => { timer = fn; return 1; }, clearTimeout: () => { timer = null; },
    window: {addEventListener(name, fn) { handlers[name] = fn; }, webkit: {messageHandlers: {
      passwordFill: {postMessage(body) { requests.push({...body}); return Promise.resolve(reply(body)); }}
    }}}
  });
  return {
    username, password, Input, requests, location,
    setFields(value) { fields = value; },
    mutate() { mutation(); },
    input(target) { handlers.input({target, isTrusted: true}); },
    async flush() { const fn = timer; timer = null; if (fn) fn(); for (let i = 0; i < 8; i++) await Promise.resolve(); }
  };
}
(async () => {
  let h = harness(); await h.flush();
  assert.equal(h.username.value, 'alice'); assert.equal(h.password.value, 'saved-test-value');
  assert.deepEqual(h.password.events, ['input', 'change'], 'Notify framework-controlled forms');
  h.username.value = 'bob'; h.input(h.username);
  assert.equal(h.password.value, '', 'Changing an autofilled username clears its old automatic password');

  h = harness(); h.password.value = 'typed-test-value'; await h.flush();
  assert.equal(h.requests.length, 0, 'Never read a saved password over existing password text');
  h = harness(); h.password.autocomplete = 'new-password'; await h.flush();
  assert.equal(h.requests.length, 0, 'Never fill registration fields');
  h = harness(); h.setFields([h.username, h.password, new h.Input('password')]); await h.flush();
  assert.equal(h.requests.length, 0, 'Never fill multiple-password forms');
  h = harness(() => ({username: 'bob', password: 'bob-test-value'})); h.username.value = 'bob'; await h.flush();
  assert.equal(h.requests[0].username, 'bob'); assert.equal(h.password.value, 'bob-test-value');
  h = harness(() => null); await h.flush(); assert.equal(h.password.value, '', 'Missing credentials leave the page unchanged');

  let resolve;
  h = harness(() => new Promise(r => { resolve = r; })); await h.flush();
  h.password.value = 'typed-while-waiting'; resolve({username: 'alice', password: 'saved-test-value'}); await h.flush();
  assert.equal(h.password.value, 'typed-while-waiting', 'Late replies never overwrite typing');
  h = harness(() => new Promise(r => { resolve = r; })); await h.flush();
  h.username.value = 'someone-else'; resolve({username: 'alice', password: 'saved-test-value'}); await h.flush();
  assert.equal(h.password.value, '', 'Late replies never apply to another entered username');
  h = harness(() => new Promise(r => { resolve = r; })); await h.flush();
  h.location.origin = 'http://other.test'; resolve({username: 'alice', password: 'saved-test-value'}); await h.flush();
  assert.equal(h.password.value, '', 'Late replies never cross origins');
  h = harness(() => new Promise(r => { resolve = r; })); await h.flush();
  h.password.isConnected = false; resolve({username: 'alice', password: 'saved-test-value'}); await h.flush();
  assert.equal(h.password.value, '', 'Late replies never fill removed forms');
  h = harness(); h.password.hidden = true; await h.flush(); assert.equal(h.requests.length, 0);
  h.password.hidden = false; h.mutate(); await h.flush(); assert.equal(h.password.value, 'saved-test-value', 'Newly visible forms autofill');
  h = harness(); h.password.value = 'manual'; h.input(h.password); h.password.value = ''; await h.flush();
  assert.equal(h.requests.length, 0, 'Clearing an edited password does not undo the user’s edits');
  console.log('Passed password AutoFill checks.');
})().catch(error => { console.error(error); process.exitCode = 1; });
