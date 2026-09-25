// @vitest-environment jsdom
import {afterEach,beforeEach,expect,it,vi} from 'vitest';
import {readQuality,switchQuality} from '../src/quality';

function item(id:string,label:string,extra='',badge=''){return `<li class="bpx-player-ctrl-quality-menu-item ${extra}" data-value="${id}"><span class="bpx-player-ctrl-quality-text">${label}</span>${badge?`<span class="bpx-player-ctrl-quality-badge">${badge}</span>`:''}</li>`}
beforeEach(()=>{
  document.body.innerHTML=`<div id="bilibili-player"><div class="bpx-player-video-wrap"><video></video></div><div class="bpx-player-ctrl-quality"><div class="bpx-player-ctrl-quality-result-name">1080P 高清</div><ul>${item('112','1080P 高码率','','大会员')}${item('80','1080P 高清','bpx-state-active')}${item('64','720P 准高清')}${item('0','自动')}</ul></div></div>`;
});
afterEach(()=>vi.useRealTimers());
it('reads actual quality tiers without mistaking VIP labels for disabled access',()=>{
  const video=document.querySelector('video')!;
  Object.defineProperties(video,{videoWidth:{value:1920},videoHeight:{value:1080}});
  expect(readQuality()).toEqual({currentId:'80',currentLabel:'1080P 高清',width:1920,height:1080,options:[{id:'112',label:'1080P 高码率',badge:'大会员',disabled:false},{id:'80',label:'1080P 高清',disabled:false},{id:'64',label:'720P 准高清',disabled:false},{id:'0',label:'自动',disabled:false}]});
});
it('keeps automatic selection distinct from the decoded video resolution',()=>{
  document.querySelector('[data-value="80"]')!.classList.remove('bpx-state-active');
  document.querySelector('[data-value="0"]')!.classList.add('bpx-state-active');
  expect(readQuality().currentId).toBe('0');
  expect(readQuality().currentLabel).toBe('1080P 高清');
});
it('does not invent tiers when the player menu is unavailable',()=>{document.body.innerHTML='';expect(readQuality().options).toEqual([]);expect(readQuality().currentId).toBeUndefined()});
it('never reads or clicks a recommendation preview when the main player is loading',async()=>{
  document.querySelector('#bilibili-player')!.removeAttribute('id');
  document.body.insertAdjacentHTML('afterbegin','<div id="bilibili-player"></div>');
  const clicked=vi.fn();document.querySelector('ul')!.addEventListener('click',clicked);
  expect(readQuality().options).toEqual([]);
  await expect(switchQuality('64',()=>true)).rejects.toMatchObject({code:'quality_unavailable'});
  expect(clicked).not.toHaveBeenCalled();
});
it('confirms the site selection after a delayed native menu click',async()=>{
  vi.useFakeTimers();
  const target=document.querySelector<HTMLElement>('[data-value="64"]')!;
  const clicked=vi.fn(()=>setTimeout(()=>{
    document.querySelector('[data-value="80"]')!.classList.remove('bpx-state-active');target.classList.add('bpx-state-active');
  },300));
  target.addEventListener('click',clicked);
  const result=switchQuality('64',()=>true);
  await vi.advanceTimersByTimeAsync(400);await result;
  expect(clicked).toHaveBeenCalledTimes(1);expect(readQuality().currentId).toBe('64');
});
it('does not claim success or retry a click when account restrictions prevent switching',async()=>{
  vi.useFakeTimers();const clicked=vi.fn();document.querySelector('[data-value="112"]')!.addEventListener('click',clicked);
  const result=expect(switchQuality('112',()=>true)).rejects.toMatchObject({code:'quality_not_changed'});
  await vi.advanceTimersByTimeAsync(8000);await result;
  expect(clicked).toHaveBeenCalledTimes(1);expect(readQuality().currentId).toBe('80');
});
it('rejects unavailable, disabled and malformed selections before clicking',async()=>{
  const clicked=vi.fn();document.querySelector('ul')!.addEventListener('click',clicked);
  document.querySelector('[data-value="64"]')!.setAttribute('aria-disabled','true');
  for(const value of ['64','120'])await expect(switchQuality(value,()=>true)).rejects.toMatchObject({code:'quality_unavailable'});
  for(const value of [80,'80]','',null])await expect(switchQuality(value,()=>true)).rejects.toMatchObject({code:'invalid_request'});
  expect(clicked).not.toHaveBeenCalled();
});
it('makes the already selected tier a no-op',async()=>{const clicked=vi.fn();document.querySelector('ul')!.addEventListener('click',clicked);await switchQuality('80',()=>true);expect(clicked).not.toHaveBeenCalled()});
it('rejects stale video or part requests and abandons verification after navigation',async()=>{
  const clicked=vi.fn();document.querySelector('ul')!.addEventListener('click',clicked);
  await expect(switchQuality('64',()=>false)).rejects.toMatchObject({code:'target_changed'});expect(clicked).not.toHaveBeenCalled();
  vi.useFakeTimers();let current=true;
  const result=expect(switchQuality('64',()=>current)).rejects.toMatchObject({code:'target_changed'});
  current=false;await vi.advanceTimersByTimeAsync(200);await result;expect(clicked).toHaveBeenCalledTimes(1);
});
