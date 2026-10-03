import Foundation

/// Swift Testing suites are structs, and `Bundle(for:)` needs a class: this one locates the
/// test bundle holding the fixtures (`sample.m4a`, the `.cue` files).
final class TestBundleAnchor {}
