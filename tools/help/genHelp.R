library(tools)
library(jsonlite)
library(stringi)
library(DBI)
library(RSQLite)

# create a dataframe with columns packagename, installed path
# df <- as.data.frame(installed.packages()[,c(1,2)])

genHelp <- function (pkg, outdir, metadir = outdir, links = tools::findHTMLlinks(), index_only = FALSE) {
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
		tags = c("\\title","\\name","\\alias","\\description")
		for (key in tags) {
			# substring to remove the backslash at the start
			meta[[substring(key, 2)]] <- getMetaValue(section, key, pkg, p)
			#paste(unlist(section[which(tags == key)]), collapse="")
		}
		meta[["package"]] <- pkg
		pmeta[[p]] <- meta
	}
	jsonpath = file.path(metadir, paste(pkg, "json", sep="."))
	fileConn <- file(jsonpath)
	writeLines(toJSON(pmeta, auto_unbox=TRUE), fileConn)
	close(fileConn)
	invisible(pmeta)
}

errorHandler <- function(c, topic) {
	print(paste0("error in ", topic, ":", c))
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

getMetaValue <- function(da, pattern, pkg, fun) {
	 indicies = which(unlist(lapply(da, function(x) {
		val = attr(x, "Rd_tag") == pattern
		return(val)
	})))
	results <- sapply(indicies, function (i) { da[i][[1]][[1]][1] })
	value <- tryCatch ({ return(results[[1]][1]) },
		error=function(c) { print(paste("val error: ", c)); return("") })
	rtype <- typeof(value)
	if (pattern == "\\alias") {
		return(stri_paste(value, collapse=':'))
	} else if (typeof(value) != "character") {
		if (rtype == "list") {
			return(stri_paste(value, collapse='\n'))
		}
		if (pattern == "\\description") {
			print(paste("go	t desc type mismatch:", results, ":", pkg, "::", fun))
		} else {
			print(paste("got invalid type for ", pattern))
		}
	}
	return(results[[1]])
}
setup
insertFunction <- function

setupDB <- function() {
	conn <- dbConnect(SQLite(), "helpindex.db")
	dbSendQuery(conn, "drop table if exists helpidx")
	dbSendQuery(conn, "drop table if exists helptopic")
	dbSendQuery(conn, "create virtual table helpidx using fts4(package,name,title,aliases,desc, tokenize=porter)")
	dbSendQuery(conn, "create table helptopic (package, name, title, aliases, desc)")
	conn
}

insertJson <- function(meta) {
	conn <- dbConnect(SQLite(), "helpindex.db")
	tryCatch( {
		
	}, finally = {
		dbDisconnect(conn)
	})
	
}
