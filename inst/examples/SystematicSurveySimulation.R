#'
#' An simulation study demonstrating how to use the main function from a systematic survey design
#'
#'

library(DSpat)  # going to simulate data using an Inhomogenous Poisson Point Process
library(INLA)
library(spatialsurvey)
library(sp)
library(ggplot2)
library(gridExtra)

set.seed(123)
# A square survey domain, no need to be though
survey_xlim = c(0,100)
survey_ylim = c(0,100)
study.area=owin(xrange = survey_xlim, yrange = survey_ylim)
survey_area = study.area$xrange[2] * study.area$yrange[2] # Area of survey
quad_width = 1
quad_height = 1
quad_x_spacing = 10 ## spacings between sampling-unit midpoints
quad_y_spacing = 10 ## spacings between sampling-unit midpoints
n_col = max(survey_xlim) /  quad_x_spacing # sampling units on x-axis
n_row = max(survey_ylim) /  quad_y_spacing # sampling units on y-axis
n_strata = n_row * n_col
n_l = quad_y_spacing / quad_height# l
n_k = quad_x_spacing / quad_width # k
n_quads = n_l * n_row * n_col * n_k
within_rows = rep(1:n_l, n_k)
within_cols = sort(rep(1:n_k, n_l))
## lower and upper limits for discrete non-overlapping quadrats
quad_x = seq(0,max(survey_xlim), by = quad_width)
quad_y = seq(0,max(survey_ylim), by = quad_height)
## spatial coverage of the survey
strata_area = survey_area  / n_strata
sample_area = (quad_height * quad_width * n_strata) / survey_area 
sample_area * 100 ## percentage sampled
kappa = survey_area /  (quad_height * quad_width)
## True population size.
N = 5e5 

## Habitat values in survey domain.
habitat_probs_vals = c(5,2,2) ## survey area dominated with largest habitat type
habitat_probs = cumsum(habitat_probs_vals / 10)
hab.range = 20 ## low number = patch, large = diffuse
n_h = length(habitat_probs) + 1
covariates = simCovariates(hab.range = hab.range, probs=habitat_probs)

## Generate extrapolation grid for model based method
project_res = quad_width
x_proj = seq(project_res/2, to = study.area$xrange[2] - project_res/2, by = project_res)
y_proj = seq(project_res/2, to = study.area$yrange[2] - project_res/2, by = project_res)
proj_df = expand.grid(x_proj, y_proj)
colnames(proj_df) = c("x","y")
proj_df$area = quad_width * quad_height
proj_df$count = 0 ## dummy variable
## mesh settings, important
cut_off = 6 ## only doing 2 or 6


#################
## Simulate a population realisation
#################
covariates = simCovariates(hab.range = hab.range, probs=habitat_probs)
xpp = simPts(covariates=covariates,int.formula=~factor(habitat),EN = N * 2,int.par=0:(n_h - 1))
## fixed N so truncate
x_coord = xpp$x[1:N] 
y_coord = xpp$y[1:N] 

## visualise the covariate
Cols = c("gray40","gray55","gray70","gray85")
plot(covariates$x,covariates$y, col = Cols[covariates$habitat], pch = 16, cex = 2, xlab = "x", ylab = "y")
## add a sample of the true population locations on top of this. Can be slow to render so only a subset
## Can see population denisty is related to habitat.
samp_ndx = sample(1:N, size = N * 0.1, replace = F)
points(x_coord[samp_ndx], y_coord[samp_ndx], pch = 16, cex = 0.3, col = adjustcolor(col = "blue", alpha.f = 0.3))


#################
## Simulate a systematic survey, randomly sample the first sampling unit, then all other
## units are deterministically evaluated based on that first random sample.
#################
first_quad = sample(1:length(within_cols), size = 1)
within_x = within_cols[first_quad] * quad_width
within_y = within_rows[first_quad] * quad_height
upper_x1 = seq(from = within_x, to = survey_xlim[2], by = quad_x_spacing)
upper_y1 = seq(from = within_y, to = survey_ylim[2], by = quad_y_spacing)
upper_x = rep(upper_x1, length(upper_y1))
upper_y = sort(rep(upper_y1, length(upper_x1)))
## get midpoints
sample_y_coord = upper_y - quad_height / 2
sample_x_coord = upper_x - quad_width / 2

## add to sample locations to the plot
points(sample_x_coord, sample_y_coord, pch = 16, cex = 1, col = "red")

sample_data = data.frame(x = sample_x_coord, y = sample_y_coord)
sample_data$count = NA
for(i in 1:length(upper_x)) {
  sample_data$count[i] = sum(x_coord >= (upper_x[i] - quad_width) & x_coord <= upper_x[i]  & y_coord >= (upper_y[i]  - quad_height) & y_coord <= upper_y[i])
}
sample_data$area = quad_height * quad_height
hist(sample_data$count)
table(sample_data$count > 0) 
head(sample_data)
## edge, n and cutoff are user supplied and will be case specific. 
## tips on mesh settings see https://becarioprecario.bitbucket.io/spde-gitbook/ch-intro.html#sec:mesh
mesh = inla.mesh.2d(max.edge = c(3,20), n =15, cutoff = 6, loc.domain = SpatialPoints( data.frame(x = c(survey_xlim[1], survey_xlim[1], survey_xlim[2], survey_xlim[2]),
                                                                                                  y= c(survey_ylim[1], survey_ylim[2], survey_ylim[2], survey_ylim[1]))))
