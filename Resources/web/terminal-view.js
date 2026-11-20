// Viewer lifecycle is independent of the conversation and its saved drafts.
export function createTerminalView({ panel, viewport, screen, status, retry, latest, open, mode, post, Terminal, text }) {
  let current = null;
  let renderer = null;
  let nextID = 0;
  let following = true;
  let placedTop = 0;
  let frames = Promise.resolve();
  let cancelWrite = null;

  // The mirrored grid keeps the agent's column count; shrink the font (down to 9px) so whole lines fit the panel.
  const BASE_FONT = 12, MIN_FONT = 9;
  function fitWidth() {
    if (!renderer) return;
    const available = viewport.clientWidth - 12;
    if (available <= 0) return;
    if (renderer.options.fontSize !== BASE_FONT) renderer.options.fontSize = BASE_FONT;
    const full = screen.querySelector('.xterm-screen')?.scrollWidth || screen.scrollWidth;
    if (full > available) renderer.options.fontSize = Math.max(MIN_FONT, Math.floor(BASE_FONT * available / full * 10) / 10);
  }
  if (typeof ResizeObserver === 'function') new ResizeObserver(() => fitWidth()).observe(viewport);

  function followCursor() {
    if (!renderer || !following) return;
    const height = screen.querySelector('.xterm-screen')?.clientHeight;
    if (!height) return;
    const cellHeight = height / renderer.rows;
    const cursorTop = renderer.buffer.active.cursorY * cellHeight;
    const cursorBottom = cursorTop + cellHeight + 16;
    if (cursorTop < viewport.scrollTop) viewport.scrollTop = cursorTop;
    else if (cursorBottom > viewport.scrollTop + viewport.clientHeight) {
      viewport.scrollTop = cursorBottom - viewport.clientHeight;
    }
    placedTop = viewport.scrollTop;
  }

  viewport.addEventListener('scroll', () => {
    if (!renderer || viewport.scrollTop === placedTop) return;
    following = false;
    latest.hidden = false;
  }, { passive: true });
  latest.addEventListener('click', () => {
    following = true;
    latest.hidden = true;
    renderer?.scrollToBottom();
    viewport.scrollTop = viewport.scrollHeight;
    placedTop = viewport.scrollTop;
    followCursor();
  });

  function show(state, message) {
    panel.dataset.state = state;
    status.dataset.key = message;
    status.textContent = text(message);
    retry.hidden = state !== 'ended' || !current;
    open.disabled = !current;
    updateMode();
  }

  function updateMode(focused = current?.interactive && renderer && document.activeElement === renderer.textarea) {
    panel.dataset.input = focused ? 'focused' : 'ready';
    mode.textContent = text(focused ? 'terminalFocused' : current?.interactive ? 'terminalClickToType' : 'readOnly');
  }

  function dispose() {
    cancelWrite?.();
    cancelWrite = null;
    frames = Promise.resolve();
    renderer?.dispose();
    renderer = null;
    screen.replaceChildren();
    viewport.scrollTop = 0;
    placedTop = 0;
    following = true;
    latest.hidden = true;
  }

  function stop() {
    const previous = current;
    if (!previous) return;
    current = null;
    dispose();
    if (previous) post({ type: 'terminalUnwatch', id: previous.id });
  }

  function sync(term, connected) {
    if (term?.state !== 'live' || !term.session || !connected) {
      stop();
      show('unavailable', !connected ? 'streamWaiting' : term?.state === 'archived' ? 'streamOffline' : 'streamUnavailable');
      return;
    }
    if (current?.address === term.address && current.session === term.session) return;
    stop();
    if (!Terminal) {
      show('unavailable', 'streamRenderFailed');
      return;
    }
    current = { id: String(++nextID), session: term.session, address: term.address, interactive: false };
    show('connecting', 'streamConnecting');
    post({ type: 'terminalWatch', id: current.id, address: term.address, session: term.session });
  }

  function event({ id, state, message, cols, rows, canType }) {
    if (id !== current?.id) return;
    if (state === 'focusError') {
      status.dataset.key = message;
      status.textContent = text(message);
      return;
    }
    if (state === 'ended') {
      if (current.interactive) current = { ...current, interactive: false };
      dispose();
      show('ended', message);
      return;
    }
    if (state !== 'grid') return;
    if (renderer) {
      const source = renderer;
      frames = frames.then(() => {
        if (renderer !== source || source.cols === cols && source.rows === rows) return;
        source.resize(cols, rows);
        fitWidth();
        followCursor();
      }).catch(() => {
        if (renderer === source) {
          stop();
          show('unavailable', 'streamRenderFailed');
        }
      });
      return;
    }
    current.interactive = canType === true;
    renderer = new Terminal({
      cols, rows, disableStdin: !current.interactive, cursorBlink: false, cursorInactiveStyle: 'none',
      scrollback: 2000, allowProposedApi: false,
      fontFamily: 'ui-monospace, Menlo, HerdrHangulCell, monospace', fontSize: BASE_FONT, lineHeight: 1.15,
      theme: { background: '#171e20', foreground: '#d8e4df', selectionBackground: '#45605b' }
    });
    renderer.open(screen);
    fitWidth();
    // Refuse terminal-supplied hyperlinks and clipboard control.
    renderer.parser.registerOscHandler(8, () => true);
    renderer.parser.registerOscHandler(52, () => true);
    renderer.onScroll(() => {
      if (!renderer || renderer.buffer.active.viewportY >= renderer.buffer.active.baseY) return;
      following = false;
      latest.hidden = false;
    });
    updateMode();
    if (current.interactive) {
      const target = current;
      const source = renderer;
      let userGesture = false;
      for (const name of ['keydown','beforeinput','input','paste','compositionend']) {
        source.element.addEventListener(name, event => {
          if (!event.isTrusted) return;
          userGesture = true;
          setTimeout(() => { userGesture = false; }, 0);
        }, true);
      }
      source.onData(data => {
        if (userGesture && current === target && document.activeElement === source.textarea) {
          post({type: 'terminalInput', id: target.id, session: target.session, address: target.address, data});
        }
      });
      source.textarea.addEventListener('focus', () => updateMode(true));
      source.textarea.addEventListener('blur', () => updateMode(false));
    }
  }

  function output(id, base64) {
    if (!renderer || id !== current?.id) return false;
    const source = renderer;
    const bytes = Uint8Array.from(atob(base64), char => char.charCodeAt(0));
    if (panel.dataset.state !== 'live') show('live', 'streamLive');
    const write = frames.then(() => {
      if (renderer !== source || id !== current?.id) return false;
      return new Promise(resolve => {
        cancelWrite = () => resolve(false);
        source.write(bytes, () => {
          const stillCurrent = renderer === source && id === current?.id;
          if (stillCurrent) {
            cancelWrite = null;
            followCursor();
          }
          resolve(stillCurrent);
        });
      });
    });
    frames = write.catch(() => false);
    return write;
  }

  retry.addEventListener('click', () => {
    if (!current) return;
    const { session, address } = current;
    stop();
    sync({ state: 'live', session, address }, true);
  });
  open.addEventListener('click', () => {
    if (current) post({ type: 'open', id: current.id, address: current.address, session: current.session });
  });

  function relabel() { if (status.dataset.key) show(panel.dataset.state, status.dataset.key); }
  return { sync, stop, event, output, relabel };
}
