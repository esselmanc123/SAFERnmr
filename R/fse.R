#' FSE Function
#'
#' Extracts feature shapes from a matrix of NMR spectra using the FSE algorithm.
#' # FSE: the spectral matrix is decomposed into compound features using feature
#' shape extraction. First, a local STOCSY is performed at every point along the
#' spectrum (within a sliding window of ~ 100 points; enough to capture multiple
#' resonances within any multiplet). For each of these STOCSYs, the central peak
#' in the correlation profile (correlation pocket; corrpocket) typically captures
#' a resonance, as the correlation is 1 by definition at the STOCSY'd point, and
#' typically falls off as you approach the boundaries of the resonance. This is
#' taken, with the next highest correlation peak within the window, to form a
#' rough statistical description of two resonances which have an correlation in
#' intensity across samples, albeit separated by chemical shift. We term this a
#' 'protofeature'. Importantly, each point and its associated window will capture
#' the dominant protofeature most associated with that point. This changes for
#' adjacent points, and many protofeatures will be duplicated multiple times. A
#' protofeature should be considered as a rough hypothesis about a statistical
#' association between two resonances, which happen to be sufficiently aligned
#' so that they produce a coherent signal.
#' If the windows are all aligned, we can plot the % of central corrpeaks containing
#' each window point. From this distribution, it is clear that nearly all
#' protofeatures, including those from noise peaks and real peaks, include the
#' most central window points. As such, these cannot reliably be used to identify
#' noise. However, the correlation peak about noise tends to be much smaller, and
#' characteristically so. As such, a noisewidth can be estimated from this
#' distribution. This is the origin of the noise.percentile cutoff, which is applied
#' like so: "given a noise.percentile = 0.99, consider only those protofeatures
#' for which both peaks have a width > the smallest 1% of peaks". Reducing this
#' number therefore gives a more selective cut. Protofeatures are also filtered so
#' that they must be bidirectional (i.e. both peaks must indicate each other as
#' highest correlated), and must include runs > noise.width.
#'
#' STORM: Joram Posma's STORM has been adapted and optimized to accept these
#' protofeatures in the following ways:
#' - first, since many of the protofeatures are noise, we provide failure modes
#'   and reporting for the following cases:
#'   "empty subset",          #' empty subset (no spectrum contains signature)
#'   "subset degenerated",    #' 1-3 spectra in the subset (not enough spectra to
#'                              get a reliable correlation)
#'   "reference degenerated", #' signature degenerates to include < 3 points (not
#'                              meaningful to correlate shapes)
#'   "did not converge"       #' subset continues to change after 24 iterations
#
#' - additionally, the correlation r and p-value cutoff q are both used during
#'   both the subset selection and reference update steps.
#' - we also remove any regions of the reference for which there are fewer than
#'   minpeak values after r and p value thresholding. This helps avoid noise.
#'
#' STORM extracts meaningful features using protofeatures to define the region of
#' interest and a rough sketch of the feature shape highly correlated with each
#' spectral point. In the future, HCA could be used to cluster potential starting
#' feature shapes correlated with each driver, or the nonoptimal subset for each
#' point could be re-STORMed to detect any other feature shapes present. It is
#' also perfectly reasonable to combine feature shapes from different STORM runs
#' for a given dataset, as these comprise a list of somewhat independently tested
#' feature shapes, and duplication is not an issue.
#'
#' @param pars A list of parameters for the function.
#'
#' @return A list of features extracted from the spectra.
#'
#' @importFrom readRDS
#' @importFrom corrPocketPairs_al
#' @importFrom plyr ldply count
#' @importFrom pander
#' @importFrom purrr pluck
#'
#'
#' @export
fse <- function(pars) {
  message("-------------------------------------------------------")
  message("-------------------       FSE       -------------------")
  message("-------------------------------------------------------")


  ################ Read parameters file ##################

  tmpdir <- pars$dirs$temp
  this.run <- paste0(tmpdir)


  ################ Get MTBLS1 data from RDS ##################

  X_raw <- readRDS(paste0(this.run, "/spectral.matrix.RDS"))
  xmat <- X_raw[-1, ] # spectral matrix (each row is a spectrum;
  # doesn't require alignment. normalization ok
  # but not necessary. scaling, no.)
  ppm <- X_raw[1, ] # ppm vector (corresponding to cols of xmat)

  ################ Set up parameters ##################

  # Corr Pocket Pairs

  half.window <- pars$corrpockets$half.window
  # Window for the sliding correlation calculation.
  # This x 2 should capture any 2 adjacent resonances
  # in a multiplet.

  noise.percentile <- pars$corrpockets$noise.percentile
  # noise characterization... For every spectral
  # point, we calculate a correlation peak. If you
  # average all of the resulting peak shapes, 99%
  # of them will be at least n points wide. All of
  # the peaks have a width of at least 3 (one point
  # on either side of the driver, due to the way
  # a peak is defined). What fraction contain 5
  # points? 30 points? This parameter determines the
  # fraction of all spectral corr peaks that noise
  # should fit within, and sets the noise width
  # accordingly. Higher is more permissive.

  cpp.rcutoff <- pars$corrpockets$rcutoff
  # correlation cutoff for picking highest secondary
  # peak in corrpocket pair extraction. Generally
  # ~ 0.75 should do fine.

  # STORM

  only.region.between <- pars$corrpockets$only.region.between
  if (is.null(only.region.between)) # which ppms to run fse between
    {
      only.region.between <- range(ppm)
    } #   (default is all)
  correlation.r.cutoff <- pars$storm$correlation.r.cutoff # rvalue cutoff for both subset selection (ref shape) and ref update (STOCSY)
  q <- pars$storm$q # q param from storm (pval cutoff after mhtc)
  b <- pars$storm$b # number of peak widths to expand ref by on each side

  # Plotting
  number.of.plots <- pars$storm$number.of.plots # pdf of all extracted features will be plotted. Choose
  # only 150 of these (evenly spaced) or suffer the
  # consequences...
  plot.location <- paste0(this.run, "/") # where to put the plot (just dump into run folder)

  plot.filename <- paste0(
    "fse_mtbls1",
    "_np_", noise.percentile,
    "_r_", correlation.r.cutoff,
    "_b_", b, ".pdf"
  ) # what to name the plot file


  ################ Use corrPocketPairs to extract likely j-pairs ##################

  # Run corrpocketPairs on everything

  pocketPairs <- corrPocketPairs_al(xmat, ppm,
    ws = half.window, plotHeatmap = FALSE,
    wdlimit = noise.percentile, # **** **** **** #
    rcutoff = cpp.rcutoff
  )

  # Report number of pairs

  numPairs <- pocketPairs$peakMap %>%
    is.na() %>%
    "!"(.) %>%
    t() %>%
    rowSums(na.rm = TRUE) %>%
    ">"(., 0) %>%
    sum()
  message("Got ", numPairs, " corrpocket pairs from dataset.")
  window.index <- -half.window:half.window

  pdf(
    file = paste0(plot.location, "corrpeak_distribution.pdf"), # The directory you want to save the file in
    width = 4, # The width of the plot in inches
    height = 4
  ) # The height of the plot in inches

  pocketPairs$noiseDist %>% plot(x = window.index, ylab = "Fraction of peaks including index", xlab = "Window index")
  noisewidth <- sum(pocketPairs$noiseDist >= noise.percentile)
  abline(h = noise.percentile, col = "red")
  title(ylab = , main = "Average Extracted Diagonal Peak Shape (pre-filtering)")

  dev.off()
  # here's a thought: if you filter all peaks based on the noise feature shape,
  # the relative prominence of true signal using those boundaries is going to be
  # minimal because signal is locally pretty flat, while noise will mostly be
  # captured within those bounds. Peaks could be classified based on the % of their
  # actual signal (using their actual bounds) captured by the n% cutoff bounds.


  # ####
  ################ Run STORM on these corrpairs ##################

  # Run code
  bounds <- vectInds(only.region.between, ppm)
  testregion <- bounds[2]:bounds[1]

  colwithPair <- pocketPairs$peakMap %>%
    is.na() %>%
    "!"(.) %>%
    t() %>%
    rowSums(na.rm = TRUE) %>%
    ">"(., 0) %>%
    which()
  regions_subset <- colwithPair %in% testregion %>% which()
  storm_rnd1 <- list()
  message("Running storm on ", numPairs, " provided protofeatures. Progress:")

  storm_rnd1 <-
    pblapply(
      regions_subset,
      function(x) {

        # Set up the region
        # x <- regions_subset[950]
        driver <- colwithPair[x]
        peakPos <- pocketPairs$peakMap[, driver] %>%
          is.na() %>%
          "!"(.) %>%
          which()
        pair.region <- pocketPairs$regions[peakPos, driver]


        # Do storm_pairplay

        # Set params
        pw <- length(peakPos) / 2 %>% ceiling()
        wind <- pair.region
        shift <- range(ppm[pair.region])

        # Use original covariance signal within corr bounds as shape seed
        # (could also use best spectrum index)
        shape <- pocketPairs$cov[peakPos, driver]
        bestSpec <- cor(xmat[, wind] %>% t(), shape) %>% which.max()

        # Do the storm

        return(storm_pairplay(xmat, ppm,
          b = (pw * b) %>% ceiling(), corrthresh = correlation.r.cutoff, q = q,
          minpeak = noisewidth, refSpec = shape, ref.idx = pair.region
        ))
      }
    )



  ################ Report run stats  ######

  fmodes <- lapply(
    1:length(storm_rnd1),
    function(x) purrr::pluck(storm_rnd1[x], 1, "status")
  )

  failed <- lapply(
    1:length(storm_rnd1),
    function(x) purrr::pluck(storm_rnd1[x], 1, "status") %in% "succeeded"
  ) %>%
    unlist() %>%
    "!"(.)
  succeeded <- !failed

  message(str_c(
    "Failed iterations (count): ", sum(failed), " (",
    (sum(failed) / length(regions_subset) * 100) %>% round(), " %)"
  ))

  message(str_c(
    "Succeeded iterations (count): ", sum(succeeded), " (",
    (sum(succeeded) / length(regions_subset) * 100) %>% round(), " %)"
  ))

  # Print out breakdown of statuses
  fmodes %>%
    plyr::ldply(rbind) %>%
    count(vars = 1)



  ################ Plotting Results #######################

  # # Plot all the storm results in grid (postage stamp) format
  #

  everyNth <- c(T, rep(
    F,
    max(c(floor(sum(succeeded) / number.of.plots) - 1, 0)) # at least 0 times (no -1 args to rep...)
  ))
  plot_stormRefRegions_grid(xmat, ppm,
    storm_rnd1[succeeded %>%
      which() %>%
      .[everyNth]], # if not doing a small region
    plotLoc = plot.location,
    filename = plot.filename,
    calcStocsy = FALSE, n_xticks = 4
  )
  # ##### Save #####

  fse.result <- list(
    storm_features = storm_rnd1[succeeded],
    xmat = xmat,
    ppm = ppm,
    noisewidth = noisewidth
  )

  message("Saving results...")

  saveRDS(fse.result, paste0(this.run, "/fse.result.RDS"))

  message("\nData written to ", this.run, "/fse.result.RDS")
  message("\nFeature Shape Extraction completed.\n\n\n")
  message("-------------------------------------------------------")
  message("-------------------       FSE       -------------------")
  message("-------------------------------------------------------")
}