## visualise the mesh
par(mfrow =c(1,1))
plot(mesh)
points(sample_data$x, sample_data$y, col = "red", pch = 16, cex = sample_data$count / max(sample_data$count))
polygon(x = c(survey_xlim[1], survey_xlim[1], survey_xlim[2], survey_xlim[2]), y = c(survey_ylim[1], survey_ylim[2], survey_ylim[2], survey_ylim[1]), border = "purple", lwd = 3)

#################
## DO some quick data manipulation
## then Pass to our function
#################
coordinates(sample_data) <- ~ x + y
class(sample_data)
## 
log(0.5 * sd(sample_data@data$count / sample_data@data$area))
fit_poisson = SpatialModelEstimator(spatial_df = sample_data, formula = count ~ 1, mesh = mesh, extrapolation_grid = proj_df, family = 0, link = 0, bias_correct = T)
fit_neg_bin = SpatialModelEstimator(spatial_df = sample_data, formula = count ~ 1, mesh = mesh, extrapolation_grid = proj_df, family = 1, link = 0,  bias_correct = T)
names(fit_out)
fit_poisson$gmrf_convergence
fit_neg_bin$gmrf_convergence
fit_neg_bin$gmrf_opt$objective
fit_poisson$gmrf_opt$objective
fit_neg_bin$gmrf_opt$par
fit_poisson$gmrf_opt$par
fit_out$init_convergence

N_hat_poisson = fit_poisson$gmrf_sd_report$value[names(fit_poisson$gmrf_sd_report$value) == "fitted_non_sample_Total"] + sum(sample_data$count)
N_hat_neg_bin = fit_neg_bin$gmrf_sd_report$value[names(fit_neg_bin$gmrf_sd_report$value) == "fitted_non_sample_Total"] + sum(sample_data$count)
N_hat_poisson_bias = fit_poisson$gmrf_sd_report$unbiased$value[names(fit_poisson$gmrf_sd_report$value) == "fitted_non_sample_Total"] + sum(sample_data$count)
N_hat_neg_bin_bias = fit_neg_bin$gmrf_sd_report$unbiased$value[names(fit_neg_bin$gmrf_sd_report$value) == "fitted_non_sample_Total"] + sum(sample_data$count)
ln_N_hat_poisson_bias = fit_poisson$gmrf_sd_report$unbiased$value[names(fit_poisson$gmrf_sd_report$value) == "log_fitted_non_sample_Total"]
ln_N_hat_neg_bin_bias = fit_neg_bin$gmrf_sd_report$unbiased$value[names(fit_neg_bin$gmrf_sd_report$value) == "log_fitted_non_sample_Total"]
## standard errors
N_se_poisson_bias = fit_poisson$gmrf_sd_report$sd[names(fit_poisson$gmrf_sd_report$value) == "fitted_non_sample_Total"]
ln_N_se_poisson_bias = fit_poisson$gmrf_sd_report$sd[names(fit_poisson$gmrf_sd_report$value) == "log_fitted_Total"]
N_se_neg_bin_bias = fit_neg_bin$gmrf_sd_report$sd[names(fit_neg_bin$gmrf_sd_report$value) == "log_fitted_Total"]
ln_N_se_poisson_bias = fit_poisson$gmrf_sd_report$unbiased$sd[names(fit_poisson$gmrf_sd_report$value) == "log_fitted_Total"]
ln_N_se_neg_bin_bias = fit_neg_bin$gmrf_sd_report$unbiased$sd[names(fit_neg_bin$gmrf_sd_report$value) == "log_fitted_Total"]
## in theory these should be the same
fit_poisson$gmrf_sd_report$unbiased$sd[names(fit_poisson$gmrf_sd_report$value) == "log_fitted_Total"]
fit_poisson$gmrf_sd_report$unbiased$sd[names(fit_poisson$gmrf_sd_report$value) == "log_fitted_non_sample_Total"]
## Walk CIs
exp(ln_N_hat_poisson_bias + c(-2, 2) * ln_N_se_poisson_bias)
exp(ln_N_hat_neg_bin_bias + c(-2, 2) * ln_N_se_neg_bin_bias)
#############################
## create obj and simulate
############################
MLE_pars = fit_poisson$start_vals
MLE_pars$betas = fit_poisson$MLE_par["betas"]
MLE_pars$ln_kappa = fit_poisson$MLE_par["ln_kappa"]
MLE_pars$ln_tau = fit_poisson$MLE_par["ln_tau"]
MLE_pars$omega = fit_poisson$MLE_par[names(fit_poisson$MLE_par) %in% "omega"]
fit_poisson$tmb_data$simulate_state = 0
poi_obj = TMB::MakeADFun(data = fit_poisson$tmb_data, random = c("omega"), parameters = MLE_pars , map = list("ln_phi" = factor(NA)), DLL = "spatialsurvey_TMBExports", silent = T)
fit_poisson$tmb_data$simulate_state = 1
poi_obj_state = TMB::MakeADFun(data = fit_poisson$tmb_data, random = c("omega"), parameters = MLE_pars , map = list("ln_phi" = factor(NA)), DLL = "spatialsurvey_TMBExports", silent = T)
## look at this
sim_data = poi_obj$simulate()
sim_data_state = poi_obj_state$simulate()
proj_df$y_sim = sim_data$y_sim
proj_df$y_sim_state = sim_data_state$y_sim
proj_df$y_fitted = fit_poisson$MLE_gmrf$mu_proj
fitted_ = ggplot(data = proj_df, aes(x = x, y = y, fill = y_fitted)) +
  geom_tile()
