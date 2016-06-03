# rc2SwiftClient TODO

# when disabling window while async task is executing, need to save and restore the first responder

* Clear console command should only available with console visible

* after clearing the console and quitting, the next launch has the old contents

* add autologin if have data from keychain (LoginViewController)

* ImageOutputController: if splitter resizes us, the pagecontroller view does not adjust its frame

* ImageOutputController: figure out how to support async image loading

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
	
* Sidebar File Controller

	* Make sure our list is updated when delegate renames a file
	
	* implement addFile in addButtonClicked
	
	* implement duplicate file
	
	* implement rename file
	
	* implement add document of type
	
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
	
