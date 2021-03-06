#install.packages("ProjectTemplate")
library(ProjectTemplate)
#create a project template in home directory
#create.project('instacart')
#cd instacart
#copy your data into data directory in instacart and add libraries in config -> global.dcf
#set instacart 
# load the project(please make sure you set the current working directory as your project directory)
load.project()

#added (library(dplyr)) after library(tidyverse) and then %>% was found.
# sometimes need library(dplyr)
library(tidyverse)


######### feature engineering ####################################
data$prod_reorder_probability <- data$prod_second_orders / data$prod_first_orders
data$prod_reorder_times <- 1 + data$prod_reorders / data$prod_first_orders
data$prod_reorder_ratio <- data$prod_reorders / data$prod_orders
data <- data %>% select(-prod_reorders, -prod_first_orders, -prod_second_orders)
data$user_average_basket <- data$user_total_products / data$user_orders
data$up_order_rate <- data$up_orders / data$user_orders
data$up_orders_since_last_order <- data$user_orders - data$up_last_order
data$up_order_rate_since_first_order <- data$up_orders / (data$user_orders - data$up_first_order + 1)


# want to add targer reorder to data by joining order_products_train and user_id
# only append user_id to order.products.train, therefore order[,c("order_id", "user_id")]
order.products.train <- order_products__train %>% inner_join(orders[,c("order_id", "user_id")])
#select("order_id", "user_id")

# train and test orders
#get train and test data from orders  eval_set = prior current is split into train and test/it's validation
us <- orders %>%
  filter(eval_set != "prior") %>%
  select(user_id, order_id, eval_set)

#get train and test from data!!!!
data <- data %>% inner_join(us)

rm(us)
#gc is to release memory of the variable you no longer used
gc()


### creating final dataset: adding target variables
data <- data %>% 
  left_join(order.products.train %>% select(user_id, product_id, reordered), 
            by = c("user_id", "product_id"))

#rm(ordert, prd, users)
#1: In rm(ordert, prd, users) : object 'ordert' not found
#gc()


# creating training and validation set
train <- data[data$eval_set == 'train',]
test <- data[data$eval_set == "test",]


# training make NA for ID columns
train$eval_set <- NULL
train$user_id <- NULL
train$product_id <- NULL
train$order_id <- NULL
# training target variable creation, NA means no reorder
train$reordered[is.na(train$reordered)] <- 0

# testing data remove ID columns, why not product_id and order_id??????
test$eval_set <- NULL
test$user_id <- NULL
test$reordered <- NULL


# split training data into training and validation set
set.seed(1)
train_bak <- train

# only sample 10 percent of data for performance reasons
train <- train[sample(nrow(train)),] %>% 
  sample_frac(0.1)

#install.packages("xgboost")
library(xgboost)
#install.packages("pROC")
library(pROC)
library(precrec)

#### modelling simple ####################

cat("Hypter-parameter tuning\n")
hyper_grid <-expand.grid(
  nrounds =               c(3000),   #iterations
  max_depth =             c(6),
  eta =                   c(0.1),
  gamma =                 c(0.7),
  colsample_bytree =      c(0.95),
  subsample =             c(0.75),
  min_child_weight =      c(10),
  alpha =                 c(2e-05),
  lambda =                c(10),
  scale_pos_weight =      c(1)
)

#use how many core/threads to run code 
nthread <- 6

#create DMatrix for xgboost


train_data_x <- data.matrix(select(train, -reordered))
train_data_y <- data.matrix(select(train, reordered))
train_data <- xgb.DMatrix(data = train_data_x, label = train_data_y)
#or use as.matrix directly
test_data <- xgb.DMatrix(as.matrix(test %>% select(-order_id, -product_id)))

# this watch list is only for observing output - doesn't change model early stopping
watchlist <- list(train = train_data)
model_pos <- 1

set.seed(1)

