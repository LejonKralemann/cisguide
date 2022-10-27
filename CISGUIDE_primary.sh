#!/bin/sh

WORKPATH="shared"
echo "looking in ${WORKPATH}"

#read the sample_information file
if [[ -f "${WORKPATH}/Sample_information.txt" ]]
then
	echo "Found Sample_information.txt"
else
	echo "Did not find Sample_information.txt, exiting";
	exit 1
fi

#get a list of refs and create indices
#REF
readarray -t LIST_REFS  < <(cat ${WORKPATH}/Sample_information.txt | awk -v OFS="\t" -v FS="\t" 'FNR>1{print $4}' | sort | uniq)
echo "Processing the following fasta reference files:" ${LIST_REFS[*]}
for j in "${LIST_REFS[@]}"
do
if [[ -f "${WORKPATH}/${j}" ]]
then
	echo "Found ${j}"
	if [[ -f "${WORKPATH}/${j}.bwt.2bit.64" ]] && [[ -f "${WORKPATH}/${j}.0123" ]] && [[ -f "${WORKPATH}/${j}.amb" ]] && [[ -f "${WORKPATH}/${j}.ann" ]] && [[ -f "${WORKPATH}/${j}.pac" ]]
	then
		echo "BWA-mem2 index of ${WORKPATH}/${j} found"
	else
		echo "Creating the index for ${j}"
		bwa-mem2 index ${WORKPATH}/${j}
	fi
else
	echo "Did not find ${j}, exiting";
	exit 1
fi
done

#get the list of samples
#fastq_name
readarray -t LIST_SAMPLES  < <(cat ${WORKPATH}/Sample_information.txt | awk -v OFS="\t" -v FS="\t" 'FNR>1{print $3}'  | sed 's/_R1.fastq.gz//g' | sort | uniq) 
echo "Processing the following samples:" ${LIST_SAMPLES[*]}

> ${WORKPATH}/file0.temp | awk -v OFS="\t" -v FS="\t" 'BEGIN {print "Sample", "Raw read count", "mapped count", "dedupped count", "preprocessed count"}' > ${WORKPATH}/read_numbers.txt

for i in "${LIST_SAMPLES[@]}" 
do
#check for presence of R1 and R2
if [[ -f "${WORKPATH}/${i}_R1.fastq.gz" ]]
then
	echo "Found ${WORKPATH}/${i}_R1.fastq.gz"
else
	echo "Did not find ${WORKPATH}/${i}_R1.fastq.gz, moving to the next sample";
	continue
fi
if [[ -f "${WORKPATH}/${i}_R2.fastq.gz" ]]
then
	echo "Found ${WORKPATH}/${i}_R2.fastq.gz"
else
	echo "Did not find ${WORKPATH}/${i}_R2.fastq.gz, moving to the next sample";
	continue
fi

#fastq_name, sample
CURRENTSAMPLE=$(cat ${WORKPATH}/Sample_information.txt | awk -v OFS="\t" -v FS="\t" -v i="$i" 'FNR>1{if($3==i) {print $1}}')
echo "Using ref: ${CURRENTSAMPLE}"
echo "looking for directory ${WORKPATH}/${CURRENTSAMPLE}"
if [[ -d "${WORKPATH}/${CURRENTSAMPLE}" ]]
then
	echo "directory exists"
else
	echo "directory does not exist, creating ${WORKPATH}/${CURRENTSAMPLE}"
	mkdir ${WORKPATH}/${CURRENTSAMPLE}
	mkdir ${WORKPATH}/${CURRENTSAMPLE}/temp
