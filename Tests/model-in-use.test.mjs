import assert from 'node:assert/strict';
import { test } from 'node:test';
import { modelInUse } from '../Resources/web/model.js';

test('the model the agent reports wins, then its launch flags, then the config default', () => {
  assert.deepEqual(modelInUse({ reportedModel: 'opus-5.5', reportedEffort: 'high', launchModel: 'x', defaultModel: 'y' }),
    { model: 'opus-5.5', effort: 'high', source: 'reported' });
  assert.deepEqual(modelInUse({ launchModel: 'gpt-6.1-sol', launchEffort: 'medium', defaultModel: 'y', defaultEffort: 'low' }),
    { model: 'gpt-6.1-sol', effort: 'medium', source: 'launch' });
  assert.deepEqual(modelInUse({ defaultModel: 'gpt-6.1-sol', defaultEffort: 'xhigh' }),
    { model: 'gpt-6.1-sol', effort: 'xhigh', source: 'default' });
});

test('a default effort is not paired with a different model, and nothing known gives nothing', () => {
  assert.deepEqual(modelInUse({ launchModel: 'gpt-6', defaultModel: 'gpt-6.1-sol', defaultEffort: 'xhigh' }), { model: 'gpt-6', effort: '', source: 'launch' });
  assert.deepEqual(modelInUse({}), { model: '', effort: '', source: '' });
  assert.deepEqual(modelInUse(undefined), { model: '', effort: '', source: '' });
});
