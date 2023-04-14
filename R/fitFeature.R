#' Fit a feature to a spectrum
#'
#' This function fits a feature to a spectrum using either least squares fitting or minmax scaling.
#'
#' @param feature A numeric vector containing the feature to fit to the spectrum
#' @param spectrum A numeric vector containing the spectrum to fit the feature to
#' @param spectrum.position A numeric value specifying the position of the spectrum
#' @param method A character string specifying the method to use for fitting. Can be "least squares" or "minmax scaling".
#'
#' @return A list containing the feature fit, the feature position, the ratio, the residuals, and the overfit
#'
#'  @export
fitFeature <- function(feature, spectrum, spectrum.position,
                       method = "minmax scaling") {

  # Handle difficult cases
  if (all(is.na(c(feature)) | is.na(c(spectrum)))) {
    return(list(
      feature.fit = NA,
      feature.pos = spectrum.position,
      ratio = NA,
      residuals = NA,
      overfit = NA
    ))
  }

  # least squares fitting
  if (method == "least squares") {
    res <- fit.leastSquares(feature, spectrum)
    feature.fit <- res$feature.fit
    ratio <- res$ratio
  }

  # minmax
  if (method == "minmax scaling") {
    res <- fit.minmax(feature, spectrum)
    feature.fit <- res$feature.fit
    ratio <- res$ratio
  }

  # Residual where feature and spectrum exists

  residuals <- spectrum - feature.fit
  overfit <- -sum(residuals[residuals < 0], na.rm = TRUE)

  # View all

  return(list(
    feature.fit = feature.fit,
    feature.pos = spectrum.position,
    ratio = ratio,
    residuals = residuals,
    overfit = overfit
  ))
}

#' Fit a feature to a spectrum using minmax scaling
#'
#'
#' @param feature a numeric vector representing the feature to be fit
#' @param spectrum a numeric vector representing the spectrum to which the feature will be fit
#'
#' @return a list with the following components:
#' \describe{
#'   \item{feature.fit}{a numeric vector representing the feature fit}
#'   \item{ratio}{a ratio of the original feature intensity to the intensity of the feature after minmax scaling}
#' }
#'
#'
#' @export
fit.minmax <- function(feature, spectrum) {
  # Do minmax scaling where there's overlap
  # If there is no non-NA overlap, quit:

  feature.fit <- scale.to.minmax(feature, spectrum) %>% c()
  ratio <- sum(feature, na.rm = TRUE) / sum(feature.fit, na.rm = TRUE)

  return(list(
    feature.fit = feature.fit,
    ratio = ratio
  ))
}