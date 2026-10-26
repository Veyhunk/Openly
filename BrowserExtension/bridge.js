'use strict';
(async () => {
  const token = location.hash.slice(1);
  const status = document.getElementById('status');
  if (!/^[\da-f]{8}(-[\da-f]{4}){3}-[\da-f]{12}$/i.test(token)) { status.textContent = '请求无效，请从 Openly 打开。'; return; }
  const send = message => chrome.runtime.sendNativeMessage('com.openly.bridge', { token, ...message });
  let own;
  try {
    own = await chrome.tabs.getCurrent();
    const request = await send({ action: 'claim' });
    if (request.error) throw new Error(request.error);
    let result;
    if (request.action === 'list') {
      const windows = await chrome.windows.getAll({ populate: true, windowTypes: ['normal'] });
      const groups = await chrome.tabGroups.query({});
      result = {
        windows: windows.filter(w => w.tabs.some(t => t.id !== own.id)).map(w => {
          const tabs = w.tabs.filter(t => t.id !== own.id);
          return { id: w.id, title: (tabs.find(t => t.active) || tabs[0])?.title || '未命名窗口', incognito: w.incognito, count: tabs.length };
        }),
        groups: groups.map(g => ({ id: g.id, windowId: g.windowId, title: g.title || '未命名组', color: g.color }))
      };
    } else if (request.action === 'open') {
      const window = await chrome.windows.get(request.windowId);
      if (request.groupId != null) {
        const group = await chrome.tabGroups.get(request.groupId);
        if (group.windowId !== window.id) throw new Error('标签组已移动，请重新选择');
      }
      const opened = [];
      try {
        for (const url of request.urls) {
          if (!/^https?:\/\//i.test(url)) throw new Error('高级浏览器路由支持 HTTP/HTTPS 链接');
          const tab = await chrome.tabs.create({ windowId: window.id, url, active: true });
          opened.push(tab.id);
          if (request.groupId != null) await chrome.tabs.group({ tabIds: [tab.id], groupId: request.groupId });
        }
        await chrome.windows.update(window.id, { focused: true });
        result = { ok: true, opened: opened.length };
      } catch (error) { result = { error: `${error.message}；已提交 ${opened.length} 项，请核对后再重试`, opened: opened.length }; }
    } else throw new Error('不支持的请求');
    await send({ action: 'complete', result });
    await chrome.tabs.remove(own.id);
  } catch (error) {
    status.textContent = `连接失败：${error.message}。可关闭本页后返回 Openly。`;
    try { await send({ action: 'complete', result: { error: error.message } }); } catch (_) {}
  }
})();
