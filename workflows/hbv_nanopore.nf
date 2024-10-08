/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    PRINT PARAMS SUMMARY
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

include { paramsSummaryLog; paramsSummaryMap } from 'plugin/nf-validation'

def logo = NfcoreTemplate.logo(workflow, params.monochrome_logs)
def citation = '\n' + WorkflowMain.citation(workflow) + '\n'
//def summary_params = paramsSummaryMap(workflow)

// Print parameter summary log to screen
log.info logo + paramsSummaryLog(workflow) + citation

WorkflowViralseq.initialise(params, log)

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    VALIDATE INPUTS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

def valid_params = [
    artic_minion_caller  : ['nanopolish', 'medaka'],
    artic_minion_aligner : ['minimap2', 'bwa']
]

def summary_params = NfcoreSchema.paramsSummaryMap(workflow, params)

// Validate input parameters
WorkflowNanopore.initialise(params, log, valid_params)

def checkPathParamList = [
    params.input, params.fastq_dir, params.fast5_dir,
    params.sequencing_summary, params.gff
]
for (param in checkPathParamList) { if (param) { file(param, checkIfExists: true) } }

if (params.input)              { ch_input              = file(params.input)              }
if (params.fast5_dir)          { ch_fast5_dir          = file(params.fast5_dir)          } else { ch_fast5_dir          = [] }
if (params.sequencing_summary) { ch_sequencing_summary = file(params.sequencing_summary) } else { ch_sequencing_summary = [] }

// Need to stage medaka model properly depending on whether it is a string or a file
ch_medaka_model = Channel.empty()
if (params.artic_minion_caller == 'medaka') {
    if (file(params.artic_minion_medaka_model).exists()) {
        ch_medaka_model = Channel.fromPath(params.artic_minion_medaka_model)
    }
}


/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    CONFIG FILES
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

ch_multiqc_config          = Channel.fromPath("$projectDir/assets/multiqc_config.yml", checkIfExists: true)
ch_multiqc_custom_config   = params.multiqc_config ? Channel.fromPath( params.multiqc_config, checkIfExists: true ) : Channel.empty()
ch_multiqc_logo            = params.multiqc_logo   ? Channel.fromPath( params.multiqc_logo, checkIfExists: true ) : Channel.empty()
ch_multiqc_custom_methods_description = params.multiqc_methods_description ? file(params.multiqc_methods_description, checkIfExists: true) : file("$projectDir/assets/methods_description_template.yml", checkIfExists: true)

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT LOCAL MODULES/SUBWORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

//
// SUBWORKFLOW: Consisting of a mix of local and nf-core/modules
//
include { INPUT_CHECK         } from '../subworkflows/local/input_check_hbv'
include { PREPARE_GENOME      } from '../subworkflows/local/prepare_genome_nanopore'
include { SNPEFF_SNPSIFT      } from '../subworkflows/local/snpeff_snpsift'
include { VARIANTS_LONG_TABLE } from '../subworkflows/local/variants_long_table'
include { FILTER_BAM_SAMTOOLS } from '../subworkflows/local/filter_bam_samtools'

//
// MODULE: Loaded from modules/local/
//

include { ASCIIGENOME } from '../modules/local/asciigenome'
include { MULTIQC     } from '../modules/local/multiqc_nanopore'
include { PLOT_MOSDEPTH_REGIONS as PLOT_MOSDEPTH_REGIONS_GENOME   } from '../modules/local/plot_mosdepth_regions'
include { PLOT_MOSDEPTH_REGIONS as PLOT_MOSDEPTH_REGIONS_AMPLICON } from '../modules/local/plot_mosdepth_regions'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT NF-CORE MODULES/SUBWORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

