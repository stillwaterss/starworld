let playwright;try{playwright=require('playwright');}catch{playwright=require('D:/Caches/npm/_npx/31e32ef8478fbf80/node_modules/playwright');}const {chromium}=playwright;
const fs=require('node:fs'),path=require('node:path');
const out=process.argv[2]||'audio-evidence',url=process.argv[3]||'http://127.0.0.1:8788/play/';
fs.mkdirSync(out,{recursive:true});
(async()=>{
 const browser=await chromium.launch({executablePath:process.env.CHROME_PATH||(process.platform==='win32'?'C:/Users/Administrator/AppData/Local/Google/Chrome/Application/chrome.exe':'/usr/bin/google-chrome'),headless:true,args:process.platform==='win32'?['--use-angle=d3d11','--enable-gpu','--ignore-gpu-blocklist']:['--no-sandbox','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
 const page=await browser.newPage({viewport:{width:1280,height:720}}),errors=[];
 page.on('pageerror',e=>errors.push(e.message));page.on('console',m=>{if(m.text().includes('SCRIPT ERROR'))errors.push(m.text());});
 await page.addInitScript(()=>{
  const nativeConnect=AudioNode.prototype.connect,outputs=[],contexts=[];
  window.audioContinuity={bins:[],errors:[],positions:[]};window.audioReviewPhase='loading';
  const processor=`class Probe extends AudioWorkletProcessor{constructor(){super();this.phase='loading';this.sum=0;this.max=0;this.n=0;this.port.onmessage=e=>{this.phase=e.data;this.sum=0;this.max=0;this.n=0;};}process(inputs){const a=inputs[0][0];if(a){for(const x of a){this.sum+=x*x;this.max=Math.max(this.max,Math.abs(x));this.n++;}if(this.n>=sampleRate*.02){this.port.postMessage({phase:this.phase,time:currentTime,rms:Math.sqrt(this.sum/this.n),max:this.max,seconds:this.n/sampleRate});this.sum=0;this.max=0;this.n=0;}}return true;}}registerProcessor('continuity-probe',Probe);`;
  async function prepare(ctx){
   try{
    await ctx.audioWorklet.addModule(URL.createObjectURL(new Blob([processor],{type:'text/javascript'})));
    const probe=new AudioWorkletNode(ctx,'continuity-probe'),mute=ctx.createGain();mute.gain.value=0;
    nativeConnect.call(probe,mute);nativeConnect.call(mute,ctx.destination);
    const entry={ctx,probe};contexts.push(entry);
    for(const output of outputs.filter(x=>x.context===ctx))nativeConnect.call(output,probe);
    probe.port.onmessage=e=>window.audioContinuity.bins.push(e.data);
   }catch(e){window.audioContinuity.errors.push(String(e));}
  }
  const Native=window.AudioContext;
  window.AudioContext=new Proxy(Native,{construct(t,args){const ctx=Reflect.construct(t,args);prepare(ctx);return ctx;}});
  AudioNode.prototype.connect=function(dest,...args){const ret=nativeConnect.call(this,dest,...args);if(dest===this.context.destination){outputs.push(this);const entry=contexts.find(x=>x.ctx===this.context);if(entry)nativeConnect.call(this,entry.probe);}return ret;};
  window.setAudioReviewPhase=phase=>{window.audioReviewPhase=phase;for(const e of contexts)e.probe.port.postMessage(phase);};
 });
 async function phase(name,seconds,kind){
  await page.evaluate(n=>window.setAudioReviewPhase(n),name);
  const positions=[];if(kind==='run')await page.keyboard.down('Shift');
  const start=Date.now();let direction='';
  try{while(Date.now()-start<seconds*1000){const next=kind?(Math.floor((Date.now()-start)/900)%2?'ArrowUp':'ArrowDown'):'';if(next!==direction){if(direction)await page.keyboard.up(direction);if(next)await page.keyboard.down(next);direction=next;}if(process.env.AUDIO_STRESS_MAIN==='1'&&Math.floor((Date.now()-start)/1000)%4===2)await page.evaluate(()=>{const end=performance.now()+300;while(performance.now()<end){}});positions.push(await page.evaluate(()=>window.starworldUi.position));await page.waitForTimeout(150);}}
  finally{if(direction)await page.keyboard.up(direction);if(kind==='run')await page.keyboard.up('Shift');}
  await page.waitForTimeout(100);
  const bins=await page.evaluate(n=>window.audioContinuity.bins.filter(x=>x.phase===n),name);let run=0,longest=0,total=0;
  for(const b of bins){if(b.rms<1e-7){run+=b.seconds;total+=b.seconds;longest=Math.max(longest,run);}else run=0;}
  const audio=await page.evaluate(()=>({status:window.starworldAudioStatus,diagnostics:window.starworldDiagnostics()}));const result={name,audio,injectedMainThreadStalls:process.env.AUDIO_STRESS_MAIN==='1',bins:bins.length,measuredSeconds:bins.reduce((s,b)=>s+b.seconds,0),maxSilentMs:longest*1000,totalSilentMs:total*1000,peakRms:Math.max(...bins.map(x=>x.rms)),positionRange:positions.reduce((v,p)=>v.map((x,i)=>[Math.min(x[0],p[i]),Math.max(x[1],p[i])]),[[Infinity,-Infinity],[Infinity,-Infinity],[Infinity,-Infinity]])};
  results.push(result);fs.writeFileSync(path.join(out,'summary.json'),JSON.stringify({results,errors},null,2));console.log(JSON.stringify(result));
 }
 const results=[];
 try{
  await page.goto(url);await page.locator('#start').click();
  await page.waitForFunction(()=>window.starworldDiagnostics?.().ready&&window.starworldUi?.booting===false,{},{timeout:300000});
  const loading=await page.evaluate(()=>({bins:window.audioContinuity.bins.filter(x=>x.phase==='loading'&&(window.starworldAudioGateOpenedAt===undefined||x.time<window.starworldAudioGateOpenedAt-.03)),diagnostics:window.starworldDiagnostics(),probeErrors:window.audioContinuity.errors}));
  fs.writeFileSync(path.join(out,'loading.json'),JSON.stringify({maxRms:Math.max(...loading.bins.map(x=>x.rms)),samples:loading.bins.length,diagnostics:loading.diagnostics,probeErrors:loading.probeErrors},null,2));
  if(process.env.AUDIO_LOADING_PROBE==='1')return;
  const ui=await page.evaluate(()=>window.starworldUi),button=ui.controls.find(x=>x.text==='先随便走走'),rect=await page.locator('canvas').boundingBox();
  await page.mouse.click(rect.x+button.x/ui.width*rect.width,rect.y+button.y/ui.height*rect.height);await page.waitForFunction(()=>!window.starworldUi.locked);
  if(process.env.AUDIO_DUSK_HEAD_ONLY==='1'){
   await page.keyboard.press('t');await page.waitForTimeout(7500);await page.keyboard.press('t');await page.waitForTimeout(7500);
   await page.waitForFunction(()=>window.starworldAudioStatus?.musicPositions[1]%(window.starworldAudioStatus?.musicLengths?.[1]||68.5714286)<1.2,{},{timeout:85000});
   await phase('dusk_loop_opening_walk',24,'walk');
  }else{
  await phase('night_run',22,'run');
  await page.keyboard.press('t');await page.waitForTimeout(7500);await phase('day_run',22,'run');
  await page.keyboard.press('t');await page.waitForTimeout(7500);await phase('dusk_idle',22,'');await phase('dusk_walk',22,'walk');await phase('dusk_run',22,'run');
  }
  fs.writeFileSync(path.join(out,'audio-bins.json'),JSON.stringify(await page.evaluate(()=>window.audioContinuity)));
  if(results.some(r=>r.peakRms<.00002))throw Error('A tested music phase was silent');
  if(errors.length)throw Error(errors.join('\n'));
 }finally{fs.writeFileSync(path.join(out,'last-state.json'),JSON.stringify(await page.evaluate(()=>({ui:window.starworldUi,diagnostics:window.starworldDiagnostics?.(),audio:window.starworldAudioStatus})).catch(()=>null),null,2));await browser.close();}
})().catch(e=>{console.error(e);process.exit(1);});
