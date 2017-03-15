# Known Issues

* Search for TODO: in project

## general issues
* add localization of strings using NSLocalizedString
* reevaluate all os_log calls to make sure using correct level
* examine all fataError calls to see if there is a better way to handle the problem
* are we properly escaping strings to prevent input buffer errors?
* enable swiftlint for entire project

## unit tests
* write unit tests for InputPrompter validation
* RestServerTests and EditorDocumentTests are disabled and need fixing.
* SystemExtensionsTests is incomplete
* implement FileImporterTests

## UX questions
* when a file is clicked in the results, it will show the newest version, not the version returned at that time. Is this a problem?
* what is UI to delete a workspace?
* when a file has changed, should user see notice that isn't the same file as when attachment icon was generated? Or should be remove icons? Or store version info and color if different?

## docker
* if dockerUrl is set but not responding, no error message is logged or notified
* eventually need to be able to reopen everything network related (DockerEventManager)
* need to remove old docker images after a pull of a new image
* need UI to reset rc2_dbdata volume
* docker event stream can timeout. need to handle this (takes hours to happen)
* if a dbserver image is updated, the dbdata volume still has the data in it. need to backup the sql and then restore it after creating a new volume. The rc2.last file created on first db run is there, which causes db container to fail.
* Validate image versions of containers. If a current container is using rc2server/appserver:0.4.1 and we've just pulled 0.4.2, the container needs to be deleted and recreated with the newer image.

## compute engine
* compute engine barfs on markdown files with a space in their name

## console
* attachment only links via id. If a generated file (pdf, html) need to match on name since id constantly changes.
* hover over image icons to see preview
* add twiddle to see output from rmd, rnw build commands (currently suppressed at compute level)

## main splitter
* opening sidebar on full screen adjust only the size of editor, not results.
* ability to center splitters (double click is standard, right?)

## error handling
* pending transactions need a timeout
* need to handle error with bad network
* show error if import fails
* restore sessions: what happens if there is an error opening a session? Probably hangs

## sidebar

### files
* txt/csv should have menu option to view as result, default as source

### help
* partial match searching not working properly

##editor
* execute current chunk if R code
* execute all chunks up to and including current chunk if R code
* chunk navigation is broken
* implement searchbar interface to use for console
* txt and csv files should be editable

## startup
* need to work without a network connection if docker images already loaded
* new workspace not consistent in full screen w/ session window
* startup dialog not shown when restoring a session. why?

## output
* html output content search
* implement searchbar interface to use for console

## other

* need to adjust progress size if only pulling 1 or 2 images
* need to move framework required defaults to each framework, and have app load them allowing each succeeding framework to overwrite lower ones
* need to add help for installed packages
* is it possible for multiple save requests to be in progress at one time? prohibit or handle
* variable sidebar should support copy: for specific types
* how are dates formatted for copy? date vs datetime. 
* write nstexfield that scales font size so text fits (for help page title)

