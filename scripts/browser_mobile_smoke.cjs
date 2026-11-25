const {chromium}=require('playwright');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const url=process.env.STARWORLD_URL || 'http://127.0.0.1:8768/play/';
const out=process.env.STARWORLD_EVIDENCE || 'browser-evidence/mobile';
(async()=>{
 fs.mkdirSync(out,{recursive:true});
 const engineArgs=process.platform==='win32'?['--use-angle=d3d11']:['--no-sandbox','--use-angle=swiftshader','--enable-unsafe-swiftshader'];
 const launch=process.env.STARWORLD_CHROME?{executablePath:process.env.STARWORLD_CHROME}:{channel:'chrome'};
 const browser=await chromium.launch({...launch,headless:true,args:engineArgs});
 // Cloud runners have no phone GPU. Keep the touch layout and DPR check, with a
 // smaller backing canvas so software rendering doesn't stall the test's clock.
 const viewport=process.platform==='win32'?{width:844,height:390}:{width:480,height:260};
 const context=await browser.newContext({viewport,isMobile:true,hasTouch:true,deviceScaleFactor:3,locale:'zh-CN'});
 const page=await context.newPage(), errors=[];
 page.on('pageerror',e=>errors.push(e.message));
 page.on('crash',()=>errors.push('Chrome tab crashed'));
 page.on('console',m=>{if(/SCRIPT ERROR|WebGL context lost|wasm streaming compile failed/i.test(m.text()))errors.push(m.text());});
 const cdp=await context.newCDPSession(page);
 const wait=(f,arg,timeout=65000)=>page.waitForFunction(f,arg,{timeout});
 const probe=()=>page.evaluate(()=>({ui:window.starworldUi,touch:window.starworldTouch,late:window.starworldLate,stats:window.StarLoader.stats(),canvas:[document.querySelector('canvas').width,document.querySelector('canvas').height]}));
 function scale(point,ui,box){return {x:Math.round(box.x+point[0]/ui.width*box.width),y:Math.round(box.y+point[1]/ui.height*box.height)};}
 const send=(type,touchPoints=[])=>cdp.send('Input.dispatchTouchEvent',{type,touchPoints});
 async function tap(label){
  const {ui,touch}=await probe();
  const b=ui.buttons.concat(ui.controls).find(x=>x.text===label || x.text.startsWith(label+'  →'));
  const xy=b?[b.x,b.y]:touch?.buttons[label];assert(xy,JSON.stringify({label,buttons:ui.buttons,controls:ui.controls,touch}));
  const pos=scale(xy,ui,await page.locator('canvas').boundingBox());
  await page.touchscreen.tap(pos.x,pos.y);
 }
 try {
  await page.goto(url+'?device=mobile',{waitUntil:'domcontentloaded'});
  await page.locator('#start').tap();
  await wait(()=>window.starworldSceneReady && window.starworldUi?.title && document.body.classList.contains('ready'),null,280000);
  console.log("MOBILE_TITLE_READY");
  const title=await probe();
  assert(title.canvas[0]<=1280 && title.canvas[0]*title.canvas[1]<=722000,JSON.stringify(title.canvas));
  assert(title.stats.total>40_000_000 && title.stats.total<53_000_000,JSON.stringify(title.stats));
  assert.equal(title.late,undefined);
  await tap('新游戏');
  await wait(()=>window.starworldUi?.buttons.some(x=>x.text==='出发吧'));
  await tap('出发吧');
  await wait(()=>window.starworldUi?.openingSkip?.visible,null,200000);
  const {ui}=await probe(), box=await page.locator('canvas').boundingBox();
  let pos=scale([ui.openingSkip.x,ui.openingSkip.y],ui,box);
  await page.touchscreen.tap(pos.x,pos.y);
  await wait(()=>window.starworldUi?.chapter && window.starworldUi.controls.some(b=>b.text.startsWith('开始第一章')),null,120000);
  await tap('开始第一章');
  await wait(()=>window.starworldTouch?.controlsVisible && window.starworldTouch?.buttons['跳跃']);
  console.log("MOBILE_CHAPTER_STARTED");
  await wait(()=>window.starworldTouch.grounded === true);
  const start=await probe();
  assert.equal(start.late,undefined);
  await page.screenshot({path:out+'/in-game.png'});
  const j=scale(start.touch.joystick,start.ui,box);
  const jump=scale(start.touch.buttons['跳跃'],start.ui,box);
  const l={x:Math.round(box.width*.64),y:Math.round(box.height*.48),id:2};
  const stick={...j,id:1}, move={x:j.x+Math.round(viewport.height*.036),y:j.y-Math.round(viewport.height*.113),id:1};
  const look={...l,x:l.x+Math.round(viewport.width*.09),y:l.y+Math.round(viewport.height*.046)};
  await send('touchStart',[stick,l,{...jump,id:3}]);
  await send('touchEnd',[stick,l]);
  await wait(jumps=>window.starworldTouch.jumps>jumps,start.touch.jumps,15000);
  await send('touchMove',[move,look]);
  await wait(()=>Math.hypot(...window.starworldTouch.move)>.5);
  await wait(p=>Math.hypot(window.starworldUi.position[0]-p[0],window.starworldUi.position[2]-p[2])>.35,start.ui.position,20000);
  await wait(y=>Math.abs(window.starworldTouch.yaw-y)>.1,start.touch.yaw);
  await send('touchEnd',[]);
  await wait(()=>window.starworldTouch.move.every(x=>x===0));
  const after=await probe(); assert(Math.hypot(after.ui.position[0]-start.ui.position[0],after.ui.position[2]-start.ui.position[2])>.35);
  await send('touchStart',[stick]);await send('touchMove',[move]);await wait(()=>window.starworldTouch.move.some(x=>x!==0));await send('touchCancel');
  await wait(()=>window.starworldTouch.move.every(x=>x===0));
  await tap('菜单');await wait(()=>window.starworldTouch.menuOpen);
  await page.screenshot({path:out+'/menu.png'});
  await tap('快速存档');await wait(()=>window.starworldUi.saveSlots>0);
  await wait(()=>!window.starworldTouch.menuOpen);
  await tap('菜单');await wait(()=>window.starworldTouch.menuOpen);
  await tap('载入存档');await wait(()=>window.starworldUi.title && window.starworldUi.saveSlots>0);
  await wait(()=>window.starworldUi.buttons.some(x=>x.text.includes('第一章')));
  console.log('MOBILE_TOUCH_SAVE_PASS');
  await page.setViewportSize({width:viewport.height,height:viewport.width});await wait(()=>document.querySelector('canvas').height>document.querySelector('canvas').width);
  const portrait=await probe(); assert(portrait.canvas[1]<=1280); await page.screenshot({path:out+'/portrait.png'});
  await page.setViewportSize(viewport);await wait(()=>document.querySelector('canvas').width>document.querySelector('canvas').height);
  await page.evaluate(()=>document.querySelector('canvas').dispatchEvent(new Event('webglcontextlost')));
  await page.locator('#game-recovery').waitFor({state:'visible'});
  assert.deepEqual(errors,[]);
  const forced=await context.newPage(); await forced.route('**/starworld_manifest.json*',r=>r.abort());
  await forced.goto(url+'?device=desktop',{waitUntil:'domcontentloaded'});
  assert.equal(await forced.evaluate(()=>window.starworldMobile),false);
  console.log('MOBILE_BROWSER_PASS',JSON.stringify({canvas:start.canvas,core:start.stats.total,move:after.ui.position,yawDelta:after.touch.yaw-start.touch.yaw,errors}));
 }catch(e){
  console.error(JSON.stringify(await probe().catch(()=>null)),errors);
  await page.screenshot({path:out+'/failure.png',timeout:4000}).catch(()=>{});
  throw e;
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1});
