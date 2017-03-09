# Rc2 Swift Client

This project is a rewrite of the [Rc2-client](https://github.com/wvuRc2/rc2client) project started at WVU 4-5 years ago. There was a lot of legacy cruft from old features that are no longer needed.

This version is a complete rewrite in Swift, though where possible it is a pretty straight forward port of the Objective C code.

## Dependencies

The macOS client requires 10.12 Sierra. Development is being done with Xcode 8.

* [CryptoSwift](https://github.com/krzyzanowskim/CryptoSwift.git) a pure swift implementation of cryptographic functions

* [Freddy](https://github.com/bignerdranch/Freddy) for simplified JSON parsing

* [HockeySDK](https://hockeyapp.net/) used for feedback beta distribution. All files are included in the git repository

* [MessagePackSwift](https://github.com/mlilback/MessagePackSwift.git) a Swift implementation of [MessagePack](http://msgpack.org/)

* [Mockingjay](https://github.com/kylef/Mockingjay) for networking unit tests

* [PEGKit](https://github.com/itod/pegkit.git) a parsing expression grammar used for syntax highlighting

* [PMKVObserver](https://github.com/postmates/PMKVObserver.git) a wrapper around KVO to make it thread-safe and type-safe

* [ReactiveSwift](https://github.com/ReactiveCocoa/ReactiveSwift) the latest core library of ReactiveCocoa.

* [Result] used by ReactiveSwift

* [SBInjector](https://github.com/mlilback/SBInjector.git) for dependency injection

* [Sparkle](https://sparkle-project.org/) enables update notification

* [Starscream](https://github.com/daltoniam/Starscream) for websocket support

* [URITemplate] used by Mockingjay

* [ZipArchive](https://github.com/ZipArchive/ZipArchive) for compressing files

# Preparing to build

1. `carthage bootstrap --no-use-binaries --platform Mac`

2. `git submodule update --init`

# Docker support

By default, all communication is done via /var/run/docker.sock. A remote host can be used by putting a URL with port number in the environment variable `DockerHostUrl`.

# Help support (local)

In the help directory, indexDocs.pl is a perl script to generate a json file with the help information necessary to make an index to search. These files are checked into git. The createHelpIndex target parses these files and creates an sqllite db that is embedded in the application for searching help.

The perl script requires `Cpanel::JSON::XS` and `Statistics::R`.

# Help support (server)

The URL for help documentation on the web is part of info.plist.

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

