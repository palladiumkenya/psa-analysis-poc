# Optional choropleth output, mirroring the jamovi module's .plot().
#
# Unlike core.R this needs sf and raster. They are installed in the Docker
# image; locally they come from whatever library you point R at - including
# the ones bundled with the installed StratificationKEN jamovi module.

#' Join strata to a shapefile and render a choropleth.
#'
#' @param result      the list returned by stratify_pca().
#' @param id_col      the column used to join, present in BOTH the data and
#'                    the shapefile attribute table (the module requires the
#'                    name to be identical on both sides).
#' @param shapefile   path to a .shp.
#' @param png_path    where to write the image; NULL draws to the current device.
#' @param shp_out     optional path to write the joined shapefile.
#' @param groups      number of strata, for the palette and legend.
#' @param title       plot title.
render_map <- function(result, id_col, shapefile, png_path = NULL,
                       shp_out = NULL, groups = 5, title = NULL) {
  for (p in c("sf", "raster")) {
    if (!requireNamespace(p, quietly = TRUE))
      stop("package '", p, "' is required for mapping but is not installed.\n",
           "Either run the Docker target, or point R at a library that has it ",
           "(the installed jamovi module bundles both).", call. = FALSE)
  }

  shp <- sf::read_sf(shapefile)
  if (!id_col %in% names(shp))
    stop("the shapefile has no '", id_col, "' field. Available: ",
         paste(setdiff(names(shp), attr(shp, "sf_column")), collapse = ", "),
         call. = FALSE)

  tbl <- result$table
  sp <- methods::as(shp, "Spatial")
  sp$strata <- tbl$Stratum[match(sp@data[, id_col], tbl[[id_col]])]

  unmatched <- sum(is.na(sp$strata))
  # The module forces unmatched polygons into the last stratum. That silently
  # paints "no data" as if it were a real result, so we warn about it.
  if (unmatched > 0)
    warning(unmatched, " of ", nrow(sp@data),
            " polygons did not match the data and are drawn as stratum ",
            groups, call. = FALSE)
  sp$strata[is.na(sp$strata)] <- groups

  if (!is.null(shp_out)) {
    sf_out <- sf::st_as_sf(sp)
    sf::st_write(sf_out, shp_out, quiet = TRUE, delete_dsn = TRUE)
  }

  pal <- rev(c("red", "orange", "yellow", "green", "darkgreen"))
  if (groups != 5) pal <- rev(grDevices::hcl.colors(groups, "RdYlGn"))

  if (!is.null(png_path))
    grDevices::png(png_path, width = 500, height = 600)
  on.exit(if (!is.null(png_path)) grDevices::dev.off(), add = TRUE)

  graphics::par(mar = c(1, 1, 2, 1))
  ext <- raster::extent(sp)
  y_delta <- ext[4] - ext[3]
  raster::plot(sp, border = grDevices::gray(0.7), lwd = 1,
               col = pal[sp$strata], axes = FALSE,
               ylim = c(ext[3] - y_delta * 0.15, ext[4] + y_delta * 0.2),
               main = title)
  graphics::legend("bottomleft", pch = 21, pt.bg = pal[seq_len(groups)],
                   legend = paste("Stratum", seq_len(groups)),
                   pt.cex = 2, cex = 1.2, bty = "o",
                   border = "white", bg = "white", title = "Strata")
  invisible(TRUE)
}
