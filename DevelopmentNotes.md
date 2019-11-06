# Development Notes

### Reactive Programming

* In SPs that have no value, always send an empty tuple as a value. Otherwise, any observer listening for a result will never be triggered.

### Notebook editor

* not using invalidationcontext because should never be enough chunks that resizing should cause a performance issue

should probably have EditorDocument send a notification/signal when contentsSaved called so notebook can reparse

notebook saving

* should we save invalid syntax?
* should we cache results?
* autosave?
* are we storing everything necessary for reproduction?

clear undo cache on file change notification from server

`clang -o mtest -I ../src/  -I src -Wl, -all_load mtest.c src/Debug/libcmark-gfm.a extensions/Debug/libcmark-gfm-extensions.a`


## Preview CSS

### classes

 * internalError
 * rcode
 * section.index
 

### pandoc

can buld stand-alone version, embed in app. Not using for now, but might need to in the future.

--data-dir=
--fail-if-warnings
--log file.json
--extract-media=<DIR>
-s // standalone with headers
--template=FILENAME/URL
--toc //generate table of contents
--id-prefix=<STRING> // when parsing in individually, set a prefix to stop id onverlap
--mathjax=<URL> or
-- mathml // use safari's builtin mathml



# Pandoc

Pandoc is used to generate different flavors of markdown. 

1. brew install haskell-stack
2. download latest src from [Haskell site](https://hackage.haskell.org/package/pandoc)
3. Unpack and cd into directory
4. `stack setup`
5. `stack build --flag pandoc:embed_data_files`
6. copy the binary executable to resources

sign with `codesign -f -s "Mac Developer: Mark Lilback" pandoc --options runtime`

verify code signing with `code sign -dv --verbose=4 pandoc`


## Live Editor

* Executing an inline determines if env changed, if not no forced reefresh. If diid change, autlmatically run all future inline chunks
* Show buttons for update chunk and all chunks forward if they've edited a cvhunk or a previous inline chunk affected the environment
* code chunks show buttons if dirty
* keep environemnt for everything executed, nesting them
* if update a single chunk, all following code chunks show up as dirty

implementation:

* every bit of code is run in its own evnironment
* if chunk 2 is edited, we can test the environment and not re-run future chunks if nothing changed
* chunk output is done via a signal

handler:
* return array of text for each code attachment. let caller integrate into markdown
* one method to get array of inline code for a particular chunk


can we call parse to tell if the function of the code changed instead of just formatting?

