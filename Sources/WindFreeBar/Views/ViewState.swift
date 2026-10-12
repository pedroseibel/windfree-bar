import SwiftUI

/// The SDK now spells `@State` as a macro whose plugin ships only with Xcode. This alias reaches the
/// underlying property wrapper so the app builds with just the Command Line Tools.
typealias ViewState<Value> = SwiftUI.State<Value>
