/* 星星人的小世界 · download loader v37 (Claude), used by game/web_shell.html.
 *
 * v36 fetched 1 MB gzip parts 4 at a time, but a browser sends every request to one site
 * over ONE HTTP/2 connection, so on a slow or lossy line the 4 parts shared one trickle; a
 * part that got nothing for 15 s was aborted and its bytes thrown away, and after 4 rounds
 * the whole download gave up ("下载中断了"). Measured on the real site through a slow line:
 * one connection ≈ 100 KB/s, 8 connections ≈ 385 KB/s; Kimi's diagnostics show the abort loop.
 * v37:
 *   - several connections at once: this site with cookies and without cookies are two
 *     separate connections in Chrome (checked with DevTools on stillwaterss.github.io), and
 *     every mirror (window.STAR_MIRRORS, manifest "mirrors") adds another. Workers on all
 *     lanes share one queue, so a faster lane simply takes more parts;
 *   - no byte is thrown away: an interrupted part continues from the byte where it stopped
 *     (HTTP Range), possibly on another lane;
 *   - it never gives up: when every lane fails it keeps retrying with growing pauses, and
 *     retries at once when the device comes back online or the page becomes visible;
 *   - end game: when the queue is empty, idle lanes help with the slowest unfinished part
 *     from where it is; the first lane to reach the end wins;
 *   - finished parts are kept in the browser cache: a refresh or a later visit resumes.
 * Without starworld_manifest.json (or without DecompressionStream) nothing changes: the
 * engine downloads index.wasm / index.<hash>.pck by itself, as before.
 *
 * API (same as v36): StarLoader.prefetch(onStatus) -> starts at once
 *      onStatus({loaded,total,speed,left,text,detail,lanes,retrying})
 *    StarLoader.ready() -> Promise (true when the bytes are in, false without a manifest)
 *    StarLoader.serve() -> hands the bytes to the engine (call before engine.startGame)
 *    StarLoader.late(engine) -> background download of the late pack
 *    StarLoader.stats() -> numbers for tests (lanes, bytes per lane, resumed parts, retries)
 */
