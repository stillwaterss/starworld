"use strict";
(() => {
  const canvas = document.getElementById('canvas');
  const help = document.getElementById('camera-help');
  const copy = document.getElementById('camera-copy');
  const button = document.getElementById('camera-lock');
  let playing = false, tried = false, hadLock = false, pending = false, down, timer;
  const locked = () => document.pointerLockElement === canvas;
  function update() {
    copy.textContent = locked() ? '移动鼠标转动镜头 · Esc 释放鼠标' :
      '按住鼠标左键或右键拖动视角';
    button.hidden = locked() || !canvas.requestPointerLock;
    help.hidden = !playing;
    clearTimeout(timer);
    if (locked()) timer = setTimeout(() => { if (locked()) help.hidden = true; }, 6500);
  }
  function lock() {
    if (!playing || !canvas.requestPointerLock || locked() || pending) return;
    pending = true;
    try { canvas.requestPointerLock()?.catch(() => { pending = false; }); }
    catch { pending = false; }
  }
  window.starworldCameraPlayable = active => {
    playing = active;
    if (!active && locked()) document.exitPointerLock();
    if (active && !tried) { tried = true; lock(); }
    update();
  };
  addEventListener('keydown', event => {
    if (event.code === 'Escape' && locked()) {
      event.preventDefault();
      event.stopImmediatePropagation();
      document.exitPointerLock();
    }
  }, true);
  button.addEventListener('click', () => { canvas.focus(); lock(); });
  canvas.addEventListener('pointerdown', e => {
    if (e.button === 0 && playing && !hadLock) down = [e.clientX, e.clientY];
  });
  canvas.addEventListener('pointerup', e => {
    const start = down; down = undefined;
    if (start && e.button === 0 && playing && !hadLock &&
        Math.hypot(e.clientX - start[0], e.clientY - start[1]) < 4) lock();
  });
  document.addEventListener('pointerlockerror', () => { pending = false; });
  document.addEventListener('pointerlockchange', () => {
    pending = false;
    if (locked()) {
      if (!playing) { document.exitPointerLock(); return; }
      hadLock = true;
    }
    update();
  });
})();
