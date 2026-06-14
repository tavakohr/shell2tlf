## shell2tlf -- setup.R
## ---------------------------------------------------------------------------
## One-shot installer for everything the app needs. Use this when
## `renv::restore()` did not pull every package (notably `arsbridge`, which is
## installed from GitHub, not CRAN).
##
## Run from the shell2tlf project directory:
##     Rscript setup.R
## or, inside an R session:
##     source("setup.R")
##
## It installs into whatever library is active -- if renv is on (a project
## `.Rprofile` sourcing `renv/activate.R`), that is the project library, which
## is exactly what `shiny::runApp()` will use.

options(repos = c(CRAN = "https://cloud.r-project.org"))

`%nin%` <- function(x, table) !(x %in% table)

install_if_missing <- function(pkgs) {
  have <- rownames(installed.packages())
  need <- pkgs[pkgs %nin% have]
  if (length(need)) {
    message("Installing CRAN packages: ", paste(need, collapse = ", "))
    install.packages(need)
  } else {
    message("All requested CRAN packages already installed.")
  }
}

## --- 1. App + arsbridge runtime dependencies (all on CRAN) ------------------
cran_pkgs <- c(
  # Shiny UI
  "shiny", "bslib", "DT", "htmltools",
  # rendering stack
  "gt", "tfrmt", "cards", "flextable", "officer", "ggplot2",
  # arsbridge runtime
  "cli", "dplyr", "ellmer", "glue", "haven", "jsonlite",
  "openxlsx2", "readxl", "rlang", "tidyselect", "xml2",
  # docx export needs a working pandoc via rmarkdown
  "rmarkdown",
  # to install arsbridge from GitHub
  "remotes"
)
install_if_missing(cran_pkgs)

## --- 2. arsbridge from GitHub (not on CRAN) --------------------------------
## Pinned to the same commit recorded in renv.lock so behaviour matches.
ARSBRIDGE_REF <- "main"   # or a specific commit SHA
if ("arsbridge" %nin% rownames(installed.packages())) {
  message("Installing arsbridge from GitHub (tavakohr/arsbridge@", ARSBRIDGE_REF, ") ...")
  remotes::install_github("tavakohr/arsbridge", ref = ARSBRIDGE_REF,
                          upgrade = "never", dependencies = TRUE)
} else {
  message("arsbridge already installed (", as.character(packageVersion("arsbridge")), ").")
}

## --- 3. Verify everything loads --------------------------------------------
need_load <- c("shiny", "bslib", "DT", "gt", "tfrmt", "cards", "flextable",
               "officer", "ggplot2", "arsbridge")
ok <- vapply(need_load, requireNamespace, logical(1), quietly = TRUE)
if (all(ok)) {
  message("\nAll set. Launch the app with:  shiny::runApp()")
} else {
  message("\nStill missing: ", paste(need_load[!ok], collapse = ", "),
          "\nRe-run setup.R, or install the missing package(s) manually.")
}
