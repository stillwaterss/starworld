/* 星星人的小世界 · download loader (Claude v36), used by game/web_shell.html.
 *
 * The page used to start downloading one 120 MB pack only after "开始旅行" was clicked, with
 * no resume: a stalled connection meant starting again from zero. Now:
 *   - downloading starts as soon as the page opens (while the player reads the cover);
 *   - the engine and the core pack come as 1 MB gzip parts (scripts/web_pack.py), 4 at a
 *     time, each kept in the browser cache when done: a refresh or a later visit resumes;
 *   - every mirror in window.STAR_MIRRORS (plus this site) is timed, the fastest goes first;
 *     a part that stalls 15 s is fetched again from the next one;
 *   - after the island is ready, the late pack (chapter pictures, the full font) follows in
 *     the background and is dropped into the engine's file system (scripts/web_late.gd).
 * Without starworld_manifest.json (or without DecompressionStream) nothing changes: the
 * engine downloads index.wasm / index.<hash>.pck by itself, as before.
 *
 * API: StarLoader.prefetch(onStatus) -> starts at once; onStatus({loaded,total,speed,left,text,detail})
 *      StarLoader.ready() -> Promise (resolves when the bytes are in, or at once without a manifest)
 *      StarLoader.serve(config) -> hands the bytes to the engine (call before engine.startGame)
 *      StarLoader.late(engine) -> background download of the late pack
 */