simulated_ = ggplot(data = proj_df, aes(x = x, y = y, fill = y_sim)) +
  geom_tile()
state_simulated_ = ggplot(data = proj_df, aes(x = x, y = y, fill = y_sim_state)) +
  geom_tile()
grid.arrange(fitted_, simulated_, state_simulated_, ncol = 3)
sum(proj_df$y_sim)
sum(proj_df$y_sim_state)
sum(proj_df$y_fitted)
fit_poisson$MLE_gmrf$fitted_non_sample_Total + sum(sample_data$count)
sim_model_Ns = vector()
sim_model_state_Ns = vector()
for(i in 1:1000) {
  sim_data = poi_obj$simulate()
  sim_data_state = poi_obj_state$simulate()
  sim_model_Ns[i] = sum(sim_data$y_sim)
  sim_model_state_Ns[i] =  sum(sim_data_state$y_sim)
  
}
sd(sim_model_Ns)
sd(sim_model_state_Ns)

boxplot(cbind(sim_model_Ns, sim_model_state_Ns))
abline(h = N_hat_poisson, lwd = 3, lty = 2, col = "red")
## simulate with new GF




N_hat_poisson
N_hat_neg_bin

fit_out$MLE_gmrf$marginal_variance
hist(fit_out$MLE_gmrf$omega)
## visualise the fitted value
proj_df$fitted_val = fit_out$MLE_gmrf$abund_proj
ggplot(proj_df, aes(x = x, y = y, fill = fitted_val)) +
  geom_tile()

## Boxlet method
s_poly = Polygon(cbind(x = c(survey_xlim[1],survey_xlim[1],survey_xlim[2],survey_xlim[2]), y = c(survey_ylim[1],survey_ylim[2],survey_ylim[2],survey_ylim[1])))
s_polys = Polygons(list(s_poly),1)
sp_survey_poly = SpatialPolygons(list(s_polys)) ## add coordinater reference here
survey_area = rgeos::gArea(sp_survey_poly)
survey_polygon = sp_survey_poly
## create fine boxlet lattice
boxlet_frame = BoxletEstimatorSamplingFrame(survey_polygon, quad_width = quad_width, quad_height = quad_height, quad_x_spacing = quad_x_spacing,
                                            quad_y_spacing = quad_y_spacing, boxlet_per_sample_width = 1, 
                                            boxlet_per_sample_height = 1, trace = F)
sample_data@data$y_i = sample_data@data$count
boxlet_estimator = BoxletEstimator(spatial_df = sample_data, survey_polygon = survey_polygon, quad_width = quad_width, 
                                   quad_height = quad_height, quad_x_spacing = quad_x_spacing, quad_y_spacing = quad_y_spacing, 
                                   boxlet_sampling_frame = boxlet_frame)
## post-stratified overlapping estimator
## function requires matrix format.
survey_data_mat = matrix(sample_data@data$count, nrow = n_row, ncol = n_col, byrow = T)
post_stratified_estimator = PoststratifiedOverlappingEstimator(y = survey_data_mat, sample_area = quad_height * quad_width, survey_area = survey_area, 1, 1)
post_stratified_nonoverlapping_estimator = PoststratifiedNonOverlappingEstimator(y = survey_data_mat, sample_area = quad_height * quad_width, survey_area = survey_area, 2, 2)
srs_estiamtor = kappa^2 * var(sample_data@data$y_i) / (nrow(sample_data@data))
sample_raster = raster::raster(survey_data_mat)
adjust_correlation = CorrelationAdjusted(sample_raster, quad_height * quad_width, survey_area = survey_area)
adjust_correlation$rho
## compare estimators
sqrt(post_stratified_estimator)
sqrt(post_stratified_nonoverlapping_estimator)
sqrt(srs_estiamtor)
sqrt(adjust_correlation$var_est)
sqrt(boxlet_estimator$var_total_boxlet)
N_se_poisson_bias
N_se_neg_bin_bias


