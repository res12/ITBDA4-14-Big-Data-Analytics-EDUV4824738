options(repos = c(CRAN = "https://cloud.r-project.org"))
needed <- c("tm", "topicmodels", "tidytext", "rvest", "xml2", "httr", "wordcloud", "DBI", "RPostgres", "igraph")
installed <- rownames(installed.packages())
to_install <- setdiff(needed, installed)
if (length(to_install) > 0) {
  cat("Installing:", paste(to_install, collapse = ", "), "\n")
  install.packages(to_install, dependencies = TRUE)
} else {
  cat("All packages already installed.\n")
}
cat("Verification:\n")
for (p in needed) {
  cat(sprintf("  %-12s : %s\n", p, requireNamespace(p, quietly = TRUE)))
}
