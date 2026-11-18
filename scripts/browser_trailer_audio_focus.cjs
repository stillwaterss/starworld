const {chromium}=require('playwright');
const assert=require('node:assert/strict');
const fs=require('node:fs');
(async()=>{
 const base=process.env.STARWORLD_TEST_URL||'http://127.0.0.1:8765/';
 const browser=await chromium.launch({...(process.platform==='win32'?{channel:'chrome'}:{executablePath:'/usr/bin/google-chrome'}),headless:true});
 const context=await browser.newContext();
 const errors=[];
 context.on('page',p=>p.on('pageerror',e=>errors.push(e.message)));
 // Playwright normally forces every page to appear focused, even background tabs.
 context.on('page',async p=>{const cdp=await context.newCDPSession(p);await cdp.send('Emulation.setFocusEmulationEnabled',{enabled:false});});
 await context.route('**/__audio-focus-check',route=>route.fulfill({contentType:'text/html',body:`<!doctype html><button id="begin">Start sound</button><canvas id="canvas" tabindex="0"></canvas><button id="sound"></button><div id="audio-note"></div><a id="trailer" href="trailer.html" target="_blank" rel="noopener">Trailer</a><script src="assets/web-audio-v172.js?v=trailer-focus-20261118"></script><script>
 begin.onclick=()=>{
  starworldRequestSound();window.ctx=new AudioContext();
  window.sourceVolume=ctx.createGain();sourceVolume.gain.value=.13;
  const tone=ctx.createOscillator();tone.connect(sourceVolume);sourceVolume.connect(ctx.destination);tone.start();
  starworldStartAudio();
 };
 </script>`}));
 const game=await context.newPage();
 try {
  await game.goto(new URL('__audio-focus-check',base).href);
  await game.locator('#begin').click();
  await game.waitForFunction(()=>starworldDiagnostics().outputGains[0]>.99);
  const before=await game.evaluate(()=>({gain:sourceVolume.gain.value,time:ctx.currentTime}));
  const popup=context.waitForEvent('page');
  await game.locator('#trailer').click();
  const trailer=await popup;await trailer.waitForLoadState();
  await trailer.bringToFront();
  await game.waitForFunction(()=>starworldDiagnostics().outputGains[0]===0,null,{polling:100,timeout:10000});
  await trailer.locator('#trailer-start').click();
  await trailer.waitForFunction(()=>{const v=document.getElementById('trailer-video');return !v.paused&&v.currentTime>.15;});
  assert.equal(await trailer.locator('#trailer-quality').inputValue(),'540');
  const silence=await game.evaluate(()=>{
   const a=new Float32Array(starworldAudioMeters[0].fftSize);
   starworldAudioMeters[0].getFloatTimeDomainData(a);
   return {peak:Math.max(...a.map(Math.abs)),gain:sourceVolume.gain.value,output:starworldDiagnostics().outputGains[0]};
  });
  assert.equal(silence.output,0);assert.ok(silence.peak<.00001);assert.equal(silence.gain,before.gain);
  await game.bringToFront();
  await game.waitForFunction(()=>starworldDiagnostics().outputGains[0]>.99);
  await trailer.waitForFunction(()=>document.getElementById('trailer-video').paused,null,{polling:100,timeout:10000});
  assert.equal(await game.evaluate(()=>sourceVolume.gain.value),before.gain);
  // The game gate must not unmute a player who chose silence in settings.
  await game.evaluate(()=>sourceVolume.gain.value=0);
  await trailer.bringToFront();await game.waitForFunction(()=>starworldDiagnostics().outputGains[0]===0,null,{polling:100,timeout:10000});
  await trailer.close();await game.bringToFront();
  await game.waitForFunction(()=>starworldDiagnostics().outputGains[0]>.99);
  assert.equal(await game.evaluate(()=>sourceVolume.gain.value),0);
  assert.deepEqual(errors,[]);
  fs.mkdirSync('browser-evidence',{recursive:true});
  fs.writeFileSync('browser-evidence/trailer-audio-focus.json',JSON.stringify({silence,restoredVolume:before.gain,mutedSettingPreserved:true,trailerPausesOnReturn:true,errors},null,2));
  console.log('TRAILER_AUDIO_FOCUS_PASS',JSON.stringify(silence));
 } finally {await browser.close();}
})().catch(e=>{console.error(e);process.exit(1)});
