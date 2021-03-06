#' @title The regular regression data object
#' @importFrom R6 R6Class
#' @importFrom matrixStats colSds
#' @keywords internal
DenseData <- R6Class("DenseData",
  portable = FALSE,
  public = list(
    initialize = function(X,Y) {
      is_numeric_matrix(X, 'X')
      if (length(which(apply(X, 2, is_zero_variance)))) stop('Input X must not have constant columns (some columns have standard deviation zero)')
      .X <<- X
      .X_has_missing <<- any(is.na(.X))
      # FIXME: might want to allow for missing in X later?
      # see stephenslab/mvsusieR/#5
      if (.X_has_missing)
        stop("Missing data in input matrix X is not allowed at this point.")
      if (is.null(dim(Y))) .Y <<- matrix(Y,length(Y),1)
      else .Y <<- Y
      .Y_missing <<- is.na(.Y)
      .Y_has_missing <<- any(.Y_missing)
      .residual <<- .Y
      .R <<- ncol(.Y)
      .N <<- nrow(.Y)
      .J <<- ncol(.X)
      # quantities involved in center and scaling
      .cm <<- rep(0, length = .J)
      .csd <<- rep(1, length = .J)
      .d <<- colSums(.X ^ 2)
      .d[.d == 0] <<- 1E-6
    },
    set_residual_variance = function(residual_variance=NULL, numeric = FALSE,
                                     precompute_covariances = TRUE,
                                     quantities = c('residual_variance','effect_variance')){
      if('residual_variance' %in% quantities){
        if (is.null(residual_variance)) {
          if (.R > 1) {
            if (!.Y_has_missing) residual_variance = cov(.Y)
            else stop("Unspecified residual_variance is not allowed in the presence of missing data in Y")
          }
          else residual_variance = var(.Y, na.rm=T)
        }
        if(numeric){
          residual_variance = as.numeric(residual_variance)
        }
        if (is.matrix(residual_variance)) {
          if(nrow(residual_variance) != .R){
            stop(paste0("The residual variance is not a ", .R, ' by ', .R, ' matrix.'))
          }
          if (any(is.na(diag(residual_variance))))
            stop("Diagonal of residual_variance cannot be NA")
          residual_variance[which(is.na(residual_variance))] = 0
          mashr:::check_positive_definite(residual_variance)
          .residual_correlation <<- cov2cor(as.matrix(residual_variance))
        }else {
          if (is.na(residual_variance) || is.infinite(residual_variance))
            stop("Invalid residual_variance")
          .residual_correlation <<- 1
        }
        .residual_variance <<- residual_variance
        tryCatch({
          .residual_variance_inv <<- invert_via_chol(residual_variance)$inv
        }, error = function(e) {
          stop(paste0('Cannot compute inverse for residual_variance:\n', e))
        })
      }
      if('effect_variance' %in% quantities){
        if(precompute_covariances){
          .svs <<- lapply(1:.J, function(j){
            res = .residual_variance /.d[j]
            res[which(is.nan(res) | is.infinite(res))] = 1E6
            return(res)
          })
          .svs_inv <<- lapply(1:.J, function(j) .residual_variance_inv * .d[j])
          .is_common_sbhat <<- is_list_common(.svs)
        }else{
          .sbhat <<- sqrt(do.call(rbind, lapply(1:.J, function(j) diag(as.matrix(.residual_variance)) / .d[j])))
          .sbhat[which(is.nan(.sbhat) | is.infinite(.sbhat))] <<- 1E3
          .is_common_sbhat <<- is_mat_common(.sbhat)
        }
      }
    },
    get_coef = function(use_residual = FALSE){
      # XtY J by R matrix
      if (use_residual) XtY = self$XtR
      else XtY = self$XtY
      bhat = XtY / .d # .d length J vector
      bhat[which(is.nan(bhat))] = 0
      return(bhat)
    },
    standardize = function(center, scale) {
      # Credit: This is heavily based on code from
      # https://www.r-bloggers.com/a-faster-scale-function/
      # The only change from that code is its treatment of columns with 0 variance.
      # This "safe" version scales those columns by 1 instead of 0.
      if(center){
        # center X
        .cm <<- colMeans(.X, na.rm=TRUE)
        # center Y
        if (.R == 1) .Y_mean <<- mean(.Y, na.rm=TRUE)
        else .Y_mean <<- colMeans(.Y, na.rm=TRUE)
        .Y <<- t(t(.Y) - .Y_mean)
      }
      if (scale) {
        .csd <<- colSds(.X, center = .cm)
        .csd[.csd==0] <<- 1
      }
      .X <<- t( (t(.X) - .cm) / .csd )
      .d <<- colSums(.X ^ 2)
      .d[.d == 0] <<- 1E-6
    },
    compute_Xb = function(b) {
      # J by R
      # tcrossprod(A,B) performs A%*%t(B) but faster
      tcrossprod(.X,t(b))
    },
    compute_MXt = function(M) {
      # tcrossprod(A,B) performs A%*%t(B) but faster
      tcrossprod(M, .X)
    },
    remove_from_residual = function(value) {
      .residual <<- .residual - value
    },
    add_to_residual = function(value) {
      .residual <<- .residual + value
    },
    compute_residual = function(fitted) {
      .residual <<- .Y - fitted
    },
    rescale_coef = function(b) {
      coefs = b/.csd
      if (is.null(dim(coefs))) {
        if (!is.null(.Y_mean)) intercept = .Y_mean - sum(.cm * coefs)
        else intercept = NA
        c(intercept, coefs)
      } else {
        if (!is.null(.Y_mean)) intercept = .Y_mean - colSums(.cm * coefs)
        else intercept = NA
        mat = as.matrix(rbind(intercept, coefs))
        rownames(mat) = NULL
        return(mat)
      }
    }
  ),
  active = list(
    X = function() .X,
    Y = function() .Y,
    X2_sum = function() .d,
    XtY = function() {
      if (is.null(.XtY)) .XtY <<- crossprod(.X, .Y)
      return(.XtY)
    },
    XtX = function() {
      if (is.null(.XtX)) .XtX <<- crossprod(.X)
      return(.XtX)
    },
    XtR = function() {
      crossprod(.X, .residual)
    },
    residual = function() .residual,
    n_sample = function() .N,
    n_condition = function() .R,
    n_effect = function() .J,
    X_has_missing = function() .X_has_missing,
    Y_has_missing = function() .Y_has_missing,
    residual_variance = function() .residual_variance,
    residual_variance_inv = function() .residual_variance_inv,
    residual_correlation = function() .residual_correlation,
    sbhat = function() .sbhat,
    svs = function() .svs,
    svs_inv = function() .svs_inv,
    is_common_cov = function() .is_common_sbhat
  ),
  private = list(
    .X = NULL,
    .Y = NULL,
    .XtX = NULL,
    .XtY = NULL,
    .d = NULL,
    .N = NULL,
    .J = NULL,
    .R = NULL,
    .residual = NULL,
    .csd = NULL,
    .cm = NULL,
    .Y_mean = NULL,
    .Y_has_missing = FALSE,
    .Y_missing = NULL,
    .X_has_missing = NULL,
    .residual_variance = NULL,
    .residual_variance_inv = NULL,
    .residual_correlation = NULL,
    .sbhat = matrix(0,0,0),
    .svs = 0,
    .svs_inv = 0,
    .is_common_sbhat = FALSE
  )
)

