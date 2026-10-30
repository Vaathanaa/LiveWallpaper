import AppKit
import Metal
import QuartzCore
import simd

public struct ShaderUniforms {
    public var time: Float
    public var resolution: SIMD2<Float>
    public var mouse: SIMD2<Float>
    public var preset: Int32
}

@MainActor
public final class MetalBackdropView: NSView {
    private var metalLayer: CAMetalLayer!
    private var device: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var pipelineState: MTLRenderPipelineState?
    
    private var renderTimer: Timer?
    private var startTime: CFTimeInterval = CACurrentMediaTime()
    private var currentMousePos: CGPoint = .zero
    private var targetMousePos: CGPoint = .zero
    private var isCurrentlyPaused: Bool = true
    
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupMetal()
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupMetal()
    }
    
    public override func makeBackingLayer() -> CALayer {
        let layer = CAMetalLayer()
        layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = true
        return layer
    }
    
    private func setupMetal() {
        wantsLayer = true
        guard let device = MTLCreateSystemDefaultDevice() else {
            NSLog("[MetalBackdropView] No Metal device available on Apple Silicon.")
            return
        }
        self.device = device
        self.commandQueue = device.makeCommandQueue()
        
        if let metalLayer = self.layer as? CAMetalLayer {
            metalLayer.device = device
            metalLayer.pixelFormat = .bgra8Unorm
            metalLayer.framebufferOnly = true
            metalLayer.isOpaque = true
            self.metalLayer = metalLayer
        }
        
        buildPipeline(device: device)
    }
    
    public override func layout() {
        super.layout()
        if let metalLayer = self.layer as? CAMetalLayer {
            metalLayer.drawableSize = convertToBacking(bounds).size
        }
    }
    
    private func buildPipeline(device: MTLDevice) {
        let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;

        struct Uniforms {
            float time;
            float2 resolution;
            float2 mouse;
            int preset;
        };

        struct VertexOut {
            float4 position [[position]];
            float2 uv;
        };

        vertex VertexOut metalVertex(uint vertexID [[vertex_id]]) {
            // Fullscreen Quad from 4 vertices (Triangle Strip)
            float2 positions[4] = {
                float2(-1.0, -1.0),
                float2( 1.0, -1.0),
                float2(-1.0,  1.0),
                float2( 1.0,  1.0)
            };
            float2 uvs[4] = {
                float2(0.0, 1.0),
                float2(1.0, 1.0),
                float2(0.0, 0.0),
                float2(1.0, 0.0)
            };
            
            VertexOut out;
            out.position = float4(positions[vertexID], 0.0, 1.0);
            out.uv = uvs[vertexID];
            return out;
        }

        // Simplex/fbm noise helpers
        float hash(float2 p) {
            return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453123);
        }

        float noise(float2 p) {
            float2 i = floor(p);
            float2 f = fract(p);
            float2 u = f * f * (3.0 - 2.0 * f);
            return mix(mix(hash(i + float2(0.0, 0.0)), hash(i + float2(1.0, 0.0)), u.x),
                       mix(hash(i + float2(0.0, 1.0)), hash(i + float2(1.0, 1.0)), u.x), u.y);
        }

        float fbm(float2 p) {
            float v = 0.0;
            float a = 0.5;
            for (int i = 0; i < 4; i++) {
                v += a * noise(p);
                p *= 2.0;
                a *= 0.5;
            }
            return v;
        }

        // Preset 0: Deep Space Nebula
        float4 renderNebula(float2 uv, float time, float2 mouse) {
            float2 p = uv - 0.5;
            p.x *= 1.77;
            p += (mouse - 0.5) * 0.15;
            
            float t = time * 0.08;
            float f1 = fbm(p * 2.5 + float2(t, -t * 0.5));
            float f2 = fbm(p * 4.0 - float2(t * 0.7, t));
            
            float3 col = float3(0.02, 0.03, 0.08); // Deep space base
            col += float3(0.4, 0.15, 0.6) * f1 * 1.4; // Violet interstellar dust
            col += float3(0.08, 0.45, 0.7) * f2 * 1.2; // Cyan stellar filaments
            
            // Subtle glowing stars
            float star = pow(hash(floor(uv * 180.0)), 35.0) * 1.5;
            col += float3(star);
            
            return float4(col, 1.0);
        }

        // Preset 1: Cyberpunk Digital Rain
        float4 renderMatrix(float2 uv, float time) {
            float2 p = uv;
            float columns = 65.0;
            float colIndex = floor(p.x * columns);
            float speed = 0.8 + hash(float2(colIndex, 1.0)) * 1.2;
            float head = fract(time * speed * 0.2 + hash(float2(colIndex, 7.0)));
            
            float dist = head - p.y;
            if (dist < 0.0) dist += 1.0;
            
            float trail = exp(-dist * 7.0);
            float headGlow = exp(-dist * 40.0) * 2.0;
            
            float3 green = float3(0.0, 0.95, 0.35);
            float3 white = float3(0.85, 1.0, 0.95);
            float3 col = mix(green * trail, white, min(1.0, headGlow));
            
            col *= step(0.08, fract(p.y * 50.0)); // Grid phosphor lines
            return float4(col, 1.0);
        }

        // Preset 2: Minimalist Liquid Fluid
        float4 renderFluid(float2 uv, float time, float2 mouse) {
            float2 p = (uv - 0.5) * 3.0;
            p += (mouse - 0.5) * 0.5;
            
            for (int i = 1; i < 4; i++) {
                float fi = float(i);
                p.x += 0.3 / fi * sin(fi * 2.0 * p.y + time * 0.4);
                p.y += 0.3 / fi * cos(fi * 2.0 * p.x + time * 0.4);
            }
            
            float r = cos(p.x + p.y + 1.0) * 0.5 + 0.5;
            float g = sin(p.x + p.y + 2.0) * 0.5 + 0.5;
            float b = (sin(p.x - p.y) + cos(p.x + p.y)) * 0.25 + 0.5;
            
            float3 col = float3(r * 0.35, g * 0.45, b * 0.8);
            return float4(col, 1.0);
        }

        // Preset 3: Atmospheric Northern Aurora
        float4 renderAurora(float2 uv, float time, float2 mouse) {
            float2 p = uv;
            p += (mouse - 0.5) * 0.08;
            float t = time * 0.15;
            
            float wave1 = sin(p.x * 4.0 + t) * 0.12 + 0.55;
            float wave2 = cos(p.x * 6.0 - t * 0.7) * 0.08 + 0.65;
            
            float dist1 = abs(p.y - wave1);
            float dist2 = abs(p.y - wave2);
            
            float glow1 = exp(-dist1 * 12.0) * 1.5;
            float glow2 = exp(-dist2 * 15.0) * 1.2;
            
            float3 auroraGreen = float3(0.05, 0.9, 0.55);
            float3 auroraViolet = float3(0.5, 0.15, 0.85);
            float3 col = float3(0.02, 0.02, 0.06); // Dark night sky
            
            col += auroraGreen * glow1;
            col += auroraViolet * glow2;
            
            return float4(col, 1.0);
        }

        fragment float4 metalFragment(VertexOut in [[stage_in]],
                                      constant Uniforms &u [[buffer(0)]]) {
            switch (u.preset) {
                case 1:
                    return renderMatrix(in.uv, u.time);
                case 2:
                    return renderFluid(in.uv, u.time, u.mouse);
                case 3:
                    return renderAurora(in.uv, u.time, u.mouse);
                case 0:
                default:
                    return renderNebula(in.uv, u.time, u.mouse);
            }
        }
        """
        
        do {
            let library = try device.makeLibrary(source: shaderSource, options: nil)
            let vertexFunc = library.makeFunction(name: "metalVertex")
            let fragmentFunc = library.makeFunction(name: "metalFragment")
            
            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.vertexFunction = vertexFunc
            pipelineDescriptor.fragmentFunction = fragmentFunc
            pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            
            self.pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            NSLog("[MetalBackdropView] Pipeline creation failed: %@", error.localizedDescription)
        }
    }
    
    public func startRendering() {
        guard renderTimer == nil else { return }
        // 60Hz - 120Hz smooth render loop with zero WebKit overhead
        let targetInterval: TimeInterval = 1.0 / 60.0
        renderTimer = Timer.scheduledTimer(withTimeInterval: targetInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.renderFrame()
            }
        }
    }
    
    public func stopRendering() {
        renderTimer?.invalidate()
        renderTimer = nil
    }
    
    public func pause() {
        isCurrentlyPaused = true
        stopRendering()
    }
    
    public func resume() {
        isCurrentlyPaused = false
        startRendering()
    }
    
    public func updateMousePosition(normalized: CGPoint) {
        self.targetMousePos = normalized
    }
    
    private func renderFrame() {
        guard !isCurrentlyPaused,
              let metalLayer = self.metalLayer,
              let pipelineState = self.pipelineState,
              let commandQueue = self.commandQueue,
              let drawable = metalLayer.nextDrawable() else { return }
        
        // Critical damping mouse interpolation
        currentMousePos.x += (targetMousePos.x - currentMousePos.x) * 0.1
        currentMousePos.y += (targetMousePos.y - currentMousePos.y) * 0.1
        
        let elapsed = Float(CACurrentMediaTime() - startTime)
        let boundsSize = bounds.size
        
        let presetIndex: Int32
        switch AppSettings.shared.metalPreset {
        case .nebula: presetIndex = 0
        case .matrix: presetIndex = 1
        case .fluid:  presetIndex = 2
        case .aurora: presetIndex = 3
        }
        
        var uniforms = ShaderUniforms(
            time: elapsed,
            resolution: SIMD2<Float>(Float(boundsSize.width), Float(boundsSize.height)),
            mouse: SIMD2<Float>(Float(currentMousePos.x), Float(currentMousePos.y)),
            preset: presetIndex
        )
        
        let passDescriptor = MTLRenderPassDescriptor()
        passDescriptor.colorAttachments[0].texture = drawable.texture
        passDescriptor.colorAttachments[0].loadAction = .clear
        passDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        passDescriptor.colorAttachments[0].storeAction = .store
        
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else { return }
        
        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ShaderUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
