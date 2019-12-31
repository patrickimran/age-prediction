# ---
# title: "age prediction/classification in the multiple datasets"
# author: "ShiHuang"
# date: "8/6/2019"
# output: html_document
# ---
#-------------------------------
# install and load necessary libraries for data analyses
#-------------------------------
## install.packages('devtools') # if devtools not installed
## devtools::install_github('shihuang047/crossRanger')
p <- c("reshape2","ggplot2", "dplyr", "biomformat", "devtools", "crossRanger", "viridis")
usePackage <- function(p) {
  if (!is.element(p, installed.packages()[,1]))
    install.packages(p, dep=TRUE, repos="https://cloud.r-project.org/")
  suppressWarnings(suppressMessages(invisible(require(p, character.only=TRUE))))
}
invisible(lapply(p, usePackage))
#-------------------------------
# input args
#-------------------------------
setwd("/Users/huangshi/MyProjects/CMI-IBM/age-prediction/")
#-------------------------------
datafile<-"Input/skin_data/skin_4168.biom" # gut_data/gut_4575_rare.biom | oral_data/oral_4014.biom | skin_data/skin_4168.biom
sample_metadata <- "Input/skin_data/skin_4168_map.txt" # gut_data/gut_4575_rare_map.txt | oral_data/oral_4014_map.txt | skin_data/skin_4168_map.txt 
feature_metadata<-"Input/skin_data/skin_taxonomy.txt" # gut_data/gut_taxonomy.txt | oral_data/oral_taxonomy.txt |
prefix_name<-"skin_4168" # gut_4575 | oral_4014 | skin_4168
s_category<-c("body_site","qiita_host_sex")  # c("cohort", "sex") | "qiita_host_sex" | c("body_site","qiita_host_sex") 
c_category<-"qiita_host_age"  #"age" "qiita_host_age" "qiita_host_age"
outpath <- "./Output/skin_4168_by_site_sex_RF.reg_out/" # ./Output/gut_4575_by_cohort_sex_RF.reg_out/ ./Output/oral_4014_by_sex_RF.reg_out/ ./Output/skin_4168_by_site_sex_RF.reg_out
dir.create(outpath)

#-------------------------------
# Biom table input
#-------------------------------
if(grepl("biom$", datafile)){
  biom <- read_biom(datafile)
  df <- data.frame(t(as.matrix(biom_data(biom))))
}else{
  df<-read.table(datafile, header=T, row.names=1, sep="\t", quote="", comment.char = "")
}

df<-df[order(rownames(df)),order(colnames(df))]
 #df<-sweep(df, 1, rowSums(df), "/")
#-------------------------------
# Feature metadata input
#-------------------------------
fmetadata<-read.table(feature_metadata,header=T,sep="\t")
add_ann<-function(tab, fmetadata, tab_id_col=1, fmetadata_id_col=1){
  matched_idx<-which(fmetadata[, fmetadata_id_col] %in% tab[, tab_id_col])
  uniq_features_len<-length(unique(tab[, tab_id_col]))
  if(uniq_features_len>length(matched_idx)){
    warning("# of features has no matching IDs in the taxonomy file: ", uniq_features_len-length(matched_idx), "\n")
  }
  fmetadata_matched<-fmetadata[matched_idx,]
  out<-merge(tab, fmetadata_matched, by.x=tab_id_col, by.y=fmetadata_id_col)
  out
}
rbind.na<-function(l){
  max_len<-max(unlist(lapply(l, length)))
  c_l<-lapply(l, function(x) {c(x, rep(NA, max_len - length(x)))})
  do.call(rbind, c_l)
}
expand_Taxon<-function(df, Taxon){
  taxa_df <- rbind.na(strsplit(as.character(df[, Taxon]), '; '))
  colnames(taxa_df) <- c("kingdom","phylum","class","order","family","genus","species") #"kingdom", 
  data.frame(df, taxa_df)
}
#-------------------------------
# Sample Metadata input
#-------------------------------
allmetadata<-read.table(sample_metadata,header=T,sep="\t",row.names=1, quote="", comment.char="")
if(length(allmetadata)==1){
  metadata<-data.frame(allmetadata[order(rownames(allmetadata)),])
  all_group<-colnames(metadata)<-colnames(allmetadata)
}else{
  metadata<-allmetadata[order(rownames(allmetadata)), ]
}
#-------------------------------
# Matching SampleID between biom data and metadata
#-------------------------------
## check if the order of rownames in the microbiome data and sample metadata are identical:
identical(rownames(df),rownames(metadata))
cat("The number of samples in biom table : ", nrow(df) ,"\n")
cat("The number of samples in metadata : ", nrow(metadata) ,"\n")

