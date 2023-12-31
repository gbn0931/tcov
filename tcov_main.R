#############################################################################
### Generate most cost-effective testing option under different scenarios ###
#############################################################################

set.seed(1876543)
alea = TRUE
Nsamples <- 1000
cost_side <- "median" ## Choose scenario for the cost of side-effects
# cost_side <- "low"
# cost_side <- "high"
  
screencost = FALSE # Include/exclude screening cost differential.
severe_effects = TRUE # Include severe corticosteroid side-effects.
mild_effects = TRUE # Include mild corticosteroid side-effects.
PCRavailable = TRUE ## Choose TRUE to compare all options, including the use of PCR alone or as a means of confirming an RDT test results.
NoVenti = FALSE ## Include scenarios in which mechanical ventilation is unavailable if true. This will include those scenarios for all options considered, including in deterministic sensitivity analysis. 
  
path.io <- "./Outputs/"
path.dat <- "./data/"  
  
###################################################################
  
  source("tcov_gen_samp.R") ### generates generic parameters
  source("tcov_gen_country_samp.R") ### generates country-specific parameters
  source("tcov_gen_useful_params.R") ### computes useful parameters
  source("tcov_tree.R") ### generates the decision tree
  source("tcov_gen_figures.R") ### generates the figures
  
  require("data.table") 
  require("tidyverse")
  require("ggplot2")
  require("readxl")
  require("lhs")
  
##################################################################
  
  start_time <- Sys.time()
  
  
### Importing parameters and their distributions 
### (the different options are meant to speed the program when not running uncommon scenarios)
  
library(readxl)
general_params <- read_excel("./Data/Parameters.xlsx", sheet = "General parameters")
country_params <- as.data.table(read_excel("./Data/Parameters.xlsx", sheet = "Country parameters"))
ifelse(PCRavailable==TRUE,
        ifelse(NoVenti==TRUE,
                tcov_trees <- as.data.table(read_excel("./Data/Parameters.xlsx", sheet = "Branches")),
                tcov_trees <- as.data.table(read_excel("./Data/Parameters.xlsx", sheet = "BranchesNoVenti"))),
        ifelse(NoVenti==TRUE,
                tcov_trees <- as.data.table(read_excel("./Data/Parameters.xlsx", sheet = "BranchesNoPCR")),
                tcov_trees <- as.data.table(read_excel("./Data/Parameters.xlsx", sheet = "BranchesNoPCRorVenti"))))
  
  
Nparams <- ncol(general_params)
Ncountries <- nrow(country_params)
Nrandparcountry <- 12
  
### Generating parameter scenarios for selected country
  
require("lhs")
A <- randomLHS(Nparams+Nrandparcountry,Nsamples)
  
  
  samp_gen <- gen_sample(Nparams, Nsamples,general_params,A) # Create a sample of general parameters
  samp_gen[,Life_Exp_HF:=gen_disc_YLL(Life_Exp_HF,Health_discount)][,Delayed_sepsis_time:=gen_disc_YLL(Delayed_sepsis_time,Health_discount)][,Time_TB_Disease_years:=gen_disc_YLL(Time_TB_Disease_years,Health_discount)]
  
  prevalences <- data.table(pcov=seq(0,0.3, by = 0.01))
  
  
  Synthesis_total <- list()

