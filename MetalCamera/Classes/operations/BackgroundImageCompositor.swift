//
//  BackgroundImageCompositor.swift
//  MetalCamera
//
//  Created by Dennis Mo on 30/12/2020.
//


import Foundation
import MetalKit

public class BackgroundImageCompositor: OperationChain {
    public let targets = TargetContainer<OperationChain>()

    public var sourceTextureKey: String = ""
    public var sourceFrame: CGRect?

    private let baseTextureKey: String
    private var sourceTexture: MTLTexture?

    private var pipelineState: MTLRenderPipelineState!
    private var render_target_vertex: MTLBuffer!
    private var render_target_uniform: MTLBuffer!

    private let textureInputSemaphore = DispatchSemaphore(value:1)
    private var textureBuffer1: MTLBuffer?
    private var textureBuffer2: MTLBuffer?

    public init(baseTextureKey: String) {
        self.baseTextureKey = baseTextureKey
        setup()
    }

    private func setup() {
        setupPiplineState()
    }

    private func setupPiplineState(_ colorPixelFormat: MTLPixelFormat = .bgra8Unorm) {
        do {
            let rpd = try sharedMetalRenderingDevice.generateRenderPipelineDescriptor("two_vertex_render_target", "alphaBlendFragment", colorPixelFormat)
            pipelineState = try sharedMetalRenderingDevice.device.makeRenderPipelineState(descriptor: rpd)
        } catch {
            debugPrint(error)
        }
    }

    public func addCompositeImage(_ image: UIImage) {
        sourceTexture = image.loadTexture(device: sharedMetalRenderingDevice.device)
    }

    public func newTextureAvailable(_ texture: Texture) {
        if texture.textureKey == self.baseTextureKey {
            baseTextureAvailable(texture)
        } else if texture.textureKey == self.sourceTextureKey {
            sourceTexture = texture.texture
        }
    }

    private func loadRenderTargetVertex(_ baseTextureSize: CGSize) {
        guard let sourceFrame = sourceFrame else { return }
        render_target_vertex = sharedMetalRenderingDevice.makeRenderVertexBuffer(sourceFrame.origin, size: sourceFrame.size)
        render_target_uniform = sharedMetalRenderingDevice.makeRenderUniformBuffer(baseTextureSize)
    }
    
    private func generateTextureBuffer(_ width: Int, _ height: Int, _ targetWidth: Int, _ targetHeight: Int) -> MTLBuffer? {
        let targetRatio = Float(targetWidth)/Float(targetHeight)
        let curRatio = Float(width)/Float(height)

        let coordinates: [Float]

        if targetRatio > curRatio {
            let remainHeight = (Float(height) - Float(width) * targetRatio)/2.0
            let remainRatio = remainHeight/Float(height)
            coordinates = [0.0, remainRatio, 1.0, remainRatio, 0.0, 1.0 - remainRatio, 1.0, 1.0 - remainRatio]
        } else {
            let remainWidth = (Float(width) - Float(height) * targetRatio)/2.0
            let remainRatio = remainWidth/Float(width)
            coordinates = [remainRatio, 0.0, 1.0 - remainRatio, 0.0, remainRatio, 1.0, 1.0 - remainRatio, 1.0]
        }

        let textureBuffer = sharedMetalRenderingDevice.device.makeBuffer(bytes: coordinates,
                                                                         length: coordinates.count * MemoryLayout<Float>.size,
                                                                         options: [])!
        return textureBuffer
    }
    
