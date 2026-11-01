import 'dart:convert';

import 'package:pure_live/i18n/i18n.dart';

/// The receiver's self-contained browser remote; no external assets, cookies,
/// tokens in URLs, HTML interpolation of user titles, or credential export.
String remoteControlHtml() {
  final labels = <String, String>{
    for (final key in [
      'remote_control_title',
      'remote_control_pair',
      'remote_control_code',
      'remote_control_link',
      'remote_control_send',
      'remote_control_unpair',
      'remote_control_idle',
      'remote_control_failed',
      'remote_control_paired',
      'remote_control_ok',
      'remote_control_application',
      'remote_control_text',
      'remote_control_text_hint',
      'play',
      'pause',
      'refresh',
      'previous',
      'next',
      'volume',
      'mute',
      'fullscreen',
      'danmaku',
      'back',
      'home',
      'screen_share_view',
      'screen_share_stop',
      'screen_share_screenshot',
      'screen_share_record',
      'screen_share_record_stop',
      'screen_share_download',
      'screen_share_video_only',
      'screen_share_local_consent',
      'screen_share_failed',
      'screen_share_recording',
    ])
      key: i18nOr(key, key),
  };
  final encoded = jsonEncode(labels).replaceAll('<', r'\u003c');
  return '''
<!doctype html><html lang="zh"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>PureLive</title>
<style>body{font:16px system-ui;background:#14161b;color:#f4f4f6;max-width:720px;margin:auto;padding:20px}input,button{font:inherit;border-radius:12px;padding:12px;border:1px solid #777;margin:4px;min-height:48px;box-sizing:border-box}input{max-width:95%}button{cursor:pointer;background:#303743;color:inherit}button:disabled{opacity:.4}#keys{display:grid;grid-template-columns:repeat(3,1fr)}#keys button{min-width:0}#state{overflow-wrap:anywhere}#status{min-height:24px}video{display:block;background:#000;width:100%;max-height:70vh}#screenActions{display:flex;flex-wrap:wrap}a{color:#b8d1ff;display:block;padding:10px;overflow-wrap:anywhere}.hint{font-size:14px;color:#ccd0d8}</style>
<h1 id="title"></h1><div id="pair"><input id="code" inputmode="numeric" maxlength="6" autocomplete="off"><button id="connect"></button></div>
<p id="status" role="status"></p><div id="remote" hidden><p id="state"></p>
<div id="keys"></div><p><input id="link" type="text" maxlength="4096"><button id="send"></button></p>
<p><input id="text" maxlength="4096" autocomplete="off"><button id="typeText"></button></p>
<label id="volumeLabel" for="volume"></label><input id="volume" type="range" min="0" max="100" value="50">
<hr><p id="screenHint" class="hint"></p><video id="screen" autoplay playsinline muted hidden></video>
<div id="screenActions"><button id="view"></button><button id="captureStop" disabled></button><button id="screenshot" disabled></button><button id="record" disabled></button></div>
<p id="recordHint" class="hint"></p><p><button id="disconnect"></button></p></div><div id="downloads"></div>
<script>
const labels=$encoded;
const el=id=>document.getElementById(id);
let token=sessionStorage.getItem('purelive-remote-token')||'',target=null,inputId=null,busy=false,polling=null,commandVersion=0;
let pc=null,screenId=null,media=null,mediaEpoch=0,screenBusy=false,recorder=null,recordTimer=null;
let localIcePort=null;
const downloads=[];
for(const [id,key]of Object.entries({title:'remote_control_title',connect:'remote_control_pair',send:'remote_control_send',disconnect:'remote_control_unpair',volumeLabel:'volume',typeText:'remote_control_text',view:'screen_share_view',captureStop:'screen_share_stop',screenshot:'screen_share_screenshot',record:'screen_share_record',screenHint:'screen_share_local_consent'}))el(id).textContent=labels[key];
el('code').placeholder=labels.remote_control_code;el('link').placeholder=labels.remote_control_link;el('text').placeholder=labels.remote_control_text_hint;
async function api(path,body,keepalive=false){const r=await fetch('/api/'+path,{method:body===undefined?'GET':'POST',headers:{'Content-Type':'application/json',...(token?{'Authorization':'Bearer '+token}:{})},body:body===undefined?undefined:JSON.stringify(body),cache:'no-store',keepalive,signal:AbortSignal.timeout(path.startsWith('screen/')?30000:15000)});if(!r.ok){if(r.status===401){token='';sessionStorage.removeItem('purelive-remote-token');closeScreen(false);show();}throw Error(r.status)}return r.headers.get('content-type')?.includes('json')?await r.json():null;}
function show(){el('pair').hidden=!!token;el('remote').hidden=!token;}
async function status(force=false){if(!token)return;if(polling){if(!force)return;await polling.catch(()=>{});}const version=commandVersion;const work=(async()=>{try{const data=await api('status');localIcePort=Number.isInteger(data.localIcePort)&&data.localIcePort>0&&data.localIcePort<=65535?data.localIcePort:null;if(version!==commandVersion||!token)return;if(pc&&screenId&&data.screen&&!data.screen.capturing)closeScreen(false);target=data.targetId;const nextInput=data.state?.inputId;const secret=!!data.state?.secretInput;if(nextInput!==inputId||(el('text').type==='password')!==secret)el('text').value='';inputId=nextInput;el('state').textContent=data.state?[data.state.nick,data.state.title].filter(Boolean).join(' · '):labels.remote_control_idle;const allowed=data.state?.commands||[];document.querySelectorAll('#keys button').forEach(b=>b.disabled=!target||!allowed.includes(b.dataset.command));el('typeText').disabled=!target||!Number.isInteger(inputId);el('text').disabled=!Number.isInteger(inputId);el('text').type=data.state?.secretInput?'password':'text';el('view').disabled=screenBusy||!!pc||!data.screen?.captureReady||!window.RTCPeerConnection;if(typeof data.state?.volume==='number'&&document.activeElement!==el('volume'))el('volume').value=Math.round(data.state.volume*100);}catch(e){el('status').textContent=labels.remote_control_failed;}})();polling=work;await work;if(polling===work)polling=null;}
async function command(name,value){if(busy||!target)return;busy=true;commandVersion++;const selected=target;try{await api('command',{targetId:selected,command:name,value});el('status').textContent=labels.remote_control_ok;}catch(e){el('status').textContent=labels.remote_control_failed;}finally{busy=false;await status(true);}}
for(const name of ['previous','up','next','left','ok','right','play','down','pause','refresh','mute','fullscreen','danmaku','back','home']){const button=document.createElement('button');button.dataset.command=name;button.textContent=({up:'↑',down:'↓',left:'←',right:'→',ok:'OK'})[name]||labels[name]||name;button.onclick=()=>command(name);el('keys').append(button);}
el('connect').onclick=async()=>{try{const data=await api('pair',{code:el('code').value.trim()});token=data.token;sessionStorage.setItem('purelive-remote-token',token);el('code').value='';el('status').textContent=labels.remote_control_paired;show();await status(true);}catch(e){el('status').textContent=labels.remote_control_failed;}};
el('send').onclick=async()=>{if(busy)return;busy=true;commandVersion++;try{await api('link',{text:el('link').value.trim()});el('status').textContent=labels.remote_control_ok;el('link').value='';}catch(e){el('status').textContent=labels.remote_control_failed;}finally{busy=false;await status(true);}};
el('typeText').onclick=async()=>{if(busy||!target||!Number.isInteger(inputId))return;busy=true;commandVersion++;try{await api('text',{targetId:target,inputId,text:el('text').value});el('text').value='';el('status').textContent=labels.remote_control_ok;}catch(e){el('status').textContent=labels.remote_control_failed;}finally{busy=false;await status(true);}};
el('volume').onchange=()=>command('volume',Number(el('volume').value)/100);
function bindPresence(channel,epoch){channel.onmessage=event=>{if(epoch===mediaEpoch&&event.data==='ping'&&channel.readyState==='open')channel.send('pong');};}
function iceComplete(connection){if(connection.iceGatheringState==='complete')return Promise.resolve();return new Promise((resolve,reject)=>{const timer=setTimeout(()=>{connection.removeEventListener('icegatheringstatechange',changed);reject(Error('ICE timeout'));},10000);function changed(){if(connection.iceGatheringState==='complete'){clearTimeout(timer);connection.removeEventListener('icegatheringstatechange',changed);resolve();}}connection.addEventListener('icegatheringstatechange',changed);changed();});}
function saveFile(blob,extension){const url=URL.createObjectURL(blob);const link=document.createElement('a');link.href=url;link.download='PureLive-screen-'+new Date().toISOString().replace(/[:.]/g,'-')+'.'+extension;link.textContent=labels.screen_share_download+' · '+link.download;el('downloads').append(link);downloads.push({url,link});while(downloads.length>2){const old=downloads.shift();URL.revokeObjectURL(old.url);old.link.remove();}link.click();}
function recordStop(){if(recorder&&recorder.state!=='inactive')recorder.stop();if(recordTimer)clearTimeout(recordTimer);recordTimer=null;}
function closeScreen(remote=true,keepalive=false){const previous=pc,id=screenId;pc=null;screenId=null;mediaEpoch++;screenBusy=false;recordStop();if(previous){previous.onconnectionstatechange=null;previous.ontrack=null;previous.ondatachannel=null;previous.close();}if(media){media.getTracks().forEach(t=>t.stop());media=null;}el('screen').srcObject=null;el('screen').hidden=true;el('captureStop').disabled=true;el('screenshot').disabled=true;el('record').disabled=true;if(remote&&id&&token)api('screen/stop',{id},keepalive).catch(()=>{});}
el('view').onclick=async()=>{if(pc||screenBusy||!token)return;screenBusy=true;el('view').disabled=true;const epoch=++mediaEpoch;const connection=new RTCPeerConnection({iceServers:localIcePort?[{urls:'stun:'+location.hostname+':'+localIcePort}]:[]});pc=connection;connection.ondatachannel=event=>bindPresence(event.channel,epoch);connection.ontrack=event=>{if(epoch!==mediaEpoch)return;media=event.streams[0]||new MediaStream([event.track]);el('screen').srcObject=media;el('screen').hidden=false;el('screen').play().catch(()=>{});el('screenshot').disabled=false;el('record').disabled=!window.MediaRecorder;event.track.onended=()=>closeScreen(true);};connection.onconnectionstatechange=()=>{if(epoch===mediaEpoch&&['failed','closed'].includes(connection.connectionState))closeScreen(true);};try{const offer=await api('screen/view',{});if(epoch!==mediaEpoch){api('screen/stop',{id:offer.id}).catch(()=>{});return;}screenId=offer.id;await connection.setRemoteDescription({type:offer.type,sdp:offer.sdp});await connection.setLocalDescription(await connection.createAnswer());await iceComplete(connection);if(epoch!==mediaEpoch)return;await api('screen/answer',{id:screenId,type:connection.localDescription.type,sdp:connection.localDescription.sdp});if(epoch!==mediaEpoch)return;el('captureStop').disabled=false;el('status').textContent=labels.screen_share_video_only;}catch(e){if(epoch===mediaEpoch){closeScreen(true);el('status').textContent=labels.screen_share_failed;}}finally{if(epoch===mediaEpoch)screenBusy=false;await status(true);}};
el('captureStop').onclick=()=>{closeScreen(true);status(true);};
el('screenshot').onclick=()=>{const video=el('screen');if(!media||!video.videoWidth||video.readyState<2)return;const canvas=document.createElement('canvas');canvas.width=video.videoWidth;canvas.height=video.videoHeight;canvas.getContext('2d').drawImage(video,0,0);canvas.toBlob(blob=>{if(blob)saveFile(blob,'png');else el('status').textContent=labels.screen_share_failed;},'image/png');};
el('record').onclick=()=>{if(recorder&&recorder.state!=='inactive'){recordStop();return;}if(!media||!window.MediaRecorder)return;try{const mime=['video/webm;codecs=vp8','video/webm','video/mp4'].find(type=>MediaRecorder.isTypeSupported(type));if(!mime)throw Error('recording unsupported');const parts=[];let bytes=0;const current=new MediaRecorder(media,{mimeType:mime,videoBitsPerSecond:2500000});recorder=current;current.ondataavailable=event=>{if(event.data.size){parts.push(event.data);bytes+=event.data.size;if(bytes>=128*1024*1024&&current.state!=='inactive')current.stop();}};current.onstop=()=>{if(parts.length)saveFile(new Blob(parts,{type:mime}),mime.includes('mp4')?'mp4':'webm');parts.length=0;if(recorder===current){recorder=null;if(recordTimer)clearTimeout(recordTimer);recordTimer=null;el('record').textContent=labels.screen_share_record;el('recordHint').textContent='';}};current.start(1000);recordTimer=setTimeout(recordStop,600000);el('record').textContent=labels.screen_share_record_stop;el('recordHint').textContent=labels.screen_share_recording;}catch(e){el('status').textContent=labels.screen_share_failed;}};
el('disconnect').onclick=async()=>{closeScreen(true);try{await api('unpair',{});}finally{token='';target=null;inputId=null;sessionStorage.removeItem('purelive-remote-token');show();}};
window.addEventListener('pagehide',()=>closeScreen(true,true));show();status();setInterval(()=>status(),2000);
</script></html>''';
}