#########################################################################################  
### Selecting sensitivity analyses
  
  for(k in 1:6){                               # use other values of k to analyze more/fewer scenarios
    
    # Different options for the cost of generic side-effects
    if(k==2){cost_side = "low"} else if(k==3) {cost_side = "high"} else{cost_side = "median"}
    
    # Integrating disease-specific corticosteroid side-effects
    if(k==4){samp_gen[,Disease_spec_mort_risk_cortico:=as.numeric(general_params$Disease_spec_mort_risk_cortico[5])]} else{samp_gen[,Disease_spec_mort_risk_cortico:=as.numeric(general_params$Disease_spec_mort_risk_cortico[1])]}
    
    # Explore different costs for IL6 receptor blockers
    if(k==5){samp_gen[,Cost_IL6:=as.numeric(general_params$Cost_IL6[5])]} else if(k==6){samp_gen[,Cost_IL6:=as.numeric(general_params$Cost_IL6[6])]} else{samp_gen[,Cost_IL6:=as.numeric(general_params$Cost_IL6[1])]}
    
    # Explore treatment refusal
    if(k==7){samp_gen[,Treat_refusal_severe:=as.numeric(general_params$Treat_refusal_severe[5])]} else if(k==8){samp_gen[,Treat_refusal_severe:=as.numeric(general_params$Treat_refusal_severe[6])]} else{samp_gen[,Treat_refusal_severe:=as.numeric(general_params$Treat_refusal_severe[1])]}
    
    # Explore other RDT sensitivity
    if(k==9){samp_gen[,RDT_sensi:=as.numeric(general_params$RDT_sensi[5])]} else if(k==10){samp_gen[,RDT_sensi:=as.numeric(general_params$RDT_sensi[6])]} else if(k==11){samp_gen[,RDT_sensi:=0.9]} else{samp_gen[,RDT_sensi:=as.numeric(general_params$RDT_sensi[1])]}
    
    # With health discounting
    if(k==12){samp_gen[,Health_discount:=as.numeric(general_params$Health_discount[5])]} else{samp_gen[,Health_discount:=as.numeric(general_params$Health_discount[1])]}
    
    # with substantial added screening costs
    if(k==13){screencost=TRUE} else{screencost=FALSE}
    
    # if RDT test kits were cheaper, more expensive or free
    if(k==14){samp_gen[,Cost_RDT_testkit:=as.numeric(general_params$Cost_RDT_testkit[5])]} else if(k==15){samp_gen[,Cost_RDT_testkit:=as.numeric(general_params$Cost_RDT_testkit[6])]} else
      if(k==16){samp_gen[,Cost_RDT_testkit:=0]}
    else{samp_gen[,Cost_RDT_testkit:=as.numeric(general_params$Cost_RDT_testkit[1])]}
    
    # With positive or negative impacts of treatment on post-COVID  
    if(k==17){samp_gen[,DALYs_postCov_Treat_Impact:=as.numeric(general_params$DALYs_postCov_Treat_Impact[5])]} else
      if(k==18){samp_gen[,DALYs_postCov_Treat_Impact:=as.numeric(general_params$DALYs_postCov_Treat_Impact[6])]}
    else{samp_gen[,DALYs_postCov_Treat_Impact:=as.numeric(general_params$DALYs_postCov_Treat_Impact[1])]}
    
    # Assuming no severe health side-effects/no severe or mild side-effects 
    if(k==19){severe_effects=FALSE 
    mild_effects=FALSE} else {severe_effects=TRUE
    mild_effects=TRUE}
    
##################################################################################################
    
### Running the model for all countries (all samples are computed simultaneously for each country)
  country_code_list = country_params[,1][[1]]
    
  Tree_countryNMB <- list()
  Tree_countryIL6 <- list()
  Tree_countryVenti <- list()
  Tree_countryOxy <- list()
    i=0
    
    for(countryCode in country_code_list){
      i=i+1
      income <- country_params[,.SD[which(Code==countryCode)]]$Num_Income
      samp_c <- gen_country_sample(Nparams, Nsamples,country_params,A,countryCode,cost_side,samp_gen) # 
     
       #Creates a sample of country-specific parameters
      paramite <- as.data.table(gen_useful_params(samp_gen,samp_c))[,country:=countryCode][,Income_level:=income][,s:=1:Nsamples]
      Tree_1country <- setkey(paramite[,c(k=1,.SD)],k)[tcov_trees[,c(k=1,.SD)],allow.cartesian=TRUE][,k:=NULL]
      Tree_1country <- setkey(Tree_1country[,c(k=1,.SD)],k)[prevalences[,c(k=1,.SD)],allow.cartesian=TRUE][,k:=NULL]
      interm <- gen_tree(Tree_1country) 
      Tree_countryNMB[[i]] <- interm[[1]]
      Tree_countryIL6[[i]] <- interm[[2]]
      Tree_countryVenti[[i]] <- interm[[3]]
      if(NoVenti==TRUE){ 
        Tree_countryOxy[[i]] <- gen_tree(Tree_1country)[[4]]
      }
    }
    Tree_countriesNMB <- rbindlist(Tree_countryNMB)
    Tree_countriesIL6 <- rbindlist(Tree_countryIL6)
    Tree_countriesVenti <- rbindlist(Tree_countryVenti)
    if(NoVenti==TRUE){ 
      Tree_countriesOxy <- rbindlist(Tree_countryOxy)
    }
    
####################################################################################
    
### Putting results for this scenario with other results for other choices in the sensitivity analyses
    k_list <- list()
    
    k_list[[1]] <- Tree_countriesNMB
    k_list[[2]] <- dcast( Tree_countriesIL6[, .SD[which.max(perIL6)], by=.(country,Income_level,pcov)][,.(per=.N),by=.(pcov,Income_level,Optscen_VentiIL6)], Income_level + Optscen_VentiIL6 ~ pcov,value.var="per")
    k_list[[3]] <- dcast( Tree_countriesVenti[, .SD[which.max(perVenti)], by=.(country,Income_level,pcov)][,.(per=.N),by=.(pcov,Income_level,Optscen_Venti)], Income_level + Optscen_Venti ~ pcov,value.var="per")
    if(NoVenti==TRUE){ 
      k_list[[4]] <- dcast( Tree_countriesOxy[, .SD[which.max(perOxy)], by=.(country,Income_level,pcov)][,.(per=.N),by=.(pcov,Income_level,Optscen_Oxy)], Income_level + Optscen_Oxy ~ pcov,value.var="per")
    }
    
    
    Synthesis_total[[k]] <- k_list
  }
  
  ####################################################################################
  
  ### Generating the outcomes in excel (if desired)
  
  library("writexl")
  # Creating files for net monetary benefit and most cost-effective options with/without IL6 receptor blocker availability
 write_xlsx(Synthesis_total[[1]][[1]],paste0(path.io,"tcov_synthNMB.xlsx"))
 write_xlsx(Synthesis_total[[1]][[2]],paste0(path.io,"tcov_synthIL6.xlsx"))
 write_xlsx(Synthesis_total[[1]][[3]],paste0(path.io,"tcov_synthCorti.xlsx"))
 write_xlsx(Synthesis_total[[2]][[1]],paste0(path.io,"tcov_lowsideNMB.xlsx"))
 write_xlsx(Synthesis_total[[2]][[2]],paste0(path.io,"tcov_lowsideIL6.xlsx"))
 write_xlsx(Synthesis_total[[2]][[3]],paste0(path.io,"tcov_lowsideCorti.xlsx"))
 write_xlsx(Synthesis_total[[3]][[1]],paste0(path.io,"tcov_highsideNMB.xlsx"))
 write_xlsx(Synthesis_total[[3]][[2]],paste0(path.io,"tcov_highsideIL6.xlsx"))
 write_xlsx(Synthesis_total[[3]][[3]],paste0(path.io,"tcov_highsideCorti.xlsx"))
 write_xlsx(Synthesis_total[[4]][[2]],paste0(path.io,"tcov_dispecsideNMB.xlsx"))
 write_xlsx(Synthesis_total[[4]][[2]],paste0(path.io,"tcov_dispecsideIL6.xlsx"))
 write_xlsx(Synthesis_total[[4]][[3]],paste0(path.io,"tcov_dispecsideCorti.xlsx"))
 write_xlsx(Synthesis_total[[5]][[1]],paste0(path.io,"tcov_CostIL6lowNMB.xlsx"))
 write_xlsx(Synthesis_total[[5]][[2]],paste0(path.io,"tcov_CostIL6lowIL6.xlsx"))
 write_xlsx(Synthesis_total[[5]][[3]],paste0(path.io,"tcov_CostIL6lowCorti.xlsx"))
 write_xlsx(Synthesis_total[[6]][[1]],paste0(path.io,"tcov_CostIL6highNMB.xlsx"))
 write_xlsx(Synthesis_total[[6]][[2]],paste0(path.io,"tcov_CostIL6highIL6.xlsx"))
 write_xlsx(Synthesis_total[[6]][[3]],paste0(path.io,"tcov_CostIL6highCorti.xlsx"))
 #write_xlsx(Synthesis_total[[7]][[1]],paste0(path.io,"tcov_30pcTreatRefuseNMB.xlsx"))
 #write_xlsx(Synthesis_total[[7]][[2]],paste0(path.io,"tcov_30pcTreatRefuseIL6.xlsx"))
 #write_xlsx(Synthesis_total[[7]][[3]],paste0(path.io,"tcov_30pcTreatRefuseCorti.xlsx"))
 #write_xlsx(Synthesis_total[[8]][[1]],paste0(path.io,"tcov_60pcTreatRefuseNMB.xlsx"))
 #write_xlsx(Synthesis_total[[8]][[2]],paste0(path.io,"tcov_60pcTreatRefuseIL6.xlsx"))
 #write_xlsx(Synthesis_total[[8]][[3]],paste0(path.io,"tcov_60pcTreatRefuseCorti.xlsx"))
 #write_xlsx(Synthesis_total[[9]][[1]],paste0(path.io,"tcov_60pcRDTsensiNMB.xlsx"))
 #write_xlsx(Synthesis_total[[9]][[2]],paste0(path.io,"tcov_60pcRDTsensiIL6.xlsx"))
 #write_xlsx(Synthesis_total[[9]][[3]],paste0(path.io,"tcov_60pcRDTsensiCorti.xlsx"))
 #write_xlsx(Synthesis_total[[10]][[1]],paste0(path.io,"tcov_40pcRDTsensiNMB.xlsx"))
 #write_xlsx(Synthesis_total[[10]][[2]],paste0(path.io,"tcov_40pcRDTsensiIL6.xlsx"))
 #write_xlsx(Synthesis_total[[10]][[3]],paste0(path.io,"tcov_40pcRDTsensiCorti.xlsx"))
 #write_xlsx(Synthesis_total[[11]][[1]],paste0(path.io,"tcov_90pcRDTsensiNMB.xlsx"))
 #write_xlsx(Synthesis_total[[11]][[2]],paste0(path.io,"tcov_90pcRDTsensiIL6.xlsx"))
 #write_xlsx(Synthesis_total[[11]][[3]],paste0(path.io,"tcov_90pcRDTsensiCorti.xlsx"))
 #write_xlsx(Synthesis_total[[12]][[1]],paste0(path.io,"tcov_3pcHealthDiscountNMB.xlsx"))
 #write_xlsx(Synthesis_total[[12]][[2]],paste0(path.io,"tcov_3pcHealthDiscountIL6.xlsx"))
 #write_xlsx(Synthesis_total[[12]][[3]],paste0(path.io,"tcov_3pcHealthDiscountCorti.xlsx"))
 #write_xlsx(Synthesis_total[[13]][[1]],paste0(path.io,"tcov_highScreenCostsNMB.xlsx"))
 #write_xlsx(Synthesis_total[[13]][[2]],paste0(path.io,"tcov_highScreenCostsIL6.xlsx"))
 #write_xlsx(Synthesis_total[[13]][[3]],paste0(path.io,"tcov_highScreenCostsCorti.xlsx"))
 #write_xlsx(Synthesis_total[[14]][[1]],paste0(path.io,"tcov_lowRDTKitCostsNMB.xlsx"))
 #write_xlsx(Synthesis_total[[14]][[2]],paste0(path.io,"tcov_lowRDTKitCostsIL6.xlsx"))
 #write_xlsx(Synthesis_total[[14]][[3]],paste0(path.io,"tcov_lowRDTKitCostsCorti.xlsx"))
 #write_xlsx(Synthesis_total[[15]][[1]],paste0(path.io,"tcov_highRDTKitCostsNMB.xlsx"))
 #write_xlsx(Synthesis_total[[15]][[2]],paste0(path.io,"tcov_highRDTKitCostsIL6.xlsx"))
 #write_xlsx(Synthesis_total[[15]][[3]],paste0(path.io,"tcov_highRDTKitCostsCorti.xlsx"))
 #write_xlsx(Synthesis_total[[16]][[1]],paste0(path.io,"tcov_freeRDTKitsNMB.xlsx"))
 #write_xlsx(Synthesis_total[[16]][[2]],paste0(path.io,"tcov_freeRDTKitsIL6.xlsx"))
 #write_xlsx(Synthesis_total[[16]][[3]],paste0(path.io,"tcov_freeRDTKitsCorti.xlsx"))
 #write_xlsx(Synthesis_total[[17]][[1]],paste0(path.io,"tcov_decreasePostCoVNMB.xlsx"))
 #write_xlsx(Synthesis_total[[17]][[2]],paste0(path.io,"tcov_decreasePostCoVIL6.xlsx"))
 #write_xlsx(Synthesis_total[[17]][[3]],paste0(path.io,"tcov_decreasePostCoVCorti.xlsx"))
 #write_xlsx(Synthesis_total[[18]][[1]],paste0(path.io,"tcov_increasePostCoVNMB.xlsx"))
 #write_xlsx(Synthesis_total[[18]][[2]],paste0(path.io,"tcov_increasePostCoVIL6.xlsx"))
 #write_xlsx(Synthesis_total[[18]][[3]],paste0(path.io,"tcov_increasePostCoVCorti.xlsx"))
 #write_xlsx(Synthesis_total[[19]][[1]],paste0(path.io,"tcov_noSideEffectNMB.xlsx"))
 #write_xlsx(Synthesis_total[[19]][[2]],paste0(path.io,"tcov_noSideEffectIL6.xlsx"))
 #write_xlsx(Synthesis_total[[19]][[3]],paste0(path.io,"tcov_noSideEffectCorti.xlsx"))
 
