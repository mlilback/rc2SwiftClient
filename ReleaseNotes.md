# Rc² release notes

## Build 70

* adjusted file/variable/help views to properly draw in dark mode
* console history button now a vector, draws like other buttons

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
