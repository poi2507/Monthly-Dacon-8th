library(DMwR);library(dplyr);library(data.table);library(caret);library(catboost);library(Matrix);library(ROCR);library(lightgbm)
setwd("C:/r/Monthly-Dacon-8th/")
source('C:/r/Monthly-Dacon-8th/monthlyDacon_8_common.R')

##################
## Data Loading ##
##################
sample_submission <- data.table::fread(
  "sample_submission.csv",
  stringsAsFactors = F,
  data.table       = F
)

train <- data.table::fread(
  "train.csv",
  stringsAsFactors = F,
  data.table = F,
  na.strings = c("NA", "NaN", "NULL", "\\N"))

test  <- data.table::fread(
  "test_x.csv",
  stringsAsFactors = F,
  data.table = F,
  na.strings = c("NA", "NaN", "NULL", "\\N"))


#################
## 이상치 처리 ##
#################
#- Q_E          :  10000 이상 값들은 전부 중앙값으로 대체
#- familysize   :  18이상인 데이터에 대해서는 이상치 처리 필요 --> 중앙값으로 대체

Q_E <- c("QaE",  "QbE",   "QcE",  "QdE",  "QeE",  "QfE",  "QgE" 
         , "QhE",   "QiE" ,  "QjE",  "QkE"  , "QlE",  "QmE",  "QnE" , "QoE",   "QpE" , "QqE",  "QrE" , "QsE" , "QtE") 

train[Q_E] <- train %>% select(matches("Q.E")) %>% mutate_all(~ifelse(.x >= 10000, NA, .x))
train      <- train %>% mutate(familysize = ifelse(familysize >= 18, NA, familysize)) 

test[Q_E] <- test %>% select(matches("Q.E")) %>% mutate_all(~ifelse(.x >= 10000, NA, .x))
test      <- test %>% mutate(familysize = ifelse(familysize >= 18, NA, familysize)) 

#################
## 결측치 처리 ##
#################
train <- DMwR::centralImputation(
  data = train  # 데이터 프레임
)

test  <- DMwR::centralImputation(
  data = test  # 데이터 프레임
)

colSums(is.na(train))
colSums(is.na(test))

###########################
## 파생변수 생성 및 변경 ##
###########################
#- 1. reverse 
#- QaA, QdA, QeA, QfA, QgA, QiA, QkA, QnA, QqA, QrA --> reverse 
revVar  <- c("QaA", "QdA", "QeA", "QfA", "QgA", "QiA", "QkA", "QnA", "QqA", "QrA")
train[revVar] <- train %>% select(revVar) %>% mutate_all(list(~6 - .))
test[revVar]  <- test %>% select(revVar) %>% mutate_all(list(~6 - .))

#- 2. machia score = 전체 점수의 평균 값 계산
machiaVar             <- train %>% select(matches("Q.A")) %>%  colnames
train$machiaScore     <- train %>% select(machiaVar) %>% transmute(machiaScore = rowMeans(across(where(is.numeric)))) %>% unlist %>% as.numeric
test$machiaScore      <- test  %>% select(machiaVar) %>% transmute(machiaScore = rowMeans(across(where(is.numeric)))) %>% unlist %>% as.numeric

#- 3 wf_mean, wr_mean, voca_mean(실제 단어를 아는 경우(wr)  - 허구인 단어를 아는 경우(wf) / 13)
wfVar <- train %>% select(matches("wf.")) %>%  colnames
wrVar <- train %>% select(matches("wr.")) %>%  colnames

#- 3.1 wf_mean
train$wf_mean <- train %>% select(wfVar) %>% transmute(wf_mean = round(rowMeans(across(where(is.numeric))), 8)) %>% unlist %>% as.numeric
test$wf_mean  <- test %>% select(wfVar)  %>% transmute(wf_mean = round(rowMeans(across(where(is.numeric))), 8)) %>% unlist %>% as.numeric

