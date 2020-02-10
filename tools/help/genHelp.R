library(tools)
library(jsonlite)
library(stringi)
library(DBI)
library(RSQLite)

# globals
globalData <- new.env(parent = emptyenv())
globalData$setupComplete = FALSE
# setup addds these variables to globalData 
# - insertHelpRS
# - insertTopicRS

genHelp <- function (pkg, outdir, links = tools::findHTMLlinks(), index_only = FALSE) {
  path = file.path(find.package(pkg), "help", pkg)
  rdb = tools:::fetchRdDB(path)
  mylinks = links
  # creates directory. Silently fails if it already exists.
  dir.create(outdir, recursive=TRUE, showWarnings=FALSE)
  
  pmeta = list() # where package metadata will be stored, one item per function
  topics = names(rdb)
  for (p in topics) {
    if (index_only == FALSE) {
      outpath = file.path(outdir, paste(p, "html", sep="."))
      tools::Rd2HTML(rdb[[p]], outpath, package = pkg, Links = mylinks)
    }
    meta <- list()
    for (key in c("\\title","\\name","\\alias","\\description")) {
      # substring to remove the backslash at the start
      meta[[substring(key, 2)]] <- getMetaValue(rdb[[p]], key, pkg, p)
    }
    meta[["package"]] <- pkg
    pmeta[[p]] <- meta
  }
#  jsonpath = file.path(metadir, paste(pkg, "json", sep="."))
#  fileConn <- file(jsonpath)
#  writeLines(toJSON(pmeta, auto_unbox=TRUE), fileConn)
#  close(fileConn)
  invisible(pmeta)
}

errorHandler <- function(c, topic) {
  print(paste0("error in ", topic, ":", c))
}

genAllHelp <- function (outdir, index_only = FALSE) {
  topics = rownames(installed.packages()[,c(1,2)])
  links = tools::findHTMLlinks()
  force(links)
  for (tname in topics) {
    tryCatch({
      genHelp(tname, outdir, index_only=index_only, links = links)
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

insertFunction <- function(record) {
  print(paste("got ", record$name))
  args <- list(meta[['package']], meta[['name']], neta[['title']], meta[['aliases']], meta[['desc']])
  dbBind(globalData$insertTopic, params = args)
  dbFetch(globalData$insertTopic)
  dbBind(globalData$insertTopic, params = args)
  dbFetch(globalData$insertHelp)
}

# should be called before calling any other function. Should eventually call closeDb
setupDb <- function(append = FALSE) {
  globalData$con <- dbConnect(SQLite(), "helpindex.db")
  existingTables <- dbListTables(globalData$conn)
  if (!append || !('helptopic' %in% existingTables)) {
    dbSendQuery(globalData$con, "DROP TABLE IF EXISTS helpidx")
    dbSendQuery(globalData$con, "DROP TABLE IF EXISTS helptopic")
    dbSendQuery(globalData$con, "CREATE VIRTUAL TABLE helpidx USING fts4(package,name,title,aliases,desc, tokenize=porter)")
    dbSendQuery(globalData$con, "CREATE TABLE helptopic (package text unique not null on conflict rollback, name tesxt, title text, aliases text, desc text)")
    dbSendQuery(globalData$con, "CREATE UNIQUE INDEX IF NOT EXISTS htopic_pkg_name ON helptopic(package, name)")
  }
  globalData$insertTopicRS = dbSendStatement(connection, "insert into helptopic values (?, ?, ?, ?, ?)")
  globalData$insertHelpRS = dbSendStatement(connection, "insert into helpidx values (?, ?, ?, ?, ?)")
  
}

# shutdown database, other global data
closeDb <- function() {
  dbClearResult(globalData$insertTopicRS)
  dbClearResult(globalData$insertHelpRS)
  dbDisconnect()
  # rm(insertTopicRS, env = globalData)
  # rm(insertHelpRS, env = globalData)
  # rm(setupComplete, env = globalData)
  # rm(con, env = globalData)
  rm(globalData)
}