shared_idx<-intersect(rownames(df), rownames(metadata))
df<-df[shared_idx, ]
cat("The number of samples in biom (after filtering out samples with no metadata): ", nrow(df) ,"\n")
metadata<-metadata[shared_idx, ]
cat("The number of samples in metadata (after filtering out samples with no metadata): ", nrow(metadata) ,"\n")
identical(rownames(df),rownames(metadata))

#-------------------------------
# To filter out samples with null values in both s and c categories
#-------------------------------
metadata_k<-metadata[which(!apply(metadata[, c(s_category, c_category)], 1,function(x) any(x==""))), ]
if(length(s_category)>1){
  metadata_k[, s_category]<-lapply(metadata_k[, s_category], factor)
}else{
  metadata_k[, s_category]<-factor(metadata_k[, s_category])
}
df_k<-df[rownames(metadata_k), ]

#-------------------------------
# fitler variables in microbiota data
#-------------------------------
#-------------------------------
cat("The number of samples : ", nrow(df_k) ,"\n")
cat("The number of variables : ", ncol(df_k) ,"\n")
#-------------------------------
#-------------------------------filtering taxa with zero variance
df_k<-df_k[,which(apply(df_k,2,var)!=0)]
cat("The number of fitlered variables (removed variables with zero variance) : ", ncol(df_k) ,"\n")
#-------------------------------filtering taxa with X% non-zero values
NonZero.p<-0.999
df_k<-df_k[,which(colSums(df_k==0)<NonZero.p*nrow(df_k))]
cat("The number of variables (removed variables containing over ", NonZero.p," zero) in training data: ", ncol(df_k) ,"\n")

#-------------------------------
# To creat a combined category if the length of s_category over 2
#-------------------------------
if(length(s_category)>=2){
  new_s_category<-paste0(s_category, collapse ="__")
  metadata[, new_s_category]<-do.call(paste, c(metadata[s_category], sep="_"))
  metadata_k[, new_s_category]<-do.call(paste, c(metadata_k[s_category], sep="_"))
  s_category=new_s_category
}
#-------------------------------
# rf_reg using all datasets
#-------------------------------
x=df_k
# convert the y to a numberical variable
if(!is.numeric(metadata_k[, c_category])){
  y=metadata_k[, c_category]=as.numeric(as.character(metadata_k[, c_category]))
}else{
  y=metadata_k[, c_category]
}

all_res_file<-paste(outpath, prefix_name, "_rf_reg_all_res.RData", sep="")
if(file.exists(all_res_file)){
  rf_all <- get(load(all_res_file))
}else{
  rf_all<-rf.cross.validation(x=x, y=y, ntree = 500, nfolds = 5)
  save(rf_all, file=all_res_file)
}

plot_obs_VS_pred(rf_all$y, rf_all$predicted, prefix="train", target_field="age", span=1, outdir = outpath)
plot_perf_VS_rand(rf_all$y, rf_all$predicted, prefix="train", target_field="age", n_features=ncol(x), permutation = 1000, outdir = outpath)
plot_reg_feature_selection(x=x, y=rf_all$y, rf_all, outdir = outpath)

#-------------------------------
# rf_reg.by_datasets
#-------------------------------
## "rf_reg.by_datasets" runs standard random forests with oob estimation for regression of 
## c_category in each the sub-datasets splited by the s_category. 
## The output includes a summary of rf models in the sub datasets
## and all important statistics for each of features.

