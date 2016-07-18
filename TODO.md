# rc2SwiftClient TODO

* don't allow two windows to same session

* restore session:

	* need to show progress while restoring sessions

* fix Session memory leak (not dealloc'd when window closed)

* need to show progress while opening a session

* add unit tests for BookmarkManager

* when disabling window while async task is executing, need to save and restore the first responder

* add autologin if have data from keychain (LoginViewController)

* change OutputColors to use a static array of colors that is updated if a color changes in NSUserDefaults

* clean up old images

* a second save of edits isn't being sent to the compute engine (or maybe app server)

* for jim, not clearing text when selecting non-file

* for jim, image display not showing after plot command

* Unit tests

	* fix FileImporterTests.testSessionMock
	
	* add test Rmd/Rnw files for SyntaxParserTests

* SessionController

	* if no image cached saved, need to recreate from cache files (is this possible?)

* ImageOutputController

	* figure out how to support async image loading
	
* Output Tab Controller

	* showHelp: handle selection if more than 1 help topic is returned
	
	* displayFileAttachment: 
		
		* check for file by name if not found by id
		
		* handle error in finding file user asked to display
	
	* showFile:
	
		* handle images in image view instead of webkit view
		
		* find better solution that using a block with a .5 second delay

* RootViewController

	* implement loadHelpItems
	
	* implement renameFile (and why is it listed here and in SidebarFileController)
	
	* implement importFiles([NSURL])
	
	* implement sessionErrorReceived

* SessionEditorController

	* Allow DI of notification center
	
	* executeQuery needs to notify  user if failed to save file to server
	
	* saveDocumentToServer needs to mark busy via appStatus
	
	* current chunk should have a a background of selection color @ 20%
	
	* didn't empty when file was deleted
		
* Sidebar File Controller

	* Make sure our list is updated when delegate renames a file
	
	* implement addFile in addButtonClicked
	
	* implement duplicate file
	
	* implement rename file
	
	* implement add document of type
	
	* why is delete button some times enabled when no file is selected
	
	* promptToImportFiles: report error to user if failed to start import
	
	* filesRefreshed:
	
		* ideally should animate changes in table view instead of reloading all
		
		* updated file always shows at bottom instead of in proper order
		
	* tableView:acceptDrop needs to update table view after accepting drop
	
* FileImporter: if we got confirmation a file was added from us, copy/move it instead of refetching from the server

* DefaultSessionFileHandler:

	* test updatFile works properly for large files not sent over websocket
	
	* handle insert update messages
	
	* handle deletion update messages

* ServerResponse:

	* for saveResponse, not looking at success boolean or error message
	
	* need to handle userid message (or remove it since it currently isn't used)	

Session:

	* trigger error notification when handling a save response
	
	* support duplicate response handling
	
	* support rename response handling

Help

	* unhardcode stat.wvu.edu from help urls, beable to work when demoing w/o a net
	* keywords for help can include a '.' character: list.files is given separate links to list and files instead of one to "list.files"
