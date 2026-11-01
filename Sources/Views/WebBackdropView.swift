import AppKit
import WebKit

@MainActor
public final class WebBackdropView: NSView, WKNavigationDelegate, WKUIDelegate {
    
    public private(set) var webView: WKWebView?
    private var isCurrentlyPaused: Bool = false
    
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupWebView()
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupWebView()
    }
    
    public override func layout() {
        super.layout()
        webView?.frame = bounds
    }
    
    private func setupWebView() {
        wantsLayer = true
        
        let config = WKWebViewConfiguration()
        
        // Security & Performance Best Practices:
        // Sandboxed, no external window opening, no audio hijacking
        let prefs = WKPreferences()
        prefs.javaScriptCanOpenWindowsAutomatically = false
        prefs.isElementFullscreenEnabled = false
        config.preferences = prefs
        
        let pagePrefs = WKWebpagePreferences()
        pagePrefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = pagePrefs
        
        config.mediaTypesRequiringUserActionForPlayback = .all
        config.suppressesIncrementalRendering = true
        
        // Hardware accelerated WebKit view
        let web = WKWebView(frame: bounds, configuration: config)
        web.navigationDelegate = self
        web.uiDelegate = self
        web.autoresizingMask = [.width, .height]
        
        // Transparent backing store so desktop icons and macOS layer compositing stay intact
        web.setValue(false, forKey: "drawsBackground")
        if #available(macOS 12.0, *) {
            web.underPageBackgroundColor = .clear
        }
        
        addSubview(web)
        self.webView = web
    }
    
    // MARK: - Navigation Security
    
    nonisolated public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        Task { @MainActor in
            if navigationAction.navigationType == .other || navigationAction.targetFrame?.isMainFrame == true {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
        }
    }
    
    // MARK: - Loading Wallpapers
    
    public func loadPreset(_ presetName: String) {
        let htmlContent = Self.htmlForPreset(presetName)
        let transition = CATransition()
        transition.type = .fade
        transition.duration = 0.35
        transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer?.add(transition, forKey: "webPresetFade")
        webView?.loadHTMLString(htmlContent, baseURL: nil)
    }
    
    public func loadURL(_ url: URL) {
        if url.isFileURL {
            webView?.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 15.0)
            webView?.load(request)
        }
    }
    
    // MARK: - Mouse Interactivity Bridge
    
    public func updateMousePosition(normalizedX: Double, normalizedY: Double, point: CGPoint) {
        guard !isCurrentlyPaused, AppSettings.shared.isMouseInteractionEnabled else { return }
        let js = "if (window.onDesktopMouseMove) { window.onDesktopMouseMove(\(normalizedX), \(normalizedY), \(point.x), \(point.y)); }"
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }
    
    // MARK: - Resource Optimization & Sleep
    
    public func pause() {
        guard !isCurrentlyPaused else { return }
        isCurrentlyPaused = true
        webView?.pauseAllMediaPlayback()
        webView?.evaluateJavaScript("if (window.onWallpaperPause) { window.onWallpaperPause(); }", completionHandler: nil)
    }
    
    public func resume() {
        guard isCurrentlyPaused else { return }
        isCurrentlyPaused = false
        webView?.evaluateJavaScript("if (window.onWallpaperResume) { window.onWallpaperResume(); }", completionHandler: nil)
    }
    
    // MARK: - Built-in M3 Pro Optimized Shader Presets
    
    public static func htmlForPreset(_ preset: String) -> String {
        let p = preset.lowercased()
        if p.contains("nebula") || p.contains("space") {
            return nebulaHTML
        } else if p.contains("network") || p.contains("interactive") {
            return particleNetworkHTML
        } else if p.contains("clock") || p.contains("wave") {
            return clockWaveHTML
        } else {
            return matrixHTML
        }
    }
    
    // Preset 1: Cyberpunk Matrix Rain
    private static let matrixHTML: String = """
    <!DOCTYPE html>
    <html>
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
    <style>
      body, html { margin: 0; padding: 0; width: 100%; height: 100%; overflow: hidden; background: #04080c; }
      canvas { display: block; position: fixed; top: 0; left: 0; width: 100vw; height: 100vh; }
    </style>
    </head>
    <body>
    <canvas id="c"></canvas>
    <script>
      const canvas = document.getElementById('c');
      const ctx = canvas.getContext('2d');
      let w, h, cols, ypos;
      let mouseX = 0, mouseY = 0;
      let isPaused = false;
      
      function resize() {
        w = canvas.width = window.innerWidth || document.documentElement.clientWidth;
        h = canvas.height = window.innerHeight || document.documentElement.clientHeight;
        cols = Math.floor(w / 20) + 1;
        ypos = Array(cols).fill(0);
      }
      window.addEventListener('resize', resize);
      resize();
      
      const chars = '0123456789ABCDEFﾊﾐﾋｰｳｼﾅﾓﾆｻﾜﾂｵﾘｱﾎﾃﾏｹﾒｴｶｷﾑﾕﾗｾﾈｽﾀﾇﾍ';
      
      window.onDesktopMouseMove = function(nx, ny, px, py) {
        mouseX = px;
        mouseY = py;
      };
      window.onWallpaperPause = function() { isPaused = true; };
      window.onWallpaperResume = function() { isPaused = false; loop(); };
      
      function loop() {
        if (isPaused) return;
        ctx.fillStyle = 'rgba(4, 8, 12, 0.08)';
        ctx.fillRect(0, 0, w, h);
        
        ctx.fillStyle = '#00ff77';
        ctx.font = '14pt monospace';
        
        for (let i = 0; i < cols; i++) {
          const char = chars[Math.floor(Math.random() * chars.length)];
          const x = i * 20;
          const y = ypos[i];
          
          // Mouse glow proximity effect
          const dist = Math.hypot(x - mouseX, y - mouseY);
          if (dist < 150) {
            ctx.fillStyle = '#77ffff';
          } else {
            ctx.fillStyle = '#00ff77';
          }
          
          ctx.fillText(char, x, y);
          
          if (y > 100 + Math.random() * 10000) ypos[i] = 0;
          else ypos[i] = y + 20;
        }
        requestAnimationFrame(loop);
      }
      loop();
    </script>
    </body>
    </html>
    """
    
    // Preset 2: Deep Space Starfield & Nebula
    private static let nebulaHTML: String = """
    <!DOCTYPE html>
    <html>
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
    <style>
      body, html { margin: 0; padding: 0; width: 100%; height: 100%; overflow: hidden; background: #030308; }
      canvas { display: block; position: fixed; top: 0; left: 0; width: 100vw; height: 100vh; }
    </style>
    </head>
    <body>
    <canvas id="c"></canvas>
    <script>
      const canvas = document.getElementById('c');
      const ctx = canvas.getContext('2d');
      let w, h;
      let mouseX = 0, mouseY = 0;
      let isPaused = false;
      const numStars = 500;
      const stars = [];
      
      function resize() {
        w = canvas.width = window.innerWidth || document.documentElement.clientWidth;
        h = canvas.height = window.innerHeight || document.documentElement.clientHeight;
      }
      window.addEventListener('resize', resize);
      resize();
      
      for (let i = 0; i < numStars; i++) {
        stars.push({
          x: (Math.random() - 0.5) * w * 2,
          y: (Math.random() - 0.5) * h * 2,
          z: Math.random() * w,
          size: Math.random() * 1.5 + 0.5
        });
      }
      
      window.onDesktopMouseMove = function(nx, ny) {
        mouseX = nx * 80;
        mouseY = ny * 80;
      };
      window.onWallpaperPause = function() { isPaused = true; };
      window.onWallpaperResume = function() { isPaused = false; render(); };
      
      function render() {
        if (isPaused) return;
        ctx.fillStyle = 'rgba(3, 3, 8, 0.2)';
        ctx.fillRect(0, 0, w, h);
        
        const cx = w / 2 + mouseX;
        const cy = h / 2 - mouseY;
        
        for (let i = 0; i < numStars; i++) {
          const s = stars[i];
          s.z -= 1.5;
          if (s.z <= 0) {
            s.z = w;
            s.x = (Math.random() - 0.5) * w * 2;
            s.y = (Math.random() - 0.5) * h * 2;
          }
          
          const k = 250 / s.z;
          const px = s.x * k + cx;
          const py = s.y * k + cy;
          
          if (px >= 0 && px <= w && py >= 0 && py <= h) {
            const alpha = Math.min(1.0, (1.0 - s.z / w) * 1.5);
            ctx.fillStyle = 'rgba(200, 225, 255, ' + alpha + ')';
            ctx.beginPath();
            ctx.arc(px, py, s.size * k * 0.8, 0, Math.PI * 2);
            ctx.fill();
          }
        }
        requestAnimationFrame(render);
      }
      render();
    </script>
    </body>
    </html>
    """
    
    // Preset 3: Interactive Particle Network
    private static let particleNetworkHTML: String = """
    <!DOCTYPE html>
    <html>
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
    <style>
      body, html { margin: 0; padding: 0; width: 100%; height: 100%; overflow: hidden; background: #080c14; }
      canvas { display: block; position: fixed; top: 0; left: 0; width: 100vw; height: 100vh; }
    </style>
    </head>
    <body>
    <canvas id="c"></canvas>
    <script>
      const canvas = document.getElementById('c');
      const ctx = canvas.getContext('2d');
      let w, h;
      let mouse = { x: -1000, y: -1000 };
      let isPaused = false;
      const count = 90;
      const pts = [];
      
      function resize() {
        w = canvas.width = window.innerWidth || document.documentElement.clientWidth;
        h = canvas.height = window.innerHeight || document.documentElement.clientHeight;
      }
      window.addEventListener('resize', resize);
      resize();
      
      for (let i = 0; i < count; i++) {
        pts.push({
          x: Math.random() * w,
          y: Math.random() * h,
          vx: (Math.random() - 0.5) * 1.2,
          vy: (Math.random() - 0.5) * 1.2,
          radius: Math.random() * 2 + 1
        });
      }
      
      window.onDesktopMouseMove = function(nx, ny, px, py) {
        mouse.x = px;
        mouse.y = py;
      };
      window.onWallpaperPause = function() { isPaused = true; };
      window.onWallpaperResume = function() { isPaused = false; step(); };
      
      function step() {
        if (isPaused) return;
        ctx.clearRect(0, 0, w, h);
        
        for (let i = 0; i < count; i++) {
          const p = pts[i];
          p.x += p.vx;
          p.y += p.vy;
          if (p.x < 0 || p.x > w) p.vx *= -1;
          if (p.y < 0 || p.y > h) p.vy *= -1;
          
          // Mouse interaction (gentle repulsion)
          const d = Math.hypot(p.x - mouse.x, p.y - mouse.y);
          if (d < 160) {
            const angle = Math.atan2(p.y - mouse.y, p.x - mouse.x);
            p.x += Math.cos(angle) * 2;
            p.y += Math.sin(angle) * 2;
          }
          
          ctx.beginPath();
          ctx.arc(p.x, p.y, p.radius, 0, Math.PI * 2);
          ctx.fillStyle = '#64d2ff';
          ctx.fill();
          
          for (let j = i + 1; j < count; j++) {
            const p2 = pts[j];
            const dist = Math.hypot(p.x - p2.x, p.y - p2.y);
            if (dist < 130) {
              ctx.beginPath();
              ctx.moveTo(p.x, p.y);
              ctx.lineTo(p2.x, p2.y);
              ctx.strokeStyle = 'rgba(100, 210, 255, ' + (1 - dist / 130) * 0.4 + ')';
              ctx.lineWidth = 0.8;
              ctx.stroke();
            }
          }
        }
        requestAnimationFrame(step);
      }
      step();
    </script>
    </body>
    </html>
    """
    
    // Preset 4: Minimal Aesthetic Live Clock & Waves
    private static let clockWaveHTML: String = """
    <!DOCTYPE html>
    <html>
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
    <style>
      body, html { margin: 0; padding: 0; width: 100%; height: 100%; overflow: hidden; background: #0c0f17; font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", sans-serif; }
      canvas { position: fixed; top: 0; left: 0; width: 100vw; height: 100vh; }
      #ui { position: absolute; bottom: 80px; left: 80px; color: #ffffff; text-shadow: 0 4px 16px rgba(0,0,0,0.4); }
      #time { font-size: 84px; font-weight: 200; letter-spacing: -2px; }
      #date { font-size: 22px; font-weight: 400; opacity: 0.7; margin-top: -6px; }
    </style>
    </head>
    <body>
    <canvas id="c"></canvas>
    <div id="ui">
      <div id="time">12:00</div>
      <div id="date">Monday, January 1</div>
    </div>
    <script>
      const canvas = document.getElementById('c');
      const ctx = canvas.getContext('2d');
      let w, h;
      let phase = 0;
      let mouseX = 0;
      let isPaused = false;
      
      function resize() {
        w = canvas.width = window.innerWidth || document.documentElement.clientWidth;
        h = canvas.height = window.innerHeight || document.documentElement.clientHeight;
      }
      window.addEventListener('resize', resize);
      resize();
      
      function updateClock() {
        const d = new Date();
        const hrs = String(d.getHours()).padStart(2, '0');
        const mins = String(d.getMinutes()).padStart(2, '0');
        document.getElementById('time').innerText = hrs + ':' + mins;
        document.getElementById('date').innerText = d.toLocaleDateString(undefined, { weekday: 'long', month: 'long', day: 'numeric' });
      }
      setInterval(updateClock, 1000);
      updateClock();
      
      window.onDesktopMouseMove = function(nx) {
        mouseX = nx * 50;
      };
      window.onWallpaperPause = function() { isPaused = true; };
      window.onWallpaperResume = function() { isPaused = false; draw(); };
      
      function draw() {
        if (isPaused) return;
        ctx.fillStyle = '#0c0f17';
        ctx.fillRect(0, 0, w, h);
        phase += 0.015;
        
        for (let l = 0; l < 4; l++) {
          ctx.beginPath();
          ctx.moveTo(0, h);
          for (let x = 0; x <= w; x += 10) {
            const y = h * 0.65 + Math.sin(x * 0.003 + phase + l * 0.8) * 45 + Math.cos(x * 0.0015 - phase) * 25 + mouseX * 0.3;
            ctx.lineTo(x, y);
          }
          ctx.lineTo(w, h);
          ctx.closePath();
          ctx.fillStyle = 'rgba(80, 140, 255, ' + (0.05 + l * 0.04) + ')';
          ctx.fill();
        }
        requestAnimationFrame(draw);
      }
      draw();
    </script>
    </body>
    </html>
    """
    
    isolated deinit {
        webView?.navigationDelegate = nil
        webView?.uiDelegate = nil
        webView?.stopLoading()
    }
}
