% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/utils.R
\name{mvsusie_get_pip_per_condition}
\alias{mvsusie_get_pip_per_condition}
\title{Compute condition specific posterior inclusion probability.}
\usage{
mvsusie_get_pip_per_condition(m, prior_obj)
}
\arguments{
\item{m}{M&M model}

\item{prior_obj}{prior mixture object}
}
\value{
P by R matrix of PIP per condition
}
\description{
This is only relevant when canonical priors are used
}
\keyword{internal}
