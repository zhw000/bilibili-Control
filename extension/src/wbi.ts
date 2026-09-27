import {RemoteError} from './types';

// Web Crypto has no MD5, which the website's WBI request signature requires (RFC 1321 over UTF-8).
const shifts=[7,12,17,22,5,9,14,20,4,11,16,23,6,10,15,21];
const constants=Array.from({length:64},(_,i)=>Math.floor(Math.abs(Math.sin(i+1))*2**32)>>>0);
export function md5(text:string):string{
  const bytes=new TextEncoder().encode(text),size=((bytes.length+8>>6)+1)*16,words=new Uint32Array(size);
  bytes.forEach((byte,i)=>{words[i>>2]|=byte<<i%4*8});
  words[bytes.length>>2]|=0x80<<bytes.length%4*8;
  words[size-2]=bytes.length*8>>>0;words[size-1]=Math.floor(bytes.length/0x20000000);
  const state=[0x67452301,0xefcdab89,0x98badcfe,0x10325476];
  for(let block=0;block<size;block+=16){
    let [a,b,c,d]=state;
    for(let i=0;i<64;i++){
      const round=i>>4;
      const f=round===0?(b&c)|(~b&d):round===1?(d&b)|(~d&c):round===2?b^c^d:c^(b|~d);
      const g=round===0?i:round===1?(5*i+1)%16:round===2?(3*i+5)%16:7*i%16;
      const sum=(a+f+constants[i]+words[block+g])>>>0,shift=shifts[round*4+i%4];
      a=d;d=c;c=b;b=(b+(sum<<shift|sum>>>32-shift))>>>0;
    }
    state[0]=(state[0]+a)>>>0;state[1]=(state[1]+b)>>>0;state[2]=(state[2]+c)>>>0;state[3]=(state[3]+d)>>>0;
  }
  return state.map(word=>[0,8,16,24].map(bits=>(word>>>bits&255).toString(16).padStart(2,'0')).join('')).join('');
}

// The website mixes its two published WBI image names in this fixed order.
const mixinOrder=[46,47,18,2,53,8,23,32,15,50,10,31,58,3,45,35,27,43,5,49,33,9,42,19,29,28,14,39,12,38,41,13,37,48,7,16,24,55,40,61,26,17,0,1,60,51,30,4,22,25,54,21,56,59,6,63,57,62,11,36,20,34,44,52];
export function wbiKey(image:unknown,sub:unknown):string{
  const name=(url:unknown)=>(String(url??'').split('/').pop()??'').split('.')[0];
  const keys=name(image)+name(sub);
  if(!/^[0-9A-Za-z]{64}$/.test(keys))throw new RemoteError('api_changed','哔哩哔哩签名参数已变化，请更新扩展');
  return mixinOrder.map(n=>keys[n]).join('').slice(0,32);
}
export function signWbi(params:Record<string,string>,key:string,now=Date.now()):Record<string,string>{
  const signed:Record<string,string>={};
  for(const [name,value] of Object.entries({...params,wts:String(Math.round(now/1000))}))signed[name]=value.replace(/[!'()*]/g,'');
  const query=Object.keys(signed).sort().map(name=>`${encodeURIComponent(name)}=${encodeURIComponent(signed[name])}`).join('&');
  return {...signed,w_rid:md5(query+key)};
}