fi
echo ">p5" >> ${WORKPATH}/${CURRENTSAMPLE}/Illumina_adapters.fa
cat ${WORKPATH}/Sample_information.txt | awk -v OFS="\t" -v FS="\t" -v i="$i" 'FNR>1{if($3==i) {print $5}}' | tr "[:lower:]" "[:upper:]" | tr "RYMKSWBDHV" "NNNNNNNNNN" >> ${WORKPATH}/${CURRENTSAMPLE}/Illumina_adapters.fa
echo ">p5_RC" >> ${WORKPATH}/${CURRENTSAMPLE}/Illumina_adapters.fa
cat ${WORKPATH}/Sample_information.txt | awk -v OFS="\t" -v FS="\t" -v i="$i" 'FNR>1{if($3==i) {print $5}}' | tr "[:lower:]" "[:upper:]" | tr "RYMKSWBDHV" "NNNNNNNNNN" | tr "ACGT" "TGCA" | rev >> ${WORKPATH}/${CURRENTSAMPLE}/Illumina_adapters.fa
echo ">p7" >> ${WORKPATH}/${CURRENTSAMPLE}/Illumina_adapters.fa
cat ${WORKPATH}/Sample_information.txt | awk -v OFS="\t" -v FS="\t" -v i="$i" 'FNR>1{if($3==i) {print $6}}' | tr "[:lower:]" "[:upper:]" | tr "RYMKSWBDHV" "NNNNNNNNNN" >> ${WORKPATH}/${CURRENTSAMPLE}/Illumina_adapters.fa
echo ">p7_RC" >> ${WORKPATH}/${CURRENTSAMPLE}/Illumina_adapters.fa
cat ${WORKPATH}/Sample_information.txt | awk -v OFS="\t" -v FS="\t" -v i="$i" 'FNR>1{if($3==i) {print $6}}' | tr "[:lower:]" "[:upper:]" | tr "RYMKSWBDHV" "NNNNNNNNNN" | tr "ACGT" "TGCA" | rev >> ${WORKPATH}/${CURRENTSAMPLE}/Illumina_adapters.fa

echo "Trimming" ${i}
trimmomatic PE ${WORKPATH}/${i}_R1.fastq.gz ${WORKPATH}/${i}_R2.fastq.gz ${WORKPATH}/${CURRENTSAMPLE}/${i}_forward_paired.fastq.gz ${WORKPATH}/${CURRENTSAMPLE}/${i}_forward_unpaired.fastq.gz ${WORKPATH}/${CURRENTSAMPLE}/${i}_reverse_paired.fastq.gz ${WORKPATH}/${CURRENTSAMPLE}/${i}_reverse_unpaired.fastq.gz ILLUMINACLIP:${WORKPATH}/${CURRENTSAMPLE}/Illumina_adapters.fa:2:30:10:1:TRUE CROP:150 -phred33

echo "Unzipping" ${i}
gunzip ${WORKPATH}/${CURRENTSAMPLE}/${i}_forward_paired.fastq.gz 
gunzip ${WORKPATH}/${CURRENTSAMPLE}/${i}_reverse_paired.fastq.gz 

#fastqname, ref
CURRENTREF=$(cat ${WORKPATH}/Sample_information.txt | awk -v OFS="\t" -v FS="\t" -v i="$i" 'FNR>1{if($3==i) {print $4}}')
echo "Using ref: $CURRENTREF"
echo "Mapping" ${i}
bwa-mem2 mem ${WORKPATH}/${CURRENTREF} ${WORKPATH}/${CURRENTSAMPLE}/${i}_forward_paired.fastq ${WORKPATH}/${CURRENTSAMPLE}/${i}_reverse_paired.fastq >${WORKPATH}/${CURRENTSAMPLE}/${CURRENTSAMPLE}.sam

samtools view -1 ${WORKPATH}/${CURRENTSAMPLE}/${CURRENTSAMPLE}.sam > ${WORKPATH}/${CURRENTSAMPLE}/${CURRENTSAMPLE}.bam
samtools sort -o ${WORKPATH}/${CURRENTSAMPLE}/${CURRENTSAMPLE}_sorted.bam ${WORKPATH}/${CURRENTSAMPLE}/${CURRENTSAMPLE}.bam
echo "Dedupping" ${i}
picard MarkDuplicates --INPUT ${WORKPATH}/${CURRENTSAMPLE}/${CURRENTSAMPLE}_sorted.bam --OUTPUT ${WORKPATH}/${CURRENTSAMPLE}/${CURRENTSAMPLE}.sorted.bam --METRICS_FILE ${WORKPATH}/${CURRENTSAMPLE}/${CURRENTSAMPLE}_sorted_dedup_metrics.txt --REMOVE_DUPLICATES TRUE
samtools index ${WORKPATH}/${CURRENTSAMPLE}/${CURRENTSAMPLE}.sorted.bam ${WORKPATH}/${CURRENTSAMPLE}/${CURRENTSAMPLE}.sorted.bam.bai

