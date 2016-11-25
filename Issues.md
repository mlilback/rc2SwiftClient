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

* eventually need to be able to reopen everthing network related (DockerEventManager)

* add localization of strings using NSLocalizedString

* need UI to reset rc2_dbdata volume

* docker event stream can timeout. need to handle this (takes hours to happen)

* make sure docker stuff works with sleep

* switching help topics adjusts width of split view

* switch all use of KVO in File to use signals

* need to move framework required defaults to each framework, and have app load them allowing each succeeding framework to overwrite lower ones

* if a dbserver image is updated, the dbdata volume still has the data in it. need to backup the sql and then restore it after creating a new volume. The rc2.last file created on first db run is there, which causes db container to fail.

* DockerErrors need to be transformed somewhere to Rc2Errors
