export function partInfo(root:ParentNode=document,url:string=location.href):{part:number;partCount:number}{
  const current=new URL(url),parsed=Number(current.searchParams.get('p'));
  const part=Number.isInteger(parsed)&&parsed>0?parsed:1;
  const heading=root.querySelector('.video-pod__header,.multi-page .head-con');
  const text=heading?.textContent??'';
  if(text.includes('视频选集')){const match=text.match(/(\d+)\s*\/\s*(\d+)/);if(match)return {part:Number(match[1]),partCount:Math.max(part,Number(match[2]))}}
  const bvid=current.pathname.match(/BV[0-9A-Za-z]+/)?.[0];
  const count=Math.max(part,...[...root.querySelectorAll<HTMLAnchorElement>('a[href*="p="]')].filter(a=>a.href.includes(bvid??'__missing__')).map(a=>Number(new URL(a.href).searchParams.get('p'))||1));
  return {part,partCount:count};
}
export function danmakuControl(root:ParentNode=document):HTMLElement|null {
  return root.querySelector('.bpx-player-dm-switch input,.bilibili-player-video-danmaku-switch input')??root.querySelector('.bpx-player-dm-switch');
}
export function danmakuOn(root:ParentNode=document):boolean {
  const control=danmakuControl(root);return control instanceof HTMLInputElement?control.checked:control?.getAttribute('aria-checked')!=='false'&&!control?.classList.contains('bpx-state-disabled');
}
export function isWebFullscreen(root:ParentNode=document):boolean {
  return root.querySelector('.bpx-player-container')?.getAttribute('data-screen')==='web'||!!root.querySelector('#biliremote-fullscreen');
}
