#' Manage python dependencies
#' according to: https://rstudio.github.io/reticulate/articles/python_dependencies.html#manual-configuration
#'
#' @name omnideconvstartup
NULL

.onLoad <- function(libname, pkgname) {
  cli::cli_alert("checking omnideconv environment and dependencies")

  # We ensure to have reticulate
  if (!dir.exists(reticulate::miniconda_path())) {
    message("Setting python version in miniconda to be 3.8")
    Sys.setenv(RETICULATE_MINICONDA_PYTHON_VERSION = 3.8)
    message("Setting up miniconda environment..")
    suppressMessages(reticulate::install_miniconda())
  }


  # We ensure to have the r-reticulate env
  # if (!file.exists(reticulate::conda_python("r-reticulate"))) {
  if (!("r-omnideconv" %in% reticulate::conda_list()$name)) {
    reticulate::conda_create(envname = "r-omnideconv", python_version = 3.8)
  }

  # locate the environment path
  paths <- reticulate::conda_list()
  path <- paths[paths$name == "r-omnideconv", 2]


  # Normalize and adjust the path for windows if necessary
  if (.Platform$OS.type == "windows") {
    # Transform the path for Windows and ensure it is valid
    path.bin <- gsub("/envs/r-omnideconv/python.exe$", "/Library/bin", path, fixed = TRUE)
    path.bin <- normalizePath(path.bin, winslash = "/", mustWork = FALSE)

    # for windows, the path separator needs to be adjusted
    if (file.exists(path.bin)) {
      separator <- ";"
      Sys.setenv(PATH = paste(path.bin, Sys.getenv("PATH"), sep = separator))
    } else {
      warning("The transformed path for 'path.bin' does not exist: ", path.bin)
    }
  } else {
    # on other platforms the path is separated with :
    separator <- ":"
    Sys.setenv(PATH = paste(path, Sys.getenv("PATH"), sep = separator))
  }

  # Set up reticulate and use the environemnt
  Sys.setenv(RETICULATE_PYTHON = path)
  reticulate::use_miniconda(condaenv = "r-omnideconv", required = TRUE)
  reticulate::py_config()
  reticulate::configure_environment(pkgname, force = TRUE)

  # install necessary python packages if not available
  if (!reticulate::py_module_available("anndata")) {
    anndata::install_anndata()
  }
}
