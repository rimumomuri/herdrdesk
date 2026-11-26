import {test} from 'node:test';
import assert from 'node:assert/strict';
import {workerRole, roleLook, ROLE_LOOKS} from '../Resources/web/role-look.js';
import {sheepStyles, sheepCoats, sheepAccessories} from '../Resources/web/portrait.js';

test('a card worker role comes from its recovery role', () => {
  assert.equal(workerRole({'recovery.role': 'lime-builder-000039'}), 'builder');
  assert.equal(workerRole({'recovery.role': 'kunkun-verifier-000105'}), 'verifier');
  assert.equal(workerRole({'recovery.role': 'kunkun-user-tester-000007'}), 'user-tester');
});

test('a spawned worker without a numbered role falls back to its team role', () => {
  assert.equal(workerRole({'task.spawned': '1', 'team.role': 'concepts'}), 'designer');
  assert.equal(workerRole({'task.spawned': '1', 'team.role': 'assistant'}), 'researcher');
});

test('leads and ordinary sessions have no role look', () => {
  assert.equal(workerRole({'recovery.role': 'lime-codex-lead', 'team.role': 'lead'}), '');
  assert.equal(workerRole({'team.role': 'production'}), '');   // not a spawned card worker
  assert.equal(roleLook({'recovery.role': 'builder'}), null);
  assert.equal(roleLook(undefined), null);
});

test('each role has its own valid look', () => {
  const seen = new Set();
  for (const [role, look] of Object.entries(ROLE_LOOKS)) {
    assert.ok(sheepStyles.includes(look.style), role);
    assert.ok(sheepCoats.has(look.coat), role);
    assert.ok(sheepAccessories.includes(look.accessory), role);
    const key = look.style + '/' + look.coat;
    assert.ok(!seen.has(key), role + ' looks like another role');
    seen.add(key);
  }
  assert.deepEqual(Object.keys(ROLE_LOOKS).sort(), ['builder', 'designer', 'planner', 'researcher', 'user-tester', 'verifier']);
  assert.deepEqual(roleLook({'recovery.role': 'lime-builder-000039'}), ROLE_LOOKS.builder);
});