model <- xgb.train(
  data =                      train_data,
  
  nrounds =                   100,
  max_depth =                 hyper_grid[1, "max_depth"],
  eta =                       hyper_grid[1, "eta"],
  gamma =                     hyper_grid[1, "gamma"],
  colsample_bytree =          hyper_grid[1, "colsample_bytree"],
  subsample =                 hyper_grid[1, "subsample"],
  min_child_weight =          hyper_grid[1, "min_child_weight"],
  alpha =                     hyper_grid[1, "alpha"],
  lambda =                    hyper_grid[1, "lambda"],
  scale_pos_weight =          hyper_grid[1, "scale_pos_weight"],
  
  booster =                   "gbtree",
  objective =                 "binary:logistic",
  eval_metric =               "auc",
  prediction =                TRUE,
  verbose =                   TRUE,
  watchlist =                 watchlist,
  early_stopping_rounds =     50,
  print_every_n =             10,
  nthread =                   nthread
)


# make a prediction on the training dataset
pred_train_data <- predict(model, newdata = train_data_x)
# check the performance of the model on training dataset
train_performance <- roc(as.vector(train_data_y), pred_train_data)

# plot ROC curve and precision-recall curve
precrec_obj <- evalmod(scores = pred_train_data, labels = as.vector(train_data_y))
autoplot(precrec_obj)

# plot the probability distribution
df <- data.frame(scores = pred_train_data, labels = as.vector(train_data_y))
ggplot(df, aes(x=scores, fill=as.factor(labels))) + geom_density(alpha = 0.5)


test$reordered <- predict(model, newdata = test_data)
test$reordered <- (test$reordered > 0.21) * 1

submission <- test %>%
  filter(reordered == 1) %>%
  group_by(order_id) %>%
  summarise(
    products = paste(product_id, collapse = " ")
  )

missing <- data.frame(
  order_id = unique(test$order_id[!test$order_id %in% submission$order_id]),
  products = "None"
)

submission <- submission %>% bind_rows(missing) %>% arrange(order_id)
write.csv(submission, file = "submit.csv", row.names = F)




####################################################################
####################################################################
####################################################################
####################################################################
#### modelling training validation split, slight complex ###########
####################################################################
####################################################################
####################################################################

# split data into train and validation
train_index <- sample(1:nrow(train), 0.8 * nrow(train))
#valid_index <- setdiff(1:nrow(data), train_index)


cat("Hypter-parameter tuning\n")
hyper_grid <-expand.grid(
  nrounds =               c(100),
  max_depth =             c(6),
  eta =                   c(0.1,0.05),
  gamma =                 c(0.7),
  colsample_bytree =      c(0.95),
  subsample =             c(0.75),
  min_child_weight =      c(10),
  alpha =                 c(2e-05),
  lambda =                c(10),
  scale_pos_weight =      c(1)
)

nthread <- 6

gc()


cat("Running model tuning\n")

final_valid_metrics <- data.frame()

for(i in 1:nrow(hyper_grid)){
  cat(paste0("\nModel ", i, " of ", nrow(hyper_grid), "\n"))
  cat("Hyper-parameters:\n")
  print(hyper_grid[i,])
  
  metricsValidComb <- data.frame()

  
  valid_data <- train[-train_index,]
  valid_data_x <- data.matrix(select(valid_data, -reordered))
  valid_data_y <- data.matrix(select(valid_data, reordered))
  
  train_data <- train[train_index,]
  train_data_x <- data.matrix(select(train_data, -reordered))
  train_data_y <- data.matrix(select(train_data, reordered))
  
  
  train_data_xgb <- xgb.DMatrix(data = train_data_x, label = train_data_y)
  valid_data_xgb <- xgb.DMatrix(data = valid_data_x, label = valid_data_y)
  
  watchlist <- list(valid = valid_data_xgb)
  
  seed <- 1
  set.seed(seed)
  
  model <- xgb.train(
    data =                      train_data_xgb,
    
    nrounds =                   hyper_grid[i, "nrounds"],
    max_depth =                 hyper_grid[i, "max_depth"],
    eta =                       hyper_grid[i, "eta"],
    gamma =                     hyper_grid[i, "gamma"],
    colsample_bytree =          hyper_grid[i, "colsample_bytree"],
    subsample =                 hyper_grid[i, "subsample"],
    min_child_weight =          hyper_grid[i, "min_child_weight"],
    alpha =                     hyper_grid[i, "alpha"],
    lambda =                    hyper_grid[i, "lambda"],
    scale_pos_weight =          hyper_grid[i, "scale_pos_weight"],
    
    booster =                   "gbtree",
    objective =                 "binary:logistic",
    eval_metric =               "auc",
    prediction =                TRUE,
    verbose =                   TRUE,
    watchlist =                 watchlist,
    early_stopping_rounds =     30,
    print_every_n =             10,
    nthread =                   nthread
  )
  
  # make prediction on the validation dataset
  evaluation <- predict(model, newdata = valid_data_x)
  # calculate AUC based on the prediction result
  metrics <- roc(as.vector(valid_data_y), evaluation)
  # get the auc value
  model_auc <- as.numeric(metrics$auc)
  # put together AUC and the best iteration value
  metrics_frame <- data.frame(AUC = model_auc, best_iter = model$best_iteration)
  # combine the result for each fold
  #metricsValidComb <- rbind(metricsValidComb, metrics_frame)
  final_valid_metrics <- rbind(final_valid_metrics, metrics_frame)
  cat(paste0("AUC: ", round(model_auc, 3), "\n"))
  
}

