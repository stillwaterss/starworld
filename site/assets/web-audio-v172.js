/* Gate all engine audio until the game is ready. Godot loops use native samples. */
(()=>{
 window.starworldAudioContexts=[];window.starworldAudioMeters=[];window.starworldAudioPeak=0;
 window.starworldGameAudioReady=false;
 const Native=window.AudioContext||window.webkitAudioContext,connect=AudioNode.prototype.connect;
 const routes=new WeakMap();
 function route(ctx){
  if(routes.has(ctx))return routes.get(ctx);
  const gate=ctx.createGain(),meter=ctx.createAnalyser();meter.fftSize=32768;
  gate.gain.value=0;connect.call(gate,meter);connect.call(meter,ctx.destination);
  const value={gate,meter,samples:new Float32Array(meter.fftSize)};
  routes.set(ctx,value);window.starworldAudioMeters.push(meter);return value;
 }
 if(Native){
  const Wrapped=new Proxy(Native,{construct(target,args){const ctx=Reflect.construct(target,args);window.starworldAudioContexts.push(ctx);route(ctx);if(navigator.userActivation?.hasBeenActive)ctx.resume().catch(()=>{});return ctx;}});
  window.AudioContext=Wrapped;if(window.webkitAudioContext)window.webkitAudioContext=Wrapped;
  AudioNode.prototype.connect=function(destination,...args){if(window.starworldAudioContexts.includes(this.context)&&destination===this.context.destination)return connect.call(this,route(this.context).gate,...args);return connect.call(this,destination,...args);};
 }
 let wantsSound=false,ready=false,lastAudioAt=performance.now();
 const sound=document.getElementById('sound'),note=document.getElementById('audio-note');
 sound.disabled=true;sound.textContent='声音准备中';
 function foreground(){return document.visibilityState!=='hidden'&&document.hasFocus();}
 function resume(){if(!foreground())return;for(const ctx of window.starworldAudioContexts)if(ctx.state==='suspended')ctx.resume().catch(()=>{});}
 function openGates(){
  for(const ctx of window.starworldAudioContexts){const gain=route(ctx).gate.gain;if(ready&&foreground()&&window.starworldAudioGateOpenedAt===undefined)window.starworldAudioGateOpenedAt=ctx.currentTime;gain.cancelScheduledValues(ctx.currentTime);gain.setValueAtTime(gain.value,ctx.currentTime);if(ready&&foreground())gain.linearRampToValueAtTime(1,ctx.currentTime+.35);else gain.setValueAtTime(0,ctx.currentTime);}
 }
 // A trailer opens in another tab/window. Silence the entire game mix while
 // away, including effects, without changing the player's stored mute/volumes.
 function syncForeground(){
  openGates();
  if(!foreground()){note.textContent='';return;}
  lastAudioAt=performance.now();
  if(ready)resume();
 }
 addEventListener('blur',()=>{for(const ctx of window.starworldAudioContexts){const g=route(ctx).gate.gain;g.cancelScheduledValues(ctx.currentTime);g.setValueAtTime(0,ctx.currentTime);}note.textContent='';});
 addEventListener('focus',syncForeground);
 document.addEventListener('visibilitychange',syncForeground);
 addEventListener('pageshow',syncForeground);
 window.starworldRequestSound=()=>{wantsSound=true;resume();};
 window.starworldStartAudio=()=>{
  if(ready)return;ready=true;window.starworldGameAudioReady=true;sound.disabled=false;
  resume();if(wantsSound&&window.starworldEnableSound)window.starworldEnableSound();openGates();lastAudioAt=performance.now();
 };
 addEventListener('pointerdown',resume,true);addEventListener('keydown',resume,true);
 sound.onclick=()=>{if(!ready)return;wantsSound=true;resume();if(window.starworldEnableSound)window.starworldEnableSound();openGates();note.textContent='正在开启声音…';document.getElementById('canvas').focus();};
 setInterval(()=>{
  let peak=0;
  for(const ctx of window.starworldAudioContexts){const r=route(ctx);r.meter.getFloatTimeDomainData(r.samples);let sum=0;for(const x of r.samples)sum+=x*x;peak=Math.max(peak,Math.sqrt(sum/r.samples.length));}
  window.starworldAudioPeak=Math.max(window.starworldAudioPeak,peak);
  if(ready&&foreground()&&peak>.00002){lastAudioAt=performance.now();sound.textContent='声音已开启 · 恢复';note.textContent='';}
  else if(ready&&foreground()&&wantsSound&&performance.now()-lastAudioAt>10000){sound.textContent='开启声音';note.textContent='若仍无声，请点击开启声音，并检查标签页是否静音。';}
 },250);
 window.starworldDiagnostics=()=>({ready,foreground:foreground(),outputGains:window.starworldAudioContexts.map(c=>route(c).gate.gain.value),contexts:window.starworldAudioContexts.map(c=>({state:c.state,sampleRate:c.sampleRate,currentTime:c.currentTime})),peakRms:window.starworldAudioPeak,meters:window.starworldAudioMeters.length,gatedUntilReady:true,backend:window.starworldAudioStatus?.backend});
})();
