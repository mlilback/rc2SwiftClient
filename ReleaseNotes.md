# Rc² release notes

## Build 83

* help now generated in R, includes packages installed in the compute engine instead of just base R.
* equations now h ighlighted

## Build 82

* preview editor highlights R code.

## Build 81

* window title more descriptive
* console commands work
* fixed crasher loading document at startup
* document switching from Rmd to Rmd keeps output ini preview mode

## Build 80

* uses new parser
* fixed editor line number bugs 
* file name field clears when a file is deleted
* fixed bugs where menu validation wasn't happening
* moved export all to export submenu, added items to export selected file and all files to a zip file

## Build 79

* no longer sandboxed
* switched markdown parser to cmark-gfm
* more implementation of live preview
* numerous bug fixes

## Build 78

* removed lots of potentially buggy code with parsing documents for preview mode
* live preview updates only the modified chunk when possible, isntead of reloading whole page

## Build 71

* fixed crashing bug when switching between editor tabs too fast
* removed last remaining interace referring to notebook mode
* editor switching bugs fixed, buttons properly enabled
* preview editor now has basic editing like source editor

## Build 70

* adjusted file/variable/help views to properly draw in dark mode
* console history button now a vector, draws like other buttons
* theme color editing works in prefs
* replaced 3rd party TAAdaptiveSpaceItem with NSToolbar builtin centering
* removed notebook editor
* fullscreen mode seems to work

## Build 63

* notebook code/equation blocks no longer color backgrounds
* chunks no longer spuriously add newlines at the top of their content
* long documents no longer crash the parser, load much faster
* implemented deletion of chunks
* notebook trims newlines from block equations which causes problems with knitr
* equation/code chunks no longer narrow if there isn't a newline at the end
* equation chunk drag image now has correct background color
* source editor and code chunks show line numbers
* imports are now case-sensitive for file extensions

## Build 61

* changed all notebook insets to 16 px (was 20/8) so scrollbar never overlaps edge of item view
* notebook editor visually implemented
* option clicking a results twiddle toggles for all chunks

## Build 60

* prefs window remembers location, selected tab
* theme prefs properly highlights theme type 
* theme names editable, saveable
* new parser
* accessibility labels added
* clear console option in contextual menu
* all output tabs have contextual menu submenu to switch tab
* updated docker image

## Build 57

* Log and Docker windows restored if open at last quit
* onboarding window switched from webview to native controls
* better error handling and logging
* added file templates for new files (both in app bundle and application support)
