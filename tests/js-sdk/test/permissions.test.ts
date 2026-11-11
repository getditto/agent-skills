import assert from 'node:assert/strict';
import { test } from 'node:test';
import { meshPermissions } from '../.generated/android-permissions';

test('runtime permission plan respects Android API and transport boundaries', () => {
  const short = (api: number, aware = true) => meshPermissions(api, aware).map(p => p.replace('android.permission.', '')).sort();
  assert.deepEqual(short(22), []);
  for (const api of [23, 30]) assert.deepEqual(short(api), ['ACCESS_COARSE_LOCATION', 'ACCESS_FINE_LOCATION']);
  for (const api of [31, 32]) assert.deepEqual(short(api), ['ACCESS_COARSE_LOCATION', 'ACCESS_FINE_LOCATION', 'BLUETOOTH_ADVERTISE', 'BLUETOOTH_CONNECT', 'BLUETOOTH_SCAN']);
  for (const api of [33, 35, 36]) assert.deepEqual(short(api), ['BLUETOOTH_ADVERTISE', 'BLUETOOTH_CONNECT', 'BLUETOOTH_SCAN', 'NEARBY_WIFI_DEVICES']);
  for (const api of [31, 32, 33]) assert.deepEqual(short(api, false), ['BLUETOOTH_ADVERTISE', 'BLUETOOTH_CONNECT', 'BLUETOOTH_SCAN']);
});