res_file<-paste(outpath, prefix_name, "_rf_reg.by_datasets_res.RData", sep="")
if(file.exists(res_file)){
  load(res_file)
}else{
  rf_reg_res<-rf_reg.by_datasets(df_k, metadata_k, s_category, c_category,
                                 nfolds=3, verbose=FALSE, ntree=500)
  save(rf_reg_res, file=res_file)
}
## replace imp scores 0 with NA for features whose prevelance equal to 0 
for(i in 1:length(rf_reg_res$feature_imps_list)) {
  rf_reg_res$feature_imps_list[[i]][colSums(rf_reg_res$x_list[[i]])==0]<-NA
}
rf_reg_res$feature_imps_rank_list<-lapply(rf_reg_res$feature_imps_list, function(i) rank(-i, na.last = "keep"))
rf_reg_res.summ<-plot.reg_res_list(rf_reg_res, outdir=outpath)
feature_res<-rf_reg_res.summ$feature_res
feature_res_rank<-apply(feature_res, 2, function(x) rank(-x, na.last = "keep"))
rf_models<-rf_reg_res$rf_model_list
# Add feature annotations using feature metadata
feature_res<-add_ann(data.frame(feature=rownames(feature_res), feature_res), fmetadata)
feature_res_rank<-add_ann(data.frame(feature=rownames(feature_res_rank), feature_res_rank), fmetadata)
#sink(paste(outpath,"feature_imps_all.xls",sep=""));write.table(feature_res,quote=FALSE,sep="\t", row.names = F);sink()
#sink(paste(outpath,"feature_imps_rank_all.xls",sep=""));write.table(feature_res_rank,quote=FALSE,sep="\t", row.names = F);sink()

# Feature selection in all sub-datasets
# RF regression performance VS number of features used
# Prediction performances at increasing number of microbial species obtained by 
# retraining the random forest regressor on the top-ranking features identified 
# with a first random forest model training in a cross-validation setting
if(file.exists(paste(outpath,"crossRF_feature_selection_summ.xls",sep=""))){
top_n_perf_list<-list()
for(n in 1:length(rf_reg_res$rf_model_list)){
  top_n_perf<-matrix(NA, ncol=5, nrow=11)
  max_n<-max(rf_reg_res$feature_imps_rank_list[[n]], na.rm = TRUE)
  n_features<-c(2, 4, 8, 16, 32, 64, 128, 256, 512, 1024)
  colnames(top_n_perf)<-c("n_features", "MSE", "RMSE", "MAE", "MAE_perc")
  rownames(top_n_perf)<-top_n_perf[,1]<-c(n_features, max_n)
  cat("Dataset: ", names(rf_reg_res$feature_imps_rank_list)[n], "\n")
  for(i in 1:length(n_features)){
    idx<-which(rf_reg_res$feature_imps_rank_list[[n]]<=n_features[i])
    x_n<-rf_reg_res$x_list[[n]][, idx]
    y_n<-rf_reg_res$y_list[[n]]
    top_n_rf<-rf.out.of.bag(x_n, y_n, ntree=500)
    top_n_perf[i, 1]<-n_features[i]
    top_n_perf[i, 2]<-top_n_rf$MSE
    top_n_perf[i, 3]<-top_n_rf$RMSE
    top_n_perf[i, 4]<-top_n_rf$MAE
    top_n_perf[i, 5]<-top_n_rf$MAE_perc
  }
  top_n_perf[11, ]<-c(max_n, rf_reg_res$rf_MSE[n], rf_reg_res$rf_RMSE[n], rf_reg_res$rf_MAE[n], rf_reg_res$rf_MAE_perc[n])
  top_n_perf_list[[n]]<-top_n_perf
}
names(top_n_perf_list)<-names(rf_reg_res$rf_model_list)
top_n_perf_list<-lapply(1:length(top_n_perf_list), 
                        function(x) data.frame(Dataset=rep(names(top_n_perf_list)[x], nrow(top_n_perf_list[[x]])), top_n_perf_list[[x]]))
top_n_perf_comb<-do.call(rbind, top_n_perf_list)
top_n_perf_comb$n_features<-as.numeric(as.character(top_n_perf_comb$n_features))
top_n_perf_comb_m<-melt(top_n_perf_comb, id.vars = c("n_features", "Dataset"))
breaks<-top_n_perf_comb_m$n_features

p<-ggplot(subset(top_n_perf_comb_m, variable=="MAE"), aes(x=n_features, y=value)) + 
  xlab("# of features used")+
  ylab("MAE (yrs)")+
  scale_x_continuous(trans = "log",breaks=breaks)+
  geom_point(aes(color=Dataset)) + geom_line(aes(color=Dataset)) +#facet_wrap(~Dataset) +
  theme_bw()+
  theme(axis.line = element_line(color="black"),
        axis.title = element_text(size=18),
        strip.background = element_rect(colour = "white"), 
        panel.border = element_blank())
ggsave(filename=paste(outpath,"MAE__top_rankings.scatterplot.pdf",sep=""), plot=p, width=6, height=4)
sink(paste(outpath,"crossRF_feature_selection_summ.xls",sep=""));write.table(top_n_perf_comb,quote=FALSE,sep="\t", row.names = F);sink()
}

