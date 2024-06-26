#' @name cpt
#' @export cpt
#' @importFrom stats terms
#' 
#' @title Compute a conditional probability table for a factor given other factors
#' @description The function \code{cpt} operates on sets of factors. Specifically,
#'   it computes the conditional probability distribution of one of the factors
#'   given other factors, and stores the result in a multidimensional \code{array}. 
#'   
#'   \code{inputCPT()} is a utility function aimed at facilitating the process of
#'   populating small conditional probability distributions, i.e., those for which
#'   the response variable doesn't have too many levels, there are relatively few
#'   independent variables, and the independent variables also don't have too many
#'   levels. 
#'   
#' @param x a list containing the names of the variables used to compute 
#'   the conditional probability table. See details.
#' @param formula a formula specifying the relationship between the dependent and
#'   independent variables.
#' @param data a data frame containing all the factors represented by the \code{formula}
#'   parameter.
#' @param wt (optional) a numeric vector of observation weights.
#' @param factorLevels (optional) a named list with the following structure: 
#'   Variable names for the factors specified in \code{vars} comprise the names
#'   of the list elements, and each list element is a character vector containing
#'   the levels of the respective factor. See examples.
#' @param reduce set to \code{TRUE} if \code{inputCPT()} is to compute probabilities
#'   for the first level of the dependent variable as the complement of the 
#'   inputted probabilities corresponding to the other levels of the dependent
#'   variable. For example, \code{reduce = TRUE} with a binary dependent variable
#'   \code{y} (say, with levels \code{'no'} and \code{'yes'}) will ask for the
#'   probabilities of \code{'yes'} at each combination of the independent variables,
#'   and compute the probability of \code{'no'} as their respective complements.
#'   See details.
#' @param ... Additional arguments to be passed to other methods.
#' 
#' @details If a \code{formula} object is entered for the \code{vars} parameter, the
#'   formula must have the following structure: \emph{response ~ var1 + var2 + etc.}.
#'   The other option is to pass a named \code{list} containing two elements \code{y}
#'   and \code{x}. Element \code{y} is a character string containing the name of the 
#'   factor variable in \code{data} to be used as the dependent variable, and 
#'   element \code{x} is a character vector containing the name(s) of the factor
#'   variable(s) to be used as independent (or conditioning) variables.
#'   
#'   In \code{inputCPT()}, when the parameter \code{reduce} is set to \code{FALSE},
#'   any non-negative number (e.g., cell counts) is accepted as input. Conditional
#'   probabilities are then calculated via a normalization procedure. However, when
#'   \code{reduce} is set to \code{TRUE}, a) only probabilities in [0,1] are accepted
#'   and b) all inputted probabilities for each specific combination of independent
#'   variable values must not sum to a value greater than 1 (or the calculated 
#'   probability for the first level of the dependent variable would be negative).
#'   
#'   The \code{cpt()} function with a weight vector passed to parameter \code{wt}
#'   works analogously to \code{inputCPT(reduce = FALSE)}, i.e., it accepts any
#'   non-negative vector, and computes the conditional probability array by 
#'   normalizing sums of weights.
#'   
#' @author Jarrod Dalton and Benjamin Nutter
#' 
#' @examples
#' # a very imbalanced dice example
#' 
#' n <- 50000
#' data <- data.frame(
#'   di1 = as.factor(1:6 %*% rmultinom(n,1,prob=c(.4,.3,.15,.10,.03,.02))),
#'   di2 = as.factor(1:6 %*% rmultinom(n,1,prob=rev(c(.4,.3,.15,.10,.03,.02)))),
#'   di3 = as.factor(1:6 %*% rmultinom(n,1,prob=c(.15,.10,.02,.3,.4,.03)))
#' )
#' 
#' cpt1 <- cpt(di3 ~ di1 + di2, data)
#' cpt1[di1 = 1, di2 = 4, ]  # Pr(di3 | di1 = 1, di2 = 4)
#' cpt1["1","4",]
#' cpt1[1,4,]
#' 
#' plyr::aaply(cpt1, c(1,2), sum) # card(di1)*card(di2) matrix of ones
#' 
#' l <- list(y = "di3", x = c("di1","di2"))
#' all(cpt(l, data) == cpt1)
#' 
#' \dontrun{
#' inputCPT(wetGrass ~ rain + morning) 
#' 
#' inputCPT(wetGrass ~ rain + morning,
#'          factorLevels <- list(wetGrass = c("dry","moist","VeryWet"),
#'                               rain     = c("nope","yep"),
#'                               morning  = c("NO","YES")),
#'          reduce = FALSE)
#' }
#' 
cpt <- function(x, data, wt, ...)
{
  UseMethod("cpt")
}

