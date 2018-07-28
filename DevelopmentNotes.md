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

### TODO

if websocket is closed (including fails to connect) need to inform user. currently still marked as opening in MacAppDelegate:274


* updated FrontMatterViewItem to use reactive binding when updated to use ReactiveCocoa 7.1

### code templates
* add dirty flag to template manager when using swift 4.2 for auto generation of Hashable
* editor needs to remember expanded categories
