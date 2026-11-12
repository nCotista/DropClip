/// The phone page served at `/web` (Tier 3 web companion). Self-contained:
/// no external scripts, fonts or images, so it works offline on the LAN.
/// Text from other devices is set with `textContent`, never as HTML.
const webCompanionPage = r'''<!doctype html>
<html lang="th">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-title" content="DropClip">
<meta name="theme-color" content="#0b0e14">
<title>DropClip</title>
<style>
  :root { --bg:#0b0e14; --card:#151a23; --line:#262d3a; --text:#e7ebf2;
          --muted:#8b95a7; --accent:#4f8cff; --ok:#33c481; --warn:#f2b84b; }
  * { box-sizing:border-box; }
  body { margin:0; background:var(--bg); color:var(--text);
         font:16px/1.45 -apple-system, "Sukhumvit Set", "Segoe UI", sans-serif;
         padding:16px 16px calc(24px + env(safe-area-inset-bottom)); }
  header { display:flex; align-items:center; gap:10px; margin-bottom:16px; }
  header h1 { font-size:20px; margin:0; flex:1; }
  .dot { width:10px; height:10px; border-radius:50%; background:var(--muted); }
  .dot.on { background:var(--ok); }
  .card { background:var(--card); border:1px solid var(--line);
          border-radius:14px; padding:14px; margin-bottom:14px; }
  .card h2 { font-size:15px; margin:0 0 10px; color:var(--muted); font-weight:600; }
  textarea { width:100%; min-height:84px; resize:vertical; border-radius:10px;
             border:1px solid var(--line); background:var(--bg); color:var(--text);
             padding:10px; font:inherit; }
  .row { display:flex; gap:8px; margin-top:10px; }
  button, .btn { flex:1; border:0; border-radius:10px; padding:12px; font:inherit;
                 font-weight:600; background:var(--accent); color:#fff; }
  button.ghost { background:transparent; border:1px solid var(--line); color:var(--text); }
  button:disabled { opacity:.5; }
  ul { list-style:none; margin:0; padding:0; }
  li { display:flex; gap:10px; align-items:flex-start; padding:10px 0;
       border-top:1px solid var(--line); }
  li:first-child { border-top:0; }
  .txt { flex:1; word-break:break-word; white-space:pre-wrap; }
  .meta { color:var(--muted); font-size:13px; }
  li button { flex:0 0 auto; padding:8px 12px; }
  .empty { color:var(--muted); }
  #msg { position:fixed; left:16px; right:16px; bottom:calc(16px + env(safe-area-inset-bottom));
         background:#222a38; padding:12px; border-radius:10px; text-align:center;
         opacity:0; transition:opacity .2s; pointer-events:none; }
  #msg.show { opacity:1; }
  progress { width:100%; margin-top:8px; }
  .hidden { display:none; }
</style>
</head>
<body>
<header><span id="dot" class="dot"></span><h1>DropClip</h1>
  <button id="unlink" class="ghost hidden" style="flex:0">เลิกเชื่อม</button></header>

<div id="unlinked" class="card hidden">
  <h2>ยังไม่ได้เชื่อม</h2>
  <p>ที่คอมพิวเตอร์ เปิด DropClip → อุปกรณ์ → “เชื่อมมือถือผ่านเว็บ” แล้วสแกน QR ด้วยกล้อง</p>
</div>

<div id="app" class="hidden">
  <div class="card">
    <h2>ส่งข้อความไปคอมพิวเตอร์</h2>
    <textarea id="text" placeholder="วางหรือพิมพ์ข้อความที่นี่"></textarea>
    <div class="row">
      <button id="paste" class="ghost">วางจากคลิปบอร์ด</button>
      <button id="send">ส่ง</button>
    </div>
    <label class="btn ghost" style="display:block;text-align:center;margin-top:8px;border:1px solid var(--line);background:transparent">ส่งรูปเข้าคลิปบอร์ดคอมพิวเตอร์
      <input id="imgpick" type="file" accept="image/*" class="hidden"></label>
  </div>
  <div class="card">
    <h2>ส่งไฟล์หรือรูป</h2>
    <label class="btn" style="display:block;text-align:center">เลือกไฟล์
      <input id="file" type="file" multiple class="hidden"></label>
    <progress id="prog" class="hidden" max="1" value="0"></progress>
  </div>
  <div class="card">
    <h2>ไฟล์จากคอมพิวเตอร์</h2>
    <ul id="files"><li class="empty">ยังไม่มี</li></ul>
  </div>
  <div class="card">
    <h2>คลิปบอร์ดล่าสุด</h2>
    <ul id="clips"><li class="empty">ยังไม่มี</li></ul>
  </div>
</div>
<div id="msg"></div>

<script>
(function () {
  var KEY = 'dropclip.token';
  var token = null, after = 0, clips = [], online = false;
  try { token = localStorage.getItem(KEY); } catch (e) {}

  function $(id) { return document.getElementById(id); }
  function toast(t) {
    var m = $('msg'); m.textContent = t; m.classList.add('show');
    clearTimeout(toast.t); toast.t = setTimeout(function () { m.classList.remove('show'); }, 1800);
  }
  function api(method, path, body, type) {
    var h = { 'x-dropclip-token': token || '' };
    if (type) h['content-type'] = type;
    return fetch('/web/api/' + path, { method: method, headers: h, body: body, cache: 'no-store' })
      .then(function (r) {
        if (r.status === 401) { unlinked(); throw new Error('401'); }
        if (!r.ok) throw new Error('HTTP ' + r.status);
        return r;
      });
  }
  function unlinked() {
    token = null; try { localStorage.removeItem(KEY); } catch (e) {}
    $('app').classList.add('hidden'); $('unlink').classList.add('hidden');
    $('unlinked').classList.remove('hidden'); setOnline(false);
  }
  function linked() {
    $('unlinked').classList.add('hidden'); $('app').classList.remove('hidden');
    $('unlink').classList.remove('hidden'); poll();
  }
  function setOnline(v) { online = v; $('dot').classList.toggle('on', v); }

  function li(text, meta, label, onClick) {
    var el = document.createElement('li');
    var box = document.createElement('div'); box.className = 'txt';
    box.textContent = text;
    var m = document.createElement('div'); m.className = 'meta'; m.textContent = meta;
    box.appendChild(m); el.appendChild(box);
    var b = document.createElement('button'); b.textContent = label; b.onclick = onClick;
    el.appendChild(b); return el;
  }
  function render(list, items, make) {
    var ul = $(list); ul.textContent = '';
    if (!items.length) { var e = document.createElement('li'); e.className = 'empty';
      e.textContent = 'ยังไม่มี'; ul.appendChild(e); return; }
    items.forEach(function (i) { ul.appendChild(make(i)); });
  }
  function size(n) { return n < 1e6 ? Math.ceil(n / 1e3) + ' KB' : (n / 1e6).toFixed(1) + ' MB'; }

  function poll() {
    if (!token) return;
    if (document.visibilityState !== 'visible') { setTimeout(poll, 1500); return; }
    api('GET', 'state?after=' + after).then(function (r) { return r.json(); }).then(function (s) {
      setOnline(true);
      s.clips.forEach(function (c) { after = Math.max(after, c.id); clips.unshift(c); });
      clips = clips.slice(0, 30);
      render('clips', clips, function (c) {
        return li(c.text, c.from + ' · ' + new Date(c.at).toLocaleTimeString('th-TH'), 'คัดลอก',
          function () {
            navigator.clipboard.writeText(c.text).then(function () { toast('คัดลอกแล้ว'); },
              function () { toast('คัดลอกไม่ได้ ลองกดค้างที่ข้อความ'); });
          });
      });
      render('files', s.files, function (f) {
        return li(f.name, size(f.size), 'ดาวน์โหลด', function () { download(f); });
      });
    }).catch(function (e) { if (e.message !== '401') setOnline(false); })
      .then(function () { if (token) setTimeout(poll, 1500); });
  }

  function download(f) {
    toast('กำลังดาวน์โหลด…');
    api('GET', 'file/' + f.id).then(function (r) { return r.blob(); }).then(function (b) {
      var a = document.createElement('a'); a.href = URL.createObjectURL(b);
      a.download = f.name; document.body.appendChild(a); a.click();
      setTimeout(function () { URL.revokeObjectURL(a.href); a.remove(); }, 4000);
    }).catch(function () { toast('ดาวน์โหลดไม่สำเร็จ'); });
  }

  $('send').onclick = function () {
    var t = $('text').value; if (!t) return;
    $('send').disabled = true;
    api('POST', 'clip', JSON.stringify({ text: t }), 'application/json')
      .then(function () { $('text').value = ''; toast('ส่งแล้ว'); })
      .catch(function () { toast('ส่งไม่สำเร็จ'); })
      .then(function () { $('send').disabled = false; });
  };
  // Any photo → PNG ≤ 4096 px on the long edge, so it fits the 32 MiB
  // clipboard limit and the PC needs no JPEG/HEIC decoder.
  function toPng(blob) {
    return new Promise(function (ok, fail) {
      var img = new Image(), url = URL.createObjectURL(blob);
      img.onload = function () {
        var s = Math.min(1, 4096 / Math.max(img.naturalWidth, img.naturalHeight));
        var c = document.createElement('canvas');
        c.width = Math.round(img.naturalWidth * s); c.height = Math.round(img.naturalHeight * s);
        c.getContext('2d').drawImage(img, 0, 0, c.width, c.height);
        URL.revokeObjectURL(url);
        c.toBlob(function (b) { b ? ok(b) : fail(new Error('png')); }, 'image/png');
      };
      img.onerror = function () { URL.revokeObjectURL(url); fail(new Error('image')); };
      img.src = url;
    });
  }
  function sendImage(blob) {
    toast('กำลังส่งรูป…');
    return toPng(blob).then(function (png) { return api('POST', 'image', png, 'image/png'); })
      .then(function () { toast('ส่งรูปเข้าคลิปบอร์ดคอมพิวเตอร์แล้ว'); },
        function () { toast('ส่งรูปไม่สำเร็จ'); });
  }
  $('imgpick').onchange = function (ev) {
    var f = (ev.target.files || [])[0]; ev.target.value = '';
    if (f) sendImage(f);
  };
  $('paste').onclick = function () {
    var cb = navigator.clipboard;
    function text() {
      if (!cb || !cb.readText) { toast('กดค้างในช่องแล้วเลือกวาง'); return; }
      cb.readText().then(function (t) { $('text').value = t; },
        function () { toast('กดค้างในช่องแล้วเลือกวาง'); });
    }
    if (!cb || !cb.read) return text();
    // A copied photo goes straight to the PC clipboard; text fills the box.
    // One read() (one Safari "Paste" prompt) serves both images and text.
    cb.read().then(function (items) {
      for (var i = 0; i < items.length; i++) {
        var type = items[i].types.filter(function (t) { return t.indexOf('image/') === 0; })[0];
        if (type) return items[i].getType(type).then(sendImage);
      }
      for (var j = 0; j < items.length; j++) {
        if (items[j].types.indexOf('text/plain') >= 0) {
          return items[j].getType('text/plain').then(function (b) { return b.text(); })
            .then(function (t) { $('text').value = t; });
        }
      }
      toast('คลิปบอร์ดว่าง');
    }, text);
  };
  $('file').onchange = function (ev) {
    var files = Array.prototype.slice.call(ev.target.files || []), prog = $('prog');
    (function next() {
      var f = files.shift(); if (!f) { prog.classList.add('hidden'); ev.target.value = ''; return; }
      prog.classList.remove('hidden'); prog.value = 0;
      var x = new XMLHttpRequest();
      x.open('POST', '/web/api/upload?name=' + encodeURIComponent(f.name));
      x.setRequestHeader('x-dropclip-token', token || '');
      x.upload.onprogress = function (e) { if (e.lengthComputable) prog.value = e.loaded / e.total; };
      x.onload = function () {
        if (x.status === 401) return unlinked();
        toast(x.status === 200 ? 'ส่ง ' + f.name + ' แล้ว' : 'ส่ง ' + f.name + ' ไม่สำเร็จ'); next();
      };
      x.onerror = function () { toast('ส่ง ' + f.name + ' ไม่สำเร็จ'); next(); };
      x.send(f);
    })();
  };
  $('unlink').onclick = function () { unlinked(); toast('เลิกเชื่อมแล้ว'); };
  document.addEventListener('visibilitychange', function () { if (!online && token) setOnline(false); });

  var code = (location.hash.match(/[#&]c=([\w-]+)/) || [])[1];
  history.replaceState(null, '', location.pathname);
  if (code) {
    var name = /iPhone/.test(navigator.userAgent) ? 'iPhone'
      : /iPad/.test(navigator.userAgent) ? 'iPad'
      : /Android/.test(navigator.userAgent) ? 'Android' : 'Browser';
    fetch('/web/api/claim', { method: 'POST', body: JSON.stringify({ code: code, name: name }) })
      .then(function (r) { return r.json().then(function (j) { return { ok: r.ok, j: j }; }); })
      .then(function (r) {
        if (!r.ok) { unlinked(); toast('QR หมดอายุ สแกนใหม่อีกครั้ง'); return; }
        token = r.j.token; try { localStorage.setItem(KEY, token); } catch (e) {}
        toast('เชื่อมกับคอมพิวเตอร์แล้ว'); linked();
      }).catch(function () { unlinked(); toast('เชื่อมไม่สำเร็จ'); });
  } else if (token) { linked(); } else { unlinked(); }
})();
</script>
</body>
</html>
''';
