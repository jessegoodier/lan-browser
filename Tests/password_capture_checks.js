// Run with node Tests/password_capture_checks.js. No packages required.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('LANBrowser/PasswordCapture.swift', 'utf8').split('static let script = #"""')[1].split('"""#')[0];
const handlers = {};
const messages = [];
let time = 0;
class Element {}
class Input extends Element {
  constructor(type, value, autocomplete = '') {
    super(); Object.assign(this, { type, value, autocomplete, disabled: false });
  }
  getClientRects() { return this.hidden ? [] : [{}]; }
}
let fields = [];
const form = { checkValidity() { return true; }, querySelectorAll(selector) { return selector.includes('password') ? fields.filter(f => f.type === 'password') : fields; } };
const document = { ...form, addEventListener(name, callback) { handlers[name] = callback; } };
vm.runInNewContext(source, {
  document, Element, HTMLInputElement: Input, performance: { now: () => time },
  window: { webkit: { messageHandlers: { passwordSubmitted: { postMessage: message => messages.push({ ...message }) } } } }
});
function submit(trusted = true) { time += 1000; handlers.submit({ isTrusted: trusted, target: form }); }
fields = [new Input('text', 'alice'), new Input('password', 'p@ss')];
submit(); assert.deepEqual(messages.pop(), { username: 'alice', password: 'p@ss' });
submit(); assert.equal(messages.length, 1, 'Unchanged credentials prompt again'); messages.length = 0;
submit(false); assert.equal(messages.length, 0, 'Synthetic submissions cannot capture credentials');
fields[1].value = ''; submit(); assert.equal(messages.length, 0, 'Empty passwords are ignored');
fields[1].value = 'new'; fields[1].autocomplete = 'new-password'; submit();
assert.equal(messages.length, 0, 'New-password forms are ignored');
fields[1].autocomplete = '';
fields.push(new Input('password', '')); submit(); assert.equal(messages.length, 0, 'Multi-password forms are ignored even with empty confirmation');
fields = [new Input('password', '秘密')]; submit();
assert.deepEqual(messages.pop(), { username: '', password: '秘密' }, 'Password-only forms preserve Unicode');
fields = [new Input('email', 'alice@example.test', 'username'), new Input('text', 'other'), new Input('password', 'secret')]; submit();
assert.equal(messages.pop().username, 'alice@example.test', 'Autocomplete username takes precedence');
const button = new Element();
Object.assign(button, { type: 'button', form, textContent: 'Sign In', getAttribute: () => null, closest: () => button });
time += 1000; handlers.click({ isTrusted: true, target: button });
handlers.submit({ isTrusted: true, target: form });
assert.equal(messages.length, 1, 'Button handler and submit yield one offer'); messages.length = 0;
button.textContent = 'Show Password'; time += 1000; handlers.click({ isTrusted: true, target: button });
assert.equal(messages.length, 0, 'Password visibility buttons do not trigger offers');
button.form = null; button.textContent = 'Log in'; time += 1000; handlers.click({ isTrusted: true, target: button });
assert.equal(messages.length, 1, 'Formless login buttons are supported'); messages.length = 0;
time += 1000; handlers.keydown({ isTrusted: true, key: 'Enter', target: fields[2] });
assert.equal(messages.length, 1, 'Formless Enter submits credentials');

messages.length = 0;
button.form = form; button.type = 'submit';
time += 1000; handlers.click({ isTrusted: true, target: button });
assert.equal(messages.length, 1, 'Submit-button clicks capture before JavaScript can prevent submission');
messages.length = 0;
form.checkValidity = () => false;
time += 1000; handlers.click({ isTrusted: true, target: button });
assert.equal(messages.length, 0, 'Invalid native forms do not offer to save');
form.checkValidity = () => true;
fields[2].form = form;
time += 1000; handlers.keydown({ isTrusted: true, key: 'Enter', target: fields[2] });
assert.equal(messages.length, 1, 'Enter captures before a JavaScript form handler clears the fields');
console.log('Passed password capture checks.');
