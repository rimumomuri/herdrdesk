// The look a card worker starts with, from its role, until the person picks one. Pure: no DOM.
// Workers are named "<team>-<role>-<number>" (recovery.role); a spawned worker also carries team.role.

export const ROLE_LOOKS = {
  planner: { style: 'clover', coat: 'sun', accessory: 'hair' },               // 기획: bright ideas
  builder: { style: 'bighorn', coat: 'tangerine', accessory: 'none' },         // 제작: horns, works with the hammer
  verifier: { style: 'lamb', coat: 'royal', accessory: 'glasses' },            // 검증: inspects closely
  researcher: { style: 'marshmallow', coat: 'aqua', accessory: 'glasses' },    // 조사: reads up
  designer: { style: 'twin', coat: 'magenta', accessory: 'bow' },              // 시안: styled
  'user-tester': { style: 'classic', coat: 'mint', accessory: 'headset' },     // 사용자 테스트: listens like a user
};
const TEAM_ROLE = { planner: 'planner', production: 'builder', qa: 'verifier', assistant: 'researcher', concepts: 'designer' };

export function workerRole(labels) {
  const named = /-(planner|builder|verifier|researcher|designer|user-tester)-\d+$/.exec(labels?.['recovery.role'] || '');
  if (named) return named[1];
  return labels?.['task.spawned'] ? TEAM_ROLE[labels['team.role']] || '' : '';
}

export const roleLook = labels => ROLE_LOOKS[workerRole(labels)] || null;
