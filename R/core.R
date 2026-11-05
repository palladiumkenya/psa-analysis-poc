# Core stratification, ported from the StratificationKEN jamovi module's
# .run() so the same analysis can run outside jamovi.
#
# Base R only - no packages - so this runs on a bare Rscript, and on the R
# that ships inside jamovi (which has no CRAN packages installed).

# Equivalent of the module's local reclassify() helper.
reclassify <- function(x, in_categories, out_categories) {
  out_categories[match(x, in_categories)]
}

#' Stratify administrative units on the first principal component.
#'
#' Mirrors the jamovi module: standardise the indicators, take PC1, round the
#' scores, cut them at quantiles and label the bins.
#'
#' @param data        data.frame holding one row per unit.
#' @param id_col      name of the column identifying each unit.
#' @param vars        character vector of indicator column names.
#' @param groups      number of strata (the module hard-codes 5).
#' @param digits      decimals to round PC1 to before cutting (module: 1).
#' @param orient      "asc"    - PC1 rises with `orient_by`; top stratum is the
#'                              highest burden. Stable across datasets.
#'                    "desc"   - the reverse; stratum 1 is the highest burden.
#'                    "module" - reproduce the module exactly: LAPACK's own
#'                              sign multiplied by -1. Arbitrary, and known to
#'                              flip between datasets. See README.
#' @param orient_by   reference column for "asc"/"desc"; defaults to vars[1].
#' @return list(table, breaks, loadings, explained, counts, orientation)
stratify_pca <- function(data, id_col, vars, groups = 5, digits = 1,
                         orient = c("asc", "desc", "module"),
                         orient_by = NULL) {
  orient <- match.arg(orient)

  missing <- setdiff(c(id_col, vars), names(data))
  if (length(missing))
    stop("column(s) not found: ", paste(missing, collapse = ", "),
         "\navailable: ", paste(names(data), collapse = ", "), call. = FALSE)
  if (length(vars) < 2)
    stop("need at least 2 indicator variables for a PCA", call. = FALSE)
  if (nrow(data) <= groups)
    stop(nrow(data), " rows is too few for ", groups, " strata", call. = FALSE)

  # --- same selection the module does -------------------------------------
  pca_db_all <- data[, c(id_col, vars), drop = FALSE]
  pca_db <- pca_db_all[, -1, drop = FALSE]
  pca_db <- sapply(pca_db, as.numeric)
  if (!is.matrix(pca_db)) pca_db <- matrix(pca_db, nrow = nrow(data))

  bad <- which(!is.finite(pca_db), arr.ind = TRUE)
  if (nrow(bad)) {
    stop("non-numeric or missing values in: ",
         paste(unique(vars[bad[, "col"]]), collapse = ", "),
         " (first at data row ", bad[1, "row"], ")", call. = FALSE)
  }
  const <- vars[apply(pca_db, 2, function(z) stats::sd(z) == 0)]
  if (length(const))
    stop("constant column(s), cannot be scaled: ",
         paste(const, collapse = ", "), call. = FALSE)

  # --- PCA ----------------------------------------------------------------
  fit <- stats::prcomp(pca_db, scale. = TRUE)
  scores <- as.numeric(fit$x[, 1])
  loadings <- fit$rotation[, 1]

  # --- sign ---------------------------------------------------------------
  # The module does `PCA_results$x <- -1 * PCA_results$x`. LAPACK's sign is
  # arbitrary, so that is reproducible for a given dataset but not comparable
  # between datasets - it flips between the demo data and the 2026 extract.
  if (orient == "module") {
    scores <- -1 * scores
    loadings <- -1 * loadings
    ref_name <- NA_character_
  } else {
    ref_name <- if (is.null(orient_by)) vars[1] else orient_by
    if (!ref_name %in% vars)
      stop("orient_by must be one of the indicator variables: ", ref_name,
           call. = FALSE)
    reference <- as.numeric(data[[ref_name]])
    is_positive <- stats::cor(scores, reference) >= 0
    if (is_positive != (orient == "asc")) {
      scores <- -scores
      loadings <- -loadings
    }
  }

  # --- cut into strata ----------------------------------------------------
  scores <- round(scores, digits)
  probs <- seq(0, 1, length.out = groups + 1)
  breaks <- stats::quantile(scores, probs = probs)

  if (anyDuplicated(breaks))
    stop("quantile breaks are not unique - too many tied PC1 scores for ",
         groups, " strata. Try fewer groups, or check for duplicate rows.",
         call. = FALSE)

  # cut() defaults to right = TRUE, include.lowest = FALSE, so the minimum
  # value falls outside every interval and returns NA; the module then forces
  # those to 1. Reproduced deliberately.
  strata_num <- as.numeric(cut(scores, breaks = breaks))
  strata_num[is.na(strata_num)] <- 1

  out <- data
  out$PCA_score <- scores
  out$Stratum <- strata_num
  out$Stratum_label <- reclassify(strata_num, seq_len(groups),
                                  paste("Stratum", seq_len(groups)))

  list(
    table       = out,
    breaks      = breaks,
    loadings    = loadings,
    explained   = fit$sdev[1]^2 / sum(fit$sdev^2),
    counts      = as.integer(table(factor(strata_num, levels = seq_len(groups)))),
    orientation = list(mode = orient, reference = ref_name)
  )
}
