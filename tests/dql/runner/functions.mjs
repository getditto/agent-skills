// Function semantics and coverage for the alphabetical index in functions.md.
// Each query has a seeded FROM collection; no standalone SELECT is silently skipped.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { loadSdk } from './version-shim.mjs';
import { loadEnv } from '../../lib/load-env.mjs';

const cases = [
  ['abs', 'abs(-3)', 3],
  ['array_contains', "array_contains(['a','b'], 'b')", true],
  ['array_contains_null', 'array_contains_null([1,null])', true],
  ['array_length', 'array_length([1,2,3])', 3],
  ['avg', 'avg(f.n)', 4, 'aggregate'],
  ['byte_length', "byte_length('é')", 2],
  ['cast', "cast('42', 'integer')", 42],
  ['ceil', 'ceil(1.2)', 2],
  ['char_length', "char_length('é')", 1],
  ['character_length', "character_length('é')", 1],
  ['clock', 'clock()', undefined, 'clock'],
  ['coalesce', "coalesce(f.absent, null, 'fallback')", 'fallback'],
  ['concat', "concat('a','b','c')", 'abc'],
  ['contains', "contains('abcdef', 'cde')", true],
  ['count', 'count(*)', 3, 'aggregate'],
  ['date_add', "date_add(0, 'day', 2)", 172800000],
  ['date_cast', "date_cast('1970-01-02T00:00:00Z')", 86400000],
  ['date_diff', "[date_diff(0, 172800000, 'day'), date_diff(172800000, 0, 'day')]", [-2, 2]],
  ['date_format', "date_format(0, 'YYYY-MM-DD', 'UTC')", '1970-01-01'],
  ['date_part', "date_part(0, 'year')", 1970],
  ['date_range', "date_range(0, 172800000, 'day', 1)", [0, 86400000]],
  ['date_sub', "date_sub(172800000, 'day', 1)", 86400000],
  ['date_trunc', "date_trunc(86401234, 'day')", 86400000],
  ['decode', "decode(2, 1, 'one', 2, 'two', 'other')", 'two'],
  ['deserialize_json', `deserialize_json('{"n":2,"ok":true}')`, { n: 2, ok: true }],
  ['duration_cast', "duration_cast('2h22m', 'seconds')", 8520],
  ['duration_format', "duration_cast(duration_format(8520, 'seconds'), 'seconds')", 8520],
  ['ends_with', "ends_with('hello', 'lo')", true],
  ['floor', 'floor(-1.2)', -2],
  ['ifmissing', "ifmissing(f.absent, 'fallback')", 'fallback'],
  ['ifmissingornull', "ifmissingornull(f.absent, null, 'fallback')", 'fallback'],
  ['ifnull', "ifnull(null, 'fallback')", 'fallback'],
  ['is_boolean', 'is_boolean(true)', true],
  ['is_number', 'is_number(1.5)', true],
  ['is_string', "is_string('text')", true],
  ['ismissing', 'ismissing(f.absent)', true],
  ['ismissingornull', 'ismissingornull(null)', true],
  ['isnull', 'isnull(null)', true],
  ['joinstr', "joinstr('-', 'a', 2, ['b','c'])", 'a-2-b-c'],
  ['json_type', 'json_type(2)', 'number'],
  ['length', "length('é')", 2],
  ['lower', "lower('ABC')", 'abc'],
  ['lpad', "lpad('7', 3, '0')", '007'],
  ['ltrim', "ltrim('xxhello', 'x')", 'hello'],
  ['max', 'max(f.n)', 10, 'aggregate'],
  ['median', 'median(f.n)', 4, 'aggregate'],
  ['mid', 'mid(f.n)', 4, 'aggregate'],
  ['min', 'min(f.n)', -2, 'aggregate'],
  ['missingif', 'ismissing(missingif(1, 1))', true],
  ['nullif', 'nullif(1, 1)', null],
  ['nvl', "nvl(null, 'fallback')", 'fallback'],
  ['object_concat', "object_concat({'a':1}, {'a':2,'b':3})", { a: 2, b: 3 }],
  ['object_content', "object_content({'a':1}, 'fields')", [{ a: 1 }]],
  ['object_keys', "object_keys({'a':1})", ['a']],
  ['object_length', "object_length({'a':1,'b':2})", 2],
  ['object_rename', "object_rename({'a':1}, 'a', 'b')", { b: 1 }],
  ['object_set', "object_set({'a':1}, 'a', 2, true)", { a: 2 }],
  ['object_unset', "object_unset({'a':1,'b':2}, 'a')", { b: 2 }],
  ['object_values', "object_values({'a':1})", [1]],
  ['pos', "pos('abcdef', 'cd')", 2],
  ['regexp_like', "regexp_like('AbC', '^abc$', 'i')", true],
  ['repeat', "repeat('*', 3)", '***'],
  ['request_info', 'request_info()', undefined, 'request_info'],
  ['rpad', "rpad('7', 3, '0')", '700'],
  ['rtrim', "rtrim('helloxx', 'x')", 'hello'],
  ['split', "split('a,b,c', ',')", ['a', 'b', 'c']],
  ['starts_with', "starts_with('hello', 'he')", true],
  ['substr', "substr('abcdef', 2, 3)", 'cde'],
  ['sum', 'sum(f.n)', 12, 'aggregate'],
  ['trim', "`trim`('  hello  ')", 'hello'],
  ['type', 'type(2)', 'integer'],
  ['tz_offset', "tz_offset('2024-06-15T14:00:00-05:00')", -300],
  ['upper', "upper('abc')", 'ABC'],
];