#final_valid_metrics
#       AUC     best_iter
#1 0.8315090       100
#2 0.8311105       100

#hyper_grid

results_valid <- cbind(hyper_grid, final_valid_metrics)

results_valid
#nrounds max_depth  eta gamma colsample_bytree subsample min_child_weight alpha lambda scale_pos_weight       AUC      best_iter
#1     100         6 0.10   0.7             0.95      0.75               10 2e-05     10                1 0.8315090     100
#2     100         6 0.05   0.7             0.95      0.75               10 2e-05     10                1 0.8311105     100


# descending on AVG_AUC and get the best parameter
results_valid <- results_valid %>% 
  arrange(desc(AUC))


############## FINAL MODEL ###################################################

#train_data <- train[-(valid_fold_start_index:valid_fold_end_index),]
train_data_x <- data.matrix(select(train, -reordered))
train_data_y <- data.matrix(select(train, reordered))
train_data <- xgb.DMatrix(data = train_data_x, label = train_data_y)
test_data <- xgb.DMatrix(as.matrix(test %>% select(-order_id, -product_id)))
# this watch list is only for observing output - doesn't change model early stopping
watchlist <- list(train = train_data)
model_pos <- 1 # to get the first row in results_valid

set.seed(seed)

model <- xgb.train(
  data =                      train_data,
  
  nrounds =                   results_valid[model_pos, "best_iter"],
  max_depth =                 results_valid[model_pos, "max_depth"],
  eta =                       results_valid[model_pos, "eta"],
  gamma =                     results_valid[model_pos, "gamma"],
  colsample_bytree =          results_valid[model_pos, "colsample_bytree"],
  subsample =                 results_valid[model_pos, "subsample"],
  min_child_weight =          results_valid[model_pos, "min_child_weight"],
  alpha =                     results_valid[model_pos, "alpha"],
  lambda =                    results_valid[model_pos, "lambda"],
  scale_pos_weight =          results_valid[model_pos, "scale_pos_weight"],
  
  booster =                   "gbtree",
  objective =                 "binary:logistic",
  eval_metric =               "auc",
  prediction =                TRUE,
  verbose =                   TRUE,
  watchlist =                 watchlist,
  early_stopping_rounds =     round(results_valid[model_pos, "best_iter"]),
  print_every_n =             10,
  nthread =                   nthread
)


# make a prediction on the training dataset
pred_train_data <- predict(model, newdata = train_data_x)
# check the performance of the model on training dataset
train_performance <- roc(as.vector(train_data_y), pred_train_data)

# plot ROC curve and precision-recall curve
precrec_obj <- evalmod(scores = pred_train_data, labels = as.vector(train_data_y))
autoplot(precrec_obj)