#' @title Regression data object with missing values in Y
#' @importFrom R6 R6Class
#' @importFrom matrixStats colSds
#' @keywords internal
DenseDataYMissing <- R6Class("DenseDataYMissing",
  inherit = DenseData,
  portable = FALSE,
  public = list(
    initialize = function(X,Y,approximate=FALSE) {
      # initialize with super class but postpone center and scaling to later
      super$initialize(X,Y)
      if(!.Y_has_missing) {
        warning("Y does not have any missing values in it. You should consider using DenseData class instead. Here we force set attribute Y_has_missing = TRUE")
        # To force use this class when there is no missing data in Y
        .Y_has_missing <<- TRUE
      }
      .Y_non_missing <<- !.Y_missing
      .approximate <<- approximate
      # store missing pattern
      .missing_pattern <<- unique(.Y_non_missing)
      .Y_missing_pattern_assign <<- numeric(.N)
      for(k in 1:nrow(.missing_pattern)){
        idx = which(apply(.Y_non_missing, 1, function(x) identical(x, .missing_pattern[k,])))
        .Y_missing_pattern_assign[idx] <<- k
      }
      .Y[.Y_missing] <<- 0
      .residual <<- .Y
      .X_for_Y_missing <<- array(.X, dim = c(.N, .J, .R))
      for(r in 1:.R) {
        .X_for_Y_missing[.Y_missing[,r],,r] <<- NA
      }
    },
    set_residual_variance = function(residual_variance=NULL, numeric = FALSE,
                                     quantities = c('residual_variance','effect_variance')){
      if('residual_variance' %in% quantities){
        if (is.null(residual_variance)) {
          if (.R > 1) {
            stop("Unspecified residual_variance is not allowed in the presence of missing data in Y")
          }
          else residual_variance = var(.Y[.Y_non_missing], na.rm=T)
        }
        if (is.matrix(residual_variance)) {
          if (any(is.na(diag(residual_variance))))
            stop("Diagonal of residual_variance cannot be NA")
          residual_variance[which(is.na(residual_variance))] = 0
          mashr:::check_positive_definite(residual_variance)
        }else {
          if (is.na(residual_variance) || is.infinite(residual_variance))
            stop("Invalid residual_variance")
        }
        if(numeric){
          residual_variance = as.numeric(residual_variance)
        }
        .residual_variance <<- residual_variance
        .residual_variance_inv <<- list()
        .residual_variance_eigen <<- list()
        for(k in 1:nrow(.missing_pattern)){
          if(.R == 1){
            .residual_variance_inv[[k]] <<- .missing_pattern[k,] / .residual_variance
            if(sum(.missing_pattern[k,])>0){
              .residual_variance_eigen[[k]] <<- .residual_variance
            }else{
              .residual_variance_eigen[[k]] <<- numeric(0)
            }
          }else{
            .residual_variance_inv[[k]] <<- matrix(0, .R, .R)
            if(sum(.missing_pattern[k,])>0){
              Vk = .residual_variance[which(.missing_pattern[k,]), which(.missing_pattern[k,])]
              eigenVk = eigen(Vk, symmetric = TRUE)
              dinv = 1/(eigenVk$values)
              .residual_variance_eigen[[k]] <<- eigenVk$values
              .residual_variance_inv[[k]][which(.missing_pattern[k,]), which(.missing_pattern[k,])] <<- eigenVk$vectors %*% (dinv * t(eigenVk$vectors))
            }else{
              .residual_variance_eigen[[k]] <<- numeric(0)
            }

          }
        }
        if(is.matrix(residual_variance)){
          .residual_correlation <<- cov2cor(residual_variance)
        }else{
          .residual_correlation <<- 1
        }
      }
      if('effect_variance' %in% quantities){
        .svs_inv <<- list()
        .svs <<- list()
        for(j in 1:.J){
          # R by R matrix
          # when there is no missing, it is sum(x_j^2) * V^{-1}
          if(.approximate){
            .svs_inv[[j]] <<- Reduce('+', lapply(1:.N, function(i) t(.residual_variance_inv[[.Y_missing_pattern_assign[i]]] *
                                                                       .X_for_Y_missing[i,j,]) * .X_for_Y_missing[i,j,]))
            .svs[[j]] <<- tryCatch(invert_via_chol(.svs_inv[[j]])$inv, error = function(e){
              invert_via_chol(.svs_inv[[j]] + 1e-8 * diag(.R))$inv} )
          }else{
            if(.R == 1){
              .svs_inv[[j]] <<- Reduce('+', lapply(1:.N, function(i) ((.X_for_Y_missing[i,j,] - .Xbar[j,,])^2) *
                                                     .residual_variance_inv[[.Y_missing_pattern_assign[i]]]))
            }else{
              A1_list = list()
              A2_list = list()
              for(i in 1:.N){
                A1_list[[i]] = t(.residual_variance_inv[[.Y_missing_pattern_assign[i]]] *
                                   .X_for_Y_missing[i,j,]) * .X_for_Y_missing[i,j,]
                A2_list[[i]] = t(t(.residual_variance_inv[[.Y_missing_pattern_assign[i]]]) * .X_for_Y_missing[i,j,])
              }
              A1 = Reduce('+', A1_list)
              A2 = Reduce('+', A2_list)
              Vinvsum = Reduce('+', lapply(1:nrow(.missing_pattern), function(i) .residual_variance_inv[[i]] * sum(.Y_missing_pattern_assign == i)))
              .svs_inv[[j]] <<- A1 - crossprod(.Xbar[j,,], A2) - crossprod(A2, .Xbar[j,,]) + crossprod(.Xbar[j,,], Vinvsum %*% .Xbar[j,,])
            }
            .svs[[j]] <<- tryCatch(invert_via_chol(.svs_inv[[j]])$inv, error = function(e){
              invert_via_chol(.svs_inv[[j]] + 1e-8 * diag(.R))$inv} )
          }
        }
        .is_common_sbhat <<- is_list_common(.svs)
      }
    },
    get_coef = function(use_residual = FALSE){
      if (use_residual) XtY = self$XtR
      else XtY = self$XtY
      bhat = t(sapply(1:.J, function(j) .svs[[j]] %*% XtY[j,]))
      bhat[which(is.nan(bhat))] = 0
      if(.R == 1){
        bhat = t(bhat)
      }
      return(bhat)
    },
    standardize = function(center, scale) {
      # precompute scale
      if(center){
        cm_x = colMeans(.X_for_Y_missing, na.rm=T) # J by R
      }else{
        cm_x = matrix(0, .J, .R) # J by R
      }
      .csd <<- matrix(1, .J, .R)
      for(r in 1:.R){
        if (scale) {
          .csd[,r] <<- colSds(.X_for_Y_missing[,,r], center = cm_x[,r], na.rm = TRUE)
          .csd[.csd[,r]==0, r] <<- 1
        }
        .X_for_Y_missing[,,r] <<- t( (t(.X_for_Y_missing[,,r]) - cm_x[,r]) / .csd[,r] )
        .X_for_Y_missing[,,r][is.na(.X_for_Y_missing[,,r])] <<- 0
      }

      if(.approximate){
        .cm <<- cm_x
        if(center){
          # center Y
          if (.R == 1) .Y_mean <<- mean(.Y[.Y_non_missing])
          else .Y_mean <<- sapply(1:.R, function(r) mean(.Y[.Y_non_missing[,r],r]))
          .Y <<- t(t(.Y) - .Y_mean)
          .Y[!.Y_non_missing] <<- 0
        }
      }else{ # exact computation
        if(center){
          # sum_i V_i^{-1} R by R matrix
          Vinvsum = Reduce('+', lapply(1:nrow(.missing_pattern), function(i)
                                   .residual_variance_inv[[i]] * sum(.Y_missing_pattern_assign == i)))
          .Vinvsuminv <<- invert_via_chol(Vinvsum)$inv

          # sum_i V_i^{-1} y_i R by 1 matrix
          Ysum = Reduce('+', lapply(1:.N, function(i)
                                   .residual_variance_inv[[.Y_missing_pattern_assign[i]]] %*% .Y[i,] ))

          # center Y
          .Y_mean <<- as.numeric(.Vinvsuminv %*% Ysum)
          .Y <<- t(t(.Y) - .Y_mean)
          .Y[!.Y_non_missing] <<- 0

          # center X
          .Xbar <<- array(0, dim=c(.J, .R, .R))
          for(j in 1:.J){
            # For variant j, Vinvsuminv sum_i V_i^{-1} X_{i,j} R by R matrix
            .Xbar[j,,] <<- .Vinvsuminv %*% Reduce('+', lapply(1:.N, function(i) t(t(.residual_variance_inv[[.Y_missing_pattern_assign[i]]]) * .X_for_Y_missing[i,j,]) ))
          }
        }
      }
    },
    compute_Xb = function(b) {
      if(is.vector(b)){
        b = matrix(b, length(b),1)
      }
      if(.approximate){
        Xb = sapply(1:.R, function(r) .X_for_Y_missing[,,r] %*% b[,r])
      }else{
        Xbarb = Reduce('+', lapply(1:.J, function(j) .Xbar[j,,] %*% b[j,]))
        Xb = sapply(1:.R, function(r) .X_for_Y_missing[,,r] %*% b[,r]) - matrix(Xbarb, .N, .R,byrow = TRUE)
      }
      if(nrow(Xb) != .N) Xb = t(Xb)
      return(Xb)
    },
    rescale_coef = function(b){
      if(.R == 1){
        .csd <<- as.vector(.csd)
        .cm <<- as.vector(.cm)
      }
      coefs = b/.csd
      if(.approximate){
        if (is.null(dim(coefs))) {
          if (!is.null(.Y_mean)){
            intercept = .Y_mean - sum(.cm * coefs)}
          else intercept = 0
          c(intercept, coefs)
        } else {
          if (!is.null(.Y_mean)) intercept = .Y_mean - colSums(.cm * coefs)
          else intercept = 0
          mat = as.matrix(rbind(intercept, coefs))
          rownames(mat) = NULL
          return(mat)
        }
      }else{
        # Length R
        # sum_i V_i^{-1} b^T X[i,]
        D = Reduce('+', lapply(1:.N, function(i) .residual_variance_inv[[.Y_missing_pattern_assign[i]]] %*% crossprod(coefs, .X[i,])))
        if (!is.null(.Y_mean)) intercept = .Y_mean - .Vinvsuminv %*% D
        else intercept = 0
        if(is.null(dim(coefs))){
          c(intercept, coefs)
        }else{
          mat = as.matrix(rbind(t(intercept), coefs))
          rownames(mat) = NULL
          return(mat)
        }
      }
    }
  ),
  active = list(
    XtY = function() {
      # J by R matrix
      if (is.null(.XtY)){
        # V_i^(-1) y_i = z_i
        VinvY = t(sapply(1:.N, function(i) .residual_variance_inv[[.Y_missing_pattern_assign[i]]] %*% .Y[i,])) # N by R
        if(.R == 1) VinvY = t(VinvY)
        if(.approximate){
          .XtY <<- t(sapply(1:.J, function(j) colSums(.X_for_Y_missing[,j,] * VinvY) ))
        }else{
          # sum_{i=1}^N (diag(X_for_Y_missing[i,j,]) - Xbar[j,,])^T z_i
          VinvYcolsum = colSums(VinvY)
          .XtY <<- t(sapply(1:.J, function(j) colSums(.X_for_Y_missing[,j,] * VinvY) - crossprod(.Xbar[j,,], VinvYcolsum) ))
        }
      }
      if (.R == 1) .XtY <<- t(.XtY)
      return(.XtY)
    },
    XtX = function() {
      # FIXME: not sure how to compute XtX with missing data
      if (is.null(.XtX)) .XtX <<- cor(.X)
      return(.XtX)
    },
    XtR = function() {
      # V_i^(-1) r_i = z_i
      VinvR = t(sapply(1:.N, function(i) .residual_variance_inv[[.Y_missing_pattern_assign[i]]] %*% .residual[i,])) # N by R
      if(.R == 1) VinvR = t(VinvR)
      if(.approximate){
        res = t(sapply(1:.J, function(j) colSums(.X_for_Y_missing[,j,] * VinvR) ))
      }else{
        # sum_{i=1}^N (diag(X_for_Y_missing[i,j,]) - Xbar[j,,])^T z_i
        res = t(sapply(1:.J, function(j) colSums(.X_for_Y_missing[,j,] * VinvR) - crossprod(.Xbar[j,,], colSums(VinvR)) ))
      }
      if(nrow(res) != .J) res = t(res)
      return(res)
    },
    Y_missing_pattern_assign = function() .Y_missing_pattern_assign,
    residual_variance_eigenvalues = function() .residual_variance_eigen
  ),
  private = list(
    .X_for_Y_missing = NULL,
    .Y_non_missing = NULL,
    .missing_pattern = NULL,
    .Y_missing_pattern_assign = NULL,
    .Vinvsuminv = NULL,
    .approximate = FALSE,
    .Xbar = NULL,
    .residual_variance_eigen = NULL
  )
)

