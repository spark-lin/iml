#' Feature importance
#' 
#' @description 
#' feature.imp() computes feature importances for machine learning models. 
#' The importance of a feature is the factor by which the model's prediction error increases when the feature is shuffled. 
#' 
#' @details
#' Read the Interpretable Machine Learning book to learn more about feature importance: 
#' \url{https://christophm.github.io/interpretable-ml-book/permutation-feature-importance.html}
#' 
#' Two permutation schemes are implemented: 
#' \itemize{
#' \item shuffle: A simple shuffling of the feature values, yielding n perturbed instances per feature (faster)
#' \item cartesian: Matching every instance with the feature value of all other instances, yielding n x (n-1) perturbed instances per feature (slow)
#' }
#' The loss function can be either specified via a string, or by handing a function to \code{feature.imp()}.
#' Using the string is a shortcut to using loss functions from the \code{Metrics} package. 
#' See \code{library(help = "Metrics")} to get a list of functions. 
#' Only use functions that return a single performance value, not a vector. 
#' You can also provide a function directly. It has to take the actual value as its first argument and the prediction as its second. 
#' 
#' 
#' @param loss The loss function. A string (e.g. "ce" for classification or "mse") or a function. See Details.
#' @param method Either 'shuffle' or 'cartesian'. See Details. 
#' @param y The vector or data.frame with the actual target values associated with X.
#' @return 
#' An Importance object (R6). Its methods and variables can be accessed with the \code{$}-operator:
#' \item{error.original}{The loss of the model before perturbing features.}
#' \item{loss}{The loss function. Can also be applied to data: \code{object$loss(actual, predicted)}}
#' \item{data()}{method to extract the results of the feature importance computation.
#' Returns a data.frame with importance and permutation error measurements per feature.}
#' \item{plot()}{method to plot the feature importances. See \link{plot.Importance}}
#' @template args_internal_methods
#' 
#' @references 
#' Fisher, A., Rudin, C., and Dominici, F. (2018). Model Class Reliance: Variable Importance Measures for any Machine Learning Model Class, from the "Rashomon" Perspective. Retrieved from http://arxiv.org/abs/1801.01489
#' @export
#' @import Metrics
#' @template args_experiment_wrap
#' @examples
#' # We train a tree on the Boston dataset:
#' if(require("rpart")){
#' data("Boston", package  = "MASS")
#' mod = rpart(medv ~ ., data = Boston)
#' 
#' # Compute the individual conditional expectations for the first feature
#' X = Boston[-which(names(Boston) == 'medv')]
#' y = Boston$medv
#' 
#' # Compute feature importances as the performance drop in mean absolute error
#' imp = feature.imp(mod, X, y, loss = 'mae')
#' 
#' # Plot the results directly
#' plot(imp)
#' 
#' 
#' # Since the result is a ggplot object, you can extend it: 
#' library("ggplot2")
#' plot(imp) + theme_bw()
#' 
#' # If you want to do your own thing, just extract the data: 
#' imp.dat = imp$data()
#' head(imp.dat)
#' ggplot(imp.dat, aes(x = ..feature, y = importance)) + geom_point() + 
#' theme_bw()
#' 
#' # feature.imp() also works with multiclass classification. 
#' # In this case, the importance measurement regards all classes
#' mod = rpart(Species ~ ., data= iris)
#' X = iris[-which(names(iris) == 'Species')]
#' y = iris$Species
#' # For some models we have to specify additional arguments for the predict function
#' imp = feature.imp(mod, X, y, loss = 'ce', predict.args = list(type = 'prob'))
#' plot(imp)
#' # Here we encounter the special case that the machine learning model perfectly predicts
#' # The importance becomes infinite
#' imp$data()
#' 
#' # For multiclass classification models, you can choose to only compute performance for one class. 
#' # Make sure to adapt y
#' imp = feature.imp(mod, X, y == 'virginica', class = 3, loss = 'ce', 
#'     predict.args = list(type = 'prob'))
#' plot(imp)
#' }
feature.imp = function(object, X, y, class=NULL, loss, method = 'shuffle', ...){
  assert_vector(y, any.missing = FALSE)
  
  samp = DataSampler$new(X, y = data.frame(y = y))
  pred = prediction.model(object, class = class,...)
  
  Importance$new(predictor = pred, sampler = samp, loss=loss, method=method)$run()
}


