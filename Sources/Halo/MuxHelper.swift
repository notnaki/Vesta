import Foundation

/// Absolute path to the `halo-attach` relay binary that sits beside the running
/// executable — works both in Halo.app/Contents/MacOS and in .build/debug.
func muxHelperPath() -> String {
    Bundle.main.executableURL!.deletingLastPathComponent()
        .appendingPathComponent("halo-attach").path
}
