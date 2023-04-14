#' Filter features based on specified criteria
#' - null features
#' - features outside of ppm range
#' - features with no runs >= min.runlength
#' - features derived from < min.subset spectra
#' - features with strong baseline effect 
#' 
#' @param feature A feature object to be filtered
#' @param ppm A vector of ppm values for each point in the spectra
#' @param ppm.range A vector specifying the range of ppm values to include
#' @param min.runlength The minimum length of a run of consecutive data points to include
#' @param min.subset The minimum number of spectra a feature must be present in to be included
#' @param prom.ratio The maximum ratio of peak prominence to intensity range for a feature to be considered monotonic
#' @param give A character string indicating whether to return the filtered feature object or the filter as a logical vector
#' 
#' @return If \code{give = "features"}, a feature object with the filtered features. If \code{give = "filter"}, a logical vector indicating which features passed the filter.
#' 
#' 
#' @export
filterFeatures <- function(feature, ppm, ppm.range, min.runlength = 3, min.subset = 5, prom.ratio = 0.3, give = "filter"){
    
  
  # No empty features, please
    message("Filtering out null features")
    nullfeatures <- apply(feature$position, 1, function(x) all(is.na(x)))
    
  # In the selected ppm range?
    message("Filtering out features outside of (", ppm.range[1], ") - (", ppm.range[2], ") ppm...")
    ppmrngs <- apply(feature$position, 1, function(x) range(x, na.rm = TRUE) %>% ppm[.] %>% rev) %>% t
    
    # plot(ppmrngs[TRUE])
    inbounds <- apply(ppmrngs, 1, function (x) (x[1] > ppm.range[1] & x[2] < ppm.range[2]) &
                                            (x[2] > ppm.range[1] & x[2] < ppm.range[2])  ) %>% 
                                                        unlist
      
  # Filter out features with runs too short
    message("Filtering out features with no runs >= ", min.runlength, " points...")
    rl.pass <- apply(feature$stack, 1,
                   function(x) {run.lens <- x %>% is.na %>% "!"(.) %>% runs.labelBy.lengths
                                return((run.lens >= min.runlength) %>% any)})
    
  # Filter out features without enough subset size 
    message("Filtering out features derived from < ", min.subset, " spectra...")
    ss.pass <- feature$subset$sizes >= min.subset 
  
  # Filter out monotonic features
    message("Filtering out features with strong baseline effect (max true peak prominence < ", prom.ratio, "*intensity range")
    message("or strong correlation (r >= .99) between valley and peak intensities). Progress...")
    
    # Are there any peaks > 0.3 * feature intensity range? (Monotonic?) ####
      bl.effect <- pblapply(1:nrow(feature$stack), function(f)
      {
         # print(f)
         feature$stack[f, , drop = FALSE] %>% 
           trim.sides %>%
           detect.baseline.effect(prom.ratio = prom.ratio)
      })
      
      bl.effect.ul <- bl.effect %>% unlist %>% as.logical
      pass.prom <- bl.effect.ul[c(TRUE,FALSE)]
      pass.fit <- bl.effect.ul[c(FALSE,TRUE)]
      
      not.monotonic <- pass.prom & pass.fit

      
  # Build the filter
    filt <- !nullfeatures & inbounds & rl.pass & ss.pass & not.monotonic
    message('Filtering complete. ', sum(filt), '/', length(filt), ' features passed filters.')
    
  if (give == "features"){
    # Go through feature object and apply filter
      feature$stack <- feature$stack[filt, ]
      feature$position <- feature$position[filt, ]
      feature$subset$ss.all <- feature$subset$ss.all[filt, ]
    return(feature)
  }
  if (give == "filter"){
    return(filt)
  }

}