(function () {
	'use strict';
	const HERE = new URL('.', location.href).href;
	const RUNS_PER_LANE = 3;
	const STALL_MS = 20000;        // a request that receives nothing for this long is stopped (its bytes are kept)
	const FIRST_BYTE_MS = 20000;   // no answer at all (a busy line can take a while to answer)
	const CACHE_PREFIX = 'starworld-parts-';
	const RESCUE_MS = 25000;       // nothing at all arrived for this long: open a fresh connection
	const S = { manifest: null, cache: null, loaded: 0, total: 0, samples: [], bytes: null, lanes: [], resumed: 0, retries: 0, lastByte: 0, why: {} };
	let readyResolve, readyReject;
	const readyPromise = new Promise((res, rej) => { readyResolve = res; readyReject = rej; });
	readyPromise.catch(() => {});
	const sleep = (ms) => new Promise((res) => setTimeout(res, ms));
	const now = () => performance.now();

	const mb = (n) => (n / 1048576).toFixed(n < 10485760 ? 1 : 0);
	function speedNow() {
		const t = now();
		S.samples = S.samples.filter((s) => t - s.t < 8000);
		if (S.samples.length < 2) return 0;
		const a = S.samples[0], b = S.samples[S.samples.length - 1];
		return (b.n - a.n) / Math.max(0.5, (b.t - a.t) / 1000);
	}
	function status() {
		S.samples.push({ t: now(), n: S.loaded });
		const v = speedNow();
		const left = v > 0 ? (S.total - S.loaded) / v : 0;
		const retrying = S.lastByte > 0 && now() - S.lastByte > 6000;
		let text = `正在下载 ${mb(S.loaded)} / ${mb(S.total)} MB`;
		let detail = '';
		if (retrying) {
			text += '  ·  网络不稳，正在重新连接…';
			detail = `已下载的 ${mb(S.loaded)} MB 都保存着，不会丢失；连上后自动接着下。`;
		} else if (v > 0) {
			text += `  ·  ${v > 1048576 ? (v / 1048576).toFixed(1) + ' MB/s' : Math.round(v / 1024) + ' KB/s'}`;
			if (left > 5) detail = left > 90 ? `预计还要约 ${Math.ceil(left / 60)} 分钟` : `预计还要约 ${Math.ceil(left)} 秒`;
			if (v < 200 * 1024 && left > 180) detail += '。网络较慢：下载会自动续传，刷新或下次再来都不会从头开始。';
		}
		return { loaded: S.loaded, total: S.total, speed: v, left, text, detail, lanes: S.lanes.filter((l) => !l.dead).length, retrying };
	}

	async function openCache(version) {
		try {
			if (!('caches' in window)) return null;
			for (const k of await caches.keys()) if (k.startsWith(CACHE_PREFIX) && k !== CACHE_PREFIX + version) caches.delete(k);
			return await caches.open(CACHE_PREFIX + version);
		} catch (e) { return null; }
	}
	async function cached(part) {
		if (!S.cache) return null;
		try {
			const r = await S.cache.match(HERE + part.name);
			if (!r) return null;
			const buf = new Uint8Array(await r.arrayBuffer());
			return buf.length === part.size ? buf : null;
		} catch (e) { return null; }
	}
	async function keep(part, buf) {
		if (!S.cache) return;
		try { await S.cache.put(HERE + part.name, new Response(buf)); } catch (e) { /* quota: fine */ }
	}

	/* Lanes: this site twice (with / without cookies: two connections), each mirror once. */
	function makeLanes() {
		const mirrors = (window.STAR_MIRRORS || []).concat((S.manifest && S.manifest.mirrors) || [])
			.map((u) => (u.endsWith('/') ? u : u + '/')).filter((u, i, a) => u !== HERE && a.indexOf(u) === i);
		const lanes = [{ base: HERE, cred: 'same-origin' }, { base: HERE, cred: 'omit' }]
			.concat(mirrors.map((base) => ({ base, cred: 'omit' })));
		S.rescue = [HERE].concat(mirrors);
		return lanes.map(lane);
	}
	function lane(l, i) {
		return Object.assign(l, { id: i, fails: 0, waitUntil: 0, dead: false, bytes: 0, done: 0, lastByte: 0 });
	}
	/* Rescue transport: requests made from a sandboxed frame (opaque origin) belong to another
	 * network partition, so the browser gives them their own connection, even to the same
	 * server. Used only when every connection has gone quiet: seen on slow lines, an old
	 * HTTP/2 connection stops answering new requests while it still answers keep-alive pings,
	 * so the browser never replaces it (another name for the same server, like "host.", is
	 * merged into the same connection and does not help). Both this site and raw.githubusercontent.com
	 * send "Access-Control-Allow-Origin: *", which such requests need. */
	const FRAME_SCRIPT = `<script>
	const ctl = {};
	onmessage = async (e) => {
		const d = e.data;
		if (d.abort) { if (ctl[d.abort]) ctl[d.abort].abort(); return; }
		const c = new AbortController(); ctl[d.id] = c;
		try {
			const r = await fetch(d.url, { headers: d.headers || {}, signal: c.signal, cache: 'no-store', credentials: 'omit' });
			parent.postMessage({ id: d.id, status: r.status }, '*');
			const rd = r.body.getReader();
			for (;;) { const x = await rd.read(); if (x.done) break; parent.postMessage({ id: d.id, chunk: x.value }, '*', [x.value.buffer]); }
			parent.postMessage({ id: d.id, done: true }, '*');
		} catch (err) { parent.postMessage({ id: d.id, error: String(err) }, '*'); }
		delete ctl[d.id];
	};
	parent.postMessage({ hello: 1 }, '*');
	<\/script>`;
	function frameFetcher() {
		const f = document.createElement('iframe');
		f.sandbox = 'allow-scripts';
		f.setAttribute('aria-hidden', 'true');
		f.style.cssText = 'position:fixed;width:0;height:0;border:0;visibility:hidden';
		const waiting = {};
		let seq = 0, readyRes;
		const ready = new Promise((res) => { readyRes = res; });
		addEventListener('message', (ev) => {
			if (ev.source !== f.contentWindow || !ev.data) return;
			if (ev.data.hello) return readyRes();
			const w = waiting[ev.data.id];
			if (w) w(ev.data);
		});
		f.srcdoc = FRAME_SCRIPT;
		document.body.appendChild(f);
		return async function (url, opt) {
			await ready;
			const id = ++seq;
			let ctrl;
			const body = new ReadableStream({ start(c) { ctrl = c; } });
			return new Promise((resolve, reject) => {
				const onAbort = () => { f.contentWindow.postMessage({ abort: id }, '*'); delete waiting[id]; const e = new DOMException('aborted', 'AbortError'); try { ctrl.error(e); } catch (x) {} reject(e); };
				if (opt.signal) opt.signal.addEventListener('abort', onAbort, { once: true });
				waiting[id] = (m) => {
					if (m.status) resolve({ status: m.status, ok: m.status >= 200 && m.status < 300, body });
					else if (m.chunk) ctrl.enqueue(m.chunk);
					else if (m.done) { delete waiting[id]; ctrl.close(); }
					else if (m.error) { delete waiting[id]; const e = new TypeError(m.error); try { ctrl.error(e); } catch (x) {} reject(e); }
				};
				f.contentWindow.postMessage({ id, url, headers: opt.headers }, '*');
			});
		};
	}
	function wake() { for (const l of S.lanes) l.waitUntil = 0; }
	addEventListener('online', wake);
	document.addEventListener('visibilitychange', () => { if (!document.hidden) wake(); });

	/* One request on one lane for one part, starting at the part's first missing byte.
	 * Every byte that extends the part's finished prefix is kept, whichever request brought it. */
	async function run(job, lane) {
		const ctl = new AbortController();
		const r0 = { ctl, lane };
		job.runs.add(r0);
		let last = now(), answered = false;
		let reason = '';
		const watch = setInterval(() => {
			if (now() - last > (answered ? STALL_MS : FIRST_BYTE_MS)) { reason = answered ? 'stall' : 'no answer'; ctl.abort(); }
		}, 1000);
		const start = job.got;
		if (start > 0) S.resumed++;
		try {
			const headers = start > 0 ? { Range: `bytes=${start}-` } : undefined;
			const r = await (lane.fetch || fetch)(lane.base + job.part.name, { headers, signal: ctl.signal, credentials: lane.cred, cache: S.cache ? 'no-store' : 'default' });
			answered = true; last = now();
			if (r.status === 404 && lane.base !== HERE) { lane.dead = true; throw new Error('mirror lacks ' + job.part.name); }
			if (r.status === 404) checkVersion();
			if (!r.ok) throw new Error('HTTP ' + r.status + ' ' + job.part.name);
			let pos = r.status === 206 ? start : 0;      // a server that ignores Range sends the whole part
			const reader = r.body.getReader();
			for (;;) {
				const { done, value } = await reader.read();
				if (done) break;
				last = now();
				const end = pos + value.length;
				if (end > job.got && pos <= job.got && !job.done) {
					const fresh = value.subarray(job.got - pos);
					job.chunks.push(fresh);
					job.got = end;
					S.loaded += fresh.length; lane.bytes += fresh.length; S.lastByte = lane.lastByte = last;
					job.onBytes(fresh.length);
				}
				pos = end;
				if (job.got >= job.part.size || job.done) break;
			}
			if (job.got > job.part.size) throw new Error('size ' + job.part.name);
			if (job.got === job.part.size) finish(job);
			if (!job.done) throw new Error('short ' + job.part.name);
			lane.fails = 0; lane.done++;
		} catch (e) {
			if (!job.done) {
				lane.fails++; S.retries++;
				const why = reason || (e && e.name === 'TypeError' ? 'network error' : String(e && e.message || e).split(' ')[0]);
				S.why[why] = (S.why[why] || 0) + 1;
				// a mirror that never delivered anything (blocked in this region, no CORS…) stops holding parts
				if (lane.base !== HERE && lane.bytes === 0 && lane.fails >= 3) lane.dead = true;
				// pause the lane only when nothing at all comes through it; one stuck request on an
				// otherwise busy connection must not idle its other requests
				if (now() - lane.lastByte > 10000) lane.waitUntil = now() + Math.min(10000, 1000 * 2 ** Math.min(lane.fails, 4));
			}
		} finally {
			clearInterval(watch);
			job.runs.delete(r0);
		}
	}
	/* This site answered 404 for a part: if a new release went live during the download, its
	 * parts replaced ours. Start over on the new release (the old parts are useless anyway). */
	let checking = false;
	async function checkVersion() {
		if (checking || !S.manifest) return;
		checking = true;
		try {
			const r = await fetch(HERE + 'starworld_manifest.json?t=' + Date.now(), { cache: 'no-store' });
			const m = r.ok ? await r.json() : null;
			if (m && m.version !== S.manifest.version && !S.bytes && !window.starworldSceneReady) {
				window.starworldLoaderNotice && window.starworldLoaderNotice('游戏刚刚更新了，正在换成新版本下载…');
				setTimeout(() => location.reload(), 1500);
				return;
			}
			if (m && m.version !== S.manifest.version) {   // already playing: just stop the background download
				S.stale = true;
				for (const l of S.lanes) l.dead = true;
				return;
			}
		} catch (e) { /* offline: the retries go on */ }
		setTimeout(() => { checking = false; }, 30000);
	}
	function finish(job) {
		if (job.done) return;
		job.done = true;
		const buf = new Uint8Array(job.part.size);
		let at = 0;
		for (const c of job.chunks) { buf.set(c, at); at += c.length; }
		job.chunks = null;
		job.buf = buf;
		for (const r of job.runs) r.ctl.abort();
		keep(job.part, buf);
		job.resolve(buf);
	}

	/* Download every part of the given files over all lanes; resolves to one Uint8Array per file. */
	async function download(files, onBytes) {
		const jobs = [];
		for (const file of files) for (const part of file.parts) {
			const job = { part, got: 0, chunks: [], runs: new Set(), done: false, buf: null, onBytes };
			job.promise = new Promise((res) => { job.resolve = res; });
			jobs.push(job);
		}
		const queue = [];
		await Promise.all(jobs.map(async (job) => {
			const hit = await cached(job.part);
			if (hit) { job.done = true; job.buf = hit; S.loaded += hit.length; onBytes(hit.length); job.resolve(hit); }
		}));
		for (const job of jobs) if (!job.done) queue.push(job);
		const open = () => jobs.some((j) => !j.done);
		function next(lane) {
			// unfinished work nobody is on (interrupted parts first, they hold bytes already)
			queue.sort((a, b) => (b.got > 0) - (a.got > 0));
			const i = queue.findIndex((j) => !j.done && j.runs.size === 0);
			if (i >= 0) return queue.splice(i, 1)[0];
			for (let k = queue.length - 1; k >= 0; k--) if (queue[k].done) queue.splice(k, 1);
			// end game: help the unfinished part with the most bytes left, from another lane
			let best = null;
			for (const j of jobs) {
				if (j.done || j.runs.size >= 2 || [...j.runs].some((r) => r.lane === lane)) continue;
				if (j.part.size - j.got < 65536) continue;
				if (!best || j.part.size - j.got > best.part.size - best.got) best = j;
			}
			return best;
		}
		async function worker(lane) {
			while (open()) {
				if (lane.dead) return;
				if (now() < lane.waitUntil) { await sleep(Math.min(1000, lane.waitUntil - now())); continue; }
				const job = next(lane);
				if (!job) { await sleep(300); continue; }
				await run(job, lane);
				if (!job.done && job.runs.size === 0 && !queue.includes(job)) queue.unshift(job);
			}
		}
		const workers = [];
		for (const l of S.lanes) for (let k = 0; k < RUNS_PER_LANE; k++) workers.push(worker(l));
		let quietSince = now(), lastRescue = 0;
		const guard = setInterval(() => {
			// if every mirror turned out dead and this site's lanes are gone too, revive this site
			if (!S.stale && S.lanes.every((l) => l.dead)) for (const l of S.lanes) if (l.base === HERE) l.dead = false;
			// every connection quiet: add a fresh one (it helps the stuck parts from where they are)
			const quiet = now() - Math.max(S.lastByte, quietSince);
			if (!S.stale && open() && quiet > RESCUE_MS && now() - lastRescue > RESCUE_MS && S.rescue.length) {
				lastRescue = now();
				const fresh = lane({ base: S.rescue.shift(), cred: 'omit', rescue: true, fetch: frameFetcher() }, S.lanes.length);
				S.lanes.push(fresh);
				S.rescues = (S.rescues || 0) + 1;
				wake();
				for (let k = 0; k < RUNS_PER_LANE; k++) workers.push(worker(fresh));
			}
		}, 2000);
		await Promise.all(jobs.map((j) => j.promise));
		clearInterval(guard);
		await Promise.all(workers);
		const out = [];
		let at = 0;
		for (const file of files) {
			out.push(jobs.slice(at, at + file.parts.length).map((j) => j.buf));
			at += file.parts.length;
		}
		return out;
	}
	function inflateStream(parts) {
		// Feed parts one at a time. Avoid copying a 40 MB buffer into a Blob or
		// holding a second uncompressed copy before Godot reads the response.
		let i = 0;
		return new ReadableStream({
			pull(controller) {
				if (i === parts.length) { controller.close(); return; }
				const part = parts[i];
				parts[i++] = null;
				controller.enqueue(part);
			}
		}).pipeThrough(new DecompressionStream('gzip'));
	}
	async function gunzip(parts, rawSize) {
		const stream = inflateStream(parts);
		const out = new Uint8Array(rawSize);
		const reader = stream.getReader();
		let at = 0;
		for (;;) {
			const { done, value } = await reader.read();
			if (done) break;
			out.set(value, at); at += value.length;
		}
		if (at !== rawSize) throw new Error('unpack size');
		return out;
	}

	async function prefetch(onStatus) {
		try {
			if (!('DecompressionStream' in window)) throw new Error('no DecompressionStream');
			let r = null;
			for (let i = 0; ; i++) {   // the manifest is tiny; a flaky line must not send us back to the old path
				try { r = await fetch(HERE + 'starworld_manifest.json?t=' + Date.now(), { cache: 'no-store' }); break; } catch (e) { if (i >= 4) throw e; await sleep(1500 * (i + 1)); }
			}
			if (!r.ok) throw new Error('no manifest');
			S.manifest = await r.json();
		} catch (e) {
			S.manifest = null;
			readyResolve(false);   // the engine downloads by itself, as before
			return;
		}
		const m = S.manifest;
		S.cache = await openCache(m.version);
		S.lanes = makeLanes();
		S.total = [m.files.wasm, m.files.pck].reduce((a, f) => a + f.parts.reduce((b, p) => b + p.size, 0), 0);
		const tick = setInterval(() => onStatus && onStatus(status()), 500);
		try {
			const [wasmParts, pckParts] = await download([m.files.wasm, m.files.pck], () => {});
			clearInterval(tick);
			onStatus && onStatus({ loaded: S.total, total: S.total, speed: 0, left: 0, text: '下载完成，正在解压…', detail: '' });
			if (window.starworldMobile) {
				S.bytes = { [m.wasm_name]: wasmParts, [m.pck_name]: pckParts };
			} else {
				const [wasm, pck] = await Promise.all([gunzip(wasmParts, m.files.wasm.raw), gunzip(pckParts, m.files.pck.raw)]);
				S.bytes = { [m.wasm_name]: wasm, [m.pck_name]: pck };
			}
			onStatus && onStatus({ loaded: S.total, total: S.total, speed: 0, left: 0, text: '下载完成', detail: '' });
			readyResolve(true);
		} catch (e) {
			clearInterval(tick);
			readyReject(e);
		}
	}

	/* Hands the downloaded bytes to the engine: its own fetch of index.wasm / the pack is
	 * answered from memory (once each), everything else goes to the network as usual. */
	function serve() {
		if (!S.bytes) return;
		const served = S.bytes;
		S.bytes = null;
		const real = window.fetch.bind(window);
		window.fetch = function (input, init) {
			const url = typeof input === 'string' ? input : input.url;
			const name = url.split('?')[0].split('/').pop();
			if (served[name]) {
				const bytes = served[name];
				delete served[name];
				const wasm = name.endsWith('.wasm');
				const type = wasm ? 'application/wasm' : 'application/octet-stream';
				const streamed = Array.isArray(bytes);
				const length = streamed ? S.manifest.files[wasm ? 'wasm' : 'pck'].raw : bytes.length;
				if (!Object.keys(served).length) window.fetch = real;
				return Promise.resolve(new Response(streamed ? inflateStream(bytes) : bytes, { headers: { 'Content-Type': type, 'Content-Length': String(length) } }));
			}
			return real(input, init);
		};
	}

	async function late(engine) {
		const file = S.manifest && S.manifest.files.late;
		if (!file || !engine || !engine.rtenv) { window.starworldLate = { state: 'none' }; return; }
		const total = file.parts.reduce((a, p) => a + p.size, 0);
		window.starworldLate = { state: 'downloading', loaded: 0, total };
		S.total += total;
		try {
			const [parts] = await download([file], (n) => { window.starworldLate.loaded += n; });
			const bytes = await gunzip(parts, file.raw);
			engine.rtenv.copyToFS('/tmp/starworld_late.pck', bytes);
			window.starworldLate = { state: 'ready', path: '/tmp/starworld_late.pck' };
		} catch (e) {
			console.warn('late pack', e);
			window.starworldLate = { state: 'error', message: String(e) };
		}
	}

	function stats() {
		return { loaded: S.loaded, total: S.total, resumed: S.resumed, retries: S.retries, why: S.why,
			rescues: S.rescues || 0, lanes: S.lanes.map((l) => ({ base: l.base, cred: l.cred, rescue: !!l.rescue, mb: +(l.bytes / 1048576).toFixed(2), parts: l.done, dead: l.dead })) };
	}
	window.StarLoader = { prefetch, ready: () => readyPromise, serve, late, active: () => !!S.manifest, stats };
})();