#-------------------------------
# rf_reg.cross_appl
#-------------------------------
# "rf_reg.cross_appl" runs standard random forests with oob estimation for regression of 
# c_category in each the sub-datasets splited by the s_category, 
# and apply the model to all the other datasets. 

crossRF_res<-rf_reg.cross_appl(rf_reg_res, rf_reg_res$x_list, rf_reg_res$y_list)
perf_summ<-crossRF_res$perf_summ
sink(paste(outpath,"crossRF_reg_perf_summ.xls",sep=""));write.table(perf_summ,quote=FALSE,sep="\t", row.names = F);sink()

#' The performance (MAE) of cross-applications  
#' The heatmap indicating MAE in the self-validation and cross-applications  
self_validation=as.factor(perf_summ$Train_data==perf_summ$Test_data)
library(viridis)
p_MAE<-ggplot(perf_summ, aes(x=as.factor(Test_data), y=as.factor(Train_data), z=MAE)) + 
  xlab("Test data")+ylab("Train data")+
  geom_tile(aes(fill = MAE, color = self_validation, width=0.9, height=0.9), size=1) + #
  scale_color_manual(values=c("white","grey80"))+
  geom_text(aes(label = round(MAE, 2)), color = "white") +
  scale_fill_viridis()+ 
  theme_bw() + theme_classic() +
  theme(axis.line = element_blank(), axis.text.x = element_text(angle = 90),
        axis.ticks = element_blank())
p_MAE
ggsave(filename=paste(outpath,"MAE_cross_appl_matrix_",c_category, "_among_", s_category,".heatmap.pdf",sep=""),plot=p_MAE, width=5, height=4)

#' The scatter plot matrix showing predicted and observed values in the self-validation and cross-applications 
predicted_summ<-dplyr::bind_rows(crossRF_res$predicted, .id = "Train_data__VS__test_data")
tmp<-data.frame(do.call(rbind, strsplit(predicted_summ$Train_data__VS__test_data, "__VS__")))
colnames(tmp)<-c("Train_data", "Test_data")
self_validation=as.factor(tmp$Train_data==tmp$Test_data)
predicted_summ<-data.frame(tmp, self_validation, predicted_summ)

#l<-levels(data$sex); l_sorted<-sort(levels(data$sex))
Mycolor <- c("#0072B2", "#D55E00") 
#if(identical(order(l), order(l_sorted))){Mycolor=Mycolor }else{Mycolor=rev(Mycolor)}
target_variable="age"
p_scatter<-ggplot(predicted_summ, aes(x=test_y, y=pred_y))+
         ylab(paste("Predicted ",target_variable,sep=""))+
         xlab(paste("Observed ",target_variable,sep=""))+
         geom_point(aes(color=self_validation), alpha=0.1)+
         geom_smooth(aes(color=self_validation), method="loess",span=1)+
         scale_color_manual(values = Mycolor)+
         facet_grid(Train_data~Test_data)+
        theme_bw()+
        theme(axis.line = element_line(color="black"),
        strip.background = element_rect(colour = "white"),
        panel.border = element_blank())+
        theme(legend.position="none")
p_scatter
ggsave(filename=paste(outpath,"Scatterplot_cross_appl_matrix_",c_category, "_among_", s_category,".pdf",sep=""),plot=p_scatter, width=8, height=8)


