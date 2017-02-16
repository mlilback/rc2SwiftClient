# Known Issues

* Search for TODO: in project

* when a file is clicked in the results, it will show the newest version, not the version returned at that time. Is this a problem?

* image icons drawn in results have a white background, not transparent. the pdfs have transparency in pixelmator and illustrator

* compute engine barfs on markdown files with a space in their name

* RestServerTests and EditorDocumentTests are disabled and need fixing.

* SystemExtensionsTests is incomplete

* BaseTest used to load a LoginSession from the actual RestServer

* need to adjust progress size if only pulling 1 or 2 images

* examine SourceKit for syntax highlighting

* if dockerUrl is set but not responding, no error message is logged or notified

* add unit test for scanning installed images for a specific docker tag

* eventually need to be able to reopen everything network related (DockerEventManager)

* add localization of strings using NSLocalizedString

* need UI to reset rc2_dbdata volume

* docker event stream can timeout. need to handle this (takes hours to happen)

* need to move framework required defaults to each framework, and have app load them allowing each succeeding framework to overwrite lower ones

* if a dbserver image is updated, the dbdata volume still has the data in it. need to backup the sql and then restore it after creating a new volume. The rc2.last file created on first db run is there, which causes db container to fail.

* make sure [restore windows full screen](http://mjtsai.com/blog/2016/11/18/full-screen-is-a-preference/) if that is how they were on last quit 

* Validate image versions of containers. If a current container is using rc2server/appserver:0.4.1 and we've just pulled 0.4.2, the container needs to be deleted and recreated with the newer image.

* need to handle error with bad network

* need to add help for installed packages

* need to remove old images after a pull of a new image

* need to work without a network connection if docker images already loaded

* write unit tests for InputPrompter validation

* pending transactions need a timeout

* reevaluate all os_log calls to make sure using correct level

* opening sidebar on full screen adjust only the size of editor, not results.

* is it possible for multiple save requests to be in progress at one time? prohibit or handle

* if no file in editor, and 2 other files. Delete first other file, and second other file is selected and then displayed. Only should select next file if it is an editable file.

* ability to center splitters (double click is standard, right?)

* attachment only links via id. If a generated file (pdf, html) need to match on name since id constantly changes.

* when a file has changed, should user see notice that isn't the same file as when attachment icon was generated? Or should be remove icons? Or store version info and color if different?

* variable sidebar should support copy: for specific types

* implement FileImporterTests

* add contextual menu for sidebar variable table

* show error if import fails

* html output content search

how are dates formatted for copy? date vs datetime. 

* add execute selected lines

* chunk navigation is broken

* add padding around icon images in results

* figure out why have to reload all webviews when displaying html output

write nstexfield that scales font size so text fits (for help page title)

implement searchbar interface to use for console output/editor

disable bookmark interface. add onboarding with list of workspaces
