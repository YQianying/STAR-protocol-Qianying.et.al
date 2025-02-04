#clear
rm(list = ls()) 
options(stringsAsFactors = F)
#install all the required packages
if (!requireNamespace("BiocManager", quietly = TRUE))
  install.packages("BiocManager")
BiocManager::install(c("TxDb.Mmusculus.UCSC.mm10.knownGene", "org.Mm.eg.db", "DESeq2"),ask = F,update = F)
install.packages(c("dplyr","ggplot2","ggthemes","ggpubr"))
#load all the required packages
library(TxDb.Mmusculus.UCSC.mm10.knownGene)
library(org.Mm.eg.db)
library(dplyr)
library(ggplot2)
library(ggthemes)
library(ggpubr)
library(DESeq2)
#integrate reads-count and group information into RStudio
#download GSE69970_htseq_counts.txt from https://www.ncbi.nlm.nih.gov/geo/query/acc.cgi?acc= GSE69970
#download GSE75951_htseq_counts.txt from https://www.ncbi.nlm.nih.gov/geo/query/acc.cgi?acc= GSE75951
#download GSE86400_cast.counts.txt from https://www.ncbi.nlm.nih.gov/geo/query/acc.cgi?acc= GSE86400
GSE69970 = read.table('GSE69970_htseq_counts.txt',header = T)
GSE75951 = read.table('GSE75951_htseq_counts.txt',header = T)
GSE86400 = read.table('GSE86400_cast.counts.txt',header = T)
colnames(GSE69970)[1]
colnames(GSE75951)[1]='symbol'
colnames(GSE86400)[1]='symbol'
allcount = merge(GSE69970,GSE75951,by.x ='symbol',all.x = T)
allcount = merge(allcount,GSE86400,by.x ='symbol',all.x = T)
allcount = allcount[-1:-5,]
allgroup = read.table('allgroup.txt',header = T)
allgroup$stage_genotype_sex = paste(allgroup$stage,allgroup$genotype,allgroup$sex,sep = '_')
allgroup$genotype_sex = paste(allgroup$genotype,allgroup$sex,sep = '_')
rownames(allcount)=allcount$symbol
save(allcount,allgroup,file = 'prepared_sample_data_of_GSE71442.RData')
save.image(file = 'STAR_PROTOCOL.RData')
#qulity control
table(apply(allcount[,2:ncol(allcount)],2,function(x)sum(x>0)>7000))
#match
allcount = allcount[,c(1,match(allgroup$sample, names(allcount)))]

##Acquire Non-Overlapping Exon Length of each gene, which is defined as gene length
library(TxDb.Mmusculus.UCSC.mm10.knownGene)
txdb <- TxDb.Mmusculus.UCSC.mm10.knownGene
  exon_txdb=exons(txdb)
  genes_txdb=genes(txdb)
  
  overlap_list = findOverlaps(exon_txdb,genes_txdb)
  overlap_list
  t1=exon_txdb[queryHits(overlap_list)]
  t2=genes_txdb[subjectHits(overlap_list)]
  t1=as.data.frame(t1)
  t1$geneid=mcols(t2)[,1]
  gene_length = lapply(split(t1,t1$geneid),function(x){
    head(x)
    tmp=apply(x,1,function(y){
      y[2]:y[3]
    })
    length(unique(unlist(tmp)))
  })
  gene_length = data.frame(gene_id=names(gene_length),length=as.numeric(gene_length))
  head(gene_length)
#Acquire the corresponding information of gene length and gene symbol
library(org.Mm.eg.db)
#Gene symbol and gene_ID
Gene_symbol=toTable(org.Mm.egSYMBOL)
#Gene chromosome and gene_ID
Gene_start = toTable(org.Mm.egCHRLOC)
Gene_end = toTable(org.Mm.egCHRLOCEND)
Gene_start_end = merge(Gene_start, Gene_end[,-3], by='gene_id', all.x =  T)
Gene_start_end = Gene_start_end[!duplicated(Gene_start_end$gene_id),]
#merge information
gene_information=merge(gene_length, Gene_symbol, by='gene_id', all.x =  T)
gene_information=merge(gene_information,Gene_start_end,by='gene_id', all.x =  T)
head(gene_information)
merge_allcount = na.omit(merge(allcount, gene_information, by='symbol', all.x =  T))

