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

import {computerSheetHTML, cloneTeams, computerStripHTML} from '../Resources/web/computers.js';
const copy = key => key;
const escape = s => String(s).replace(/[&<>"']/g, c => '&#' + c.charCodeAt(0) + ';');

test('rows carry projects, roles turned off and whether the list can be edited', () => {
  const rows = computerRows([{name:'laptop', label:'Laptop', ready:true, projects:{shop:'/u/shop'}, rolesOff:{planner:'not logged in'}}],
                            [{name:'laptop', state:'connected'}], []);
  assert.deepEqual(rows[0].projects, {shop:'/u/shop'});
  assert.deepEqual(rows[0].rolesOff, {planner:'not logged in'});
  assert.equal(rows[0].editable, true);
  assert.equal(computerRows([], [{name:'laptop', state:'connected'}], [])[1].editable, false);
});

test('the strip makes editable computers clickable', () => {
  const html = computerStripHTML(computerRows([{name:'laptop', label:'Laptop', ready:true}], [{name:'laptop', state:'connected'}], []), copy, escape);
  assert.match(html, /<button[^>]*data-computer="laptop"/);
});

test('cloneTeams offers teams with a local lead that the computer does not have yet', () => {
  const terms = [
    {address:'t1', machine:'', state:'live', labels:{'team.id':'shop', 'team.role':'lead'}},
    {address:'t2', machine:'', state:'live', labels:{'team.id':'cafe', 'team.role':'lead'}},
    {address:'laptop/t3', machine:'laptop', state:'live', labels:{'team.id':'bakery', 'team.role':'lead'}},
    {address:'t4', machine:'', state:'live', labels:{'team.id':'deli'}},
  ];
  assert.deepEqual(cloneTeams([{id:'shop', title:'Shop'}], terms, {cafe:'/u/cafe'}), [{id:'shop', title:'Shop'}]);
  assert.deepEqual(cloneTeams([], terms, {}).map(t => t.id), ['cafe', 'shop']);
});

test('the sheet lists projects with an unlink button and a clone form for a remote computer', () => {
  const [row] = computerRows([{name:'laptop', label:'Laptop', ready:true, tier:'heavy', slots:4,
                               projects:{shop:'/u/shop'}, rolesOff:{planner:'not logged in'}}], [{name:'laptop', state:'connected'}], []);
  const html = computerSheetHTML(row, [{id:'cafe', title:'Cafe'}], copy, escape);
  assert.match(html, /data-unlink="shop"/);
  assert.match(html, /\/u\/shop/);
  assert.match(html, /<option value="cafe">Cafe<\/option>/);
  assert.match(html, /id="computerCloneForm"/);
  assert.match(html, /planner/);
  assert.match(html, /not logged in/);
  assert.match(html, /id="computerReady"[^>]*checked/);
  assert.match(html, /id="computerSlots"[^>]*value="4"/);
});

test('Mac Studio (every project) and a disconnected computer get no clone form', () => {
  const rows = computerRows([{name:'local', label:'Studio', ready:true, projects:'*'}, {name:'laptop', label:'Laptop', ready:true, projects:{}}], [], []);
  const local = computerSheetHTML(rows[0], [{id:'cafe', title:'Cafe'}], copy, escape);
  assert.doesNotMatch(local, /computerCloneForm/);
  assert.match(local, /allProjects/);
  assert.doesNotMatch(computerSheetHTML(rows[1], [{id:'cafe', title:'Cafe'}], copy, escape), /computerCloneForm/);
});

test('the sheet escapes names and paths', () => {
  const [row] = computerRows([{name:'laptop', label:'<b>x</b>', ready:true, projects:{shop:'/u/<i>'}}], [{name:'laptop', state:'connected'}], []);
  const html = computerSheetHTML(row, [], copy, escape);
  assert.doesNotMatch(html, /<b>x<\/b>|<i>/);
});

test('cloneTeams also offers teams with a Mac Studio repo even when no lead is live', () => {
  assert.deepEqual(cloneTeams([{id:'shop', title:'Shop'}], [], {}, {shop:'/u/shop'}), [{id:'shop', title:'Shop'}]);
  assert.deepEqual(computerRows([{name:'local', ready:true, projects:'*', repos:{shop:'/u/shop'}}], [], [])[0].repos, {shop:'/u/shop'});
});
