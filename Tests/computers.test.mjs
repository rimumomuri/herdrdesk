import {test} from 'node:test';
import assert from 'node:assert/strict';
import {computerRows} from '../Resources/web/computers.js';

const profiles = [
  {name:'local', label:'Mac Studio', tier:'heavy', slots:6, ready:true},
  {name:'macbook-m6', label:'M6 맥북', tier:'heavy', slots:4, ready:false},
  {name:'macbook-pro', label:'인텔 맥북', tier:'light', slots:2, ready:true},
];

test('each computer shows connection, readiness and card workers in use', () => {
  const live = [{name:'macbook-m6', state:'connected'}, {name:'macbook-pro', state:'unreachable'}];
  const terms = [
    {address:'t5', machine:'', state:'live', labels:{'task.spawned':'1'}},
    {address:'t6', machine:'', state:'live', labels:{}},
    {address:'macbook-pro/t1', machine:'macbook-pro', state:'live', labels:{'task.spawned':'1'}},
  ];
  const rows = computerRows(profiles, live, terms);
  assert.deepEqual(rows.map(r => [r.name, r.state, r.used, r.slots]), [
    ['local', 'ready', 1, 6], ['macbook-m6', 'not-ready', 0, 4], ['macbook-pro', 'offline', 1, 2]]);
  assert.equal(rows[2].tier, 'light');
});

test('without a profile list, only connected computers from hc are shown', () => {
  const rows = computerRows([], [{name:'macbook-m6', state:'connected'}], []);
  assert.deepEqual(rows.map(r => [r.name, r.state]), [['local', 'ready'], ['macbook-m6', 'ready']]);
});