#Calculate normalized gene expression (TPM)
#define a countToTpm function
countToTpm = function(counts, genelength)
{
  rate = log(counts) - log(genelength)
  denom = log(sum(exp(rate)))
  exp(rate - denom + log(1e6))
}
#calculate TPM by countToTPM function
alltpm = merge_allcount 
alltpm[,2:ncol(alltpm)] = as.data.frame(apply(alltpm[,2:ncol(alltpm)],2,function(x){countToTpm(x,alltpm$length)}))
head(alltpm)

#Calculate contribution value of each X-linked genes:

#retain the genes located in autosomes and sex chromosomes
table(alltpm$Chromosome)
chromosome = c(1:19,"X","Y")
alltpm = alltpm[alltpm$Chromosome %in% chromosome,]
#retain the genes expressed at least in three samples
table(apply(alltpm[,2:ncol(alltpm)],1,function(x)sum(x>0)>2))
alltpm = alltpm[apply(alltpm[,2:ncol(alltpm)],1,function(x)sum(x>0)>2),]
dim(alltpm)

#alignment of sample names
table(allgroup$sample==colnames(alltpm)[2:ncol(alltpm)])

#calculate meanA
X_number = sum(alltpm$Chromosome == 'X')
A_number = sum(alltpm$Chromosome %in% chromosome[1:19])
allgroup$Xist = as.numeric(alltpm[alltpm$symbol=='Xist',2:ncol(alltpm)])
allgroup$totalY = apply(alltpm[alltpm$Chromosome == 'Y',2:ncol(alltpm)],2,sum)
allgroup$meanA = apply(alltpm[alltpm$Chromosome %in% chromosome[1:19],2:ncol(alltpm)],2,function(x)sum(x)/A_number)
contribution_value = alltpm[alltpm$Chromosome=='X',]
contribution_value[,2:ncol(alltpm)] = as.data.frame(t(apply(contribution_value[,2:ncol(alltpm)],1,function(x) x / allgroup$meanA)))
#plot X/A
allgroup$X_A = apply(contribution_value[,2:ncol(alltpm)],2,function(x)sum(x)/X_number)

library(dplyr)
group_means = allgroup[allgroup$genotype != "RlimKO",] %>% group_by(stage, genotype_sex) %>% 
  summarize(mean_X_A = mean(X_A), sd_X_A = sd(X_A), se_X_A = sd_X_A / sqrt(n()))
library(ggplot2)
library(ggthemes)
plot = ggplot(group_means,
       aes(x = stage ,y = mean_X_A, color = genotype_sex, group = genotype_sex)) + 
  geom_line(size = 1)+
  geom_errorbar(aes(ymin = mean_X_A - se_X_A, ymax = mean_X_A + se_X_A), width = 0.2) + 
  geom_point(size=2) + labs(x = ' ', y = 'normalized X/A')+ ylim(c(0.4,1.6))+
  theme_base()
ggsave(plot,filename = "normalized X_A ratios.pdf")
#calculate contribution increment
#extration of 4cell and E3.5 WT male samples
groupWTmale = allgroup[allgroup$stage_genotype_sex %in% c('4cell_WT_male','E3.5_WT_male'),]
#calculation of contribution increment of each genes from 4cell to E3.5
XCU_gene = data.frame(symbol= contribution_value$symbol,
                      mean4cell = apply(contribution_value[,groupWTmale$sample[groupWTmale$stage=='4cell']],1,mean),
                      meanE3.5 = apply(contribution_value[,groupWTmale$sample[groupWTmale$stage=='E3.5']],1,mean)
) 
XCU_gene$contribution_increment = XCU_gene$meanE3.5 - XCU_gene$mean4cell
XCU_gene = XCU_gene[order(XCU_gene$contribution_increment,decreasing = T),]