#- 3.2 wr_mean
train$wr_mean <- train %>% select(wrVar) %>% transmute(wr_mean = round(rowMeans(across(where(is.numeric))), 8)) %>% unlist %>% as.numeric
test$wr_mean  <- test %>% select(wrVar)  %>% transmute(wr_mean = round(rowMeans(across(where(is.numeric))), 8)) %>% unlist %>% as.numeric

#- 3.3 voca_mean
train$voca_mean <- train %>% transmute(voca_mean = round((wr_01 + wr_02 + wr_03 + wr_04 + wr_05 + wr_06 + wr_07 + wr_08 + wr_09 + wr_10 + wr_11 + wr_12 + wr_13 - wf_01 - wf_02 - wf_03 / 16), 8)) %>% unlist %>% as.numeric
test$voca_mean <- test %>% transmute(voca_mean = round((wr_01 + wr_02 + wr_03 + wr_04 + wr_05 + wr_06 + wr_07 + wr_08 + wr_09 + wr_10 + wr_11 + wr_12 + wr_13 - wf_01 - wf_02 - wf_03 / 16), 8)) %>% unlist %>% as.numeric

#- tp variable
tpPs <- c("tp01", "tp03", "tp05", "tp07", "tp09")
tpNg <- c("tp02", "tp04", "tp06", "tp08", "tp10")

#- 3.4 tp_positive
train$tp_positive  <- train %>% select(tpPs) %>% transmute(tp_positive = round(rowMeans(across(where(is.numeric))), 8)) %>%  unlist %>% as.numeric 
test$tp_positive   <- test  %>% select(tpPs) %>% transmute(tp_positive = round(rowMeans(across(where(is.numeric))), 8)) %>%  unlist %>% as.numeric 

#- 3.5 tp_negative 
train$tp_negative  <- train %>% select(tpNg) %>% transmute(tp_negative = round(rowMeans(across(where(is.numeric))), 8)) %>%  unlist %>% as.numeric 
test$tp_negative   <- test  %>% select(tpNg) %>% transmute(tp_negative = round(rowMeans(across(where(is.numeric))), 8)) %>%  unlist %>% as.numeric 

#- 3.6 tp_mean
train$tp_mean <- train %>% transmute(tp_mean = round(((tp01 + tp03 + tp05 + tp07 + tp09 + (6 - tp02) + (6 - tp04) + (6 - tp06) + (6 - tp08) + (6 - tp10)) / 10), 8)) %>%  unlist %>% as.numeric
test$tp_mean  <- test %>% transmute(tp_mean = round(((tp01 + tp03 + tp05 + tp07 + tp09 + (6 - tp02) + (6 - tp04) + (6 - tp06) + (6 - tp08) + (6 - tp10)) / 10), 8)) %>%  unlist %>% as.numeric

#- 3.7 QE_mean
# QEVar <- train %>% select(matches("Q.E")) %>%  colnames
# train$QE_mean  <- train %>% select(QEVar) %>% transmute(QE_mean = round(rowMeans(across(where(is.numeric))), 8)) %>%  unlist %>% as.numeric 
# test$QE_mean   <- test  %>% select(QEVar) %>% transmute(QE_mean = round(rowMeans(across(where(is.numeric))), 8)) %>%  unlist %>% as.numeric 


##############################
## 변수타입설정 & 변수 선택 ##
##############################
#- 수치형 변수 
num_var <- train %>%  select_if(is.numeric) %>%  colnames 

#- 범주형(명목형) 변환
factor_var <- c("engnat",
                "age_group",
                "education",
                "gender",
                "hand",
                "married",
                "race",
                "religion",
                "urban",
                "voted")

train[factor_var]        <- train %>% select(all_of(factor_var))        %>% mutate_all(as.factor)
test[factor_var[c(-10)]]  <-  test %>% select(all_of(factor_var[c(-10)])) %>% mutate_all(as.factor)

#- 범주형(순서형) 변환
ordered_var1 <- colnames(train)[grep("Q.A", colnames(train))]
ordered_var2 <- colnames(train)[grep("tp|wr|wf.", colnames(train))]

