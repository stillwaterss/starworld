"use strict";
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