# plot the probability distribution
df <- data.frame(scores = pred_train_data, labels = as.vector(train_data_y))
ggplot(df, aes(x=scores, fill=as.factor(labels))) + geom_density(alpha = 0.5)


test$reordered <- predict(model, newdata = test_data)
test$reordered <- (test$reordered > 0.21) * 1

submission <- test %>%
  filter(reordered == 1) %>%
  group_by(order_id) %>%
  summarise(
    products = paste(product_id, collapse = " ")
  )

missing <- data.frame(
  order_id = unique(test$order_id[!test$order_id %in% submission$order_id]),
  products = "None"
)

submission <- submission %>% bind_rows(missing) %>% arrange(order_id)
write.csv(submission, file = "submit.csv", row.names = F)






####################################################################
####################################################################
####################################################################
####################################################################
#### modelling cross validation, complex ###########################
####################################################################
####################################################################
####################################################################

# define the number of fold
n_fold <- 5
fold_row_num <- nrow(train)/n_fold

cat("Hypter-parameter tuning\n")
hyper_grid <-expand.grid(
  nrounds =               c(100),
  max_depth =             c(6),
  eta =                   c(0.1,0.05),
  gamma =                 c(0.7),
  colsample_bytree =      c(0.95,0.7),
  subsample =             c(0.75),
  min_child_weight =      c(10),
  alpha =                 c(2e-05),
  lambda =                c(10),
  scale_pos_weight =      c(1)
)

nthread <- 6

gc()


cat("Running model tuning\n")

final_valid_metrics <- data.frame()

for(i in 1:nrow(hyper_grid)){
  cat(paste0("\nModel ", i, " of ", nrow(hyper_grid), "\n"))
  cat("Hyper-parameters:\n")
  print(hyper_grid[i,])
  
  metricsValidComb <- data.frame()
  #get valid fold
  for(j in 1:n_fold){
    cat(paste0("\nFold ", j, " of ", n_fold, "\n"))
    valid_fold_start_index <- 1+(j-1)*fold_row_num
    if(j < n_fold){
      valid_fold_end_index <- j*fold_row_num
    }else{
      valid_fold_end_index <- nrow(train)
    }
    
    valid_cv_data <- train[valid_fold_start_index:valid_fold_end_index,]
    valid_cv_data_x <- data.matrix(select(valid_cv_data, -reordered))
    valid_cv_data_y <- data.matrix(select(valid_cv_data, reordered))
    
    train_cv_data <- train[-(valid_fold_start_index:valid_fold_end_index),]
    train_cv_data_x <- data.matrix(select(train_cv_data, -reordered))
    train_cv_data_y <- data.matrix(select(train_cv_data, reordered))
    
    
    train_cv_data_xgb <- xgb.DMatrix(data = train_cv_data_x, label = train_cv_data_y)
    valid_cv_data_xgb <- xgb.DMatrix(data = valid_cv_data_x, label = valid_cv_data_y)
    
    watchlist <- list(valid = valid_cv_data_xgb)
    
    seed <- 1
    set.seed(seed)
    
    model <- xgb.train(
      data =                      train_cv_data_xgb,
      
      nrounds =                   hyper_grid[i, "nrounds"],
      max_depth =                 hyper_grid[i, "max_depth"],
      eta =                       hyper_grid[i, "eta"],
      gamma =                     hyper_grid[i, "gamma"],
      colsample_bytree =          hyper_grid[i, "colsample_bytree"],
      subsample =                 hyper_grid[i, "subsample"],
      min_child_weight =          hyper_grid[i, "min_child_weight"],
      alpha =                     hyper_grid[i, "alpha"],
      lambda =                    hyper_grid[i, "lambda"],
      scale_pos_weight =          hyper_grid[i, "scale_pos_weight"],
      
      booster =                   "gbtree",
      objective =                 "binary:logistic",
      eval_metric =               "auc",
      prediction =                TRUE,
      verbose =                   FALSE,
      watchlist =                 watchlist,
      early_stopping_rounds =     30,
      print_every_n =             10,
      nthread =                   nthread
    )
    
    # make prediction on the validation dataset
    evaluation <- predict(model, newdata = valid_cv_data_x)
    # calculate AUC based on the prediction result
    metrics <- roc(as.vector(valid_cv_data_y), evaluation)
    # get the auc value
    model_auc <- as.numeric(metrics$auc)
    # put together AUC and the best iteration value
    metrics_frame <- data.frame(AUC = model_auc, best_iter = model$best_iteration)
    # combine the result for each fold
    metricsValidComb <- rbind(metricsValidComb, metrics_frame)
    cat(paste0("AUC: ", round(model_auc, 3), "\n"))
  }
  
  #above just finish folds
  #now metricsValidComb is a df with 5 rows(5 folds) and 2 columns
  #get the mean
  metricsValidComb_avg <- metricsValidComb %>% 
    group_by() %>% 
    summarise(AVG_AUG = mean(AUC), AVG_best_iter = mean(best_iter))
  #now metricsValidComb_avg has 2 new columns AVG_AUG, AVG_best_iter
  final_valid_metrics <- rbind(final_valid_metrics, metricsValidComb_avg)
  
}