train[c(ordered_var1, ordered_var2)]   <- train %>% select(all_of(ordered_var1), all_of(ordered_var2)) %>% mutate_all(as.ordered)
test[c(ordered_var1, ordered_var2) ]   <- test %>% select(all_of(ordered_var1), all_of(ordered_var2)) %>% mutate_all(as.ordered)

#-  변수 제거
remv_var <- c("index")
train    <- train %>%  select(-remv_var)
test     <- test  %>%  select(-remv_var)

#- one-hot encoding (필요시) -- LightGBM
oneHotVar       <- c(factor_var[-10])
train_fac       <- train %>% select(all_of(oneHotVar))
dmy_model       <- caret::dummyVars("~ .", data = train_fac)
train_oneHot    <- data.frame(predict(dmy_model, train_fac))

train  <- train %>% select(-oneHotVar) 
train  <- dplyr::bind_cols(train, train_oneHot)

test_fac       <- test %>% select(all_of(oneHotVar[c(-10)]))
dmy_model      <- caret::dummyVars("~ .", data = test_fac)
test_oneHot    <- data.frame(predict(dmy_model, test_fac))

test  <- test %>% select(-oneHotVar) 
test  <- dplyr::bind_cols(test, test_oneHot)

rm(ls = test_oneHot)
rm(ls = train_oneHot)
rm(ls = train_fac)
rm(ls = test_fac)

############
## 모델링 ##
############
set.seed(1)
trainIdx <- createDataPartition(train[,"voted"], p = 0.7, list = F)
trainData <- train[ trainIdx, ]
testData  <- train[-trainIdx, ]

## final 제출시, 적용
trainData <- train
testData  <- test

rm(ls = train)
rm(ls = test)
#################
## 2. CatBoost ##
#################
# voted  1 --> 0, 2 --> 1로 변경 
trainData_cat <- trainData
testData_cat  <- testData

YIdx       <- which(colnames(trainData_cat) %in% c('voted'))
features   <- trainData_cat[-YIdx]
labels     <- ifelse(trainData_cat[,YIdx] == 1, 0, 1)
train_pool <- catboost.load_pool(data = features, label = labels)

# 2. catboost.train 함수를 이용하여 train
set.seed(1)
model1 <- catboost.train(
  train_pool,                                  #- 학습에 사용하고자 하는 train_pool  
  NULL,                                        #- 
  params = list(loss_function = 'Logloss',     #- loss function 지정(여기서는 분류모형이므로 Logloss)
                random_seed   = 1,             #- seed number
                custom_loss   = "AUC",         #- 모델링 할 때 추가로 추출할 값들 (train_dir로 지정한 곳으로 해당 결과를 파일로 내보내준다)
                train_dir     = "./model/CatBoost_R_output", #- 모델링 한 결과를 저장할 directory
                iterations    = 2000,                         #- 학습 iteration 수
                metric_period = 10)            
)           
# save(model1, file = "catBoost_model.RData")
# load("catBoost_model.RData")

# catboost importance 
catboost_imp           <- data.frame(model1$feature_importances)
catboost_imp$variables <- rownames(model1$feature_importances)
colnames(catboost_imp) <- c("importance", 'variables')
catboost_imp           <- catboost_imp %>% arrange(-importance)
View(catboost_imp)
catboost_imp$variables

# 3. catboost.predict function
real_pool    <- catboost.load_pool(testData_cat)
YHat_cat_1   <- catboost.predict(
  model1, 
  real_pool,
  prediction_type = c('Probability'))  # Probability, Class


set.seed(123)
model2 <- catboost.train(
  train_pool,                                  #- 학습에 사용하고자 하는 train_pool  
  NULL,                                        #- 
  params = list(loss_function = 'Logloss',     #- loss function 지정(여기서는 분류모형이므로 Logloss)
                random_seed   = 123,           #- seed number
                custom_loss   = "AUC",         #- 모델링 할 때 추가로 추출할 값들 (train_dir로 지정한 곳으로 해당 결과를 파일로 내보내준다)
                train_dir     = "./model/CatBoost_R_output", #- 모델링 한 결과를 저장할 directory
                iterations    = 1000,                         #- 학습 iteration 수
                metric_period = 10)            
)           