#fastqname, primer
PRIMERSEQFULL=$(cat ${WORKPATH}/Sample_information.txt | awk -v OFS="\t" -v FS="\t" -v i="$i" 'FNR>1{if($3==i) {print $2}}')
PRIMERSEQ="$( echo "$PRIMERSEQFULL" | tr "[:lower:]" "[:upper:]" | sed -e 's#^TCAGACGTGTGCTCTTCCGATCT##' )"

if [ -z "$PRIMERSEQ" ]
then
	echo "Primer sequence not found, moving to the next sample"
	continue
else
	echo "Using this primer sequence: ${PRIMERSEQ}"
fi

echo "Creating empty output files"
> ${WORKPATH}/file1.temp | awk -v OFS="\t" -v FS="\t" ' BEGIN{print "QNAME", "RNAME_1", "POS_1", "CIGAR_1", "SEQ_1", "QUAL_1", "SATAG_1", "SEQ_RCed_1", "RNAME_2", "POS_2", "CIGAR_2", "SEQ_2", "QUAL_2", "SATAG_2", "SEQ_RCed_2", "FILE_NAME", "PRIMER_SEQ"}' > ${WORKPATH}/${CURRENTSAMPLE}/${CURRENTSAMPLE}_A.txt

echo "Processing fw reads of ${i}"
samtools view -uF 0x100 ${WORKPATH}/${CURRENTSAMPLE}/${CURRENTSAMPLE}.sorted.bam | samtools view -uF 0x4 | samtools view -uF 0x800 | samtools view -uf 0x80 |samtools view -uF 0x8 | samtools view -F 0x10 | sort -T ${WORKPATH}/${CURRENTSAMPLE}/temp/ -k 1,1 | awk -v OFS="\t" -v FS="\t" '{ if ($5>50 && length($10)>89){print $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, "FALSE"}}' > ${WORKPATH}/${CURRENTSAMPLE}/Primer_reads_fw.txt

echo "Processing rev reads of ${i}"
samtools view -uF 0x100 ${WORKPATH}/${CURRENTSAMPLE}/${CURRENTSAMPLE}.sorted.bam | samtools view -uF 0x4 | samtools view -uF 0x800| samtools view -uf 0x80 |samtools view -uF 0x8 | samtools view -f 0x10 | sort -T ${WORKPATH}/${CURRENTSAMPLE}/temp/ -k 1,1 | awk -v OFS="\t" -v FS="\t" '{ if ($5>50 && length($10)>89){print $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12}}' > ${WORKPATH}/${CURRENTSAMPLE}/Primer_reads_rv.txt

echo "Rev complementing rev reads of ${i}"
awk -v OFS="\t" -v FS="\t" '{print $10}' ${WORKPATH}/${CURRENTSAMPLE}/Primer_reads_rv.txt | tr ACGTacgt TGCAtgca | rev > ${WORKPATH}/${CURRENTSAMPLE}/Primer_reads_rv_RCseqs.txt
paste ${WORKPATH}/${CURRENTSAMPLE}/Primer_reads_rv.txt ${WORKPATH}/${CURRENTSAMPLE}/Primer_reads_rv_RCseqs.txt | awk -v OFS="\t" -v FS="\t" '{print $1, $2, $3, $4, $5, $6, $7, $8, $9, $13, $11, $12, "TRUE"}' > ${WORKPATH}/${CURRENTSAMPLE}/Primer_reads_rv_RCed.txt

