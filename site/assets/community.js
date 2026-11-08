"use strict";
const trailerStart = document.getElementById('trailer-start');
const trailer = document.getElementById('trailer-video');
const trailerStatus = document.getElementById('trailer-status');
const quality = document.getElementById('trailer-quality');
const sources = {'360':'trailer/starworld_trailer_360.mp4','540':'trailer/starworld_trailer_540.mp4','1080':'trailer/starworld_trailer.mp4'};
let started = false;
let switchId = 0;
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
  trailerStatus.textContent = quality.value === '360' ? '正在缓冲…也可以稍等片刻再播放。' : '正在缓冲…网络慢时可切换到「省流」。';
});
trailer.addEventListener('error', () => {
  if (quality.value !== '360') {
    quality.value = '360';
    changeQuality(true);
  } else trailerStatus.textContent = '视频暂时无法加载，请试试下方的「直接打开视频」。';
});

const copy = document.getElementById('wechat-copy');
if (navigator.clipboard?.writeText) {
  copy.hidden = false;
  copy.addEventListener('click', async () => {
    const status = document.getElementById('wechat-status');
    try {
      await navigator.clipboard.writeText(document.getElementById('wechat-name').textContent);
      status.textContent = '已复制。打开微信，在「搜一搜」选择公众号并粘贴。';
    } catch {
      status.textContent = '请长按或选中「昱说还休」，手动复制。';
    }
  });
}

const recent = document.getElementById('feedback-recent');
recent.addEventListener('toggle', async () => {
  if (!recent.open || recent.dataset.loaded) return;
  recent.dataset.loaded = 'pending';
  const status = document.getElementById('feedback-status');
  const list = document.getElementById('feedback-list');
  status.textContent = '正在读取公开留言…';
  try {
    const response = await fetch('https://api.github.com/repos/stillwaterss/starworld/issues?state=all&labels=player-feedback&per_page=8', {
      headers: { Accept: 'application/vnd.github+json' },
      signal: AbortSignal.timeout(8000)
    });
    if (!response.ok) throw new Error('Feedback unavailable');
    const issues = (await response.json()).filter(item => !item.pull_request && Number.isInteger(item.number));
    for (const issue of issues) {
      const li = document.createElement('li');
      const a = document.createElement('a');
      a.href = 'https://github.com/stillwaterss/starworld/issues/' + issue.number;
      a.textContent = issue.title;
      li.append(a);
      list.append(li);
    }
    status.textContent = issues.length ? '点击标题，查看留言和回复。' : '还没有公开留言。欢迎写下你的试玩感受。';
    recent.dataset.loaded = 'yes';
  } catch {
    delete recent.dataset.loaded;
    status.textContent = '暂时读不到留言，可以点击「看全部留言」。';
  }
});