#' @title Summary statistics object
# Z and R
#' @importFrom R6 R6Class
#' @keywords internal
RSSData <- R6Class("RSSData",
  inherit = DenseData,
  portable = FALSE,
  public = list(
    initialize = function(Z, R=NULL, eigenR=NULL, tol) {
      if(any(is.infinite(Z))){
        stop('Z scores contain infinite value.')
      }
      if (is.null(dim(Z))) {
        Z = matrix(Z, length(Z), 1)
      }
      if(is.null(R) & is.null(eigenR)){
        stop('At least one of R and eigen-decomposition of R should be provided.')
      }
      if(!is.null(eigenR)){
        if(any(names(eigenR) != c("values", "vectors"))){
          stop('eigen-decomposition of R must contains 2 elements with the following names: values, vectors')
        }
        if(nrow(eigenR$vectors) != nrow(Z)){
          stop('The dimension of eigenvectors of R does not agree with expected.')
        }
        .eigenR <<- eigenR
      }
      if(!is.null(R)){
        is_numeric_matrix(R, "R")
        # Check input R.
        if (!susieR:::is_symmetric_matrix(R)) {
          stop('R is not a symmetric matrix.')
        }
        if (nrow(R) != nrow(Z)) {
          stop(paste0('The dimension of correlation matrix (',nrow(R),' by ',ncol(R),
                      ') does not agree with expected (',nrow(Z),' by ',nrow(Z),')'))
        }
        .XtX <<- R
      }

      # replace NA in z with 0
      if (any(is.na(Z))) {
        warning('NA values in Z-scores are replaced with 0.')
        Z[is.na(Z)] = 0
      }
      .J <<- nrow(Z)
      .R <<- ncol(Z)
      private$check_semi_pd(tol)
      .X <<- t(.eigenvectors[, .eigenvalues !=0]) * .eigenvalues[.eigenvalues != 0] ^ (0.5)
      .Y <<- (t(.eigenvectors[, .eigenvalues != 0]) * .eigenvalues[.eigenvalues != 0] ^ (-0.5)) %*% Z
      .Y_has_missing <<- FALSE
      .X_has_missing <<- FALSE
      .XtY <<- .UUt %*% Z # = Z when Z is in eigen space of R
      .residual <<- .Y
    }
  ),
  active = list(
    # n_sample doesn't mean sample size here, it means the number of non zero eigenvalues
    n_sample = function() sum(.eigenvalues > 0)
  ),
  private = list(
    .UUt = NULL,
    .eigenR = NULL,
    .eigenvectors = NULL,
    .eigenvalues = NULL,
    check_semi_pd = function(tol) {
      if(is.null(private$.eigenR)){
        private$.eigenR <<- eigen(.XtX, symmetric = TRUE)
      }
      private$.eigenR$values[abs(.eigenR$values) < tol] = 0

      if (any(private$.eigenR$values < 0)) {
        private$.eigenR$values[private$.eigenR$values < 0] = 0
        warning('Negative eigenvalues are set to 0.')
      }

      .XtX <<- private$.eigenR$vectors %*% (t(private$.eigenR$vectors) * private$.eigenR$values)
      .csd <<- rep(1, length = .J)
      .d <<- diag(.XtX)
      private$.eigenvectors <<- private$.eigenR$vectors
      private$.eigenvalues <<- private$.eigenR$values
      private$.UUt <<- tcrossprod(private$.eigenvectors[, which(private$.eigenvalues > 0)])
    }
  )
)

