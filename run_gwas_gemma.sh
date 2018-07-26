#!/bin/bash

# AUTHOR: Johan Zicola
# DATE: 2018-01-26

# DESCRIPTION: This script performs GWAS using as input a vcf file and a phenotype file
# The phenotype file should contain as many values as individuals in the vcf file.
# The order of the accessions in the vcf file should be the same than the order of the 
# phenotype in the phenotype file

# USAGE:
# run_gwas_gemma.sh <phenotype_file.tsv> <vcf_file.vcf> <model>

# Output is a .assoc.clean.txt file which can be loaded in R to look at significant SNPs.
# All generated files are located where <phenotype_file.tsv> is and the subdirectory "output"

# Path to python script assoc2qqman.py (assumes the script is in the same
# directory as this script)

# Get directory of running bash script
current_path=$(dirname $0)
current_path=$(cd $current_path && pwd)

# Assign path of the python script assoc2qqman.py to $assoc2qqman
assoc2qqman="${current_path}/assoc2qqman.py"


####################################################################################

# Help command if no arguments or -h argument is given 
if [ "$1" == "-h" -o "$#" -eq 0 ] ; then
	echo -e "\n" 
	echo "Usage: `basename $0` <phenotype_file.tsv> <vcf_file.vcf> <model> [-h]"
	echo -e "\n" 
	echo "Description: Provide as main argument a phenotype file" 
	echo "generated in R (should have a .tsv extension) and a vcf files containing "
	echo "the accessions described in the phenotype file (should have a .vcf extension)"
	echo "`basename $0` generates several files derived from vcftools, p-link, and gemma"
	echo "The file with ".assoc.clean.txt" as suffix contains the GWAS results and can be "
	echo "uploaded in R for visualization (qqman library)"
	echo -e "\n"
exit 0
fi

# Test if 2 arguments were provided
if [ "$#" -ne 2	]; then
	echo "Argument(s) missing"
	exit 0
fi

# Phenotype file is generated by R and has a tsv extension (can have several phenotypes
# tab-separated in different columns
phenotype_file=$1
if [ ! -e $phenotype_file ]; then
	echo "File $phenotype_file does not exist"
     	exit 0
elif [[ $phenotype_file != *.tsv ]]; then
	echo "Provide a phenotype file with .tsv extension"
	exit 0
fi

# Define location of vcf file to analyze
vcf_file=$2
if [ ! -e $vcf_file ]; then
	echo "File $vcf_file does not exist"
     	exit 0
elif [[ $vcf_file != *.vcf ]]; then
	echo "Provide a vcf file with .vcf extension"
	exit 0
fi

##################################################################################

# Get prefix from phenotype name (assume the phenotype file has a .tsv extension)
prefix=$(basename -s .tsv $phenotype_file)
dir_file=$(dirname $phenotype_file)

# VCF into bed file => make .ped and .map files
vcftools --vcf $vcf_file --plink --out ${dir_file}/${prefix} 

# Make bed files: 3 files are created => .bed, .bim, .fam
p-link --noweb --file ${dir_file}/${prefix} --make-bed --out ${dir_file}/${prefix}  

# Paste to fam file
paste -d ' ' ${dir_file}/${prefix}.fam $phenotype_file > ${dir_file}/${prefix}_modified.fam

# Remove 6th column (-9)
awk '!($6="")' ${dir_file}/${prefix}_modified.fam  > ${dir_file}/${prefix}_modified1.fam

# Remove double spaces
sed -i 's/  / /g' ${dir_file}/${prefix}_modified1.fam 

mv ${dir_file}/${prefix}_modified1.fam ${dir_file}/${prefix}.fam

# Run Gemma
# Per default, gemma put the results in an "output" directory located in working directory ($current_path)
# There is apparently no way to change this (adding fullpath in -o  /srv/biodata/dep_coupland/grp_hancock/johan/GWAS/rDNA_copy_number_MOR)
# does not work: 
# error writing file: ./output//srv/biodata/dep_coupland/grp_hancock/johan/GWAS/rDNA_copy_number_MOR.cXX.txt
# Instead, just transfer the generated files into the ${dir_file}/output directory at the end

## Estimate relatedness matrix from genotypes (n x n individuals)
# Generate relatedness matrix based on centered genotypes (cXX)
# centered matrix preferred in general, accounts better for population structure
# If standardized genotype matrix is needed, change to -gk 2 (sXX)
# standardized matrix preferred if SNPs with lower MAF have larger effects 
gemma -bfile ${dir_file}/${prefix} -gk 1 -o ${prefix}


## If needed, the relatedness matrix can transformed into eigen values and eigen vectors
## Generates 3 files: log, eigen values (1 column of na elements) and eigen vectors  (na x na matrix)
## Use of eigen transformation allows quicker analysis (if samples > 10 000)
# gemma -bfile ${dir_file}/${prefix} -k ${current_path}/output/${prefix}.cXX.txt -eigen -o ${prefix}

## Association Tests with Univariate Linear Mixed Models
# Use lmm 2 to performs likelihood ratio test
# prefix.log.txt contains PVE estimate and its standard error in the null linear mixed model.
# assoc.txt file contains the results
gemma -bfile ${dir_file}/${prefix} -k ${current_path}/output/${prefix}.cXX.txt -lmm 2 -o ${prefix}

# # Association Tests with Multivariate Linear Mixed Models
# # several phenotypes can be given (for instance columns 1,2,3 of the phenotype file). Less than 10
# # phenotypes are recommended
# gemma -bfile ${dir_file}/${prefix} -k ${current_path}/output/${prefix}.cXX.txt -lmm 2 -n 1 2 3 -o ${prefix}

## Bayesian Sparse Linear Mixed Model
## Use a standard linear BSLMM (-bslmm 1)
## Does not require a relatedness matrix (calculates it internally)
## Generates 5 output files: log, hyp.txt (estimated hyper-parameters), param.txt (posterior mean 
## estimates for the effect size parameters), prefix.bv contains 
# gemma -bfile ${dir_file}/${prefix} -bslmm 1 -o ${prefix}

# To analyze the output of bslmm in R, one needs to plot the gamma value multiplied by beta value from the # param.txt (see more details on https://visoca.github.io/popgenomworkshop-gwas_gemma/)
# see R script gemma_param.R


# Polish file for R
python $assoc2qqman ${current_path}/output/${prefix}.assoc.txt > ${current_path}/output/${prefix}.assoc.clean.txt


# Move the output data into dir_file

# Check if output directory is present in dir_file
if [ ! -d  ${dir_file}/output ]; then
    mkdir ${dir_file}/output
fi

mv ${current_path}/output/* ${dir_file}/output/

# Delete output directory in current_dir
rm -r ${current_path}/output

# Create a log output file
echo "File analyzed: $phenotype_file" >> ${dir_file}/log_gwas_${prefix}.txt
echo "VCF file used: $vcf_file" >> ${dir_file}/log_gwas_${prefix}.txt
echo "Output file in ${dir_file}/output" >> ${dir_file}/log_gwas_${prefix}.txt
echo "Date: $(date)" >> ${dir_file}/log_gwas_${prefix}.txt






