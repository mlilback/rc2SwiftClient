library(tools)
#library(jsonlite)
library(stringi)
library(DBI)
library(RSQLite)

#' Creates the help index database and the html documentation in "helpdocs" in the output directory
#' @param packages Vector of character strings of the packages names to generate help for. If NULL or empty, generates help for all installed packages.
#' @param output_dir The directory in which "helpdocs" will be created, along with htmlindex.db. If all packages are being generated, all existing files will be deleted.
#' @param index_only If TRUE, no html files will be generated.
generateHelp <- function(packages = NULL, output_dir = ".", index_only = FALSE) {
  if (!file.exists(output_dir)) {
    dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)
  }
  data <- setupDb(output_dir, append = length(packages) > 0)
  on.exit( { closeDb(data) }, add = TRUE )
  output_root <- file.path(output_dir, "helpdocs")
  genAllHelp(data, file.path(output_root, "library"))
  root_source <- R.home("doc")
  dir.create(file.path(output_root, "manual"), recursive=TRUE, showWarnings=FALSE)
  file.copy(file.path(root_source, "manual"), output_root, recursive=TRUE)
  dir.create(file.path(output_root, "html"), recursive=TRUE, showWarnings=FALSE)
  file.copy(file.path(root_source, "html"), output_root, recursive=TRUE)
  invisible(TRUE)
}

genHelp <- function (dbData, pkg, output_root, links = tools::findHTMLlinks(), index_only = FALSE) {
  path = file.path(find.package(pkg), "help", pkg)
  rdb = tools:::fetchRdDB(path)
  mylinks = links
  # creates directory. Silently fails if it already exists.
  outdir <- file.path(output_root, pkg, "html")
  dir.create(outdir, recursive=TRUE, showWarnings=FALSE)
  
  pmeta = list() # where package metadata will be stored, one item per function
  topics = names(rdb)
  for (curTopic in topics) {
   suppressWarnings({
    if (index_only == FALSE) {
      outpath = file.path(outdir, paste(curTopic, "html", sep="."))
      tools::Rd2HTML(rdb[[curTopic]], outpath, package = pkg, Links = mylinks)
    }
    meta <- c(pkg)
    for (key in c("\\name","\\title","\\alias","\\description")) {
      # substring to remove the backslash at the start
      meta <- c(meta, getMetaValue(rdb[[curTopic]], key, pkg, curTopic))
    }
    pmeta[[curTopic]] <- meta
    insertFunction(dbData, meta)
   })
  }
  invisible(pmeta)
}

errorHandler <- function(c, topic) {
  print(paste0("error in ", topic, ":", c))
}

genAllHelp <- function (dbData, outdir, index_only = FALSE) {
  topics = rownames(installed.packages()[,c(1,2)])
  links = tools::findHTMLlinks()
  force(links)
  for (tname in topics) {
    tryCatch({
      genHelp(dbData, tname, outdir, index_only=index_only, links = links)
    }, 
    error = function(c) { errorHandler(c, tname) },
    warning = function(c) { errorHandler(c, tname) })
  }
  invisible("")
}

getMetaValue <- function(da, pattern, pkg, fun) {
  indicies = which(unlist(lapply(da, function(x) {
    val = attr(x, "Rd_tag") == pattern
    return(val)
  })))
  results <- sapply(indicies, function (i) { da[i][[1]][[1]][1] })
  if (length(results[[1]]) < 1) { return("") }
  value <- results
  rtype <- typeof(value)
  if (pattern == "\\alias") {
    return(stri_paste(value, collapse=':'))
  } else if (typeof(value) != "character") {
    if (rtype == "list") {
      return(stri_paste(value, collapse='\n'))
    }
    if (pattern == "\\description") {
      print(paste("got desc type mismatch:", results, ":", pkg, "::", fun))
    } else {
      print(paste("got invalid type for ", pattern))
    }
  }
  return(trimws(results[[1]]))
}

insertFunction <- function(globalData, listOfData) {
  #print(paste("got ", listOfData[1], ' ', listOfData[3]))
  args <- listOfData
  while (length(args) < 5) {
    args <- c(args, "")
  }
  res1 <- dbSendStatement(globalData$con, "insert into helptopic values (?, ?, ?, ?, ?)", args)
  dbClearResult(res1)
  res2 <- dbSendStatement(globalData$con, "insert into helpidx values (?, ?, ?, ?, ?)", args)
  dbClearResult(res2)
}

# should be called before calling any other function. Should eventually call closeDb
setupDb <- function(output_dir, append = FALSE) {
  globalData <- new.env(parent = emptyenv())
  globalData$con <- dbConnect(SQLite(), file.path(output_dir, "helpindex.sqlite"))
  existingTables <- dbListTables(globalData$con)
  if (!append || !('helptopic' %in% existingTables)) {
    rs <- dbSendQuery(globalData$con, "DROP TABLE IF EXISTS helpidx")
    dbClearResult(rs)
    rs <- dbSendQuery(globalData$con, "DROP TABLE IF EXISTS helptopic")
    dbClearResult(rs)
    rs <- dbSendQuery(globalData$con, "CREATE VIRTUAL TABLE helpidx USING fts4(package,name,title,aliases,desc, tokenize=porter)")
    dbClearResult(rs)
    rs <- dbSendQuery(globalData$con, "CREATE TABLE helptopic (package text, name tesxt, title text, aliases text, desc text)")
    dbClearResult(rs)
    rs <- dbSendQuery(globalData$con, "CREATE UNIQUE INDEX IF NOT EXISTS htopic_pkg_name ON helptopic(package, name)")
    dbClearResult(rs)
  }
  return(globalData)
}

# shutdown database, other global data
closeDb <- function(globalData) {
  dbDisconnect(globalData$con)
}
