
maxlik.fd.scoring <- function(m, step = NULL, 
  information = c("expected", "observed", "mix"),
  ls = list(type = "optimize", tol = .Machine$double.eps^0.25, cap = 1),
  barrier = list(type = c("1", "2"), mu = 0), 
  control = list(maxit = 100, tol = 0.001, trace = FALSE, silent = FALSE), 
  debug = FALSE)
{
  if (!is.null(step) && (step <= 0 || !is.numeric(step)))
    stop("'step' must be a numeric positive value.")

  mcall <- match.call()

  mfcn.step <- function(x, m, pd, barrier)
  {
    m <- set.pars(m, get.pars(m) + x * pd)

    mloglik.fd(x = NULL, model = m, barrier = barrier) 
  }

  mgr.step <- function(x, m, pd, barrier)
  {
    m@pars <- m@pars + x * pd

    gr <- mloglik.fd.deriv(m, gradient = TRUE,
      hessian = FALSE, infomat = FALSE, modcovgrad = FALSE,
      barrier = barrier, version = "2")$gradient
    gr <- drop(gr %*% pd)
    gr
  }

  cargs <- list(maxit = 100, tol = 0.001, trace = FALSE, silent = TRUE)
  ncargs0 <- names(cargs)
  cargs[ncargs <- names(control)] <- control
  if (length(nocargs <- ncargs[!ncargs %in% ncargs0]))
    warning("unknown names in 'control': ", paste(nocargs, collapse = ", "))
  control <- cargs

  info <- match.arg(information)[1]
  use.gcov <- info == "expected"
  use.hess <- info == "observed"
  use.mix <- info == "mix"

  lsres <- list(ls.iter = NULL, ls.counts = c("fcn" = 0, "grd" = 0))
  lsintv <- c(0, ls$cap)

  pars0 <- m@pars
  convergence <- FALSE
  iter <- 0

  # periodogram

  if (is.null(m@ssd)) {
    pg <- Mod(fft(m@diffy))^2 / (2 * pi * length(m@diffy))
    #pi2.pg <- pi2 * pg
  } else
    pg <- m@ssd

  # spectral generating function (constants)

  # iterative process

  Mpars <- if (control$trace) rbind(c(m@cpar, m@pars), 
    matrix(nrow = control$maxit + 1, ncol = length(m@pars) + length(m@cpar))) else NULL
  steps <- if (control$trace) rep(NA, control$maxit + 2) else NULL

if (debug)
{
  val <- logLik(object = m, domain = "frequency", barrier = barrier)
  cat(paste("\niter =", iter, "logLik =", round(val, 4), "\n"))
  print(get.pars(m))
}

  while (!(convergence || iter > control$maxit))
  {
    tmp <- mloglik.fd.deriv(m, gradient = TRUE, 
      hessian = use.hess, infomat = use.gcov, modcovgrad = use.mix,
      barrier = barrier, version = "2")

    # gradient

    G <- -tmp$gradient

    # information matrix

    M <- switch(info, "expected" = tmp$infomat, 
      "observed" = tmp$hessian, "mix" = tmp$modcovgrad)

    if (info == "observed" || info == "mix")
    {
      M <- force.defpos(M, 0.001, FALSE)
    }

    # direction vector

    pd <- drop(solve(M) %*% G)

    # step size (choose the step that maximizes the increase in 
    # the log-likelihood function given the direction vector 'pd')

    if (is.null(step))
    {
      lsintv[2] <- step.maxsize(m@pars, m@lower, m@upper, pd, ls$cap)

      lsout <- switch(ls$type,

      "optimize" = optimize(f = mfcn.step, interval = lsintv, 
        maximum = FALSE, tol = ls$tol, m = m, pd = pd, 
        barrier = barrier),

      "brent.fmin" = Brent.fmin(a = 0, b = lsintv[2], 
        fcn = mfcn.step, tol = ls$tol, m = m, pd = pd, 
        barrier = barrier),

      "wolfe" = linesearch(b = lsintv[2], 
        fcn = mfcn.step, grd = mgr.step, 
        ftol = ls$ftol, gtol = ls$gtol, m = m, pd = pd, 
        barrier = barrier))

      lambda <- lsout$minimum
      lsres$ls.iter <- c(lsres$ls.iter, lsout$iter)
      lsres$ls.counts <- lsres$ls.counts + lsout$counts
    } else
    if (is.numeric(step))
      lambda <- step

    # update (new guess)

    pars.old <- m@pars
    pars.new <- pars.old + lambda * pd
    m <- set.pars(m, pars.new)

    # stopping criteria

    if (sqrt(sum((pars.old - pars.new)^2)) < control$tol)
    {
      convergence <- TRUE
    }

    iter <- iter + 1

    if (control$trace)
    {
      Mpars[iter+1,] <- c(get.cpar(m), get.pars(m))
      steps[iter] <- lambda
    }

if (debug)
{
  val <- logLik(object = m, domain = "frequency", barrier = barrier)
  cat(paste("\niter =", iter, "logLik =", round(val, 4), "\n"))
  print(get.pars(m))
}

if (debug && !is.null(m@lower) && !is.null(m@upper))
{
  check.bounds(m)
}
  }

  if (!control$silent && !convergence)
    warning(paste("Possible convergence problem.",
    "Maximum number of iterations reached."))

  if (control$trace)
  {
    Mpars <- na.omit(Mpars)
    attr(Mpars, "na.action") <- NULL
    steps <- na.omit(steps)
    attr(steps, "na.action") <- NULL
  }

  # output

  # the barrier term is not added to the final likelihood value
  val <- logLik(object = m, domain = "frequency", barrier = list(mu = 0))

  res <- c(list(call = mcall,
    init = pars0, pars = m@pars, model = m, loglik = val,
    convergence = convergence, iter = iter, message = "",
    Mpars = Mpars, steps = steps), lsres)
  class(res) <- "stsmFit"
  res
}