results_valid <- cbind(hyper_grid, final_valid_metrics)

# descending on AVG_AUC and get the best parameter
results_valid <- results_valid %>% 
  arrange(desc(AVG_AUG))


############## FINAL MODEL ###################################################

#train_data <- train[-(valid_fold_start_index:valid_fold_end_index),]
train_data_x <- data.matrix(select(train, -reordered))
train_data_y <- data.matrix(select(train, reordered))
train_data <- xgb.DMatrix(data = train_data_x, label = train_data_y)
test_data <- xgb.DMatrix(as.matrix(test %>% select(-order_id, -product_id)))
# this watch list is only for observing output - doesn't change model early stopping
watchlist <- list(train = train_data)
model_pos <- 1

set.seed(seed)

model <- xgb.train(
  data =                      train_data,
  
  nrounds =                   results_valid[model_pos, "AVG_best_iter"],
  max_depth =                 results_valid[model_pos, "max_depth"],
  eta =                       results_valid[model_pos, "eta"],
  gamma =                     results_valid[model_pos, "gamma"],
  colsample_bytree =          results_valid[model_pos, "colsample_bytree"],
  subsample =                 results_valid[model_pos, "subsample"],
  min_child_weight =          results_valid[model_pos, "min_child_weight"],
  alpha =                     results_valid[model_pos, "alpha"],
  lambda =                    results_valid[model_pos, "lambda"],
  scale_pos_weight =          results_valid[model_pos, "scale_pos_weight"],
  
  booster =                   "gbtree",
  objective =                 "binary:logistic",
  eval_metric =               "auc",
  prediction =                TRUE,
  verbose =                   TRUE,
  seed =                      seed,
  watchlist =                 watchlist,
  early_stopping_rounds =     round(results_valid[model_pos, "AVG_best_iter"]),
  print_every_n =             10,
  nthread =                   nthread
)


# make a prediction on the training dataset
pred_train_data <- predict(model, newdata = train_data_x)
# check the performance of the model on training dataset
train_performance <- roc(as.vector(train_data_y), pred_train_data)

# plot ROC curve and precision-recall curve
precrec_obj <- evalmod(scores = pred_train_data, labels = as.vector(train_data_y))
autoplot(precrec_obj)

# plot the probability distribution
df <- data.frame(scores = pred_train_data, labels = as.vector(train_data_y))
ggplot(df, aes(x=scores, fill=as.factor(labels))) + geom_density(alpha = 0.5)


test$reordered <- predict(model, newdata = test_data)
test$reordered <- (test$reordered > 0.21) * 1

submission <- test %>%
  filter(reordered == 1) %>%
  group_by(order_id) %>%
  summarise(
    products = paste(product_id, collapse = " ")
  )

missing <- data.frame(
  order_id = unique(test$order_id[!test$order_id %in% submission$order_id]),
  products = "None"
)

submission <- submission %>% bind_rows(missing) %>% arrange(order_id)
write.csv(submission, file = "submit.csv", row.names = F)