#' Feature importance plot
#' 
#' plot.Importance() plots the feature importance results of an Importance object.
#' 
#' For examples see \link{feature.imp}
#' @param x The feature importance. An Importance R6 object
#' @param sort logical. Should the features be sorted in descending order? Defaults to TRUE.
#' @param ... Further arguments for the objects plot function
#' @return ggplot2 plot object
#' @export
#' @importFrom dplyr group_by_
#' @seealso 
#' \link{feature.imp}
plot.Importance = function(x, sort = TRUE, ...){
  x$plot(sort = sort, ...)
}


Importance = R6::R6Class('Importance', 
  inherit = Experiment,
  public = list(
    loss = NULL,
    error.original = NULL,
    initialize = function(predictor, sampler, loss, method){
      if(!inherits(loss, 'function')){
        ## Only allow metrics from Metrics package
        private$loss.string  = loss
        loss = getFromNamespace(loss, "Metrics")
      } else {
        private$loss.string = head(loss)
      }
      checkmate::assert_choice(method, c('shuffle', 'cartesian'))
      super$initialize(predictor = predictor, sampler = sampler)
      self$loss = private$set.loss(loss)
      private$method = method
      private$get.data = private$sampler$get.xy
      self$error.original = loss(private$sampler$y[[1]], private$Q(private$predict(private$sampler$X))[[1]])
    }
  ),
  private = list(
    method = NULL,
    # for printing
    loss.string = NULL,
    shuffle.feature = function(feature.name, method){
      if(method == 'shuffle'){
        X.inter = private$X.sample
        X.inter[feature.name] = X.inter[sample(1:nrow(private$X.sample)), feature.name]
      } else if(method == 'cartesian'){
        n = nrow(private$X.sample)
        row.indices = rep(1:n, times = n)
        replace.indices = rep(1:n, each = n)
        # Indices of instances to keep. Removes those where instance matched with own value
        keep.indices = as.logical(as.vector(1 - diag(n)))
        X.inter = private$X.sample[row.indices, ]
        X.inter[feature.name] = X.inter[replace.indices, feature.name]
        X.inter = X.inter[keep.indices,]
      } else {
        stop(sprintf('%s method not implemented'))
      }
      X.inter$..feature = feature.name
      X.inter 
    },
    Q = function(pred) probs.to.labels(pred),
    intervene = function(){
      X.inter.list = lapply(private$sampler$feature.names, function(i) private$shuffle.feature(i, method = private$method))
      data.frame(data.table::rbindlist(X.inter.list))
    },
    aggregate = function(){
      y = private$X.design[private$sampler$y.names]
      y.hat = private$Q.results
      # For classification we work with the class labels instead of probs
      result = data.frame(..feature = private$X.design$..feature, ..actual = y[[1]], ..predicted = y.hat[[1]])
      
      result.grouped  = group_by_(result, "..feature")
      result = summarise(result.grouped, error = self$loss(..actual, ..predicted), 
        importance = error / self$error.original)
      result = result[order(result$importance, decreasing = TRUE),]
      result
    },
    generate.plot = function(sort = TRUE, ...){
      res = private$results
      if(sort){
        res$..feature = factor(res$..feature, levels = res$..feature[order(res$importance)])
      }
      ggplot(res, aes(y = ..feature, x = importance)) + geom_point()+ 
        geom_segment(aes(y = ..feature, yend = ..feature, x=1, xend = importance)) + 
        scale_x_continuous("Feature Importance") + 
        scale_y_discrete("Feature")
    }, 
    set.loss = function(loss){
      self$loss = loss
    }, 
    print.parameters = function(){
      cat('error function:', private$loss.string)
    }
  )
)









