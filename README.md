# Rc2 Swift Client

This project is a rewrite of the [Rc2-client](https://github.com/wvuRc2/rc2client) project started at WVU in 2012. There was a lot of legacy cruft from old features that are no longer needed.

The current Mac client requires Docker, and runs the server portion in docker containers. The server portions are developed at [rc2server](https://github.com/rc2server/rc2). Eventually this client project will move there, too.

Eventually we'll add back iOS support, once we figure out a hosting solution for the server side stuff.

The wiki contains more details on specific topics.

## Dependencies

The macOS client requires 10.14 Mojhave. Development is being done with Xcode 11.3, swift version 5.1.

The rc2server and mlilback packages are split out so they can also be used by the AppServer, which is also written in Swift.

The following packages/frameworks are used (mostly by SPM, a few require Carthage, some are git submodules in the vendor directory). 

* [Down](https://github.com/iwasrobbed/Down.git) Markdown parsing/generation

* [GRDB](https://github.com/groue/GRDB.swift) wrapper around SQlite

* [iosMath](https://github.com/kostub/iosMath.git) renders equations

* [Logging](https://github.com/apple/swift-log.git) Swift API for logging. Allows unified logging across dependencies.

* [MJLLogger](https://github.com/mlilback/MJLLogger.git) a logging framework that works cross-framework, allows only the application to enable logging, and allows enabling logging per LogCategory. Usable as a Logging implementation.

* [PEGKit](https://github.com/itod/pegkit.git) a parsing expression grammar used for syntax highlighting

* [ReactiveCocoa](https://github.com/ReactiveCocoa/ReactiveCocoa) reactive programming is awesome for handling of async callbacks (like making 14 network calls in a row with a single block of error handling code)

* [SBInjector](https://github.com/mlilback/SBInjector.git) very simple dependency injection

* [SigmaSwiftStatistics](https://github.com/evgenyneu/SigmaSwiftStatistics.git) swift statistical library

* [Sparkle](https://sparkle-project.org/) enables update notifications, downloading

* [Starscream](https://github.com/daltoniam/Starscream) for websocket support

* [SwiftyUserDefaults](https://github.com/sunshinejr/SwiftyUserDefaults.git) swifty wrapper around UserDefaults

* [ZipFoundation](https://github.com/weichsel/ZIPFoundation.git) for compressing files

# Preparing to build

1. `carthage bootstrap --no-use-binaries --platform Mac`

2. `git submodule update --init`

3. `(cd ..; git clone https://github.com/rc2server/appmodelSwift.git appmodel2)`. This will eventually be handled by the SPM, but I don't want to have to keep making releases while under active development.

4. `touch config/Local.xcconfig`. See below for details on this file.

# Generating help files

To generate the help index and html files:
```
	cd tools/help
	R --vanilla
	> source("genHelp.R")
	> generateHelp()
```

This will create `helpindex.sqlite` and `helpdocs`. Move the sqllite file to `${SRC_ROOT}ClientCore/help/helpindex.db`. Update the version number in `rc2help.json`.  `Run the command zip -9r help.zip rc2help.json helpdocs`` and then move the zip file to `${SRC_ROOT}ClientCore/help/help.zip`. Update HtlpController.swift.currentHelpVersion to the same as in the json file.

# xcconfig usage

The two main config files are `Debug.xcconfig` and `Release.xcconfig`. Both include `Shared.xcconfig`, which includes `Local.config`. The local file is in .gitignore so you need to create an empty one if you don't want warnings about the file being missing.

Therefore the local config file can be used to supply settings that shouldn't be included in git, like API keys and secrets.

An example that uses the official hockeyapp setup and imageInfo URL would be:

	INFOPLIST_PREPROCESS = YES
	INFOPLIST_PREPROCESSOR_DEFINITIONS=SPARKLE_FEED_URL='https:&#47;&#47;rink.hockeyapp.net/api/2/apps/7574682489924a239272b421546d00f8' LSERVER_UPDATE_URL='http:&#47;&#47;www.rc2.io/imageInfo.json'
 
	OTHER_SWIFT_FLAGS = $(inherited) -DHOCKEYAPP_ENABLED 
	GCC_PREPROCESSOR_DEFINITIONS = $(inherited) HOCKEYAPP_ENABLED=1 HOCKEY_IDENTIFIER='@"7574682489924a239272b421546d00f8"'

	DEVELOPMENT_TEAM = #Your Team Code#

# HockeyApp support

All apps will link with the HockeyApp SDK, but it is only activated if certain preprocessor macros are set in Local.xcconfig. Here is an example:

```C
OTHER_SWIFT_FLAGS = $(inherited) -DHOCKEYAPP_ENABLED
 
GCC_PREPROCESSOR_DEFINITIONS = $(inherited) HOCKEYAPP_ENABLED=1 HOCKEY_IDENTIFIER='@"7574682489924a239272b421546d00f8"'
```
# Github Flavored Markdown

The repository is a submodule in vendor. Follow these steps to build it (if not already built).

```
cd vendor/cmark-gfm
mkdir build; cd build
cmake .. -DCMAKE_INSTALL_PREFIX=./installed
make install
cp ../src/registry.h installed/cmark-gfm/
cp ../src/plugin.h installed/cmark-gfm/
cp ../src/syntax_extension.h /installed/cmark-gfm/
rm build/installed/lib/*.dylib
```

The additional header files are necessary to call some functions defined in cmark-gfm.h

The build directory is in .gitignore, so there should never be any issues with git and unkown files.

ld on macOS will link to dylibs if they are in the same directory as static libraries, even if they aren't in the project settings. So they need to be removed.

# Process arguments

* `--resetSupportData` forces removal of Caches and ApplicationSupport directories and all contents

# Environment Variables

* `DisableHockeyApp` disables HockeyApp loading

* `XCTestConfigurationFilePath` is set by Xcode when running unit tests. If set, skips startup actions.

# Logging

Logging is done via MJLLogger using a configuration class of Rc2LogConfig. Allows setting log level per LogCategory (e.g. enable debug logging for networking only). The swift-log Logging framework is bootstraped with MJLLogger, so any dependencies using swift-log will be logged along with everything else.