echo "Combining fw and rev reads and keeping only those starting with primer seq ${PRIMERSEQ}"
cat ${WORKPATH}/${CURRENTSAMPLE}/Primer_reads_fw.txt ${WORKPATH}/${CURRENTSAMPLE}/Primer_reads_rv_RCed.txt | sort -T ${WORKPATH}/${CURRENTSAMPLE}/temp/ -k 1,1 | awk -v OFS="\t" -v FS="\t" -v test="$PRIMERSEQ" '$10 ~ "^"test {print}'  > ${WORKPATH}/${CURRENTSAMPLE}/Primer_reads_all.txt
awk -v OFS="\t" -v FS="\t" '{print $1}' ${WORKPATH}/${CURRENTSAMPLE}/Primer_reads_all.txt > ${WORKPATH}/${CURRENTSAMPLE}/Primer_reads_all_names.txt

echo "Processing fw mates of accepted reads of ${i}"
samtools view -uF 0x100 ${WORKPATH}/${CURRENTSAMPLE}/${CURRENTSAMPLE}.sorted.bam | samtools view -uF 0x4 | samtools view -uF 0x800| samtools view -uf 0x40 | samtools view -uF 0x8 | samtools view -f 0x10 | sort -T ${WORKPATH}/${CURRENTSAMPLE}/temp/ -k 1,1 | awk -v OFS="\t" -v FS="\t" '{ if ($5>50){print $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, "FALSE"}}' | grep -f ${WORKPATH}/${CURRENTSAMPLE}/Primer_reads_all_names.txt > ${WORKPATH}/${CURRENTSAMPLE}/Mates_fw.txt

echo "Processing rev mates of accepted reads of ${i}"
samtools view -uF 0x100 ${WORKPATH}/${CURRENTSAMPLE}/${CURRENTSAMPLE}.sorted.bam | samtools view -uF 0x4 | samtools view -uF 0x800| samtools view -uf 0x40 | samtools view -uF 0x8 | samtools view -F 0x10 | sort -T ${WORKPATH}/${CURRENTSAMPLE}/temp/ -k 1,1 | awk -v OFS="\t" -v FS="\t" '{ if ($5>50){print $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12}}' | grep -f ${WORKPATH}/${CURRENTSAMPLE}/Primer_reads_all_names.txt > ${WORKPATH}/${CURRENTSAMPLE}/Mates_rv.txt

echo "Rev complementing rev mates of ${i}"
awk -v OFS="\t" -v FS="\t" '{print $10}' ${WORKPATH}/${CURRENTSAMPLE}/Mates_rv.txt | tr ACGTacgt TGCAtgca | rev > ${WORKPATH}/${CURRENTSAMPLE}/Mates_rv_RCseqs.txt
paste ${WORKPATH}/${CURRENTSAMPLE}/Mates_rv.txt ${WORKPATH}/${CURRENTSAMPLE}/Mates_rv_RCseqs.txt | awk -v OFS="\t" -v FS="\t" '{print $1, $2, $3, $4, $5, $6, $7, $8, $9, $13, $11, $12, "TRUE"}' > ${WORKPATH}/${CURRENTSAMPLE}/Mates_rv_RCed.txt

echo "Combining fw and rev mates of ${i}"
cat ${WORKPATH}/${CURRENTSAMPLE}/Mates_fw.txt ${WORKPATH}/${CURRENTSAMPLE}/Mates_rv_RCed.txt | sort -T ${WORKPATH}/${CURRENTSAMPLE}/temp/ -k 1,1 > ${WORKPATH}/${CURRENTSAMPLE}/Mates_all.txt

echo "Combining selected reads and mates of ${i}"
join -j 1 -o 1.1,1.3,1.4,1.6,1.10,1.11,1.12,1.13,2.3,2.4,2.6,2.10,2.11,2.12,2.13 -t $'\t' ${WORKPATH}/${CURRENTSAMPLE}/Primer_reads_all.txt ${WORKPATH}/${CURRENTSAMPLE}/Mates_all.txt | awk -v OFS="\t" -v FS="\t" -v i="$i" -v PRIMERSEQ="$PRIMERSEQ" ' {print $0, i, PRIMERSEQ}'  >> ${WORKPATH}/${CURRENTSAMPLE}/${CURRENTSAMPLE}_A.txt

