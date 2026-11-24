"use strict";
const trailerStart = document.getElementById('trailer-start');
const trailer = document.getElementById('trailer-video');
const trailerStatus = document.getElementById('trailer-status');
const quality = document.getElementById('trailer-quality');
const sources = {'360':'trailer/starworld_trailer_360.mp4','540':'trailer/starworld_trailer_540.mp4','1080':'trailer/starworld_trailer.mp4'};
let started = false;
let switchId = 0;
// v36 (Claude): a phone on data saver or a slow connection starts with the light version
const net = navigator.connection || {};
if (net.saveData || /(^|-)(slow-2g|2g|3g)$/.test(net.effectiveType || '')) quality.value = '360';
let stalls = [];
function changeQuality(resume) {
  const id = ++switchId;
  const at = trailer.currentTime || 0;
  trailer.src = sources[quality.value];
  trailerStart.href = sources[quality.value];
  trailerStatus.textContent = '正在加载视频…';
  trailer.addEventListener('loadedmetadata', () => {
    if (id !== switchId) return;
    trailer.currentTime = Math.min(at, Math.max(0, trailer.duration - .1));
    if (resume) trailer.play().catch(() => { trailerStatus.textContent = '请点击播放键继续。'; });
    else trailerStatus.textContent = '';
  }, {once:true});
  trailer.load();
}
quality.addEventListener('change', () => {
  trailerStart.href = sources[quality.value];
  if (started) changeQuality(!trailer.paused);
});
trailerStart.addEventListener('click', event => {
  if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
  event.preventDefault();
  started = true;
  trailer.hidden = false;
  trailerStart.hidden = true;
  trailer.src = sources[quality.value];
  trailer.focus();
  trailer.play().catch(() => { if (!trailer.error) trailerStatus.textContent = '请点击播放器上的播放键。'; });
});
trailer.addEventListener('playing', () => { trailerStatus.textContent = ''; });
trailer.addEventListener('waiting', () => {
  // v36: buffering twice within 20 s at 540p/1080p: go on in 360p from the same moment
  const now = performance.now();
  stalls = stalls.filter((t) => now - t < 20000).concat(now);
  if (quality.value !== '360' && stalls.length >= 2 && trailer.currentTime > 0.5) {
    stalls = [];
    quality.value = '360';
    changeQuality(true);
    trailerStatus.textContent = '网络有点慢，已自动切换到「省流」画质。';
    return;
  }
  trailerStatus.textContent = quality.value === '360' ? '正在缓冲…也可以稍等片刻再播放。' : '正在缓冲…网络慢时可切换到「省流」。';
});
trailer.addEventListener('error', () => {
  if (quality.value !== '360') {
    quality.value = '360';
    changeQuality(true);
  } else trailerStatus.textContent = '视频暂时无法加载，请试试下方的「直接打开视频」。';
});


// Returning to the game must not leave a second soundtrack in this tab.
// Keep the position; the player can resume here with the normal play control.
function pauseTrailerAway() {
  if (!trailer.paused) trailer.pause();
}
document.addEventListener('visibilitychange', () => {
  if (document.hidden) pauseTrailerAway();
});
window.addEventListener('blur', pauseTrailerAway);
window.addEventListener('pagehide', pauseTrailerAway);