//
// MODULE: Installed directly from nf-core/modules
//
include { PYCOQC                        } from '../modules/nf-core/pycoqc/main'
include { NANOPLOT                      } from '../modules/nf-core/nanoplot/main'
include { ARTIC_GUPPYPLEX               } from '../modules/nf-core/artic/guppyplex/main'
include { ARTIC_MINION                  } from '../modules/nf-core/artic/minion/main'
include { VCFLIB_VCFUNIQ                } from '../modules/nf-core/vcflib/vcfuniq/main'
include { TABIX_TABIX                   } from '../modules/nf-core/tabix/tabix/main'
include { BCFTOOLS_STATS                } from '../modules/nf-core/bcftools/stats/main'
include { QUAST                         } from '../modules/nf-core/quast/main'
include { PANGOLIN                      } from '../modules/nf-core/pangolin/main'
include { NEXTCLADE_RUN                 } from '../modules/nf-core/nextclade/run/main'
include { CUSTOM_DUMPSOFTWAREVERSIONS   } from '../modules/nf-core/custom/dumpsoftwareversions/main'
include { MOSDEPTH as MOSDEPTH_GENOME   } from '../modules/nf-core/mosdepth/main'
include { MOSDEPTH as MOSDEPTH_AMPLICON } from '../modules/nf-core/mosdepth/main'
include { IVAR_TRIM } from '../modules/nf-core/ivar/trim/main'
include { IVAR_CONSENSUS } from '../modules/nf-core/ivar/consensus/main'
include { MINIMAP2_ALIGN } from '../modules/nf-core/minimap2/align/main'
include { MINIMAP2_INDEX } from '../modules/nf-core/minimap2/index/main'
include { SAMTOOLS_SORT } from '../modules/nf-core/samtools/sort/main'
include { SAMTOOLS_INDEX } from '../modules/nf-core/samtools/index/main'
include { PORECHOP_PORECHOP } from '../modules/nf-core/porechop/porechop/main'
include { BAM_MARKDUPLICATES_SAMTOOLS } from '../subworkflows/nf-core/bam_markduplicates_samtools/main'
include { MEDAKA } from '../modules/nf-core/medaka/main'


/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

// Info required for completion email and summary
def multiqc_report     = []
def pass_barcode_reads = [:]
def fail_barcode_reads = [:]

