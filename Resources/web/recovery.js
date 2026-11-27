// Agent recovery in the sidebar: after a reboot, one button resumes the saved agent conversations. Pure: no DOM.

const needsLook = role => !['skip', 'resume', 'create', 'submitted'].includes(role.action);

/** rec: the app's recovery payload; ui: {confirming, dismissed} kept by the page. Empty when there is nothing to say. */
export function recoveryBarHTML(rec, ui, copy, escape) {
  if (!rec?.enabled) return '';
  const report = rec.report;
  if (rec.busy) return '<div class="recovery-bar" data-state="busy" role="status"><span class="recovery-spin" aria-hidden="true"></span>'
    + copy(rec.busy === 'restoring' ? 'recoveryRestoring' : 'recoveryChecking') + '</div>';
  if (rec.error) return '<div class="recovery-bar" data-state="error" role="status"><span>' + copy('recoveryFailed') + ' · ' + escape(rec.error)
    + '</span><button type="button" data-recovery="check">' + copy('recoveryRetry') + '</button></div>';
  if (!report) return '';
  const waiting = report.roles.filter(role => role.action === 'resume' || role.action === 'create');
  const attention = report.roles.filter(needsLook);
  const details = attention.length ? '<ul class="recovery-details">' + attention.map(role =>
    '<li>' + escape(role.title) + ' · ' + escape(role.reason || copy('recovery_' + role.action)) + '</li>').join('') + '</ul>' : '';
  if (waiting.length && ui?.confirming) {
    return '<div class="recovery-bar" data-state="confirm"><span>' + copy('recoveryConfirm').replace('{n}', () => '<b>' + waiting.length + '</b>') + '</span>'
      + '<ul class="recovery-details">' + waiting.map(role => '<li>' + escape(role.title) + '</li>').join('') + '</ul>'
      + '<div class="recovery-actions"><button type="button" class="primary" data-recovery="restore">' + copy('recoveryStart') + '</button>'
      + '<button type="button" data-recovery="cancel">' + copy('cancel') + '</button></div></div>';
  }
  if (waiting.length) {
    return '<div class="recovery-bar" data-state="pending"><button type="button" class="recovery-main" data-recovery="confirm">'
      + copy('recoveryPending').replace('{n}', () => '<b>' + waiting.length + '</b>') + '</button>' + details + '</div>';
  }
  if (report.applied && ui?.dismissed !== report.at) {
    return '<div class="recovery-bar" data-state="' + (attention.length ? 'attention' : 'done') + '" role="status"><span>'
      + (attention.length ? copy('recoveryAttention').replace('{n}', () => '<b>' + attention.length + '</b>') : copy('recoveryDone')) + '</span>'
      + '<button type="button" class="recovery-close" data-recovery="dismiss" aria-label="' + copy('close') + '">×</button>' + details + '</div>';
  }
  if (attention.length && ui?.dismissed !== report.at) {
    return '<div class="recovery-bar" data-state="attention"><span>' + copy('recoveryAttention').replace('{n}', () => '<b>' + attention.length + '</b>') + '</span>'
      + '<button type="button" class="recovery-close" data-recovery="dismiss" aria-label="' + copy('close') + '">×</button>' + details + '</div>';
  }
  return '';
}

/** The settings line: how many agents are saved automatically, when, and a button to check now. */
export function recoverySettingsHTML(rec, copy, escape, time) {
  if (!rec?.enabled) return '';
  const when = rec.savedAt ? time(rec.savedAt) : '';
  return '<div class="recovery-settings-line"><span>' + copy('recoveryAutoSaved').replace('{n}', () => String(rec.saved || 0))
    + (when ? ' · ' + escape(when) : '') + '</span><button type="button" data-recovery="check"' + (rec.busy ? ' disabled' : '') + '>'
    + copy('recoveryCheck') + '</button></div>';
}