(function () {
	'use strict';
	const HERE = new URL('.', location.href).href;
	const CONCURRENCY = 4;
	const STALL_MS = 15000;
	const CACHE_PREFIX = 'starworld-parts-';
	const S = { manifest: null, mirrors: [HERE], cache: null, loaded: 0, total: 0, samples: [], bytes: null, error: null };
	let readyResolve, readyReject;
	const readyPromise = new Promise((res, rej) => { readyResolve = res; readyReject = rej; });
	readyPromise.catch(() => {});

	const mb = (n) => (n / 1048576).toFixed(n < 10485760 ? 1 : 0);
	function speedNow() {
		const now = performance.now();
		S.samples = S.samples.filter((s) => now - s.t < 6000);
		if (S.samples.length < 2) return 0;
		const a = S.samples[0], b = S.samples[S.samples.length - 1];
		return (b.n - a.n) / Math.max(0.5, (b.t - a.t) / 1000);
	}
	function status() {
		S.samples.push({ t: performance.now(), n: S.loaded });
		const v = speedNow();
		const left = v > 0 ? (S.total - S.loaded) / v : 0;
		let text = `正在下载 ${mb(S.loaded)} / ${mb(S.total)} MB`;
		let detail = '';
		if (v > 0) {
			text += `  ·  ${v > 1048576 ? (v / 1048576).toFixed(1) + ' MB/s' : Math.round(v / 1024) + ' KB/s'}`;
			if (left > 5) detail = left > 90 ? `预计还要约 ${Math.ceil(left / 60)} 分钟` : `预计还要约 ${Math.ceil(left)} 秒`;
			if (v < 200 * 1024 && left > 180) detail += '。网络较慢：下载会自动续传，刷新或下次再来都不会从头开始。';
		}
		return { loaded: S.loaded, total: S.total, speed: v, left, text, detail };
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
	async function rankMirrors(probe) {
		// mirrors from the page (window.STAR_MIRRORS) and from the manifest ("mirrors")
		const list = (window.STAR_MIRRORS || []).concat((S.manifest && S.manifest.mirrors) || []).map((u) => (u.endsWith('/') ? u : u + '/'));
		if (!list.includes(HERE)) list.push(HERE);
		if (list.length === 1) return list;
		const timed = await Promise.all(list.map(async (base) => {
			const ctl = new AbortController();
			const t0 = performance.now();
			const timer = setTimeout(() => ctl.abort(), 8000);
			try {
				const r = await fetch(base + probe.name, { headers: { Range: 'bytes=0-262143' }, signal: ctl.signal, cache: 'no-store' });
				if (!r.ok) throw new Error(r.status);
				const n = (await r.arrayBuffer()).byteLength;
				return { base, score: n / ((performance.now() - t0) / 1000) };
			} catch (e) { return { base, score: -1 }; } finally { clearTimeout(timer); }
		}));
		timed.sort((a, b) => b.score - a.score);
		return timed.filter((m) => m.score >= 0).map((m) => m.base).concat(timed.filter((m) => m.score < 0).map((m) => m.base));
	}
	async function fetchPart(part, onBytes) {
		const hit = await cached(part);
		if (hit) { onBytes(hit.length); return hit; }
		let lastErr = null;
		for (let round = 0; round < 4; round++) {
			for (const base of S.mirrors) {
				const ctl = new AbortController();
				let got = 0, last = performance.now();
				const watch = setInterval(() => { if (performance.now() - last > STALL_MS) ctl.abort(); }, 2000);
				try {
					const r = await fetch(base + part.name, { signal: ctl.signal, cache: 'no-cache' });
					if (!r.ok) throw new Error('HTTP ' + r.status + ' ' + part.name);
					const reader = r.body.getReader();
					const chunks = [];
					for (;;) {
						const { done, value } = await reader.read();
						if (done) break;
						chunks.push(value); got += value.length; last = performance.now();
						onBytes(value.length);
					}
					const buf = new Uint8Array(got);
					let at = 0;
					for (const c of chunks) { buf.set(c, at); at += c.length; }
					if (buf.length !== part.size) throw new Error('size ' + part.name);
					await keep(part, buf);
					return buf;
				} catch (e) {
					lastErr = e; onBytes(-got);
				} finally { clearInterval(watch); }
			}
			await new Promise((res) => setTimeout(res, 1500 * (round + 1)));
		}
		throw lastErr || new Error('download failed');
	}
	async function gunzip(parts, rawSize) {
		const stream = new Blob(parts).stream().pipeThrough(new DecompressionStream('gzip'));
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
	async function getFile(file, onBytes) {
		const parts = new Array(file.parts.length);
		let next = 0;
		async function worker() {
			while (next < file.parts.length) {
				const i = next++;
				parts[i] = await fetchPart(file.parts[i], onBytes);
			}
		}
		await Promise.all(Array.from({ length: Math.min(CONCURRENCY, file.parts.length) }, worker));
		return gunzip(parts, file.raw);
	}

	async function prefetch(onStatus) {
		try {
			if (!('DecompressionStream' in window)) throw new Error('no DecompressionStream');
			const r = await fetch(HERE + 'starworld_manifest.json?t=' + Date.now(), { cache: 'no-store' });
			if (!r.ok) throw new Error('no manifest');
			S.manifest = await r.json();
		} catch (e) {
			S.manifest = null;
			readyResolve(false);   // the engine downloads by itself, as before
			return;
		}
		const m = S.manifest;
		S.cache = await openCache(m.version);
		S.total = [m.files.wasm, m.files.pck].reduce((a, f) => a + f.parts.reduce((b, p) => b + p.size, 0), 0);
		S.mirrors = await rankMirrors(m.files.pck.parts[0]);
		const tick = setInterval(() => onStatus && onStatus(status()), 500);
		try {
			const onBytes = (n) => { S.loaded += n; };
			const [wasm, pck] = await Promise.all([getFile(m.files.wasm, onBytes), getFile(m.files.pck, onBytes)]);
			S.bytes = { [m.wasm_name]: wasm, [m.pck_name]: pck };
			clearInterval(tick);
			onStatus && onStatus({ loaded: S.total, total: S.total, speed: 0, left: 0, text: '下载完成', detail: '' });
			readyResolve(true);
		} catch (e) {
			clearInterval(tick);
			S.error = e;
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
				const type = name.endsWith('.wasm') ? 'application/wasm' : 'application/octet-stream';
				return Promise.resolve(new Response(bytes, { headers: { 'Content-Type': type, 'Content-Length': String(bytes.length) } }));
			}
			return real(input, init);
		};
	}

	async function late(engine) {
		const file = S.manifest && S.manifest.files.late;
		if (!file || !engine || !engine.rtenv) { window.starworldLate = { state: 'none' }; return; }
		window.starworldLate = { state: 'downloading', loaded: 0, total: file.parts.reduce((a, p) => a + p.size, 0) };
		try {
			const bytes = await getFile(file, (n) => { window.starworldLate.loaded += n; });
			engine.rtenv.copyToFS('/tmp/starworld_late.pck', bytes);
			window.starworldLate = { state: 'ready', path: '/tmp/starworld_late.pck' };
		} catch (e) {
			console.warn('late pack', e);
			window.starworldLate = { state: 'error', message: String(e) };
		}
	}

	window.StarLoader = { prefetch, ready: () => readyPromise, serve, late, active: () => !!S.manifest };
})();
