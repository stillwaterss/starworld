// Runs on the Linux build runner, against the exported game, before publishing.
const {chromium}=require('playwright');
const fs=require('node:fs');
(async()=>{
 fs.mkdirSync('browser-evidence',{recursive:true});
 const browser=await chromium.launch({executablePath:'/usr/bin/google-chrome',headless:true,args:['--no-sandbox','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
 const page=await browser.newPage({viewport:{width:800,height:500}});
 const logs=[],errors=[];
 page.on('console',m=>{logs.push(m.type()+': '+m.text());if(m.text().includes('SCRIPT ERROR'))errors.push(m.text());});
 page.on('pageerror',e=>errors.push(e.message));
 try{
  await page.goto('http://127.0.0.1:8765/');
  await page.screenshot({path:'browser-evidence/home.png'});
  await page.getByRole('link',{name:'去小世界走走 →'}).click();
  await page.screenshot({path:'browser-evidence/loading.png'});
  const begun=Date.now();
  await page.locator('#start').click();
  await page.waitForFunction(()=>window.starworldDiagnostics?.().ready,{},{timeout:120000});
  await page.locator('#sound').click({force:true,timeout:90000,noWaitAfter:true});
  await page.waitForFunction(()=>window.starworldDiagnostics().peakRms>0.00002,{},{timeout:45000});
  await page.waitForFunction(()=>window.starworldMusicPeakDb>-65,{},{timeout:45000});
  const result=await page.evaluate(()=>window.starworldDiagnostics());
  result.musicPeakDb=await page.evaluate(()=>window.starworldMusicPeakDb);
  result.startupMs=Date.now()-begun;
  result.errors=errors;
  fs.writeFileSync('browser-evidence/audio.json',JSON.stringify(result,null,2));
  await page.screenshot({path:'browser-evidence/game.png'});
  console.log('BROWSER_AUDIO_VERIFIED',JSON.stringify(result));
  if(errors.length)throw Error(errors.join('\n'));
 }finally{
  const diagnostics=await page.evaluate(()=>window.starworldDiagnostics?.()).catch(()=>null);
  fs.writeFileSync('browser-evidence/diagnostics.json',JSON.stringify(diagnostics,null,2));
  fs.writeFileSync('browser-evidence/console.log',logs.join('\n'));
  await page.screenshot({path:'browser-evidence/final.png'}).catch(()=>{});
  await browser.close();
 }
})().catch(e=>{console.error(e);process.exit(1);});
