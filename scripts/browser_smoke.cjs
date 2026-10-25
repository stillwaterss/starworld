// Runs on the Linux build runner, against the exported game, before publishing.
const {chromium}=require('playwright');
const fs=require('node:fs');
(async()=>{
 fs.mkdirSync('browser-evidence',{recursive:true});
 const browser=await chromium.launch({executablePath:'/usr/bin/google-chrome',headless:true,args:['--no-sandbox','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
 // CI uses software rasterization; a small viewport keeps GPU cost bounded.
 const page=await browser.newPage({viewport:{width:400,height:250}});
 const logs=[],errors=[];
 page.on('console',m=>{logs.push(m.type()+': '+m.text());if(m.text().includes('SCRIPT ERROR'))errors.push(m.text());});
 page.on('pageerror',e=>errors.push(e.message));
 try{
  await page.goto('http://127.0.0.1:8765/');
  await page.screenshot({path:'browser-evidence/home.png'});
  await page.getByRole('link',{name:'去小世界走走 →'}).first().click();
  await page.screenshot({path:'browser-evidence/loading.png'});
  const begun=Date.now();
  await page.locator('#start').click();
  await page.waitForFunction(()=>window.starworldDiagnostics?.().ready,{},{timeout:120000});
  await page.locator('#sound').click({force:true,timeout:90000,noWaitAfter:true});
  await page.waitForFunction(()=>window.starworldDiagnostics().peakRms>0.00002,{},{timeout:45000});
  await page.waitForFunction(()=>window.starworldMusicPeakDb>-65,{},{timeout:45000});
  await page.waitForFunction(()=>window.starworldUi?.buttons?.length>0,{},{timeout:30000});
  await page.waitForFunction(()=>window.starworldUi?.booting===false,{},{timeout:30000});
  const ui=await page.evaluate(()=>window.starworldUi);
  const free=ui.buttons.find(b=>b.text==='先随便走走');
  if(!free)throw Error('Free-roam button missing');
  const box=await page.locator('canvas').boundingBox();
  await page.mouse.click(box.x+free.x/ui.width*box.width,box.y+free.y/ui.height*box.height,{delay:150});
  await page.waitForFunction(()=>window.starworldUi?.title===false,{},{timeout:30000});
  const before=await page.evaluate(()=>window.starworldUi.position);
  await page.keyboard.down('ArrowRight');
  await page.waitForTimeout(2200);
  await page.keyboard.up('ArrowRight');
  const after=await page.evaluate(()=>window.starworldUi.position);
  const moved=Math.hypot(...after.map((v,i)=>v-before[i]));
  if(moved<0.1)throw Error('Player did not move after keyboard input');
  await page.keyboard.press('n');
  await page.waitForFunction(()=>window.starworldUi.panel==='map',{},{timeout:15000});
  await page.screenshot({path:'browser-evidence/map.png'});
  await page.keyboard.press('Escape');
  const result=await page.evaluate(()=>window.starworldDiagnostics());
  result.movementMetres=moved;
  result.testViewport={width:400,height:250,renderer:'Chromium SwiftShader software rasterization'};
  result.musicPeakDb=await page.evaluate(()=>window.starworldMusicPeakDb);
  result.startupMs=Date.now()-begun;
  result.errors=errors;
  fs.writeFileSync('browser-evidence/audio.json',JSON.stringify(result,null,2));
  await page.screenshot({path:'browser-evidence/game.png'});
  console.log('BROWSER_AUDIO_VERIFIED',JSON.stringify(result));
  if(errors.length)throw Error(errors.join('\n'));
 }finally{
  const diagnostics=await page.evaluate(()=>window.starworldDiagnostics?.()).catch(()=>null);
  const ui=await page.evaluate(()=>window.starworldUi).catch(()=>null);
  fs.writeFileSync('browser-evidence/diagnostics.json',JSON.stringify({diagnostics,ui},null,2));
  fs.writeFileSync('browser-evidence/console.log',logs.join('\n'));
  await page.screenshot({path:'browser-evidence/final.png'}).catch(()=>{});
  await browser.close();
 }
})().catch(e=>{console.error(e);process.exit(1);});
