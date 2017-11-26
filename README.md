# Rc2 Swift Client

This project is a rewrite of the [Rc2-client](https://github.com/wvuRc2/rc2client) project started at WVU 4-5 years ago. There was a lot of legacy cruft from old features that are no longer needed.

The current Mac client requires Docker, and runs the server portion in docker containers. The server portions are developed at [rc2server](https://github.com/rc2server/rc2). Eventually this client project will move there, too.

Eventually we'll add back iOS support, once we figure out a hosting solution for the server side stuff.

The wiki contains more details on specific topics.

## Dependencies

The macOS client requires 10.12 Sierra. Development is being done with Xcode 9.1, swift version 4.0.2.

The following 3rd party frameworks are used (via Carthage or in the vendor directory). Aside from HockeyApp, I'm willing/capable of maintaining a fork if necessary (or replacing them). Using them allows much faster development (or I wrote them myself).

* [CryptoSwift](https://github.com/krzyzanowskim/CryptoSwift.git) a pure swift implementation of cryptographic functions

* [FMDB](https://github.com/ccgus/fmdb} wrapper around SQlite

* [Freddy](https://github.com/bignerdranch/Freddy) for simplified JSON parsing

* [HockeySDK](https://hockeyapp.net/) used for feedback beta distribution. All files are included in the git repository

* [MessagePackSwift](https://github.com/mlilback/MessagePackSwift.git) a Swift implementation of [MessagePack](http://msgpack.org/)

* [Mockingjay](https://github.com/kylef/Mockingjay) for network unit tests

* [NotifyingCollection](https://github.com/mlilback/NotifyingCollection) allows monitoring changes in nested arrays (one callback for any nested change in array of Projects that has an array of Workspaces with an array of Files).

* [PEGKit](https://github.com/itod/pegkit.git) a parsing expression grammar used for syntax highlighting

* [ReactiveCocoa](https://github.com/ReactiveCocoa/ReactiveCocoa) reactive programming is awesome for handling of async callbacks (like making 14 network calls in a row with a single block of error handling code)

* [Result] used by ReactiveCocoa

* [SBInjector](https://github.com/mlilback/SBInjector.git) very simple dependency injection

* [Sparkle](https://sparkle-project.org/) enables update notification

* [Starscream](https://github.com/daltoniam/Starscream) for websocket support

* [URITemplate] used by Mockingjay

* [ZipArchive](https://github.com/ZipArchive/ZipArchive) for compressing files

# Preparing to build

1. `carthage bootstrap --no-use-binaries --platform Mac`

2. `git submodule update --init`

3. Setup HeliumLogger

	1. `cd vendor/HeliumLogger`
	2. If you are using swiftenv, `export SWIFT_VERSION=4.0.2`
	3. `swift package generate-xcodeproj`

Step 2 is necessary because HeliumLogger includes a .swift-version file that sets it to 3.1.1. That needs to be overridden when generating the xcode project.

# Help support

In the help directory, indexDocs.pl is a perl script to generate a json file with the help information necessary to make an index to search. These files are checked into git. The createHelpIndex target parses these files and creates an sqllite db that is embedded in the application for searching help.

The perl script requires `Cpanel::JSON::XS` and `Statistics::R`.

## Generating help files ##

```
cd R-3.3.1
./configure --enable-prebuilt-html
make
tar zcf rdocs.tgz doc library/*/html/*
# cd destination-directory
tar xzf rdocs.tgz
```

# xcconfig usage

The two main config files are `Debug.xcconfig` and `Release.xcconfig`. Both include `Shared.xcconfig`, which includes `Local.config`. The local file is in .gitignore so you need to create an empty one if you don't want warnings about the file being missing.

Therefore the local config file can be used to supply settings that shouldn't be included in git, like API keys and secrets.

# HockeyApp support

All apps will link with the HockeyApp SDK, but it is only activated if certain preprocessor macros are set in Local.xcconfig. Here is an example:

```C
OTHER_SWIFT_FLAGS = $(inherited) -DHOCKEYAPP_ENABLED
 
GCC_PREPROCESSOR_DEFINITIONS = $(inherited) HOCKEYAPP_ENABLED=1 HOCKEY_IDENTIFIER='@"7574682489924a239272b421546d00f8"'
```

# Logging

Logging is done via os_log. To enable debug logging, use `sudo log config --mode "level:debug" --subsystem io.rc2.MacClient`. To stream in the console, use `sudo log stream --level=debug --predicate 'subsystem contains "io.rc2"'`.

