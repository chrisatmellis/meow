// Linux typecheck shim mirroring the Metal API surface the game uses.
//
// Only `RenderQuality` touches Metal, and only to ask the GPU which family it
// belongs to. There is no GPU here, so the default device is nil and the tier
// falls back the same way it would on a device that refused to report one.
@_exported import Foundation

public enum MTLGPUFamily: Int {
    case apple1 = 1001, apple2, apple3, apple4, apple5, apple6, apple7, apple8, apple9
    case common1 = 3001, common2, common3
}

public protocol MTLDevice: AnyObject {
    var name: String { get }
    var recommendedMaxWorkingSetSize: UInt64 { get }
    func supportsFamily(_ family: MTLGPUFamily) -> Bool
}

public func MTLCreateSystemDefaultDevice() -> MTLDevice? { nil }
