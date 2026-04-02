import Foundation

func appDebugLog(_ message: @autoclosure () -> String) {
#if DEBUG
    print(message())
#endif
}

func appDebugTrace(_ block: () -> Void) {
#if DEBUG
    block()
#endif
}