if(NoVenti==TRUE){ 
# Creating files for scenarios when mechanical ventilation is unavailable
write_xlsx(Synthesis_total[[1]][[4]],paste0(path.io,"tcov_synthNoMV.xlsx"))
write_xlsx(Synthesis_total[[2]][[4]],paste0(path.io,"tcov_lowsideNoMV.xlsx"))
write_xlsx(Synthesis_total[[3]][[4]],paste0(path.io,"tcov_highsideNoMV.xlsx"))
write_xlsx(Synthesis_total[[4]][[4]],paste0(path.io,"tcov_dispecsideNoMV.xlsx"))
write_xlsx(Synthesis_total[[5]][[4]],paste0(path.io,"tcov_CostIL6lowNoMV.xlsx"))
write_xlsx(Synthesis_total[[6]][[4]],paste0(path.io,"tcov_CostIL6highNoMV.xlsx"))
#write_xlsx(Synthesis_total[[7]][[4]],paste0(path.io,"tcov_30pcTreatRefusehNoMV.xlsx"))
#write_xlsx(Synthesis_total[[8]][[4]],paste0(path.io,"tcov_60pcTreatRefuseNoMV.xlsx"))
#write_xlsx(Synthesis_total[[9]][[4]],paste0(path.io,"tcov_60pcRDTsensiNoMV.xlsx"))
#write_xlsx(Synthesis_total[[10]][[4]],paste0(path.io,"tcov_40pcRDTsensiNoMV.xlsx"))
#write_xlsx(Synthesis_total[[11]][[4]],paste0(path.io,"tcov_90pcRDTsensiNoMV.xlsx"))
#write_xlsx(Synthesis_total[[12]][[4]],paste0(path.io,"tcov_3pcHealthDiscountNoMV.xlsx"))
#write_xlsx(Synthesis_total[[13]][[4]],paste0(path.io,"tcov_highScreenCostsNoMV.xlsx"))
#write_xlsx(Synthesis_total[[14]][[4]],paste0(path.io,"tcov_lowRDTKitCostsNoMV.xlsx"))
#write_xlsx(Synthesis_total[[15]][[4]],paste0(path.io,"tcov_highRDTKitCostsNoMV.xlsx"))
#write_xlsx(Synthesis_total[[16]][[4]],paste0(path.io,"tcov_freeRDTKitsNoMV.xlsx"))
#write_xlsx(Synthesis_total[[17]][[4]],paste0(path.io,"tcov_decreasePostCoVNoMV.xlsx"))
#write_xlsx(Synthesis_total[[18]][[4]],paste0(path.io,"tcov_increasePostCoVNoMV.xlsx"))
#write_xlsx(Synthesis_total[[19]][[4]],paste0(path.io,"tcov_noSideEffectNoMV.xlsx"))
}
  
  end_time <- Sys.time()
  end_time - start_time
