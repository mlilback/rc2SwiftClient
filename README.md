# Rc2 Swift Client

This project is a rewrite of the [Rc2-client](https://github.com/wvuRc2/rc2client) project started at WVU 4-5 years ago. There was a lot of legacy cruft from old features that are no longer needed.

This version is a complete rewrite in Swift, though where possible it is a pretty straight forward port of the Objective C code.

## Dependencies

The OSX client requires 10.11 El Capitan. Development is being done with Xcode 7.3.

* [Bright Futures](https://github.com/Thomvis/BrightFutures.git) a promise/future library to make async code look a lot cleaner

* [CryptoSwift](https://github.com/krzyzanowskim/CryptoSwift.git) a pure swift implementation of cryptographic functions

* [HockeySDK](https://hockeyapp.net/) used for feedback beta distribution. All files are included in the git repository

* [MessagePackSwift](https://github.com/mlilback/MessagePackSwift.git) a Swift implementation of [MessagePack](http://msgpack.org/)

* [Mockingjay](https://github.com/kylef/Mockingjay) for networking unit tests

* [PEGKit](https://github.com/itod/pegkit.git) a parsing expression grammar used for syntax highlighting

* [PMKVObserver](https://github.com/postmates/PMKVObserver.git) a wrapper around KVO to make it thread-safe and type-safe

* [Result] used by BrightFutures

* [Sparkle](https://sparkle-project.org/) enables update notification

* [SwiftWebSocket](https://github.com/tidwall/SwiftWebSocket) for websocket support

* [SwiftyJSON](https://github.com/SwiftyJSON/SwiftyJSON) for simplified JSON parsing

* [Swinject](https://github.com/Swinject/Swinject) for dependency injection

* [URITemplate] used by Mockingjay

* [SwinjectStoryboard](https://github.com/Swinject/SwinjectStoryboard) for dependency injection into objects loaded from a storyboard (since container segues don't call prepareForSegue)

* [XCGLogger](https://github.com/DaveWoodCom/XCGLogger) for logging

# Building

1. `carthage build --no-use-binaries --platform Mac .`

2. Copy all files from Carthage/Build/Mac to the `Build/Products/Debug` folder in the project's folder in `~/Library/Developer/Xcode/DerivedData`.

# Help support

In the help directory, indexDocs.pl is a perl script to generate a json file with the help information necessary to make an index to search. These files are checked into git. The createHelpIndex target parses these files and creates an sqllite db that is embedded in the application for searching help.

The perl script requires `Cpanel::JSON::XS` and `Statistics::R`.

# xcconfig usage

The two main config files are `Debug.xcconfig` and `Release.xcconfig`. Both include `Shared.xcconfig`, which includes `Local.config`. The local file is in .gitignore so you need to create an empty one if you don't want warnings about the file being missing.

Therefore the local config file can be used to supply settings that shouldn't be included in git, like API keys and secrets.

# HockeyApp support

All apps will link with the HockeyApp SDK, but it is only activated if certain preprocessor macros are set in Local.xcconfig. Here is an example:

```C
OTHER_SWIFT_FLAGS = $(inherited) -DHOCKEYAPP_ENABLED
 
GCC_PREPROCESSOR_DEFINITIONS = $(inherited) HOCKEYAPP_ENABLED=1 HOCKEY_IDENTIFIER='@"7574682489924a239272b421546d00f8"'
```
