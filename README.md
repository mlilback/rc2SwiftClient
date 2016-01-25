# Rc2 Swift Client

This project is a rewrite of the [Rc2-client](https://github.com/wvuRc2/rc2client) project started at WVU 4-5 years ago. There was a lot of legacy cruft from old features that are no longer needed.

This version is a complete rewrite in Swift, though where possible it is a pretty straight forward port of the Objective C code.

## Dependencies

The OSX client requires 10.11 El Capitan. Development is being done with Xcode 7.2.

Due to a bug in clang that causes crashes with [Carthage](https://github.com/Carthage/Carthage) dependency management is done via git submodules. Dependencies include:

* [SwiftWebSocket](https://github.com/tidwall/SwiftWebSocket) for websocket support

* [XCGLogger](https://github.com/DaveWoodCom/XCGLogger) for logging.

* [SwiftyJSON](https://github.com/SwiftyJSON/SwiftyJSON) for simplified JSON parsing.

* [Swinject](https://github.com/Swinject/Swinject) for dependency injection into objects loaded from a storyboard (since container seques don't call prepareForSeque)

* [Mockingjay](https://github.com/kylef/Mockingjay) for networking unit tests.