    private func baseTextureAvailable(_ texture: Texture) {
        let source1 = texture
        guard let source2 = try? Texture(texture: sourceTexture!, timestamp: nil) else {
            // Bypass received texture if there is no source texture.
            operationFinished(texture)
            return
        }
        let _ = textureInputSemaphore.wait(timeout:DispatchTime.distantFuture)
        defer {
            textureInputSemaphore.signal()
        }

        let minX = min(source1.texture.width, source2.texture.width)
        let minY = min(source1.texture.height, source2.texture.height)

        if textureBuffer1 == nil {
            textureBuffer1 = generateTextureBuffer(source1.texture.width, source1.texture.height, minX, minY)
        }
        if textureBuffer2 == nil {
            textureBuffer2 = generateTextureBuffer(source2.texture.width, source2.texture.height, minX, minY)
        }

        let outputTexture = Texture(minX, minY, timestamp: source1.timestamp, textureKey: source1.textureKey)

        let renderPassDescriptor = MTLRenderPassDescriptor()
        let attachment = renderPassDescriptor.colorAttachments[0]
        attachment?.clearColor = MTLClearColorMake(1, 0, 0, 1)
        attachment?.texture = outputTexture.texture
        attachment?.loadAction = .clear
        attachment?.storeAction = .store

        let commandBuffer = sharedMetalRenderingDevice.commandQueue.makeCommandBuffer()
        let commandEncoder = commandBuffer?.makeRenderCommandEncoder(descriptor: renderPassDescriptor)

        commandEncoder?.setFrontFacing(.counterClockwise)
        commandEncoder?.setRenderPipelineState(pipelineState)

        let vertexBuffer = sharedMetalRenderingDevice.device.makeBuffer(bytes: standardImageVertices,
                                                                        length: standardImageVertices.count * MemoryLayout<Float>.size,
                                                                        options: [])!
        vertexBuffer.label = "Vertices"
        commandEncoder?.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        commandEncoder?.setVertexBuffer(textureBuffer1, offset: 0, index: 1)
        commandEncoder?.setVertexBuffer(textureBuffer2, offset: 0, index: 2)

        commandEncoder?.setFragmentTexture(source1.texture, index: 0)
        commandEncoder?.setFragmentTexture(source2.texture, index: 1)
        let uniformBuffer = sharedMetalRenderingDevice.device.makeBuffer(bytes: [1],
                                                                         length: 1 * MemoryLayout<Float>.size,
                                                                         options: [])!
        commandEncoder?.setFragmentBuffer(uniformBuffer, offset: 0, index: 1)

//        commandEncoder?.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        commandEncoder?.endEncoding()
        commandBuffer?.commit()

        textureInputSemaphore.signal()
        operationFinished(outputTexture)
        let _ = textureInputSemaphore.wait(timeout:DispatchTime.distantFuture)
    }
//    private func baseTextureAvailable(_ texture: Texture) {
//        guard let sourceTexture = try? Texture(texture: sourceTexture!, timestamp: nil) else {
//            // Bypass received texture if there is no source texture.
//            operationFinished(texture)
//            return
//        }
//
//        let _ = textureInputSemaphore.wait(timeout:DispatchTime.distantFuture)
//        defer {
//            textureInputSemaphore.signal()
//        }
//
////        if render_target_vertex == nil {
////            let baseTextureSize = CGSize(width: texture.texture.width, height: texture.texture.height)
////            loadRenderTargetVertex(baseTextureSize)
////        }
//
//        if render_target_vertex == nil {
//            let baseTextureSize = CGSize(width: sourceTexture.texture.width, height: sourceTexture.texture.height)
//            loadRenderTargetVertex(baseTextureSize)
//        }
//
//        let renderPassDescriptor = MTLRenderPassDescriptor()
//        let attachment = renderPassDescriptor.colorAttachments[0]
////        attachment?.texture = texture.texture
//        attachment?.texture = sourceTexture.texture
//        attachment?.loadAction = .load
//        attachment?.storeAction = .store
//
//        let commandBuffer = sharedMetalRenderingDevice.commandQueue.makeCommandBuffer()
//        let commandEncoder = commandBuffer?.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
//
//        commandEncoder?.setRenderPipelineState(pipelineState)
//
//        commandEncoder?.setVertexBuffer(render_target_vertex, offset: 0, index: 0)
//        commandEncoder?.setVertexBuffer(render_target_uniform, offset: 0, index: 1)
////        commandEncoder?.setFragmentTexture(sourceTexture, index: 0)
//        commandEncoder?.setFragmentTexture(texture.texture, index: 0)
//        commandEncoder?.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
//
//        commandEncoder?.endEncoding()
//        commandBuffer?.commit()
//
//        textureInputSemaphore.signal()
////        operationFinished(texture)
//        operationFinished(texture)
//        let _ = textureInputSemaphore.wait(timeout:DispatchTime.distantFuture)
//
//    }
}