#Differential gene expression analysis by DESeq2
library(DESeq2)
#extract expression matrix of male 4-cell and E3.5 embryos, as well as corresponded group information
allcount_WTmale = allcount[,c('symbol',groupWTmale$sample)]
colData = groupWTmale[,c(1,4)]
colData$stage = factor(colData$stage)
#construct differential analysis matrix
dds <- DESeqDataSetFromMatrix(countData = allcount_WTmale[,2:40], colData = colData, design = ~ stage)
dds <- DESeq(dds)
colData$stage
DEG <- results(dds, contrast = c('stage','E3.5','4cell')) 
#rank according to Padj
DEG <- as.data.frame(DEG[order(DEG$padj),])
DEG$symbol = rownames(DEG)
DEG = DEG[,6:7] 
DEG[,1][is.na(DEG[,1])] = 1
colnames(DEG)[1] = 'padj4_E3.5'
XCU_gene = merge(XCU_gene, DEG, by = 'symbol', all.x = T)
#annotate the XCU_gene
XCU_contributing_genes = XCU_gene[XCU_gene$padj4_E3.5<0.05 & XCU_gene$contribution_increment>0,'symbol']

#Visualization of contribution changes of X-linked genes
library(ggpubr)
library(ggthemes)
XCU_gene$change = ifelse(XCU_gene$padj4_E3.5<0.05,
                         ifelse(XCU_gene$contribution_increment>0,'UP','DOWN'),'stable')
df = XCU_gene
df$lgpadj = -log10(df$padj4_E3.5)
head(df)
#label genes
df = df[order(df$contribution_increment),]
df = df[order(df$change),]
head(df)
labelname = c(as.character(tail(df$symbol[which(df$change == 'UP')],10)))
plot2 = ggscatter(df, x = "contribution_increment", y = "lgpadj", color = "change",size = 1,
          label = 'symbol',
          label.select = labelname, repel = T,
          ylab = '-Log10 FDR', xlab = 'contribution increment',
          palette = c("#2F5688", "grey", "#CC0000"))+theme_base()+
  geom_vline(xintercept = 0,linetype = 'dashed')+
  geom_hline(yintercept = 1.3,linetype = 'dashed') 
ggsave(plot2,filename = "XCU-contributing genes.pdf")
#location of XCU-contributing genes
XCU_gene$start_location = abs(gene_information[match(XCU_gene$symbol,gene_information$symbol),'start_location'])
XCU_gene$Mlocation = XCU_gene$start_location / 1000000 
UP_XCU_gene = XCU_gene[XCU_gene$change=='UP',]
UP_XCU_gene$log2contribution = log2(UP_XCU_gene$contribution_increment +1)
# plot distribution
plot3 = ggscatter(UP_XCU_gene,x = "Mlocation", y = "log2contribution", 
          color = "red",
          size=2, 
          repel = T,
          ylab = 'Log2(contribution increment +1)', xlab = 'Genomic position on X chromosome (Mb)')+
  theme_base()+
  geom_hline(yintercept = 0,linetype = 'dashed')
ggsave(plot3,filename = "distribution.pdf")
# The contribution percentage of each XCU-contributing gene
UP_XCU_gene = UP_XCU_gene[order(-UP_XCU_gene$contribution_increment),]
UP_XCU_gene$percentages = UP_XCU_gene$contribution_increment / sum(UP_XCU_gene$contribution_increment)
df = c(UP_XCU_gene$percentages[1:7],sum(UP_XCU_gene$percentages[8:143]))
plot4 = pie(df, labels = c(UP_XCU_gene$symbol[1:7],'other'),col = c(rainbow(7,end = 4/6),"white"),
    main = 'contribution percentage')
ggsave(plot4,filename = "contribution percentage.pdf")
save.image('STAR_PROTOCOL.RData')
