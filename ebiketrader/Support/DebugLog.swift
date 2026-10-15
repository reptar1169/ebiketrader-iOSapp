//
//  DebugLog.swift
//  ebiketrader
//

import Foundation

/// Progress chatter that is useful while developing and has no business in a
/// shipped build. The device console is readable by anyone with the phone and
/// a Mac, so anything routed through here should be assumed visible on a
/// debug build and absent on a release one.
///
/// Failures deliberately keep calling print directly: if a tester hits a real
/// problem, a trace is worth having.
///
/// @autoclosure so the interpolation isn't even evaluated in a release build.
func logDebug(_ message: @autoclosure () -> String) {
    #if DEBUG
    print(message())
    #endif
}
