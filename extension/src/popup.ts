async function update(reconnect=false){const result=await chrome.runtime.sendMessage({popup:reconnect?'connect':'status'});document.getElementById('status')!.textContent=result.connected?'● 已连接电脑助手':'○ 助手未连接，请先启动助手'}
document.getElementById('connect')!.addEventListener('click',()=>void update(true));void update();
