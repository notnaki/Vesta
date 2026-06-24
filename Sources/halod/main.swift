import Foundation
import HaloMux

// Version probe for `halo attach ssh://…` deploy decision. Must run without
// touching the socket so a remote one-shot `halod --proto-version` is cheap.
if CommandLine.arguments.dropFirst().first == "--proto-version" {
    print("halod-proto \(muxProtocolVersion)")
    exit(0)
}

let daemon = Daemon()
daemon.run()
