library(tools)
library(jsonlite)

# create a dataframe with columns packagename, installed path
# df <- as.data.frame(installed.packages()[,c(1,2)])

genHelp <- function (pkg, outdir, metadir = outdir, links = tools::filndHTMLlinks(), index_only = FALSE) {
	path = file.path(find.package(pkg), "help", pkg)
	rdb = tools:::fetchRdDB(path)
	mylinks = links

	dir.create(outdir, recursive=TRUE, showWarnings=FALSE)

	pmeta = list()
	topics = names(rdb)
	for (p in topics) {
		section = rdb[[p]]
		if (index_only == FALSE) {
			outpath = file.path(outdir, paste(p, "html", sep="."))
			tools::Rd2HTML(rdb[[p]], outpath, package = pkg, Links = mylinks)
		}
		meta <- list()
		tags = c("title","name","alias","description")
		for (key in tags) {
			meta[[key]] <- paste(unlist(section[which(tags == key)]), collapse="")
		}
		meta[["package"]] <- pkg
		pmeta[[p]] <- meta
	}
	jsonpath = file.path(metadir, paste(pkg, "json", sep="."))
	fileConn <- file(jsonpath)
	writeLines(toJSON(pmeta, auto_unbox=TRUE), fileConn)
	close(fileConn)
	pmeta
}

errorHandler <- function(c, topic) {
	print(paste0("error in ", topic))
}

genAllHelp <- function (outdir, metadir = outdir, index_only = FALSE) {
	topics = rownames(installed.packages()[,c(1,2)])
	links = tools::findHTMLlinks()
	force(links)
	for (tname in topics) {
		tryCatch({
			genHelp(tname, outdir, metadir = metadir, index_only=index_only, links = links)
		}, 
			error = function(c) { errorHandler(c, tname) },
			warning = function(c) { errorHandler(c, tname) },
			message = function(c) { errorHandler(c, tname) })
	}
	invisible("")
}

