# Rc2 Swift Client

This project is a rewrite of the [Rc2-client](https://github.com/wvuRc2/rc2client) project started at WVU 4-5 years ago. There was a lot of legacy cruft from old features that are no longer needed.

This version is a complete rewrite in Swift, though where possible it is a pretty straight forward port of the Objective C code.

## Dependencies

The OSX client requires 10.11 El Capitan. Development is being done with Xcode 7.2.

[Carthage](https://github.com/Carthage/Carthage) is used as a dependency manager. Other dependencies include:

* [Starscream](https://github.com/daltoniam/Starscream/issues) for websocket support

* [XCGLogger](https://github.com/DaveWoodCom/XCGLogger) for logging.

* [SwiftyJSON](https://github.com/SwiftyJSON/SwiftyJSON) for simplified JSON parsing.

## Building

For some reason, carthage was getting an error building the iOS version of Starscream. Therefore, it is better to use `carthage update --platform Mac` to prep opening in Xcode.