catboost_imp           <- data.frame(model2$feature_importances)
catboost_imp$variables <- rownames(model2$feature_importances)
colnames(catboost_imp) <- c("importance", 'variables')
catboost_imp           <- catboost_imp %>% arrange(-importance)
View(catboost_imp)
catboost_imp$variables

real_pool    <- catboost.load_pool(testData_cat)
YHat_cat_2   <- catboost.predict(
  model2, 
  real_pool,
  prediction_type = c('Probability'))  # Probability, Class

set.seed(2020)
model3 <- catboost.train(
  train_pool,                                  #- 학습에 사용하고자 하는 train_pool  
  NULL,                                        #- 
  params = list(loss_function = 'Logloss',     #- loss function 지정(여기서는 분류모형이므로 Logloss)
                random_seed   = 2020,           #- seed number
                custom_loss   = "AUC",         #- 모델링 할 때 추가로 추출할 값들 (train_dir로 지정한 곳으로 해당 결과를 파일로 내보내준다)
                train_dir     = "./model/CatBoost_R_output", #- 모델링 한 결과를 저장할 directory
                iterations    = 1000,                         #- 학습 iteration 수
                metric_period = 10)            
)           

catboost_imp           <- data.frame(model3$feature_importances)
catboost_imp$variables <- rownames(model3$feature_importances)
colnames(catboost_imp) <- c("importance", 'variables')
catboost_imp           <- catboost_imp %>% arrange(-importance)
View(catboost_imp)
catboost_imp$variables

real_pool    <- catboost.load_pool(testData_cat)
YHat_cat_3   <- catboost.predict(
  model3, 
  real_pool,
  prediction_type = c('Probability'))  # Probability, Class

AUC_catboost_1 <- mkAUCValue(
  YHat = YHat_cat_1, 
  Y    = ifelse(testData$voted == 2, 1, 0))

AUC_catboost_2 <- mkAUCValue(
  YHat = YHat_cat_2, 
  Y    = ifelse(testData$voted == 2, 1, 0))

AUC_catboost_3 <- mkAUCValue(
  YHat = YHat_cat_3, 
  Y    = ifelse(testData$voted == 2, 1, 0))

AUC_catboost <- mkAUCValue(
  YHat = (YHat_cat_1 + YHat_cat_2 + YHat_cat_3) / 3, 
  Y    = ifelse(testData$voted == 2, 1, 0))



caret::confusionMatrix(
  factor(YHat_cat),
  factor(ifelse(testData$voted == 2, 1, 0))
)

AUC_catboost <- mkAUCValue(
  YHat = YHat_cat, 
  Y    = ifelse(testData$voted == 2, 1, 0))

#- 투표를 했는데,(Yes, 0), 투표를 하지 않았다고 예측한 경우,(No, 1)
testData_wrongNo  <- testData[!YHat_cat  == ifelse(testData$voted == 2, 1, 0),] %>% filter(voted == 1)  
save(testData_wrongNo, file = "testData_wrongNo_CatBoost.RData")

#- 투표를 하지 않았는데(No, 1), 투표를 했다고 예측한 경우, (Yes, 0)
testData_wrongYes <- testData[!YHat_cat  == ifelse(testData$voted == 2, 1, 0),] %>% filter(voted == 2)
save(testData_wrongYes, file = "testData_wrongYes_CatBoost.RData")

####################
## final assemble ##
####################
AUC_final <- mkAUCValue(
  YHat = (YHat_cat_1 + YHat_cat_2 + YHat_cat_3) / 3, 
  Y    = ifelse(testData$voted == 2, 1, 0))

sample_submission$voted <- (YHat_cat_1 + YHat_cat_2 + YHat_cat_3) / 3
write.csv(sample_submission, "submission_data.csv", row.names = F)