workflow HBV_NANOPORE {

    ch_versions = Channel.empty()

    //
    // MODULE: PycoQC on sequencing summary file
    //
    ch_pycoqc_multiqc = Channel.empty()
    if (params.sequencing_summary && !params.skip_pycoqc) {
        PYCOQC (
            Channel.of(ch_sequencing_summary).map { [ [:], it ] }
        )
        ch_pycoqc_multiqc = PYCOQC.out.json
        ch_versions       = ch_versions.mix(PYCOQC.out.versions)
    }

    //
    // SUBWORKFLOW: Uncompress and prepare reference genome files
    //
    PREPARE_GENOME ()
    ch_versions = ch_versions.mix(PREPARE_GENOME.out.versions)

    // Check primer BED file only contains suffixes provided --primer_left_suffix / --primer_right_suffix
    PREPARE_GENOME
        .out
        .primer_bed
        .map { WorkflowCommons.checkPrimerSuffixes(it, params.primer_left_suffix, params.primer_right_suffix, log) }

    // Check whether the contigs in the primer BED file are present in the reference genome
    PREPARE_GENOME
        .out
        .primer_bed
        .map { [ WorkflowCommons.getColFromFile(it, col=0, uniqify=true, sep='\t') ] }
        .set { ch_bed_contigs }

    PREPARE_GENOME
        .out
        .fai
        .map { [ WorkflowCommons.getColFromFile(it, col=0, uniqify=true, sep='\t') ] }
        .concat(ch_bed_contigs)
        .collect()
        .map { fai, bed -> WorkflowCommons.checkContigsInBED(fai, bed, log) }

    barcode_dirs       = file("${params.fastq_dir}/barcode*", type: 'dir' , maxdepth: 1)
    single_barcode_dir = file("${params.fastq_dir}/*.fastq" , type: 'file', maxdepth: 1)
    ch_custom_no_sample_name_multiqc = Channel.empty()
    ch_custom_no_barcodes_multiqc    = Channel.empty()
    if (barcode_dirs) {
        Channel
            .fromPath( barcode_dirs )
            .filter( ~/.*barcode[0-9]{1,4}$/ )
            .map { dir ->
                def count = 0
                for (x in dir.listFiles()) {
                    if (x.isFile() && x.toString().contains('.fastq')) {
                        count += x.countFastq()
                    }
                }
                return [ dir.baseName , dir, count ]
            }
            .set { ch_fastq_dirs }

        //
        // SUBWORKFLOW: Read in samplesheet containing sample to barcode mappings
        //
        if (params.input) {
            INPUT_CHECK (
                ch_input,
                params.platform
            )
            .sample_info
            .join(ch_fastq_dirs, remainder: true)
            .set { ch_fastq_dirs }
            ch_versions = ch_versions.mix(INPUT_CHECK.out.versions)

            //
            // MODULE: Create custom content file for MultiQC to report barcodes were allocated reads >= params.min_barcode_reads but no sample name in samplesheet
            //
            ch_fastq_dirs
                .filter { it[1] == null }
                .filter { it[-1] >= params.min_barcode_reads }
                .map { it -> [ "${it[0]}\t${it[-1]}" ] }
                .collect()
                .map {
                    tsv_data ->
                        def header = ['Barcode', 'Read count']
                        WorkflowCommons.multiqcTsvFromList(tsv_data, header)
                }
                .set { ch_custom_no_sample_name_multiqc }

            //
            // MODULE: Create custom content file for MultiQC to report samples that were in samplesheet but have no barcodes
            //
            ch_fastq_dirs
                .filter { it[-1] == null }
                .map { it -> [ "${it[1]}\t${it[0]}" ] }
                .collect()
                .map {
                    tsv_data ->
                        def header = ['Sample', 'Missing barcode']
                        WorkflowCommons.multiqcTsvFromList(tsv_data, header)
                }
                .set { ch_custom_no_barcodes_multiqc }

            ch_fastq_dirs
                .filter { (it[1] != null)  }
                .filter { (it[-1] != null) }
                .set { ch_fastq_dirs }

        } else {
            ch_fastq_dirs
                .map { barcode, dir, count -> [ barcode, barcode, dir, count ] }
                .set { ch_fastq_dirs }
        }
    } else if (single_barcode_dir) {
        Channel
            .fromPath("${params.fastq_dir}", type: 'dir', maxDepth: 1)
            .map { it -> [ 'SAMPLE_1', 'single_barcode', it, 10000000 ] }
            .set{ ch_fastq_dirs }
    } else {
        log.error "Please specify a valid folder containing ONT basecalled, barcoded fastq files generated by guppy_barcoder or guppy_basecaller e.g. '--fastq_dir ./20191023_1522_MC-110615_0_FAO93606_12bf9b4f/fastq_pass/"
        System.exit(1)
    }

    //
    // MODULE: Create custom content file for MultiQC to report samples with reads < params.min_barcode_reads
    //
    ch_fastq_dirs
        .branch { barcode, sample, dir, count  ->
            pass: count > params.min_barcode_reads
                pass_barcode_reads[sample] = count
                return [ "$sample\t$count" ]
            fail: count < params.min_barcode_reads
                fail_barcode_reads[sample] = count
                return [ "$sample\t$count" ]
        }
        .set { ch_pass_fail_barcode_count }

    ch_pass_fail_barcode_count
        .fail
        .collect()
        .map {
            tsv_data ->
                def header = ['Sample', 'Barcode count']
                WorkflowCommons.multiqcTsvFromList(tsv_data, header)
        }
        .set { ch_custom_fail_barcodes_count_multiqc }

    // Re-arrange channels to have meta map of information for sample
    ch_fastq_dirs
        .filter { it[-1] > params.min_barcode_reads }
        .map { barcode, sample, dir, count -> [ [ id: sample, barcode:barcode ], dir ] }
        .set { ch_fastq_dirs }

    //
    // MODULE: Run Artic Guppyplex
    //
    ARTIC_GUPPYPLEX (
        ch_fastq_dirs
    )
    ch_versions = ch_versions.mix(ARTIC_GUPPYPLEX.out.versions.first().ifEmpty(null))

    //
    // MODULE: Create custom content file for MultiQC to report samples with reads < params.min_guppyplex_reads
    //
    ARTIC_GUPPYPLEX
        .out
        .fastq
        .branch { meta, fastq  ->
            def count = fastq.countFastq()
            pass: count > params.min_guppyplex_reads
                return [ "$meta.id\t$count" ]
            fail: count < params.min_guppyplex_reads
                return [ "$meta.id\t$count" ]
        }
        .set { ch_pass_fail_guppyplex_count }

    ch_pass_fail_guppyplex_count
        .fail
        .collect()
        .map {
            tsv_data ->
                def header = ['Sample', 'Read count']
                WorkflowCommons.multiqcTsvFromList(tsv_data, header)
        }
        .set { ch_custom_fail_guppyplex_count_multiqc }

    //
    // MODULE: Nanoplot QC for FastQ files
    //
    if (!params.skip_nanoplot) {
        NANOPLOT (
            ARTIC_GUPPYPLEX.out.fastq
        )
        ch_versions = ch_versions.mix(NANOPLOT.out.versions.first().ifEmpty(null))
    }

    //
    // MODULE: Map reads to reference genome with Minimap2
    //
    //Channel.value(file(params.references)).map { [ [:], it ] } // Add empty meta map before the reference file path
    MINIMAP2_ALIGN (
        ARTIC_GUPPYPLEX.out.fastq.filter { it[-1].countFastq() > params.min_guppyplex_reads },
        PREPARE_GENOME.out.fasta.collect().map { [ [:], it ] }, // Add empty meta map before the reference file path
        true,
        false,
        false,
        false
    )
    ch_versions = ch_versions.mix(MINIMAP2_ALIGN.out.versions.first().ifEmpty(null))

    //
    // MODULE: Sort bam file
    //
    SAMTOOLS_SORT (
        MINIMAP2_ALIGN.out.bam,
        PREPARE_GENOME.out.fasta.collect().map { [ [:], it ] } // Add empty meta map before the reference file path
    )
    ch_versions = ch_versions.mix(SAMTOOLS_SORT.out.versions.first().ifEmpty(null))

    SAMTOOLS_INDEX (
        SAMTOOLS_SORT.out.bam
    )
    ch_versions = ch_versions.mix(SAMTOOLS_INDEX.out.versions.first().ifEmpty(null))

    //
    // MODULE: Trim primers with iVar trim
    //
    IVAR_TRIM (
        SAMTOOLS_SORT.out.bam.join(SAMTOOLS_INDEX.out.bai),
        PREPARE_GENOME.out.primer_bed.collect()
    )
    ch_versions = ch_versions.mix(IVAR_TRIM.out.versions.first().ifEmpty(null))

    //
    // MODULE: Remove duplicates
    //
    BAM_MARKDUPLICATES_SAMTOOLS (
        IVAR_TRIM.out.bam,
        PREPARE_GENOME.out.fasta.collect().map { [ [:], it ] } // Add empty meta map before the reference file path
    )
    ch_versions = ch_versions.mix(BAM_MARKDUPLICATES_SAMTOOLS.out.versions.first().ifEmpty(null))

    IVAR_CONSENSUS (
        BAM_MARKDUPLICATES_SAMTOOLS.out.bam,
        PREPARE_GENOME.out.fasta.collect(),
        false // Do not save mpileup file
    )
    ch_versions = ch_versions.mix(IVAR_CONSENSUS.out.versions.first().ifEmpty(null))

    if (!params.skip_medaka) {
        MEDAKA (
            // NB: The module input is locally changed from the nf-core version.
            // It takes two input channels, one for the reads and one for the reference genome.
            ARTIC_GUPPYPLEX.out.fastq.filter { it[-1].countFastq() > params.min_guppyplex_reads },
            PREPARE_GENOME.out.fasta.collect()
        )

    //
    // MODULE: Run Artic minion
    //
    if (!params.skip_minion) {
    ARTIC_MINION (
        ARTIC_GUPPYPLEX.out.fastq.filter { it[-1].countFastq() > params.min_guppyplex_reads },
        ch_fast5_dir,
        ch_sequencing_summary,
        PREPARE_GENOME.out.fasta.collect(),
        PREPARE_GENOME.out.primer_bed.collect(),
        ch_medaka_model.collect().ifEmpty([]),
        params.artic_minion_medaka_model ?: '',
        params.artic_scheme,
        params.primer_set_version
    )
    ch_versions = ch_versions.mix(ARTIC_MINION.out.versions.first().ifEmpty(null))

    //
    // MODULE: Remove duplicate variants
    //
    VCFLIB_VCFUNIQ (
        ARTIC_MINION.out.vcf.join(ARTIC_MINION.out.tbi, by: [0]),
    )
    ch_versions = ch_versions.mix(VCFLIB_VCFUNIQ.out.versions.first().ifEmpty(null))

    //
    // MODULE: Index VCF file
    //
    TABIX_TABIX (
        VCFLIB_VCFUNIQ.out.vcf
    )
    ch_versions = ch_versions.mix(TABIX_TABIX.out.versions.first().ifEmpty(null))

    //
    // MODULE: VCF stats with bcftools stats
    //
    BCFTOOLS_STATS (
        VCFLIB_VCFUNIQ.out.vcf.join(TABIX_TABIX.out.tbi, by: [0]),
        [ [:], [] ],
        [ [:], [] ],
        [ [:], [] ],
        [ [:], [] ],
        [ [:], [] ]
    )
    ch_versions = ch_versions.mix(BCFTOOLS_STATS.out.versions.first().ifEmpty(null))

    //
    // SUBWORKFLOW: Filter unmapped reads from BAM
    //
    FILTER_BAM_SAMTOOLS (
        ARTIC_MINION.out.bam.join(ARTIC_MINION.out.bai, by: [0]),
        []
    )
    ch_versions = ch_versions.mix(FILTER_BAM_SAMTOOLS.out.versions)
    }

    //
    // MODULE: Genome-wide and amplicon-specific coverage QC plots
    //
    ch_mosdepth_multiqc         = Channel.empty()
    ch_amplicon_heatmap_multiqc = Channel.empty()
    if (!params.skip_mosdepth) {

        MOSDEPTH_GENOME (
            ARTIC_MINION.out.bam_primertrimmed.join(ARTIC_MINION.out.bai_primertrimmed, by: [0]),
            [ [:], [] ]
        )
        ch_mosdepth_multiqc  = MOSDEPTH_GENOME.out.global_txt
        ch_versions          = ch_versions.mix(MOSDEPTH_GENOME.out.versions.first().ifEmpty(null))

        PLOT_MOSDEPTH_REGIONS_GENOME (
            MOSDEPTH_GENOME.out.regions_bed.collect { it[1] }
        )
        ch_versions = ch_versions.mix(PLOT_MOSDEPTH_REGIONS_GENOME.out.versions)

        MOSDEPTH_AMPLICON (
            // TODO: This is a temporary fix to get the amplicon coverage plot working
            // Check if the input channels are correct
            ARTIC_MINION.out.bam_primertrimmed.join(ARTIC_MINION.out.bai_primertrimmed, by: [0]),
            //PREPARE_GENOME.out.primer_collapsed_bed.map { [ [:], it ] }.collect(),
            [ [:], [] ]
        )
        ch_versions = ch_versions.mix(MOSDEPTH_AMPLICON.out.versions.first().ifEmpty(null))

        PLOT_MOSDEPTH_REGIONS_AMPLICON (
            MOSDEPTH_AMPLICON.out.regions_bed.collect { it[1] }
        )
        ch_amplicon_heatmap_multiqc = PLOT_MOSDEPTH_REGIONS_AMPLICON.out.heatmap_tsv
        ch_versions                 = ch_versions.mix(PLOT_MOSDEPTH_REGIONS_AMPLICON.out.versions)
    }

    //
    // MODULE: Lineage analysis with Pangolin
    //
    ch_pangolin_multiqc = Channel.empty()
    if (!params.skip_pangolin) {
        PANGOLIN (
            ARTIC_MINION.out.fasta
        )
        ch_pangolin_multiqc = PANGOLIN.out.report
        ch_versions         = ch_versions.mix(PANGOLIN.out.versions.first().ifEmpty(null))
    }

    //
    // MODULE: Clade assignment, mutation calling, and sequence quality checks with Nextclade
    //
    ch_nextclade_multiqc = Channel.empty()
    if (!params.skip_nextclade) {
        NEXTCLADE_RUN (
            ARTIC_MINION.out.fasta,
            PREPARE_GENOME.out.nextclade_db.collect()
        )
        ch_versions = ch_versions.mix(NEXTCLADE_RUN.out.versions.first().ifEmpty(null))

        //
        // MODULE: Get Nextclade clade information for MultiQC report
        //
        NEXTCLADE_RUN
            .out
            .csv
            .map {
                meta, csv ->
                    def clade = WorkflowCommons.getNextcladeFieldMapFromCsv(csv)['clade']
                    return [ "$meta.id\t$clade" ]
            }
            .collect()
            .map {
                tsv_data ->
                    def header = ['Sample', 'clade']
                    WorkflowCommons.multiqcTsvFromList(tsv_data, header)
            }
            .set { ch_nextclade_multiqc }
    }

    //
    // MODULE: Consensus QC across all samples with QUAST
    //
    ch_quast_multiqc = Channel.empty()
    if (!params.skip_variants_quast) {
        QUAST (
            ARTIC_MINION.out.fasta.collect{ it[1] },
            PREPARE_GENOME.out.fasta.collect(),
            params.gff ? PREPARE_GENOME.out.gff : [],
            true,
            params.gff
        )
        ch_quast_multiqc = QUAST.out.tsv
        ch_versions      = ch_versions.mix(QUAST.out.versions)
    }

    //
    // SUBWORKFLOW: Annotate variants with snpEff
    //
    ch_snpeff_multiqc = Channel.empty()
    ch_snpsift_txt    = Channel.empty()
    if (params.gff && !params.skip_snpeff) {
        SNPEFF_SNPSIFT (
            VCFLIB_VCFUNIQ.out.vcf,
            PREPARE_GENOME.out.snpeff_db.collect(),
            PREPARE_GENOME.out.snpeff_config.collect(),
            PREPARE_GENOME.out.fasta.collect()
        )
        ch_snpeff_multiqc = SNPEFF_SNPSIFT.out.csv
        ch_snpsift_txt    = SNPEFF_SNPSIFT.out.snpsift_txt
        ch_versions       = ch_versions.mix(SNPEFF_SNPSIFT.out.versions)
    }

    //
    // MODULE: Variant screenshots with ASCIIGenome
    //
    if (!params.skip_asciigenome) {
        ARTIC_MINION
            .out
            .bam_primertrimmed
            .join(VCFLIB_VCFUNIQ.out.vcf, by: [0])
            .join(BCFTOOLS_STATS.out.stats, by: [0])
            .map { meta, bam, vcf, stats ->
                if (WorkflowCommons.getNumVariantsFromBCFToolsStats(stats) > 0) {
                    return [ meta, bam, vcf ]
                }
            }
            .set { ch_asciigenome }

        ASCIIGENOME (
            ch_asciigenome,
            PREPARE_GENOME.out.fasta.collect(),
            PREPARE_GENOME.out.chrom_sizes.collect(),
            params.gff ? PREPARE_GENOME.out.gff : [],
            PREPARE_GENOME.out.primer_bed.collect(),
            params.asciigenome_window_size,
            params.asciigenome_read_depth
        )
        ch_versions = ch_versions.mix(ASCIIGENOME.out.versions.first().ifEmpty(null))
    }

    //
    // SUBWORKFLOW: Create variants long table report
    //
    if (!params.skip_variants_long_table && params.gff && !params.skip_snpeff) {
        VARIANTS_LONG_TABLE (
            VCFLIB_VCFUNIQ.out.vcf,
            TABIX_TABIX.out.tbi,
            ch_snpsift_txt,
            ch_pangolin_multiqc
        )
        ch_versions = ch_versions.mix(VARIANTS_LONG_TABLE.out.versions)
    }

    //
    // MODULE: Pipeline reporting
    //
    CUSTOM_DUMPSOFTWAREVERSIONS (
        ch_versions.unique().collectFile(name: 'collated_versions.yml')
    )

    //
    // MODULE: MultiQC
    //
    if (!params.skip_multiqc) {
        workflow_summary    = WorkflowCommons.paramsSummaryMultiqc(workflow, summary_params)
        ch_workflow_summary = Channel.value(workflow_summary)

        if (!params.skip_minion) {
            ch_minion = ARTIC_MINION.out.json.collect{it[1]}.ifEmpty([])
            ch_filtbamsam = FILTER_BAM_SAMTOOLS.out.flagstat.collect{it[1]}.ifEmpty([])
            ch_bcftoolsstats = BCFTOOLS_STATS.out.stats.collect{it[1]}.ifEmpty([])
        } else {
            ch_minion = []
            ch_filtbamsam = []
            ch_bcftoolsstats = []
        }

        MULTIQC (
            ch_multiqc_config,
            ch_multiqc_custom_config,
            CUSTOM_DUMPSOFTWAREVERSIONS.out.mqc_yml.collect(),
            ch_workflow_summary.collectFile(name: 'workflow_summary_mqc.yaml'),
            ch_custom_no_sample_name_multiqc.collectFile(name: 'fail_barcodes_no_sample_mqc.tsv').ifEmpty([]),
            ch_custom_no_barcodes_multiqc.collectFile(name: 'fail_no_barcode_samples_mqc.tsv').ifEmpty([]),
            ch_custom_fail_barcodes_count_multiqc.collectFile(name: 'fail_barcode_count_samples_mqc.tsv').ifEmpty([]),
            ch_custom_fail_guppyplex_count_multiqc.collectFile(name: 'fail_guppyplex_count_samples_mqc.tsv').ifEmpty([]),
            ch_amplicon_heatmap_multiqc.ifEmpty([]),
            ch_pycoqc_multiqc.collect{it[1]}.ifEmpty([]),
            ch_minion,
            ch_filtbamsam,
            ch_bcftoolsstats,
            ch_mosdepth_multiqc.collect{it[1]}.ifEmpty([]),
            ch_quast_multiqc.collect().ifEmpty([]),
            ch_snpeff_multiqc.collect{it[1]}.ifEmpty([]),
            ch_pangolin_multiqc.collect{it[1]}.ifEmpty([]),
            ch_nextclade_multiqc.collectFile(name: 'nextclade_clade_mqc.tsv').ifEmpty([])
        )
        multiqc_report = MULTIQC.out.report.toList()
    }
}
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    COMPLETION EMAIL AND SUMMARY
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow.onComplete {
    if (params.email || params.email_on_fail) {
        NfcoreTemplate.email(workflow, params, summary_params, projectDir, log, multiqc_report)
    }
    NfcoreTemplate.summary(workflow, params, log)
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
