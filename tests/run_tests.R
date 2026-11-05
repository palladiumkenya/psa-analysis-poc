#!/usr/bin/env Rscript
# Base-R test runner - no testthat, so this works on a bare Rscript and on
# the R bundled inside jamovi.
#
#   Rscript tests/run_tests.R

.args_all <- commandArgs(trailingOnly = FALSE)
.file_arg <- grep("^--file=", .args_all, value = TRUE)
.here <- if (length(.file_arg))
  dirname(normalizePath(sub("^--file=", "", .file_arg[1]))) else getwd()
source(file.path(.here, "..", "R", "core.R"))

PASS <- 0L; FAIL <- 0L
ok <- function(label, cond) {
  if (isTRUE(cond)) { PASS <<- PASS + 1L; cat("  ok   ", label, "\n") }
  else              { FAIL <<- FAIL + 1L; cat("  FAIL ", label, "\n") }
}

cat("R semantics the port depends on\n")
# cut() is right-closed and excludes the lowest break, so the minimum is NA.
x <- c(5, 1, 2, 3, 4)
b <- quantile(x, probs = seq(0, 1, 0.2))
ok("quantile type 7 gives 1.8 at p=0.2", abs(b[[2]] - 1.8) < 1e-12)
ok("cut() returns NA for the minimum", is.na(as.numeric(cut(x, breaks = b))[2]))
ok("round() is half-to-even",
   round(0.25, 1) == 0.2 && round(0.35, 1) == 0.3 && round(-0.25, 1) == -0.2)
ok("prcomp scales by the n-1 sd",
   isTRUE(all.equal(unname(prcomp(cbind(c(1, 2, 3, 4), c(2, 4, 5, 9)),
                                  scale. = TRUE)$scale),
                    c(sd(c(1, 2, 3, 4)), sd(c(2, 4, 5, 9))))))

cat("\nstratify_pca behaviour\n")
set.seed(42)
toy <- data.frame(id = paste0("u", 1:20), a = rnorm(20), b = rnorm(20), c = rnorm(20))
r <- stratify_pca(toy, "id", c("a", "b", "c"))
ok("every unit gets a stratum", !any(is.na(r$table$Stratum)))
ok("strata are within range", all(r$table$Stratum %in% 1:5))
ok("counts sum to n", sum(r$counts) == nrow(toy))
ok("labels line up with numbers",
   all(r$table$Stratum_label == paste("Stratum", r$table$Stratum)))
ok("explained variance is a proportion", r$explained > 0 && r$explained <= 1)

# Orientation must be deterministic and must actually reverse.
r_asc  <- stratify_pca(toy, "id", c("a", "b", "c"), orient = "asc",  orient_by = "a")
r_desc <- stratify_pca(toy, "id", c("a", "b", "c"), orient = "desc", orient_by = "a")
ok("asc  makes PC1 rise with the reference", cor(r_asc$table$PCA_score, toy$a) > 0)
ok("desc makes PC1 fall with the reference", cor(r_desc$table$PCA_score, toy$a) < 0)
ok("asc and desc negate the scores exactly",
   all(r_asc$table$PCA_score == -r_desc$table$PCA_score))
# The strata mirror too, but NOT for a score sitting exactly on a break.
# cut() uses half-open (lo, hi] intervals, which are not symmetric under
# negation: a value equal to a break joins the bin below it either way. With
# scores rounded to 1dp, exact hits on a break are common. This is R's
# behaviour, inherited on purpose, so the test documents it rather than
# pretending it away.
on_break <- r_asc$table$PCA_score %in% r_asc$breaks
ok("asc and desc mirror, away from exact break values",
   all(r_asc$table$Stratum[!on_break] == 6 - r_desc$table$Stratum[!on_break]))
ok("scores landing exactly on a break are the only exceptions",
   all(which(r_asc$table$Stratum != 6 - r_desc$table$Stratum) %in% which(on_break)))
ok("orientation is stable when rows are reordered", {
  s <- stratify_pca(toy[sample(nrow(toy)), ], "id", c("a", "b", "c"),
                    orient = "asc", orient_by = "a")
  all(s$table$Stratum[match(toy$id, s$table$id)] == r_asc$table$Stratum)
})

cat("\nguard rails\n")
ok("rejects an unknown column",
   inherits(try(stratify_pca(toy, "id", c("a", "nope"), ), silent = TRUE), "try-error"))
ok("rejects a single variable",
   inherits(try(stratify_pca(toy, "id", "a"), silent = TRUE), "try-error"))
ok("rejects a constant column", {
   t2 <- toy; t2$k <- 1
   inherits(try(stratify_pca(t2, "id", c("a", "k")), silent = TRUE), "try-error") })
ok("rejects too few rows for the strata requested",
   inherits(try(stratify_pca(toy[1:4, ], "id", c("a", "b")), silent = TRUE), "try-error"))

cat("\ngolden: matches the jamovi module on the 2026 county extract\n")
vars <- c("Incidence of Outpatient Malaria (per 1000 population)",
          "Malaria Test Positivity Rate - Overall",
          "Confirmed Malaria cases Per 1000 Population",
          "Total Outpatient attendance Workload",
          "Proportion of suspected malaria cases tested")
dat <- read.csv(file.path(.here, "data", "county_2026.csv"), check.names = FALSE)
gold <- read.csv(file.path(.here, "data", "golden_county_2026.csv"), check.names = FALSE)
g <- stratify_pca(dat, "ADM1_EN", vars, orient = "module")
ok("same unit order", all(g$table$ADM1_EN == gold$ADM1_EN))
ok("PC1 scores identical to jamovi", all(abs(g$table$PCA_score - gold$pc1) < 1e-9))
ok("strata identical to jamovi", all(g$table$Stratum == gold$stratum))
ok("stratum counts identical", all(g$counts == as.integer(table(
     factor(gold$stratum, levels = 1:5)))))

# The default orientation should be the mirror of what the module produced
# here - this is the colour-inversion fix, pinned down.
ga <- stratify_pca(dat, "ADM1_EN", vars, orient = "asc",
                   orient_by = "Incidence of Outpatient Malaria (per 1000 population)")
ok("default orientation puts highest burden in the top stratum", {
  inc <- dat[["Incidence of Outpatient Malaria (per 1000 population)"]]
  mean(inc[ga$table$Stratum == 5]) > mean(inc[ga$table$Stratum == 1]) })
ok("module orientation was inverted on this dataset", {
  inc <- dat[["Incidence of Outpatient Malaria (per 1000 population)"]]
  mean(inc[g$table$Stratum == 1]) > mean(inc[g$table$Stratum == 5]) })

cat(sprintf("\n%d passed, %d failed\n", PASS, FAIL))
if (FAIL > 0) quit(status = 1)
