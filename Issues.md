# Known Issues

* Search for TODO: in project

* when a file is clicked in the results, it will show the newest version, not the version returned at that time. Is this a problem?

* image icons drawn in results have a white background, not transparent. the pdfs have transparency in pixelmator and illustrator

* compute engine barfs on markdown files with a space in their name

* add output segmented control (console, html, pdf, image)

* RestServerTests and EditorDocumentTests are disabled and need fixing.

* SystemExtensionsTests is incomplete

* BaseTest used to load a LoginSession from the actual RestServer

* need to adjust progress size if only pulling 1 or 2 images

* examine SourceKit for syntax highlighting

* if dockerUrl is set but not responding, no error message is logged or notified

* add unit test for scanning installed images for a specific docker tag

* eventually need to be able to reopen everthing network related (DockerEventManager)

* add localization of strings using NSLocalizedString