// Fail if the documentation gains a name without executable coverage, or if tests
// accidentally stop calling the function whose behavior they claim to establish.
const reference = fs.readFileSync(new URL('../../../skills/write-dql/references/functions.md', import.meta.url), 'utf8');
const index = reference.split('## 11. Alphabetical function index\n')[1]?.split('\n## ')[0];
assert.ok(index, 'Function index must be present');
const documented = [...index.matchAll(/`([a-z][a-z_0-9]*)`/g)].map(match => match[1]);
assert.equal(new Set(documented).size, documented.length, 'Duplicate documented names');
assert.equal(new Set(cases.map(([name]) => name)).size, cases.length, 'Duplicate test cases');
assert.deepEqual(cases.map(([name]) => name).sort(), documented.sort(), 'Function index coverage');
for (const [name, expression] of cases) {
  assert.match(expression, new RegExp(`\\b${name}\\x60?\\s*\\(`), `${name} must be invoked`);
}
if (process.argv.includes('--check-coverage')) {
  console.log(`PASS function index coverage: ${cases.length} names`);
  process.exit(0);
}

loadEnv();
const version = process.env.DITTO_SDK_VERSION;
assert.ok(version, 'Set DITTO_SDK_VERSION');
const license = process.env.DITTO_OFFLINE_LICENSE || process.env.DITTO_PLAYGROUND_TOKEN;
assert.ok(license, 'Set DITTO_OFFLINE_LICENSE');
const databaseID = process.env.DITTO_DATABASE_ID || '00000000-1111-2222-3333-444444444444';
const sdk = await loadSdk(version);
await sdk.init();
const directory = fs.mkdtempSync(path.join(os.tmpdir(), `ditto-functions-${version}-`));
let ditto;
let failed = 0;
try {
  ditto = version.startsWith('4.')
    ? new sdk.Ditto({ type: 'offlinePlayground', appID: databaseID }, directory)
    : await sdk.Ditto.open(new sdk.DittoConfig(databaseID, { mode: 'smallPeersOnly' }, directory));
  ditto.setOfflineOnlyLicenseToken(license);
  if (version.startsWith('4.')) await ditto.disableSyncWithV3();
  await ditto.store.execute('ALTER SYSTEM SET dql_strict_mode = false');
  await ditto.store.execute("INSERT INTO function_checks DOCUMENTS ({'_id':'one','n':-2}), ({'_id':'two','n':4}), ({'_id':'three','n':10})");
  for (const [name, expression, expected, kind] of cases) {
    try {
      const before = Date.now();
      const result = await ditto.store.execute(`SELECT ${expression} AS actual FROM function_checks f${kind === 'aggregate' ? '' : " WHERE _id = 'one'"}`);
      const after = Date.now();
      assert.equal(result.items.length, 1, 'Expected exactly one row');
      const item = result.items[0];
      const row = typeof item.value === 'function' ? item.value() : item.value;
      assert.ok(Object.hasOwn(row, 'actual'), 'Function unexpectedly returned MISSING');
      const actual = row.actual;
      if (kind === 'clock') {
        assert.equal(typeof actual, 'number');
        assert.ok(actual >= before && actual <= after, 'clock() must report current epoch milliseconds');
      } else if (kind === 'request_info') {
        assert.equal(typeof actual.app_id, 'string');
        assert.equal(typeof actual.request_id, 'string');
        assert.equal(typeof actual.start_time, 'string');
        assert.match(actual.start_time, /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/);
        const timestamp = Date.parse(actual.start_time);
        assert.ok(Number.isFinite(timestamp), 'start_time must be a parseable ISO timestamp');
        assert.ok(timestamp >= before - 1000 && timestamp <= after + 1000,
          'start_time must describe the current request, allowing second precision');
      } else {
        assert.deepEqual(actual, expected);
      }
    } catch (error) {
      failed += 1;
      console.error(`FAIL function ${name} on ${version}: ${error.message}`);
    }
  }
} finally {
  await ditto?.close();
  fs.rmSync(directory, { recursive: true, force: true });
}
console.log(`${failed ? 'FAIL' : 'PASS'} functions ${version}: ${cases.length - failed}/${cases.length}; complete alphabetical-index coverage`);
process.exitCode = failed ? 1 : 0;