#' @title Sufficient statistics object
# XtX, XtY, YtY, N
#' @importFrom R6 R6Class
#' @keywords internal
SSData <- R6Class("SSData", inherit = DenseData,
  portable = FALSE,
  public = list(
    initialize = function(XtX, XtY, YtY, N, X_colmeans, Y_colmeans) {
      if (is.null(dim(XtY))) .XtY <<- matrix(XtY,length(XtY),1)
      else .XtY <<- XtY
      if (ncol(XtX) != nrow(.XtY))
        stop(paste0("The dimension of XtX (",nrow(XtX)," by ",ncol(XtX),
                    ") does not agree with expected (",nrow(.XtY)," by ",
                    nrow(.XtY),")"))
      if (!susieR:::is_symmetric_matrix(XtX))
        stop("XtX is not a symmetric matrix")
      if (any(is.infinite(.XtY)))
        stop("XtY contains infinite values")
      is_numeric_matrix(XtX, 'XtX')
      
      .XtX <<- XtX
      .YtY <<- YtY
      .Y_has_missing <<- FALSE
      .Xtresidual <<- .XtY
      .R <<- ncol(.XtY)
      .N <<- N
      .J <<- ncol(.XtX)
      # quantities involved in center and scaling
      .cm <<- rep(0, length = .J)
      .csd <<- rep(1, length = .J)
      .d <<- diag(.XtX)
      .d[.d == 0] <<- 1E-6
      
      if(all(!is.null(X_colmeans), !is.null(Y_colmeans))){
        if(length(X_colmeans) == 1 && X_colmeans == 0){
          X_colmeans = numeric(.J)
        }
        if(length(Y_colmeans) == 1 && Y_colmeans == 0){
          y_colmeans = numeric(.R)
        }
        if(length(X_colmeans) != .J){
          stop('The length of X_colmeans does not agree with number of variables.')
        }
        if(length(Y_colmeans) != .R){
          stop('The length of Y_colmeans does not agree with number of conditions.')
        }
      }
      .cm <<- X_colmeans
      .Y_mean <<- Y_colmeans
    },
    set_residual_variance = function(residual_variance=NULL, numeric = FALSE,
                                     precompute_covariances = TRUE,
                                     quantities = c('residual_variance','effect_variance')){
      if('residual_variance' %in% quantities){
        if (is.null(residual_variance)) {
          if (.R > 1) {
            residual_variance = cov2cor(.YtY)
          }
          else residual_variance = .YtY/(.N-1)
        }
        if(numeric){
          residual_variance = as.numeric(residual_variance)
        }
        if (is.matrix(residual_variance)) {
          if(nrow(residual_variance) != .R){
            stop(paste0("The residual variance is not a ", .R, ' by ', .R, ' matrix.'))
          }
          if (any(is.na(diag(residual_variance))))
            stop("Diagonal of residual_variance cannot be NA")
          residual_variance[which(is.na(residual_variance))] = 0
          mashr:::check_positive_definite(residual_variance)
          .residual_correlation <<- cov2cor(as.matrix(residual_variance))
        }else {
          if (is.na(residual_variance) || is.infinite(residual_variance))
            stop("Invalid residual_variance")
          .residual_correlation <<- 1
        }
        .residual_variance <<- residual_variance
        tryCatch({
          .residual_variance_inv <<- invert_via_chol(residual_variance)$inv
        }, error = function(e) {
          stop(paste0('Cannot compute inverse for residual_variance:\n', e))
        })
      }
      if('effect_variance' %in% quantities){
        if(precompute_covariances){
          .svs <<- lapply(1:.J, function(j){
            res = .residual_variance /.d[j]
            res[which(is.nan(res) | is.infinite(res))] = 1E6
            return(res)
          })
          .svs_inv <<- lapply(1:.J, function(j) .residual_variance_inv * .d[j])
          .is_common_sbhat <<- is_list_common(.svs)
        }else{
          .sbhat <<- sqrt(do.call(rbind, lapply(1:.J, function(j) diag(as.matrix(.residual_variance)) / .d[j])))
          .sbhat[which(is.nan(.sbhat) | is.infinite(.sbhat))] <<- 1E3
          .is_common_sbhat <<- is_mat_common(.sbhat)
        }
      }
    },
    standardize = function(scale) {
      if (scale) {
        dXtX = diag(.XtX)
        .csd <<- sqrt(dXtX/(.N-1))
        .csd[.csd == 0] <<- 1
        .XtX <<- (1/.csd) * t((1/.csd) * XtX)
        .XtY <<- (1/.csd) * XtY
        .d <<- diag(.XtX)
        .d[.d == 0] <<- 1E-6
      }
    },
    compute_Xb = function(b) {
      # J by R
      # tcrossprod(A,B) performs A%*%t(B) but faster
      tcrossprod(.XtX,t(b))
    },
    compute_MXt = function(M) {
      # tcrossprod(A,B) performs A%*%t(B) but faster
      tcrossprod(M, .XtX)
    },
    remove_from_residual = function(value) {
      .Xtresidual <<- .Xtresidual - value
    },
    add_to_residual = function(value) {
      .Xtresidual <<- .Xtresidual + value
    },
    compute_residual = function(fitted) {
      .Xtresidual <<- .XtY - fitted
    },
    rescale_coef = function(b) {
      coefs = b/.csd
      
      if (is.null(dim(coefs))) {
        if(any(is.null(.cm), is.null(.Y_mean))){
          intercept = NA
        }else{
          intercept = .Y_mean - sum(.cm * coefs)
        }
        c(intercept, coefs)
      } else {
        if(any(is.null(.cm), is.null(.Y_mean))){
          intercept = NA
        }else{
          intercept = .Y_mean - colSums(.cm * coefs)
        }
        mat = as.matrix(rbind(intercept, coefs))
        rownames(mat) = NULL
        return(mat)
      }
    }),
  active = list(
    YtY = function() .YtY,
    XtX = function() .XtX,
    XtY = function() .XtY,
    XtR = function() .Xtresidual,
    residual = function() .Xtresidual
    )
)