#' @rdname cpt
#' @export
cpt.formula <- function(formula, data, wt, ...)
{
  variables       <- as.character(attr(stats::terms(formula), "variables"))[-1]
  dependentVar    <- variables[1]
  independentVars <- variables[-1]
  cpt_workhorse(variables = variables, 
                dependentVar = dependentVar, 
                independentVars = independentVars, 
                data = data, 
                wt = wt, ...)
}

#' @rdname cpt
#' @export 
cpt.list <- function(x, data, wt, ...)
{
  coll <- checkmate::makeAssertCollection()

  checkmate::assertSubset(names(x), c("x", "y"),
                          add = coll)
  
  checkmate::assertCharacter(x[["x"]],
                             add = coll)
  checkmate::assertCharacter(x[["y"]],
                             len = 1,
                             add = coll)

  checkmate::reportAssertions(coll)

  variables       <- c(x[["y"]], x[["x"]])
  dependentVar    <- x[["y"]]
  independentVars <- x[["x"]]
  
  cpt_workhorse(variables = variables, 
                dependentVar = dependentVar, 
                independentVars = independentVars, 
                data = data, 
                wt = wt, ...)
}

#******** UNEXPORTED FUNCTION
cpt_workhorse <- function(variables, dependentVar, independentVars,
                          data, wt, na.rm=FALSE, ...)
{
  wt_text <- 
    if (missing(wt))
    {
      NULL
    }
    else if (is.character(wt))
    {
      wt 
    }
    else 
    {
      NULL
    }
  
  err.flag <- 0
  err.msg <- ""
  
  wrn.flag <- 0
  wrn.msg <- ""
  
  coll <- checkmate::makeAssertCollection()

  checkmate::assertDataFrame(data)
  
  checkmate::assertSubset(variables, 
                          choices = names(data))
  
  lapply(data[variables],
         checkmate::assertFactor,
         add = coll)
  
  vars  <- c(dependentVar, independentVars)  
  
  #check for NAs, remove if the user wants
  completeData <- data[stats::complete.cases(data), ]
  if((nrow(data) != nrow(completeData)) * !na.rm){
    coll$push("Missing values in the supplied variable(s). See help('cpt')")
  }
  checkmate::reportAssertions(coll)
  
  data <- completeData
  n <- nrow(data)

  if(missing(wt)) 
  {
    wt <- rep(1,n) 
  }
  else 
  {
    if(is.character(wt))
    {
      if(length(wt)>1)
      {
        warning("Character vector of length >1 given for 'wt'. ",
                "Using only the first element.")
        wt <- wt[1]
        wt_text <- wt_text[1]
      }
      
      if(wt %in% names(data))
      {
        wt <- data[,wt]
      } 
      else
      {
        coll$push("'wt' must be a numeric vector or the name of a variable in 'data'")
      }
    }
    
    if(!is.numeric(wt))
    {
      coll$push("'wt' must be a numeric vector or the name of a variable in 'data'")
    } 
    else if(length(wt) != n)
    {
      coll$push("Length of 'wt' not equal to number of rows in 'data'")
    } 
    else if(min(wt) < 0)
    {
      coll$push("Negative values in parameter 'wt' not allowed")
    }
  }
  
  checkmate::reportAssertions(coll)
  
  ..vars <- lapply(X = vars, 
                   FUN = as.symbol)
  ..independentVars <- lapply(X = independentVars, 
                              FUN = as.symbol)
  
  # data     <- dplyr::bind_cols(dplyr::tbl_df(data[,vars]),
  #                              dplyr::tbl_df(data.frame(wt = wt)))
  data <- cbind(data[, vars], 
                data.frame(wt = wt, 
                           stringsAsFactors = FALSE))
  
  
  joint <- 
    data %>% 
    dplyr::group_by(.dots = ..vars) %>%  
    dplyr::summarise(wt = ~sum(wt))
 
  marginal <- 
    joint %>% 
    dplyr::group_by(.dots = ..independentVars) %>% 
    dplyr::summarise(sumWt = ~sum(wt))
  
  cpt <- 
    dplyr::left_join(joint, marginal, 
                     by = independentVars) %>%
    dplyr::mutate(p = ~ wt / sumWt) %>% 
    dplyr::select(~-c(wt, sumWt)) %>%
    plyr::daply(c(vars[-1], vars[1]), 
                function(x) x$p)
  
  cpt[is.na(cpt)] <- 0

  model <- data[c(names(dimnames(cpt)), "wt")]
  
  if ("wt" %in% names(model) && !is.null(wt_text)) 
  {
    names(model)[length(model)] <- wt_text
  }
  
  if (is.null(wt_text))
  {
    model <- cbind(model, wt)
  }

  attr(cpt, "model") <- model
  
  class(cpt) <- c("cpt", "array")
  return(cpt)
}
