// Exercise the exported V17 with real browser input and audible output after reload.
const {chromium}=require('playwright');
const fs=require('node:fs');
(async()=>{
 fs.mkdirSync('browser-evidence',{recursive:true});
 const browser=await chromium.launch({executablePath:'/usr/bin/google-chrome',headless:true,args:['--no-sandbox','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
 const page=await browser.newPage({viewport:{width:400,height:250}});
 const logs=[],errors=[];
 page.on('console',m=>{logs.push(m.type()+': '+m.text());if(m.text().includes('SCRIPT ERROR'))errors.push(m.text());});
 page.on('pageerror',e=>errors.push(e.message));
 async function clickControl(label,titleOnly=false){
  const ui=await page.evaluate(()=>window.starworldUi);
  const item=(titleOnly?ui.buttons:ui.controls).find(x=>x.text===label || x.text.startsWith(label+'  →'));
  if(!item)throw Error('Visible game button missing: '+label);
  const box=await page.locator('canvas').boundingBox();
  await page.mouse.click(box.x+item.x/ui.width*box.width,box.y+item.y/ui.height*box.height,{delay:150});
 }
 async function verifySound(){
  for(let attempt=0;attempt<3;attempt++){
   await page.locator('#sound').click({force:true,timeout:90000,noWaitAfter:true});
   try{
    await page.waitForFunction(()=>window.starworldDiagnostics().peakRms>0.00002 && window.starworldMusicPeakDb>-65,{},{timeout:15000});return;
   }catch(error){if(attempt===2)throw error;}
  }
 }
 try{
  await page.goto('http://127.0.0.1:8765/');
  await page.screenshot({path:'browser-evidence/home.png'});
  await page.getByRole('link',{name:'去小世界走走 →'}).first().click();
  await page.screenshot({path:'browser-evidence/loading.png'});
  const begun=Date.now();await page.locator('#start').click();
  await page.waitForFunction(()=>window.starworldDiagnostics?.().ready,{},{timeout:600000});
  const readyMs=Date.now()-begun;await verifySound();
  await page.waitForFunction(()=>window.starworldUi?.buttons?.length>0 && window.starworldUi?.booting===false,{},{timeout:30000});
  const font=await page.evaluate(()=>window.starworldFontCheck);
  if(!font || Object.values(font).some(v=>v!==true))throw Error('Bundled Chinese font coverage failed: '+JSON.stringify(font));
  fs.writeFileSync('browser-evidence/font.json',JSON.stringify(font,null,2));
  const ui=await page.evaluate(()=>window.starworldUi);
  for(const label of ['新游戏','先随便走走','设置','关于与声明','退出游戏'])if(!ui.buttons.some(x=>x.text===label))throw Error('V17 home entry missing: '+label);
  await page.screenshot({path:'browser-evidence/game-home.png'});
  await clickControl('设置',true);
  await page.waitForFunction(()=>window.starworldUi.panel==='settings',{},{timeout:20000});
  await page.keyboard.press('Escape');await page.waitForFunction(()=>window.starworldUi.panel==='title',{},{timeout:20000});
  await clickControl('关于与声明',true);
  await page.waitForFunction(()=>window.starworldUi.about===true,{},{timeout:20000});
  await page.keyboard.press('Escape');await page.waitForFunction(()=>window.starworldUi.about===false,{},{timeout:20000});
  await clickControl('新游戏',true);
  await page.waitForFunction(()=>window.starworldUi.buttons.some(x=>x.text==='出发吧'),{},{timeout:20000});
  // Reset diagnostics only, so later checks cannot reuse pre-reload sound evidence.
  await page.evaluate(()=>{window.starworldAudioPeak=0;window.starworldMusicPeakDb=-200;});
  await clickControl('出发吧',true);
  await page.waitForFunction(()=>window.starworldUi.title===false,{},{timeout:30000});
  // Wait for the actual skip affordance. A Space loop could also dismiss the
  // following chapter page before its real Start button is inspected.
  await page.waitForFunction(()=>window.starworldUi.openingSkip?.visible,{},{timeout:120000});
  const openingUi=await page.evaluate(()=>window.starworldUi),skip=openingUi.openingSkip;
  const openingCanvas=await page.locator('canvas').boundingBox();
  await page.mouse.click(openingCanvas.x+skip.x/openingUi.width*openingCanvas.width,openingCanvas.y+skip.y/openingUi.height*openingCanvas.height,{delay:150});
  await page.waitForFunction(()=>window.starworldUi.chapter===true && window.starworldUi.opening===false,{},{timeout:60000});
  await page.screenshot({path:'browser-evidence/chapter.png'});
  await clickControl('开始第一章');
  await page.waitForFunction(()=>!window.starworldUi.chapter && !window.starworldUi.locked,{},{timeout:30000});
  await page.evaluate(()=>{window.starworldAudioPeak=0;window.starworldMusicPeakDb=-200;});
  await verifySound();
  await page.keyboard.down('ArrowUp');
  try{await page.waitForFunction(()=>window.starworldUi.position[2]<3.0,{},{timeout:30000});}
  finally{await page.keyboard.up('ArrowUp');}
  // A prepared prop must remain usable after the normal New Game / opening flow.
  await page.keyboard.press('l');
  await page.waitForFunction(()=>window.starworldUi.performance==='wish',{},{timeout:20000});
  await page.screenshot({path:'browser-evidence/wish-after-new-game.png'});
  await page.keyboard.press('e');await page.waitForFunction(()=>!window.starworldUi.performing,{},{timeout:120000});
  const before=await page.evaluate(()=>window.starworldUi.position);
  await page.keyboard.down('ArrowRight');
  try{await page.waitForFunction(p=>Math.hypot(...window.starworldUi.position.map((v,i)=>v-p[i]))>.15,before,{timeout:30000});}
  finally{await page.keyboard.up('ArrowRight');}
  const after=await page.evaluate(()=>window.starworldUi.position);
  const moved=Math.hypot(...after.map((v,i)=>v-before[i]));
  if(moved<0.1)throw Error('Player did not move after keyboard input');
  await page.keyboard.press('n');await page.waitForFunction(()=>window.starworldUi.panel==='map',{},{timeout:15000});
  await page.screenshot({path:'browser-evidence/map.png'});await page.keyboard.press('Escape');
  const result=await page.evaluate(()=>window.starworldDiagnostics());
  Object.assign(result,{movementMetres:moved,startupReadyMs:readyMs,totalSmokeMs:Date.now()-begun,musicPeakDb:await page.evaluate(()=>window.starworldMusicPeakDb),verified:['home entries','settings return','about Escape','new game','chapter start button','wish after new game','movement','map','font','real audio after opening'],testViewport:{width:400,height:250,renderer:'Chromium SwiftShader software rasterization'},errors});
  fs.writeFileSync('browser-evidence/audio.json',JSON.stringify(result,null,2));
  await page.screenshot({path:'browser-evidence/game.png'});console.log('BROWSER_V17_VERIFIED',JSON.stringify(result));
  if(errors.length)throw Error(errors.join('\n'));
 }finally{
  const diagnostics=await page.evaluate(()=>window.starworldDiagnostics?.()).catch(()=>null);
  const ui=await page.evaluate(()=>window.starworldUi).catch(()=>null);
  const musicPeakDb=await page.evaluate(()=>window.starworldMusicPeakDb).catch(()=>null);
  const preparation=await page.evaluate(()=>({sceneReady:window.starworldSceneReady,warmup:window.starworldWarmup})).catch(()=>null);
  fs.writeFileSync('browser-evidence/diagnostics.json',JSON.stringify({diagnostics,ui,musicPeakDb,preparation},null,2));
  fs.writeFileSync('browser-evidence/console.log',logs.join('\n'));
  await page.screenshot({path:'browser-evidence/final.png'}).catch(()=>{});await browser.close();
 }
})().catch(e=>{console.error(e);process.exit(1);});