echo "counting reads of ${CURRENTSAMPLE}"
RAWNO=$(gunzip -c ${WORKPATH}/${i}_R1.fastq.gz | wc -l)
echo "RAWNO: ${RAWNO}"
MAPNO=$(cat ${WORKPATH}/${CURRENTSAMPLE}/${CURRENTSAMPLE}.sam | grep -Ev '^(\@)' | awk '$3 != "*" {print $0}' | sort -u -t$'\t' -k1,1 | wc -l)
echo "MAPNO: ${MAPNO}"
samtools view -h -o ${WORKPATH}/${CURRENTSAMPLE}/${CURRENTSAMPLE}.dedup.sam ${WORKPATH}/${CURRENTSAMPLE}/${CURRENTSAMPLE}.sorted.bam
DEDUPNO=$(cat ${WORKPATH}/${CURRENTSAMPLE}/${CURRENTSAMPLE}.dedup.sam | grep -Ev '^(\@)' | awk '$3 != "*" {print $0}' | sort -u -t$'\t' -k1,1 | wc -l)
echo "DEDUPNO: ${DEDUPNO}"
PREPRONO=$(cat ${WORKPATH}/${CURRENTSAMPLE}/${CURRENTSAMPLE}_A.txt | wc -l)
echo "PREPRONO: ${PREPRONO}"
cat ${WORKPATH}/read_numbers.txt | awk -v OFS="\t" -v FS="\t" -v CURRENTSAMPLE="${CURRENTSAMPLE}" -v RAWNO="${RAWNO}" -v MAPNO="${MAPNO}" -v DEDUPNO="${DEDUPNO}" -v PREPRONO="${PREPRONO}" ' END{print CURRENTSAMPLE, RAWNO / 4, MAPNO, DEDUPNO, PREPRONO - 1}' >> ${WORKPATH}/read_numbers.txt

now=$(date)

echo "removing temporary files"
rm ${WORKPATH}/${CURRENTSAMPLE}/${CURRENTSAMPLE}.bam 
rm ${WORKPATH}/${CURRENTSAMPLE}/${CURRENTSAMPLE}_sorted.bam 
rm ${WORKPATH}/${CURRENTSAMPLE}/${CURRENTSAMPLE}.sam 
rm ${WORKPATH}/${CURRENTSAMPLE}/${CURRENTSAMPLE}.dedup.sam 
rm ${WORKPATH}/${CURRENTSAMPLE}/Mates_rv_RCseqs.txt
rm ${WORKPATH}/${CURRENTSAMPLE}/Mates_all.txt 
rm ${WORKPATH}/${CURRENTSAMPLE}/Mates_fw.txt 
rm ${WORKPATH}/${CURRENTSAMPLE}/Mates_rv.txt 
rm ${WORKPATH}/${CURRENTSAMPLE}/Mates_rv_RCed.txt 
rm ${WORKPATH}/${CURRENTSAMPLE}/Primer_reads_fw.txt 
rm ${WORKPATH}/${CURRENTSAMPLE}/Primer_reads_rv.txt 
rm ${WORKPATH}/${CURRENTSAMPLE}/Primer_reads_rv_RCed.txt 
rm ${WORKPATH}/${CURRENTSAMPLE}/Primer_reads_all.txt 
rm ${WORKPATH}/${CURRENTSAMPLE}/Primer_reads_all_names.txt 
rm ${WORKPATH}/${CURRENTSAMPLE}/Primer_reads_rv_RCseqs.txt
rm ${WORKPATH}/${CURRENTSAMPLE}/Illumina_adapters.fa
rm ${WORKPATH}/${CURRENTSAMPLE}/${i}_forward_paired.fastq 
rm ${WORKPATH}/${CURRENTSAMPLE}/${i}_reverse_paired.fastq 
rm ${WORKPATH}/${CURRENTSAMPLE}/${i}_forward_unpaired.fastq.gz 
rm ${WORKPATH}/${CURRENTSAMPLE}/${i}_reverse_unpaired.fastq.gz 
rm ${WORKPATH}/${CURRENTSAMPLE}/${CURRENTSAMPLE}_sorted_dedup_metrics.txt 
rm -r ${WORKPATH}/${CURRENTSAMPLE}/temp

echo "Finished at $now"

done

echo "removing temporary files"
rm ${WORKPATH}/file0.temp ${WORKPATH}/file1.temp 

exit 0
